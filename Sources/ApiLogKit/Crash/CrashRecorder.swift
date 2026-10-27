//
//  CrashRecorder.swift
//  ApiLogKit
//
//  Records what killed the app, so the next launch can pair it with the
//  exchange that was live at the time.
//
//  Why this looks nothing like the Android counterpart
//  ---------------------------------------------------
//  On Android the crash handler can block, drain the pending database writes
//  and store the crash, because it runs as ordinary Java on a dying thread.
//  iOS gives no such latitude:
//
//  * Most **Swift** crashes — a force unwrap of nil, an out-of-range index,
//    `fatalError` — do not raise an `NSException`. They trap, and arrive as a
//    POSIX signal.
//  * Inside a signal handler only **async-signal-safe** functions may be
//    called. `JSONEncoder`, `FileManager`, `Data.write`, `DispatchQueue`,
//    `String` and anything that allocates are all off-limits; calling them
//    risks deadlocking against a lock the interrupted thread already holds, in
//    the middle of the one write we are trying to save.
//
//  So the durability problem is solved *before* the crash instead of during it:
//  `LogJournal` puts every entry on disk as it is captured, which is why this
//  file never has to flush anything. All the signal path does is append a small,
//  mostly pre-rendered record using raw `write(2)`, then hand the signal back.
//
//  Which entries to blame is not written here either — it is derived on the next
//  launch from the journal, by `CrashSuspects`.
//
//  The residual window
//  -------------------
//  Writing ahead is a weaker guarantee than Android's blocking flush, and the
//  difference is worth being honest about. An entry reaches disk one queue hop
//  after it is captured, so a crash in that gap still loses it. In practice the
//  gap is sub-millisecond and the crashes this feature is for — a decode or
//  mapping failure — happen after the app has done real work with the response,
//  by which time the line is written. A crash *synchronous* with the capturing
//  call can still outrun it, and nothing short of blocking every log write on
//  `fsync` would close that, which is too high a price for a debug logger.
//

import Darwin
import Foundation

// MARK: - Signal-handler state
//
// Everything the signal handler touches is plain C storage, allocated and
// filled at install time. The handler itself must not allocate, so nothing here
// may be a Swift String, Array or object.

/// Descriptor for the signal record, opened during `install` so the handler
/// never has to call `open`.
private var crashFileDescriptor: Int32 = -1

/// `"apilogkit-crash 1\nsession <uuid>\n"`, rendered once at install.
private var crashHeader: UnsafeMutablePointer<CChar>?
private var crashHeaderLength: Int = 0

/// Scratch space for formatting integers. One shared buffer is fine: the
/// handler re-raises and the process dies, so it never runs twice.
private var crashScratch: UnsafeMutablePointer<CChar>?

/// Pre-allocated frame storage for `backtrace`.
private var crashFrames: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
private let crashFrameCapacity = 64

/// The handlers that were installed before ours, restored before re-raising so
/// the host's crash reporter sees the signal exactly as it would have.
private var previousActions: [Int32: sigaction] = [:]

/// The signals worth catching. `SIGPIPE` and friends are left alone — they are
/// not crashes, and a debug logger has no business touching them.
private let handledSignals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGBUS, SIGFPE, SIGTRAP]

/// Appends `text` to the crash file. Async-signal-safe: `write` is on the
/// POSIX safe list, and the pointer is pre-allocated.
private func crashWrite(_ pointer: UnsafePointer<CChar>, _ length: Int) {
    guard crashFileDescriptor >= 0, length > 0 else { return }
    var written = 0
    while written < length {
        let result = write(crashFileDescriptor, pointer + written, length - written)
        // EINTR is the only retryable case; anything else means give up rather
        // than spin inside a crash.
        if result <= 0 {
            if errno == EINTR { continue }
            return
        }
        written += result
    }
}

/// Writes a `key value\n` line with an integer value, formatting the digits by
/// hand because `String(describing:)` would allocate.
private func crashWriteInt(_ key: StaticString, _ value: Int) {
    guard let scratch = crashScratch else { return }

    // StaticString's utf8Start is a stable pointer into the binary — safe to
    // read from a signal handler, unlike a Swift String.
    crashWrite(UnsafeRawPointer(key.utf8Start).assumingMemoryBound(to: CChar.self), key.utf8CodeUnitCount)

    var magnitude = value < 0 ? -value : value
    var digits = 0
    // Render least-significant digit first into the end of the scratch buffer.
    repeat {
        scratch[31 - digits] = CChar(48 + (magnitude % 10))
        magnitude /= 10
        digits += 1
    } while magnitude > 0 && digits < 20

    if value < 0 {
        digits += 1
        scratch[31 - digits + 1] = CChar(45) // '-'
    }
    crashWrite(scratch + (32 - digits), digits)
    var newline = CChar(10)
    crashWrite(&newline, 1)
}

