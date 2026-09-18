//
//  LogPersistence.swift
//  ApiLogKit
//
//  Writes the log buckets to disk so they survive a relaunch — the logs that
//  explain a crash are usually the ones destroyed by it.
//
//  Writes are debounced rather than per-entry (a chatty app would otherwise hit
//  the disk constantly) and flushed on backgrounding, which is the last reliable
//  moment before the process can be killed.
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

    // MARK: - Reading

    /// Reads and decodes off the main thread — this runs at launch, and the
    /// archive can be several megabytes.
    ///
    /// Restored entries are prepended, so logs recorded while the read is in
    /// flight still end up after them.
    private func restore() {
        io.async {
            guard let url = Self.fileURL,
                  let data = try? Data(contentsOf: url),
                  let archive = try? JSONDecoder().decode(PersistedLogArchive.self, from: data),
                  archive.version == PersistedLogArchive.currentVersion
            else { return }

            ApiLogger.shared.restore(
                api: archive.api.map { $0.toApiLog() },
                eventTracker: archive.eventTracker.map { $0.toApiLog() },
                thirdParty: archive.thirdParty.map { $0.toApiLog() }
            )
        }
    }

    // MARK: - Writing

    private func save() {
        guard isEnabled, let url = Self.fileURL else { return }

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
    }

    /// Trims to the retention budget and drops in-flight entries.
    ///
    /// A restored pending entry could never complete, and its spinner would imply
    /// activity that isn't happening — so those are left out rather than frozen
    /// into the archive.
    private static func prepare(_ logs: [ApiLog], options: PersistenceOptions) -> [PersistedApiLog] {
        logs
            .filter { $0.state == .finished }
            .suffix(max(0, options.maxEntries))
            .map { PersistedApiLog($0, maxBodyBytes: max(0, options.maxBodyBytes)) }
    }

    // MARK: - Files

    /// Application Support rather than Caches: the OS may evict Caches under disk
    /// pressure, which would quietly lose exactly what this feature exists for.
    static var fileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ApiLogKit", isDirectory: true)
            .appendingPathComponent("logs.json")
    }

    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = url
        try? url.setResourceValues(values)
    }

    /// Removes the archive from disk.
    func deleteArchive() {
        guard let url = Self.fileURL else { return }
        io.async { try? FileManager.default.removeItem(at: url) }
    }
}
