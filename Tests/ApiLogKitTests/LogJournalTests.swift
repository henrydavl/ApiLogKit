//
//  LogJournalTests.swift
//  ApiLogKitTests
//
//  The journal is what makes a response outlive the crash it caused, so the
//  properties that matter are durability-shaped: an entry is readable straight
//  after it is written, a completion supersedes its own pending line, and a
//  half-written tail costs one entry rather than the file.
//

import XCTest
@testable import ApiLogKit

final class LogJournalTests: XCTestCase {

    private var options: PersistenceOptions {
        var options = PersistenceOptions()
        options.maxBodyBytes = 64 * 1024
        return options
    }

    override func setUp() {
        super.setUp()
        LogJournal.shared.delete()
    }

    override func tearDown() {
        LogJournal.shared.delete()
        super.tearDown()
    }

    private func finished(_ url: String) -> ApiLog {
        ApiLog(
            responseCode: "200",
            method: "GET",
            url: url,
            responseTime: "0.10",
            size: "2",
            date: Date(),
            responseHeader: [:],
            responseBody: #"{"name":"ada"}"#,
            requestHeader: [:],
            requestBody: [:]
        )
    }

    func testAppendedEntryIsReadableImmediately() {
        let session = UUID()
        let log = finished("https://api.example.com/profile")

        LogJournal.shared.append(log, bucket: .api, session: session, options: options)

        let entries = LogJournal.shared.readAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.bucket, .api)
        XCTAssertEqual(entries.first?.session, session)
        XCTAssertEqual(entries.first?.log.id, log.id)
    }

    /// The pending half has to survive on its own: if the app dies before the
    /// response lands, this line is the only evidence the request happened.
    func testPendingEntryIsWrittenAndKeepsItsState() {
        let log = ApiLog(method: "POST", url: "https://api.example.com/checkout")

        LogJournal.shared.append(log, bucket: .api, session: UUID(), options: options)

        let restored = LogJournal.shared.readAll().first?.log.toApiLog()
        XCTAssertEqual(restored?.state, .pending)
        XCTAssertEqual(restored?.id, log.id)
    }

    /// Completion appends a second line for the same id rather than rewriting
    /// the first; the reader keeps the last one, so the pair collapses.
    func testCompletionSupersedesThePendingLine() {
        let session = UUID()
        var log = ApiLog(method: "POST", url: "https://api.example.com/checkout")
        LogJournal.shared.append(log, bucket: .api, session: session, options: options)

        let id = log.id
        log = finished("https://api.example.com/checkout")
        log.restoreIdentity(id: id, date: Date())
        LogJournal.shared.append(log, bucket: .api, session: session, options: options)

        let entries = LogJournal.shared.readAll()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.log.id), [id, id])
        // Last wins, and it is the finished one.
        XCTAssertEqual(entries.last?.log.state, .finished)
    }

    func testEntriesAreReadBackInWriteOrder() {
        let session = UUID()
        for index in 0..<5 {
            LogJournal.shared.append(
                finished("https://api.example.com/\(index)"),
                bucket: .api, session: session, options: options
            )
        }

        let urls = LogJournal.shared.readAll().map(\.log.url)
        XCTAssertEqual(urls, (0..<5).map { "https://api.example.com/\($0)" })
    }

    /// The crash-safety property of the format: a process dying mid-append
    /// leaves a partial final line, and one JSON object per line means the
    /// reader loses only that entry.
    func testTruncatedFinalLineCostsOnlyThatEntry() throws {
        let session = UUID()
        LogJournal.shared.append(finished("https://api.example.com/one"),
                                 bucket: .api, session: session, options: options)
        LogJournal.shared.append(finished("https://api.example.com/two"),
                                 bucket: .api, session: session, options: options)
        LogJournal.shared.close()

        // Chop the file mid-way through the last line, as a crash would.
        let url = try XCTUnwrap(LogJournal.fileURL)
        let data = try Data(contentsOf: url)
        try data.prefix(data.count - 20).write(to: url)

        let entries = LogJournal.shared.readAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.log.url, "https://api.example.com/one")
    }

    func testTruncateEmptiesTheJournal() {
        LogJournal.shared.append(finished("https://api.example.com/one"),
                                 bucket: .api, session: UUID(), options: options)
        LogJournal.shared.truncate()
        XCTAssertTrue(LogJournal.shared.readAll().isEmpty)
    }

    func testBucketsAreKeptApart() {
        let session = UUID()
        LogJournal.shared.append(finished("https://api.example.com/api"),
                                 bucket: .api, session: session, options: options)
        LogJournal.shared.append(finished("checkout_tapped"),
                                 bucket: .eventTracker, session: session, options: options)

        let buckets = LogJournal.shared.readAll().map(\.bucket)
        XCTAssertEqual(buckets, [.api, .eventTracker])
    }
}