/// The signal handler. Nothing in here may allocate or take a lock.
private func crashSignalHandler(_ signalNumber: Int32) {
    if let header = crashHeader {
        crashWrite(header, crashHeaderLength)
    }
    crashWriteInt("signal ", Int(signalNumber))
    // `time` is async-signal-safe; `Date()` would not be.
    crashWriteInt("time ", Int(time(nil)))

    let framesLabel: StaticString = "frames\n"
    crashWrite(
        UnsafeRawPointer(framesLabel.utf8Start).assumingMemoryBound(to: CChar.self),
        framesLabel.utf8CodeUnitCount
    )

    if let frames = crashFrames {
        let count = backtrace(frames, Int32(crashFrameCapacity))
        // The _fd variant writes straight to the descriptor without allocating;
        // `backtrace_symbols` would malloc and is unusable here.
        backtrace_symbols_fd(frames, count, crashFileDescriptor)
    }

    fsync(crashFileDescriptor)

    // Hand the signal back exactly as it arrived: restore whoever was there
    // before us and re-raise, so the host's reporter and the system's own
    // handling both run.
    if var previous = previousActions[signalNumber] {
        sigaction(signalNumber, &previous, nil)
    } else {
        var fallback = sigaction()
        fallback.__sigaction_u.__sa_handler = SIG_DFL
        sigaction(signalNumber, &fallback, nil)
    }
    raise(signalNumber)
}

/// Uncaught `NSException` handler. Unlike the signal path this runs in an
/// ordinary context, so it can allocate and use Foundation freely.
private func crashExceptionHandler(_ exception: NSException) {
    CrashRecorder.shared.writeExceptionRecord(
        name: exception.name.rawValue,
        reason: exception.reason,
        callStack: exception.callStackSymbols
    )
    CrashRecorder.previousExceptionHandler?(exception)
}

private var previousExceptionHandlerStorage: (@convention(c) (NSException) -> Void)?

// MARK: - Recorder

final class CrashRecorder {
    static let shared = CrashRecorder()
    private init() {}

    static var previousExceptionHandler: (@convention(c) (NSException) -> Void)? {
        previousExceptionHandlerStorage
    }

    private var isInstalled = false

    /// Identifies this run, so the next launch blames only the entries this run
    /// recorded.
    private(set) var sessionID = UUID()

    // MARK: - Install

    /// Installs the handlers for `sessionID`.
    ///
    /// Call **after** `readPendingReport()`: opening the signal file truncates
    /// it, so the previous run's record has to be consumed first.
    ///
    /// Installing is one-way. Handing the handlers back later would mean
    /// overwriting whoever installed theirs in the meantime, which is worse than
    /// leaving a no-op in place — so disabling persistence simply leaves nothing
    /// for the record to be attached to.
    func install(sessionID: UUID) {
        guard !isInstalled else { return }
        isInstalled = true
        self.sessionID = sessionID

        prepareSignalBuffers(sessionID: sessionID)
        installSignalHandlers()

        previousExceptionHandlerStorage = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler(crashExceptionHandler)
    }

    /// Renders everything the signal handler needs up front, while allocating is
    /// still allowed.
    private func prepareSignalBuffers(sessionID: UUID) {
        guard let url = Self.signalFileURL else { return }
        Self.createDirectory(for: url)

        let header = "apilogkit-crash 1\nsession \(sessionID.uuidString)\n"
        let bytes = Array(header.utf8)
        let headerBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
        for (index, byte) in bytes.enumerated() {
            headerBuffer[index] = CChar(bitPattern: byte)
        }
        crashHeader = headerBuffer
        crashHeaderLength = bytes.count

        crashScratch = UnsafeMutablePointer<CChar>.allocate(capacity: 32)
        crashFrames = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(
            capacity: crashFrameCapacity
        )

        crashFileDescriptor = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        // Protection has to be set here, not from the handler: setting file
        // attributes allocates.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private func installSignalHandlers() {
        for signalNumber in handledSignals {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = crashSignalHandler
            sigemptyset(&action.sa_mask)
            // SA_ONSTACK so a stack-overflow crash still has somewhere to run.
            action.sa_flags = SA_ONSTACK
            var previous = sigaction()
            if sigaction(signalNumber, &action, &previous) == 0 {
                previousActions[signalNumber] = previous
            }
        }
    }

    // MARK: - Writing (exception path)

