//
//  LogJournal.swift
//  ApiLogKit
//
//  Append-only tail in front of the archive, so an entry is on disk within
//  milliseconds of being captured.
//
//  The archive alone cannot survive a crash. It is rewritten whole, which is
//  too expensive to do per entry, so saves are debounced by two seconds and
//  flushed on backgrounding. A crash in the foreground — the interesting case —
//  arrives before either, and takes the response that caused it with it.
//
//  The journal closes that window: one JSON line appended per entry, written
//  straight away. The archive still exists and still does the bulk storage; a
//  save writes it and then truncates the journal, which is what compaction
//  means here.
//
//  Crash-safety of the format
//  --------------------------
//  A process dying mid-append leaves a truncated final line. One JSON object
//  per line makes that recoverable by construction: the reader decodes what it
//  can and discards the rest, losing at most the entry that was being written.
//  Storing the whole file as one JSON array would instead lose everything.
//

import Foundation

struct JournalEntry: Codable {
    var bucket: LogEventType
    var session: UUID
    var log: PersistedApiLog
}

final class LogJournal {
    static let shared = LogJournal()
    private init() {}

    /// Opened lazily and kept open — reopening per entry would cost more than
    /// the write itself.
    private var handle: FileHandle?

    /// Guards `handle`. Appends come from the persistence queue, but `truncate`
    /// can arrive from a save on the same queue and `close` from `disable`.
    private let lock = NSLock()

    // MARK: - Writing

    /// Appends one entry. Best-effort: a failed debug write must never surface
    /// to the host app.
    func append(_ log: ApiLog, bucket: LogEventType, session: UUID, options: PersistenceOptions) {
        let entry = JournalEntry(
            bucket: bucket,
            session: session,
            log: PersistedApiLog(log, maxBodyBytes: max(0, options.maxBodyBytes))
        )
        guard var data = try? JSONEncoder().encode(entry) else { return }
        data.append(0x0A) // newline

        lock.lock()
        defer { lock.unlock() }
        guard let handle = openedHandle() else { return }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // The descriptor may have gone stale (archive deleted underneath
            // us); drop it so the next append reopens.
            self.handle = nil
        }
    }

    private func openedHandle() -> FileHandle? {
        if let handle { return handle }
        guard let url = Self.fileURL else { return nil }

        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        }
        handle = try? FileHandle(forWritingTo: url)
        return handle
    }

    // MARK: - Reading

    /// Every entry still in the journal, oldest first.
    ///
    /// Undecodable lines are skipped rather than failing the read — see the
    /// note on crash-safety above.
    func readAll() -> [JournalEntry] {
        guard let url = Self.fileURL,
              let data = try? Data(contentsOf: url),
              !data.isEmpty
        else { return [] }

        let decoder = JSONDecoder()
        var entries: [JournalEntry] = []
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let entry = try? decoder.decode(JournalEntry.self, from: Data(line)) {
                entries.append(entry)
            }
        }
        return entries
    }

    // MARK: - Lifecycle

    /// Empties the journal. Called straight after a successful archive write —
    /// everything in it is now in the archive.
    func truncate() {
        lock.lock()
        defer { lock.unlock() }
        guard let handle = openedHandle() else { return }
        try? handle.truncate(atOffset: 0)
        try? handle.synchronize()
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.close()
        handle = nil
    }

    /// Removes the file entirely, for `clearPersistedLogs()`.
    func delete() {
        close()
        guard let url = Self.fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static var fileURL: URL? {
        LogPersistence.directoryURL?.appendingPathComponent("journal.jsonl")
    }
}
