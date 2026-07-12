import Foundation
import os.signpost

enum NPPerformanceTrace {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "NotePatch",
        category: .pointsOfInterest
    )

    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        #if DEBUG
        os_signpost(.begin, log: log, name: name, signpostID: id)
        #endif
        return id
    }

    static func end(_ name: StaticString, id: OSSignpostID) {
        #if DEBUG
        os_signpost(.end, log: log, name: name, signpostID: id)
        #endif
    }
}