    /// Stores an `NSException` record as JSON. Internal rather than private so
    /// the tests can write a record without raising a real exception.
    func writeExceptionRecord(name: String, reason: String?, callStack: [String]) {
        guard let url = Self.exceptionFileURL else { return }
        Self.createDirectory(for: url)

        let record = PersistedCrashReport(
            kind: .exception,
            label: name,
            signalNumber: 0,
            reason: reason,
            date: Date(),
            callStack: callStack,
            session: sessionID
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: - Reading

    /// Reads the record left by the previous run, if there is one.
    ///
    /// An `NSException` that goes unhandled is followed by `abort()`, so a single
    /// crash can leave both files behind. The exception record wins: it carries a
    /// name, a reason and a symbolicated stack, where the signal record would
    /// only say `SIGABRT`.
    func readPendingReport() -> CrashReport? {
        readExceptionReport() ?? readSignalReport()
    }

    private func readExceptionReport() -> CrashReport? {
        guard let url = Self.exceptionFileURL,
              let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(PersistedCrashReport.self, from: data)
        else { return nil }
        return record.toCrashReport()
    }

    /// Parses the line-oriented record the signal handler writes.
    ///
    /// Written from a dying process, so it may be truncated anywhere: every
    /// field is optional and a half-written file degrades to fewer frames rather
    /// than to nothing.
    private func readSignalReport() -> CrashReport? {
        guard let url = Self.signalFileURL,
              let data = try? Data(contentsOf: url),
              !data.isEmpty
        else { return nil }

        let text = String(decoding: data, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "apilogkit-crash 1" else { return nil }
        lines.removeFirst()

        var session: UUID?
        var signalNumber: Int32?
        var timestamp: TimeInterval?
        var frames: [String] = []
        var inFrames = false

        for line in lines {
            if inFrames {
                if !line.isEmpty { frames.append(line) }
                continue
            }
            if line == "frames" {
                inFrames = true
            } else if line.hasPrefix("session ") {
                session = UUID(uuidString: String(line.dropFirst("session ".count)))
            } else if line.hasPrefix("signal ") {
                signalNumber = Int32(String(line.dropFirst("signal ".count)))
            } else if line.hasPrefix("time ") {
                timestamp = Double(String(line.dropFirst("time ".count)))
            }
        }

        guard let session, let signalNumber else { return nil }
        return CrashReport(
            cause: .signal(name: Self.name(for: signalNumber), number: signalNumber),
            reason: nil,
            date: timestamp.map(Date.init(timeIntervalSince1970:)) ?? Date(),
            callStack: Self.trimmingHandlerFrames(frames),
            sessionID: session
        )
    }

    /// Drops the frames belonging to this file from the top of the stack.
    ///
    /// `backtrace` is taken inside the signal handler, so the first frames are
    /// always ApiLogKit's own handler and the kernel's `_sigtramp` trampoline.
    /// Leaving them in puts `crashSignalHandler` at frame 0 of every report,
    /// which reads as though the logger caused the crash — the opposite of what
    /// the report is for. Everything from `_sigtramp` up is dropped so the stack
    /// starts where the app actually trapped.
    ///
    /// If the trampoline isn't found the stack is left exactly as captured:
    /// showing a few extra frames beats silently discarding real ones.
    static func trimmingHandlerFrames(_ frames: [String]) -> [String] {
        guard let trampoline = frames.firstIndex(where: { $0.contains("_sigtramp") }) else {
            return frames
        }
        return Array(frames.dropFirst(trampoline + 1))
    }

    /// Removes both records, once the report has been attached to its logs.
    func clearPendingReport() {
        for url in [Self.exceptionFileURL, Self.signalFileURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Files

    static var exceptionFileURL: URL? {
        LogPersistence.directoryURL?.appendingPathComponent("crash-exception.json")
    }

    static var signalFileURL: URL? {
        LogPersistence.directoryURL?.appendingPathComponent("crash-signal.txt")
    }

    private static func createDirectory(for url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    static func name(for signalNumber: Int32) -> String {
        switch signalNumber {
        case SIGABRT: return "SIGABRT"
        case SIGILL:  return "SIGILL"
        case SIGSEGV: return "SIGSEGV"
        case SIGBUS:  return "SIGBUS"
        case SIGFPE:  return "SIGFPE"
        case SIGTRAP: return "SIGTRAP"
        default:      return "Signal \(signalNumber)"
        }
    }
}

// MARK: - On-disk form

/// Codable form of a `CrashReport`, following the same DTO split as
/// `PersistedApiLog`.
struct PersistedCrashReport: Codable {
    enum Kind: String, Codable {
        case exception
        case signal
    }

    var kind: Kind
    var label: String
    var signalNumber: Int32
    var reason: String?
    var date: Date
    var callStack: [String]
    var session: UUID

    func toCrashReport() -> CrashReport {
        CrashReport(
            cause: kind == .exception
                ? .exception(name: label)
                : .signal(name: label, number: signalNumber),
            reason: reason,
            date: date,
            callStack: callStack,
            sessionID: session
        )
    }
}
