//
//  CrashCaptureTests.swift
//  ApiLogKitTests
//
//  The crash → log pairing. Getting the blame wrong is worse than not
//  assigning it: the inspector would point confidently at the wrong response.
//

import XCTest
@testable import ApiLogKit

final class CrashCaptureTests: XCTestCase {

    private let session = UUID()

    // MARK: - Helpers

    private func finished(_ url: String, code: String = "200") -> ApiLog {
        ApiLog(
            responseCode: code,
            method: "GET",
            url: url,
            responseTime: "0.10",
            size: "2",
            date: Date(),
            responseHeader: [:],
            responseBody: "{}",
            requestHeader: [:],
            requestBody: [:]
        )
    }

    private func pending(_ url: String) -> ApiLog {
        ApiLog(method: "POST", url: url)
    }

    private func report(
        session: UUID,
        cause: CrashCause = .signal(name: "SIGTRAP", number: SIGTRAP),
        reason: String? = nil
    ) -> CrashReport {
        CrashReport(
            cause: cause,
            reason: reason,
            date: Date(),
            callStack: ["0 MyApp 0x0000 main"],
            sessionID: session
        )
    }

    /// Every entry attributed to `session`, as the journal would.
    private func sessions(_ logs: [ApiLog], _ session: UUID) -> [UUID: UUID] {
        Dictionary(uniqueKeysWithValues: logs.map { ($0.id, session) })
    }

    // MARK: - Headline

    func testHeadlineCombinesCauseAndReason() {
        let crash = report(
            session: session,
            cause: .exception(name: "NSInvalidArgumentException"),
            reason: "unrecognized selector sent to instance"
        )
        XCTAssertEqual(
            crash.headline,
            "NSInvalidArgumentException: unrecognized selector sent to instance"
        )
    }

    func testHeadlineIsJustTheCauseWhenThereIsNoReason() {
        XCTAssertEqual(report(session: session).headline, "SIGTRAP")
    }

    /// A bare signal name tells a Swift developer nothing; the note is what
    /// turns it into a starting point.
    func testSwiftTrapExplainsItself() {
        let explanation = report(session: session).explanation
        XCTAssertNotNil(explanation)
        XCTAssertTrue(explanation!.contains("force unwrap"))
    }

    func testExceptionsHaveNoSignalExplanation() {
        let crash = report(session: session, cause: .exception(name: "NSRangeException"))
        XCTAssertNil(crash.explanation)
    }

    // MARK: - Suspect selection

    func testNothingIsBlamedWhenThereAreNoLogs() {
        let suspects = CrashSuspects.identify(
            api: [], sessions: [:], report: report(session: session)
        )
        XCTAssertTrue(suspects.isEmpty)
    }

    /// A crash landing milliseconds after a response is almost always the app
    /// choking on that payload, so the newest finished entry is a suspect even
    /// though it completed cleanly.
    func testNewestFinishedEntryIsBlamed() {
        let logs = [finished("https://api.example.com/first"),
                    finished("https://api.example.com/second")]
        let suspects = CrashSuspects.identify(
            api: logs, sessions: sessions(logs, session), report: report(session: session)
        )
        XCTAssertEqual(suspects, [logs[1].id])
    }

    /// An in-flight request leaves no other trace at all — nothing came back,
    /// so nothing else can explain the failure.
    func testEveryInFlightEntryIsBlamedAlongsideTheLastFinishedOne() {
        let logs = [finished("https://api.example.com/done"),
                    pending("https://api.example.com/slow"),
                    pending("https://api.example.com/slower")]
        let suspects = CrashSuspects.identify(
            api: logs, sessions: sessions(logs, session), report: report(session: session)
        )
        XCTAssertEqual(suspects, Set(logs.map(\.id)))
    }

    func testASingleInFlightEntryIsBlamedExactlyOnce() {
        let logs = [pending("https://api.example.com/only")]
        let suspects = CrashSuspects.identify(
            api: logs, sessions: sessions(logs, session), report: report(session: session)
        )
        XCTAssertEqual(suspects.count, 1)
    }

    /// The one that would otherwise mislead: an app that launched, sat idle and
    /// crashed would pin the blame on the previous run's last response.
    func testEntriesFromAnotherRunAreNeverBlamed() {
        let earlier = [finished("https://api.example.com/yesterday")]
        let suspects = CrashSuspects.identify(
            api: earlier,
            sessions: sessions(earlier, UUID()),   // a different run
            report: report(session: session)
        )
        XCTAssertTrue(suspects.isEmpty)
    }

    /// Archived entries carry no session — they predate the journal lines — and
    /// so can never be the crash's doing.
    func testEntriesWithoutASessionAreNeverBlamed() {
        let logs = [finished("https://api.example.com/archived")]
        let suspects = CrashSuspects.identify(
            api: logs, sessions: [:], report: report(session: session)
        )
        XCTAssertTrue(suspects.isEmpty)
    }

    func testAnEarlierRunDoesNotDisplaceThisRunsSuspect() {
        let old = finished("https://api.example.com/yesterday")
        let new = finished("https://api.example.com/today")
        var map = sessions([old], UUID())
        map[new.id] = session

        let suspects = CrashSuspects.identify(
            api: [old, new], sessions: map, report: report(session: session)
        )
        XCTAssertEqual(suspects, [new.id])
    }

