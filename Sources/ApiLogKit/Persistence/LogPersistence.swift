//
//  LogPersistence.swift
//  ApiLogKit
//
//  Writes the log buckets to disk so they survive a relaunch — the logs that
//  explain a crash are usually the ones destroyed by it.
//
//  Storage is in two parts. The **archive** holds the bulk: it is rewritten
//  whole, so saves are debounced and flushed on backgrounding. The **journal**
//  is the write-ahead tail in front of it, appended per entry so nothing waits
//  on a debounce; a save writes the archive and then truncates the journal,
//  which is what compaction amounts to here.
//
//  That split is what makes a crash survivable. A foreground crash arrives long
//  before any debounce fires, so before the journal existed the response that
//  caused it was lost with the process — see `LogJournal` and `CrashRecorder`.
//

import Combine
import Foundation
import UIKit

final class LogPersistence {
    static let shared = LogPersistence()
    private init() {}

    private var cancellables = Set<AnyCancellable>()
    private let io = DispatchQueue(label: "apilogkit.persistence.queue", qos: .utility)
    private var isEnabled = false

    /// Identifies this run in the journal, so a crash blames only the entries
    /// this run recorded.
    private(set) var sessionID = UUID()

    // MARK: - Lifecycle

    /// Loads anything already on disk into the logger, then starts saving.
    func enable() {
        guard !isEnabled else { return }
        isEnabled = true

        restore()
        observeChanges()
        observeBackgrounding()
    }

    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        cancellables.removeAll()
        LogJournal.shared.close()
    }

    private func observeChanges() {
        let logger = ApiLogger.shared
        Publishers.Merge3(
            logger.logsPublisher.map { _ in () },
            logger.eventTrackerLogsPublisher.map { _ in () },
            logger.thirdPartyLogsPublisher.map { _ in () }
        )
        .debounce(for: .seconds(2), scheduler: io)
        .sink { [weak self] in self?.save() }
        .store(in: &cancellables)
    }

    /// Backgrounding is the last dependable checkpoint — a debounce in flight
    /// would otherwise be lost if the system kills the app while suspended.
    private func observeBackgrounding() {
        NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.io.async { self?.save() } }
            .store(in: &cancellables)
    }

    // MARK: - Recording

    /// Appends one entry to the journal, as it is captured.
    ///
    /// Called for both halves of an in-flight entry: once when the request goes
    /// out, once when the response lands. The reader keeps the last line per id,
    /// so the pair collapses back into a single entry.
    ///
    /// Written inline rather than hopped onto `io`. The caller is already on the
    /// logger's serial queue — off the main thread — and every queue hop between
    /// capturing an entry and it reaching disk is a window in which a crash
    /// loses it. One hop is the least this can be without blocking the caller;
    /// see the note on the residual window in `CrashRecorder`.
    func record(_ log: ApiLog, bucket: LogEventType) {
        guard isEnabled else { return }
        LogJournal.shared.append(
            log,
            bucket: bucket,
            session: sessionID,
            options: ApiLogKitConfig.persistence
        )
    }

    // MARK: - Reading

    /// Reads and decodes off the main thread — this runs at launch, and the
    /// archive can be several megabytes.
    ///
    /// Restored entries are prepended, so logs recorded while the read is in
    /// flight still end up after them.
    private func restore() {
        io.async { [self] in
            let options = ApiLogKitConfig.persistence

            // The crash record has to be consumed before the recorder installs:
            // opening the signal file truncates it.
            let report = options.captureCrashes
                ? CrashRecorder.shared.readPendingReport()
                : nil

            var buckets = loadBuckets(options: options)
            if let report {
                CrashSuspects.apply(report, to: &buckets.api, sessions: buckets.sessions)
            }

            ApiLogger.shared.restore(
                api: buckets.api,
                eventTracker: buckets.eventTracker,
                thirdParty: buckets.thirdParty,
                crash: report
            )

            if options.captureCrashes {
                CrashRecorder.shared.clearPendingReport()
                CrashRecorder.shared.install(sessionID: sessionID)
            }
        }
    }

    private struct Buckets {
        var api: [ApiLog] = []
        var eventTracker: [ApiLog] = []
        var thirdParty: [ApiLog] = []
        /// Entry id → the run that recorded it, for `CrashSuspects`. Only
        /// journal lines carry a session; archived entries predate the crash.
        var sessions: [UUID: UUID] = [:]
    }

    /// Merges the archive with the journal tail.
    ///
    /// Journal lines win: they are newer by construction, and a line written
    /// after the last save is the only record of that entry. An id appearing in
    /// both means a save wrote the archive but didn't get to truncate, which
    /// this collapses rather than duplicating.
    private func loadBuckets(options: PersistenceOptions) -> Buckets {
        var ordered: [LogEventType: [UUID]] = [:]
        var persisted: [UUID: PersistedApiLog] = [:]
        var sessions: [UUID: UUID] = [:]

        func absorb(_ log: PersistedApiLog, bucket: LogEventType, session: UUID?) {
            if persisted[log.id] == nil {
                ordered[bucket, default: []].append(log.id)
            }
            persisted[log.id] = log
            if let session { sessions[log.id] = session }
        }

        if let url = Self.archiveURL,
           let data = try? Data(contentsOf: url),
           let archive = try? JSONDecoder().decode(PersistedLogArchive.self, from: data),
           archive.version == PersistedLogArchive.currentVersion {
            archive.api.forEach { absorb($0, bucket: .api, session: nil) }
            archive.eventTracker.forEach { absorb($0, bucket: .eventTracker, session: nil) }
            archive.thirdParty.forEach { absorb($0, bucket: .thirdParty, session: nil) }
        }

        for entry in LogJournal.shared.readAll() {
            absorb(entry.log, bucket: entry.bucket, session: entry.session)
        }

        let limit = max(0, options.maxEntries)
        func bucket(_ type: LogEventType) -> [ApiLog] {
            (ordered[type] ?? []).suffix(limit).compactMap { persisted[$0]?.toApiLog() }
        }

        return Buckets(
            api: bucket(.api),
            eventTracker: bucket(.eventTracker),
            thirdParty: bucket(.thirdParty),
            sessions: sessions
        )
    }

    // MARK: - Writing

    private func save() {
        guard isEnabled, let url = Self.archiveURL else { return }

        let options = ApiLogKitConfig.persistence
        let logger = ApiLogger.shared
        let archive = PersistedLogArchive(
            api: Self.prepare(logger.getLogs(), options: options),
            eventTracker: Self.prepare(logger.getEventTrackerLogs(), options: options),
            thirdParty: Self.prepare(logger.getThirdPartyLogs(), options: options)
        )

        guard let data = try? JSONEncoder().encode(archive) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // `.completeUntilFirstUserAuthentication` keeps the file encrypted at rest
        // while still allowing a background write after the device has been
        // unlocked once.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        Self.excludeFromBackup(url)

        // Only now is the journal redundant. Truncating before the archive
        // landed would risk losing both copies.
        LogJournal.shared.truncate()
    }

    /// Trims to the retention budget.
    ///
    /// In-flight entries are kept, where they used to be filtered out. The old
    /// reasoning — that a restored pending entry can never complete, so its
    /// spinner would imply activity that isn't happening — was right about the
    /// spinner and wrong about the entry: a request that was in flight when the
    /// app died is precisely what you want to see afterwards. The UI shows it
    /// as *No response* instead.
    private static func prepare(_ logs: [ApiLog], options: PersistenceOptions) -> [PersistedApiLog] {
        logs
            .suffix(max(0, options.maxEntries))
            .map { PersistedApiLog($0, maxBodyBytes: max(0, options.maxBodyBytes)) }
    }

    // MARK: - Files

    /// Application Support rather than Caches: the OS may evict Caches under disk
    /// pressure, which would quietly lose exactly what this feature exists for.
    static var directoryURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ApiLogKit", isDirectory: true)
    }

    static var archiveURL: URL? {
        directoryURL?.appendingPathComponent("logs.json")
    }

    /// Retained under its original name for source compatibility.
    static var fileURL: URL? { archiveURL }

    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = url
        try? url.setResourceValues(values)
    }

    /// Removes everything on disk — archive, journal and any crash record.
    func deleteArchive() {
        io.async {
            if let url = Self.archiveURL {
                try? FileManager.default.removeItem(at: url)
            }
            LogJournal.shared.delete()
            CrashRecorder.shared.clearPendingReport()
        }
    }
}
