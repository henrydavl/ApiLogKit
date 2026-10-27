//
//  CrashReport.swift
//  ApiLogKit
//
//  A crash that killed the app, kept on disk next to the logs it is blamed on.
//

import Foundation

/// What brought the process down.
///
/// The distinction matters because the two arrive through completely different
/// channels, and only one of them can be caught usefully by Objective-C
/// machinery — see `CrashRecorder`.
public enum CrashCause: Equatable {
    /// An uncaught `NSException`. Objective-C in origin: an unrecognised
    /// selector, a KVO misuse, an out-of-range `NSArray` index.
    case exception(name: String)

    /// A fatal POSIX signal. This is where **Swift** crashes land: a force
    /// unwrap of nil, an array index out of bounds, `fatalError`, a failed
    /// precondition — all of them trap rather than raise an exception.
    case signal(name: String, number: Int32)
}

/// A crash recorded by ApiLogKit, paired with the exchange that was live when
/// it happened.
///
/// The pairing is the point, not the stack trace on its own: Xcode and your
/// crash reporter already tell you *where* the app died. What they cannot tell
/// you is *what the server sent* a moment earlier — and for a decoding or
/// mapping crash that payload is the whole bug.
public struct CrashReport: Equatable {

    public let cause: CrashCause

    /// `NSException.reason` where there is one. Signals carry no reason, so this
    /// is nil for the Swift traps that make up most crashes.
    public let reason: String?

    /// When the crash was recorded.
    public let date: Date

    /// Call stack as captured at crash time.
    ///
    /// Symbolicated for an exception (`NSException.callStackSymbols`). For a
    /// signal these come from `backtrace_symbols_fd`, so they carry the image
    /// and symbol name but no file or line.
    public let callStack: [String]

    /// The run this crash belongs to, used to blame only that run's entries —
    /// see `CrashSuspects`.
    let sessionID: UUID

    /// The exception name or signal name on its own, without the reason.
    public var causeLabel: String {
        switch cause {
        case .exception(let name):   return name
        case .signal(let name, _):   return name
        }
    }

    /// One line for a badge or banner, e.g.
    /// `NSInvalidArgumentException: unrecognized selector sent to instance`.
    public var headline: String {
        let label = causeLabel
        guard let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reason.isEmpty
        else { return label }
        return "\(label): \(reason)"
    }

    /// Plain-language note for signals that carry no reason of their own.
    ///
    /// `SIGTRAP` in a Swift app almost always means the Swift runtime trapped
    /// deliberately — a force unwrap of nil, an out-of-bounds index, an
    /// overflow, or an explicit `fatalError`. Saying so turns an opaque signal
    /// name into a starting point, and it is exactly the class of bug a bad
    /// response payload produces.
    public var explanation: String? {
        guard case .signal(_, let number) = cause else { return nil }
        switch number {
        case SIGTRAP, SIGILL:
            return "Swift runtime trap — a force unwrap of nil, an out-of-range index, "
                 + "an overflow or an explicit fatalError. Check the response below "
                 + "against what the decoding code expects."
        case SIGSEGV, SIGBUS:
            return "Bad memory access — often an over-released object or a dangling pointer."
        case SIGABRT:
            return "Aborted — usually an uncaught exception or a failed assertion."
        case SIGFPE:
            return "Arithmetic fault — a division by zero or an overflowing conversion."
        default:
            return nil
        }
    }
}