    func testApplyMarksOnlyTheSuspects() {
        let logs = [finished("https://api.example.com/first"),
                    finished("https://api.example.com/second")]
        var api = logs
        let crash = report(session: session)
        CrashSuspects.apply(crash, to: &api, sessions: sessions(logs, session))

        XCTAssertNil(api[0].crash)
        XCTAssertEqual(api[1].crash, crash)
    }

    // MARK: - Record round trip

    func testExceptionRecordRoundTrips() throws {
        CrashRecorder.shared.clearPendingReport()
        defer { CrashRecorder.shared.clearPendingReport() }

        CrashRecorder.shared.writeExceptionRecord(
            name: "NSInvalidArgumentException",
            reason: "boom",
            callStack: ["0 MyApp 0x1 -[Foo bar]", "1 MyApp 0x2 main"]
        )

        let read = try XCTUnwrap(CrashRecorder.shared.readPendingReport())
        XCTAssertEqual(read.cause, .exception(name: "NSInvalidArgumentException"))
        XCTAssertEqual(read.reason, "boom")
        XCTAssertEqual(read.callStack.count, 2)
    }

    func testClearingRemovesThePendingRecord() {
        CrashRecorder.shared.writeExceptionRecord(name: "X", reason: nil, callStack: [])
        CrashRecorder.shared.clearPendingReport()
        XCTAssertNil(CrashRecorder.shared.readPendingReport())
    }

    /// The signal record is written by hand from a dying process, so its
    /// parsing is exercised against the exact bytes the handler emits.
    func testSignalRecordIsParsed() throws {
        CrashRecorder.shared.clearPendingReport()
        defer { CrashRecorder.shared.clearPendingReport() }

        let session = UUID()
        let text = """
        apilogkit-crash 1
        session \(session.uuidString)
        signal \(SIGSEGV)
        time 1700000000
        frames
        0   MyApp    0x0000000102a4c000 main + 42
        1   libdyld  0x00000001bb6d1000 start + 4

        """
        try writeSignalFile(text)

        let read = try XCTUnwrap(CrashRecorder.shared.readPendingReport())
        XCTAssertEqual(read.cause, .signal(name: "SIGSEGV", number: SIGSEGV))
        XCTAssertEqual(read.sessionID, session)
        XCTAssertEqual(read.date, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(read.callStack.count, 2)
    }

    /// A process can die part-way through writing the record. Losing the tail
    /// must not lose the whole report.
    func testTruncatedSignalRecordStillYieldsAReport() throws {
        CrashRecorder.shared.clearPendingReport()
        defer { CrashRecorder.shared.clearPendingReport() }

        let session = UUID()
        try writeSignalFile("""
        apilogkit-crash 1
        session \(session.uuidString)
        signal \(SIGTRAP)
        time 1700000000
        frames
        0   MyApp    0x0000000102a4c000 ma
        """)

        let read = try XCTUnwrap(CrashRecorder.shared.readPendingReport())
        XCTAssertEqual(read.cause, .signal(name: "SIGTRAP", number: SIGTRAP))
        XCTAssertEqual(read.callStack.count, 1)
    }

    func testRecordWithoutTheMagicLineIsIgnored() throws {
        CrashRecorder.shared.clearPendingReport()
        defer { CrashRecorder.shared.clearPendingReport() }

        try writeSignalFile("garbage\nsignal 11\n")
        XCTAssertNil(CrashRecorder.shared.readPendingReport())
    }

    /// An unhandled `NSException` aborts, so one crash can leave both files.
    /// The exception record carries a name, a reason and a symbolicated stack
    /// where the signal record would only say `SIGABRT`.
    func testExceptionRecordWinsOverASignalRecord() throws {
        CrashRecorder.shared.clearPendingReport()
        defer { CrashRecorder.shared.clearPendingReport() }

        try writeSignalFile("""
        apilogkit-crash 1
        session \(UUID().uuidString)
        signal \(SIGABRT)
        time 1700000000
        frames
        """)
        CrashRecorder.shared.writeExceptionRecord(
            name: "NSRangeException", reason: "index out of bounds", callStack: []
        )

        let read = try XCTUnwrap(CrashRecorder.shared.readPendingReport())
        XCTAssertEqual(read.cause, .exception(name: "NSRangeException"))
    }

    // MARK: - Stack trimming

    /// Leaving the handler in place would put `crashSignalHandler` at frame 0
    /// of every report, reading as though ApiLogKit caused the crash.
    func testOwnHandlerFramesAreTrimmedFromTheTop() {
        let trimmed = CrashRecorder.trimmingHandlerFrames([
            "0   MyApp     0x1 $s9ApiLogKit18crashSignalHandler… + 532",
            "1   MyApp     0x2 $s9ApiLogKit18crashSignalHandler…To + 12",
            "2   libsystem_platform.dylib 0x3 _sigtramp + 52",
            "3   libswiftCore.dylib 0x4 _assertionFailure + 460",
            "4   MyApp     0x5 OutletMapper.map(_:) + 72"
        ])

        XCTAssertEqual(trimmed.count, 2)
        XCTAssertTrue(trimmed.first!.contains("_assertionFailure"))
    }

    /// Showing a few extra frames beats silently discarding real ones.
    func testStackIsLeftAloneWhenTheTrampolineIsAbsent() {
        let frames = ["0   MyApp 0x1 main + 4", "1   MyApp 0x2 start + 8"]
        XCTAssertEqual(CrashRecorder.trimmingHandlerFrames(frames), frames)
    }

    private func writeSignalFile(_ text: String) throws {
        let url = try XCTUnwrap(CrashRecorder.signalFileURL)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
    }
}
