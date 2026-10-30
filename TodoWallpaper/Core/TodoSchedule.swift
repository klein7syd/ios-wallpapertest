import Foundation

/// Floating calendar components keep a date-only task on the chosen date when
/// the phone changes time zone. No alarm or system-calendar write is implied.
struct TodoSchedule: Codable, Equatable, Sendable {
    let year: Int
    let month: Int
    let day: Int
    let hour: Int?
    let minute: Int?
    var includesTime: Bool { hour != nil }
    init(date: Date, includesTime: Bool, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        year = components.year ?? 2026; month = components.month ?? 1; day = components.day ?? 1
        hour = includesTime ? components.hour : nil; minute = includesTime ? components.minute : nil
    }
    func date(timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour ?? 12, minute: minute ?? 0)) ?? .distantPast
    }
    func validate() throws {
        guard (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day),
              (hour == nil) == (minute == nil), hour.map({ (0...23).contains($0) }) != false,
              minute.map({ (0...59).contains($0) }) != false else { throw TodoDataError.invalidDocument }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let roundtrip = calendar.dateComponents([.year, .month, .day], from: date(timeZone: calendar.timeZone))
        guard roundtrip.year == year, roundtrip.month == month, roundtrip.day == day else { throw TodoDataError.invalidDocument }
    }
    var label: String {
        ScheduleLabelFormatters.shared.string(from: date(), includesTime: includesTime)
    }
}

// Target Membership：App + Widget；格式对象跨线程共用，系统设置变化时失效。
private final class ScheduleLabelFormatters {
    static let shared = ScheduleLabelFormatters()
    private let lock = NSLock()
    private var formats: [Bool: DateFormatter] = [:]
    private var observers: [NSObjectProtocol] = []
    private init() {
        for name in [NSLocale.currentLocaleDidChangeNotification, .NSSystemTimeZoneDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.invalidate()
            })
        }
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    private func invalidate() { lock.lock(); formats.removeAll(); lock.unlock() }
    func string(from date: Date, includesTime: Bool) -> String {
        lock.lock(); defer { lock.unlock() }
        let formatter: DateFormatter
        if let cached = formats[includesTime] { formatter = cached }
        else {
            formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent; formatter.calendar = .autoupdatingCurrent
            formatter.timeZone = .autoupdatingCurrent
            formatter.dateStyle = .short; formatter.timeStyle = includesTime ? .short : .none
            formats[includesTime] = formatter
        }
        return formatter.string(from: date)
    }
}
