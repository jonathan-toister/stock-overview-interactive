import SwiftUI

// Number and date formatting.

enum Fmt {
    private static func currencyStyle(_ currency: String, digits: Int) -> FloatingPointFormatStyle<Double>.Currency {
        .currency(code: currency).precision(.fractionLength(digits)).locale(Locale(identifier: "en_US"))
    }

    static func money(_ v: Double, _ currency: String = "USD") -> String {
        v.formatted(currencyStyle(currency, digits: 2))
    }

    /// Whole amounts for big totals, where cents would just be noise
    static func money0(_ v: Double, _ currency: String = "USD") -> String {
        v.formatted(currencyStyle(currency, digits: 0))
    }

    static func signedMoney(_ v: Double, _ currency: String = "USD") -> String {
        (v > 0 ? "+" : "") + money(v, currency)
    }

    static func signedMoney0(_ v: Double, _ currency: String = "USD") -> String {
        (v > 0 ? "+" : "") + money0(v, currency)
    }

    /// Big amounts shortened to something readable: $2.9T, $466.8B
    static func compactMoney(_ v: Double, _ currency: String = "USD") -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .currency
        f.currencyCode = currency
        let symbol = f.currencySymbol ?? ""
        let units: [(Double, String)] = [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")]
        for (size, suffix) in units where abs(v) >= size {
            let n = (v / size).formatted(.number.precision(.fractionLength(0...1)))
            return "\(symbol)\(n)\(suffix)"
        }
        return money0(v, currency)
    }

    /// 1.234 → "+1.2%"
    static func percent(_ v: Double, digits: Int = 1) -> String {
        (v > 0 ? "+" : "") + String(format: "%.\(digits)f%%", v)
    }

    /// A fraction as a plain percentage: 0.0345 → "3.5%"
    static func rate(_ fraction: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", fraction * 100)
    }

    /// Same, with a + or − so it reads as a move: 0.307 → "+30.7%"
    static func signedRate(_ fraction: Double, digits: Int = 1) -> String {
        percent(fraction * 100, digits: digits)
    }

    static func shares(_ q: Double) -> String {
        let n = q.formatted(.number.precision(.fractionLength(0...4)))
        return "\(n) \(q == 1 ? "share" : "shares")"
    }

    static func number(_ q: Double) -> String {
        q.formatted(.number.precision(.fractionLength(0...4)))
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func day(_ iso: String) -> Date? { dayParser.date(from: iso) }

    /// "5 Mar 2025"
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "en_GB")))
    }

    static func shortDate(_ iso: String) -> String {
        day(iso).map(shortDate) ?? iso
    }

    static func timeAgo(_ date: Date, now: Date = Date()) -> String {
        let mins = Int((now.timeIntervalSince(date) / 60).rounded())
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins) min ago" }
        let hours = Int((Double(mins) / 60).rounded())
        if hours < 24 { return "\(hours) hour\(hours == 1 ? "" : "s") ago" }
        let days = Int((Double(hours) / 24).rounded())
        return "\(days) day\(days == 1 ? "" : "s") ago"
    }
}

extension Color {
    /// Green for gains, red for losses, plain for zero
    static func gain(_ v: Double?) -> Color {
        guard let v else { return .secondary }
        return v > 0 ? .green : v < 0 ? .red : .secondary
    }
}
