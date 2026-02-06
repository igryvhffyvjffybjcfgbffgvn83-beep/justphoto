import Foundation
import GRDB

// PRD counters:
// - workset_count: count(items present in the session workset)
//   - capture_failed creates no session_item, so it is excluded by construction.
// - in_flight_count: count(items where state in {captured_preview, writing})
enum WorksetCounter {
    struct Counts: Sendable, Equatable {
        let worksetCount: Int
        let inFlightCount: Int
    }

    static let worksetStates: Set<SessionItemState> = [
        .captured_preview,
        .writing,
        .write_failed,
        .finalized,
    ]

    static let inFlightStates: Set<SessionItemState> = [
        .captured_preview,
        .writing,
    ]

    static func compute(stateCounts: [SessionItemState: Int]) -> Counts {
        var workset = 0
        var inflight = 0

        for (state, count) in stateCounts {
            if worksetStates.contains(state) {
                workset += count
            }
            if inFlightStates.contains(state) {
                inflight += count
            }
        }

        return Counts(worksetCount: workset, inFlightCount: inflight)
    }

    static func fetch(db: Database, sessionId: String) throws -> Counts {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT state, COUNT(*) AS c FROM session_items WHERE session_id = ? GROUP BY state",
            arguments: [sessionId]
        )

        var map: [SessionItemState: Int] = [:]
        map.reserveCapacity(rows.count)
        for row in rows {
            let raw: String = row["state"]
            guard let state = SessionItemState(rawValue: raw) else { continue }
            let count: Int = row["c"]
            map[state] = count
        }

        return compute(stateCounts: map)
    }
}
