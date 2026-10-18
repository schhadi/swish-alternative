import Foundation

extension Date {
    /// Row subtitle: "14:05" today, "Yesterday", a weekday within the last week, else "14 Oct" (with year if not this year).
    var quidRelativeDescription: String {
        let calendar = Calendar.current
        let now = Date()
        if calendar.isDateInToday(self) {
            return formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(self) {
            return "Yesterday"
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)), self >= weekAgo {
            return formatted(.dateTime.weekday(.wide))
        }
        if calendar.isDate(self, equalTo: now, toGranularity: .year) {
            return formatted(.dateTime.day().month(.abbreviated))
        }
        return formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// Activity section title: "Today", "Yesterday", else "Tuesday 14 October" (with year if not this year).
    var quidSectionTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return "Today"
        }
        if calendar.isDateInYesterday(self) {
            return "Yesterday"
        }
        if calendar.isDate(self, equalTo: Date(), toGranularity: .year) {
            return formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    /// Receipt timestamps: "14 Oct 2026 at 14:05".
    var quidReceiptDescription: String {
        formatted(date: .abbreviated, time: .shortened)
    }

    /// Due dates: "Due 24 Oct" / "Due today" / "Overdue".
    var quidDueDescription: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return "Due today"
        }
        if self < Date() {
            return "Overdue"
        }
        return "Due \(formatted(.dateTime.day().month(.abbreviated)))"
    }
}
