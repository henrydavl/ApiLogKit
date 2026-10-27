//
//  CrashDisplayTests.swift
//  ApiLogKitTests
//
//  How a crash-linked entry presents itself: the extra detail section, the
//  export block, and the restored entry that can never complete.
//

import XCTest
@testable import ApiLogKit

final class CrashDisplayTests: XCTestCase {

    private let crash = CrashReport(
        cause: .signal(name: "SIGTRAP", number: SIGTRAP),
        reason: nil,
        date: Date(timeIntervalSince1970: 1_700_000_000),
        callStack: [
            "0   MyApp   0x0000000102a4c000 OutletMapper.map(_:) + 42",
            "1   MyApp   0x0000000102a4c100 main + 8"
        ],
        sessionID: UUID()
    )

    private func makeLog(crash: CrashReport? = nil, pending: Bool = false, restored: Bool = false) -> ApiLog {
        var log: ApiLog
        if pending {
            log = ApiLog(method: "GET", url: "https://api.example.com/profile")
        } else {
            log = ApiLog(
                responseCode: "200",
                method: "GET",
                url: "https://api.example.com/profile",
                responseTime: "0.10",
                size: "2",
                date: Date(),
                responseHeader: [:],
                responseBody: #"{"name":"ada"}"#,
                requestHeader: [:],
                requestBody: [:]
            )
        }
        if restored { log.markRestored() }
        if let crash { log.markCrashed(with: crash) }
        return log
    }

    // MARK: - Detail sections

    func testEntryWithoutACrashHasNoCrashSection() {
        let viewModel = ApiLogDetailViewModel(log: makeLog(), logType: .api)
        XCTAssertFalse(viewModel.sections.contains(.crash))
    }

    /// First, because on that row the stack is what you opened it for.
    func testCrashSectionComesFirst() {
        let viewModel = ApiLogDetailViewModel(log: makeLog(crash: crash), logType: .api)
        XCTAssertEqual(viewModel.sections.first, .crash)
    }

    func testCrashSectionCarriesTheSummaryAndTheStack() throws {
        let viewModel = ApiLogDetailViewModel(log: makeLog(crash: crash), logType: .api)
        let rows = viewModel.rows(for: .crash)

        XCTAssertEqual(rows.first?.value, "SIGTRAP")
        XCTAssertTrue(rows.contains { $0.key == "Likely cause" })
        XCTAssertTrue(rows.contains { $0.key == "Signal" })
        XCTAssertTrue(rows.contains { $0.key == "Time" })
        let stack = try XCTUnwrap(rows.first { $0.key == "Call Stack" })
        XCTAssertTrue(stack.value.contains("OutletMapper.map"))
    }

    /// A call stack is as column-aligned as pretty-printed JSON.
    func testCrashSectionIsMonospaced() {
        let viewModel = ApiLogDetailViewModel(log: makeLog(crash: crash), logType: .api)
        XCTAssertTrue(viewModel.isMonospaced(for: .crash))
    }

    func testCopyingTheCrashSectionYieldsTheFullReport() {
        let viewModel = ApiLogDetailViewModel(log: makeLog(crash: crash), logType: .api)
        let copied = viewModel.copyValue(for: .crash)

        XCTAssertTrue(copied.contains("SIGTRAP"))
        XCTAssertTrue(copied.contains("OutletMapper.map"))
    }

    // MARK: - Restored in-flight entries

    /// The spinner would never stop: that request's process is gone, so no
    /// response can arrive to clear it.
    func testRestoredInFlightEntryReadsAsUnfinishedNotPending() {
        let viewModel = ApiLogDetailViewModel(
            log: makeLog(pending: true, restored: true), logType: .api
        )
        XCTAssertFalse(viewModel.isPending)
        XCTAssertTrue(viewModel.isUnfinished)
    }

    func testLiveInFlightEntryStillReadsAsPending() {
        let viewModel = ApiLogDetailViewModel(log: makeLog(pending: true), logType: .api)
        XCTAssertTrue(viewModel.isPending)
        XCTAssertFalse(viewModel.isUnfinished)
    }

    // MARK: - Export

    /// One file carrying the payload and the stack together is what gets
    /// pasted into the bug report, so the crash leads the raw log.
    func testCrashLinkedRawLogLeadsWithTheCrashBlock() {
        let text = ApiLogExporter.rawLog(for: makeLog(crash: crash))

        XCTAssertTrue(text.hasPrefix("---------- Crash\n"))
        XCTAssertTrue(text.contains("SIGTRAP"))
        XCTAssertTrue(text.contains("OutletMapper.map"))
        // The log itself still follows, unchanged.
        XCTAssertTrue(text.contains("---------- Response Body"))
        XCTAssertTrue(text.contains(#"{"name":"ada"}"#))
    }

    /// Parity with the Android export and with earlier versions: an entry
    /// without a crash is byte-for-byte what it always was.
    func testRawLogWithoutACrashIsUnchanged() {
        let text = ApiLogExporter.rawLog(for: makeLog())

        XCTAssertTrue(text.hasPrefix("https://api.example.com/profile"))
        XCTAssertFalse(text.contains("Crash"))
    }
}
