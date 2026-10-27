//
//  CrashSuspects.swift
//  ApiLogKit
//
//  Decides which restored entries a crash is allowed to blame.
//
//  Unlike the Android counterpart, nothing is marked at crash time: a signal
//  handler cannot safely build a list of ids. Everything needed is already in
//  the journal, so the blame is worked out on the next launch instead — which
//  also keeps the rule in one pure function that can be tested directly.
//

import Foundation

enum CrashSuspects {

    /// Returns the ids of the entries `report` should be pinned to.
    ///
    /// Two kinds qualify, answering different questions:
    ///
    /// * **Everything still in flight.** A request that never came back is the
    ///   prime suspect, and the entry that would otherwise be hardest to
    ///   reconstruct after the fact.
    /// * **The newest finished entry.** A crash that follows a response by
    ///   milliseconds is almost always the app choking on *that* payload — a
    ///   missing field, a null where a string was promised.
    ///
    /// Only entries from the crashed run are eligible. Without that, an app
    /// that launched, sat idle and crashed would pin the blame on the last
    /// response of a previous run — confidently, and wrongly. `sessions` maps
    /// each entry id to the run that recorded it; an entry with no known
    /// session (restored from the archive, whose lines predate the crash) is
    /// never blamed.
    static func identify(
        api: [ApiLog],
        sessions: [UUID: UUID],
        report: CrashReport
    ) -> Set<UUID> {
        let fromCrashedRun = api.filter { sessions[$0.id] == report.sessionID }
        guard !fromCrashedRun.isEmpty else { return [] }

        var suspects = Set(fromCrashedRun.filter { $0.state == .pending }.map(\.id))
        if let lastFinished = fromCrashedRun.last(where: { $0.state == .finished }) {
            suspects.insert(lastFinished.id)
        }
        return suspects
    }

    /// Applies `report` to the entries it is allowed to blame.
    static func apply(
        _ report: CrashReport,
        to api: inout [ApiLog],
        sessions: [UUID: UUID]
    ) {
        let suspects = identify(api: api, sessions: sessions, report: report)
        guard !suspects.isEmpty else { return }
        for index in api.indices where suspects.contains(api[index].id) {
            api[index].markCrashed(with: report)
        }
    }
}
