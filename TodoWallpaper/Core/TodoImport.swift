import Foundation
import CryptoKit

struct TodoImportCandidate: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let detail: String
    let isCompleted: Bool
    let sortDate: Date
    func item(now: Date = .now) -> TodoItem {
        TodoItem(id: id, title: title, isCompleted: isCompleted, createdAt: now, updatedAt: now)
    }
}
enum TodoImportIdentity {
    /// Stable local source identity, never an Apple Account or device identifier.
    /// Length prefixes prevent ambiguous concatenation; recurrence is per occurrence.
    static func make(source: String, calendar: String, item: String, occurrence: String = "single") -> UUID {
        let key = [source, calendar, item, occurrence].map { "\($0.utf8.count):\($0)" }.joined()
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
