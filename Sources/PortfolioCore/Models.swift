import Foundation

// Shared data shapes, also the layout of the cached account.json. All money
// amounts are in the position's own currency unless stated otherwise.

public struct Position: Codable, Hashable, Sendable {
    public var symbol: String
    public var description: String
    public var quantity: Double
    /// Total amount paid for the shares currently held
    public var costBasis: Double
    /// Average price paid per share
    public var avgCost: Double
    /// Price and value as of the last IBKR report snapshot
    public var snapshotPrice: Double
    public var snapshotValue: Double
    public var currency: String
}

public enum TradeSide: String, Codable, Sendable {
    case buy = "BUY"
    case sell = "SELL"
}

public struct Trade: Codable, Hashable, Sendable {
    public var date: String // yyyy-MM-dd
    public var symbol: String
    public var description: String
    public var side: TradeSide
    public var quantity: Double
    public var price: Double
    /// Total money the trade moved (positive number)
    public var amount: Double
    public var currency: String
}

public struct Dividend: Codable, Hashable, Sendable {
    public var date: String // yyyy-MM-dd
    public var symbol: String
    public var description: String
    /// Amount the company paid you, before tax
    public var amount: Double
    /// Tax automatically withheld from the payment (0 if none reported)
    public var taxWithheld: Double
    /// What actually landed in your account
    public var netAmount: Double
    public var currency: String
    /// Whether the money was used to buy more shares (best-effort guess).
    /// nil = could not tell.
    public var reinvested: Bool?
}

public struct Balances: Codable, Hashable, Sendable {
    /// Cash in the account, in the account's base currency
    public var cash: Double
    public var currency: String
}

public struct AccountData: Codable, Sendable {
    public var positions: [Position]
    public var trades: [Trade]
    public var dividends: [Dividend]
    public var balances: Balances
    /// When we downloaded the report (ISO timestamp)
    public var fetchedAt: String
    /// The date the report data is "as of"
    public var reportDate: String?
    /// The first day the report's trades and dividends cover (yyyy-MM-dd)
    public var periodStart: String?

    public var fetchedDate: Date {
        ISO8601DateFormatter.withFractions.date(from: fetchedAt)
            ?? ISO8601DateFormatter().date(from: fetchedAt)
            ?? .distantPast
    }
}

/// A position with today's price filled in (from Yahoo when available).
public struct EnrichedPosition: Hashable, Sendable, Identifiable {
    public var id: String { position.symbol }
    public var position: Position
    public var name: String
    public var currentPrice: Double
    public var currentValue: Double
    /// Worth now − what you paid
    public var gainLoss: Double
    public var gainLossPercent: Double?
    public var changeTodayPercent: Double?
    /// false = Yahoo had no price, so this is the price from the last IBKR report
    public var priceIsLive: Bool

    public var symbol: String { position.symbol }
    public var currency: String { position.currency }
}

public struct Summary: Sendable {
    /// Stocks + cash
    public var totalValue: Double
    /// What the stocks are worth now
    public var investedValue: Double
    /// What you paid for the stocks you hold
    public var totalPaid: Double
    public var gainLoss: Double
    public var cash: Double
    public var currency: String
    /// Dividends received this calendar year, after tax
    public var dividendsThisYear: Double
    public var positionCount: Int
    public var lastUpdated: Date
    public var reportDate: String?

    public var gainLossPercent: Double? {
        totalPaid != 0 ? gainLoss / totalPaid * 100 : nil
    }
}

extension ISO8601DateFormatter {
    static let withFractions: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
