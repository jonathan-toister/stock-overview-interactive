import Foundation

// IBKR Flex Web Service is a two-step download:
// 1) SendRequest with token + query id -> reference code
// 2) GetStatement with token + reference code -> the report XML
//    (IBKR builds the report on demand; retry while it's not ready)

private let base = "https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService"

/// Which part of the IBKR connection a problem is about, so the setup guide
/// can open on the screen that fixes it.
public enum ConnectionFix: Sendable {
    case queryId
    case token
}

/// A problem talking to IBKR, already worded for the user.
public struct FlexError: LocalizedError, Sendable {
    public var message: String
    /// Set when the fix is to change the token or Query ID
    public var fix: ConnectionFix?
    /// IBKR's error number, when the problem came from IBKR
    public var code: String?

    public init(message: String, fix: ConnectionFix? = nil) {
        self.message = message
        self.fix = fix
    }

    public var errorDescription: String? { message }

    /// Turns IBKR's numbered error codes into plain sentences.
    static func fromIBKR(code: String?, message ibkrMessage: String?) -> FlexError {
        var error = plain(code: code, message: ibkrMessage)
        error.code = code
        return error
    }

    private static func plain(code: String?, message ibkrMessage: String?) -> FlexError {
        switch code {
        case "1012":
            return FlexError(message: "Your IBKR token has expired. Make a new one on the IBKR website — it takes a minute.", fix: .token)
        case "1015":
            return FlexError(message: "IBKR didn't accept the token. Check that you copied the whole number.", fix: .token)
        case "1011":
            return FlexError(message: "Report downloads are switched off for your IBKR account. Turn on the Flex Web Service again.", fix: .token)
        case "1013":
            return FlexError(message: "Your IBKR token only works from certain internet addresses. Make a new token without that limit.", fix: .token)
        case "1014":
            return FlexError(message: "IBKR doesn't recognise that Query ID. Check the number next to your report in the Flex Queries list.", fix: .queryId)
        case "1018":
            return FlexError(message: "IBKR says too many requests were made. Wait a minute and try again.")
        case "1001", "1004", "1005", "1006", "1007", "1008", "1009", "1021":
            return FlexError(message: "IBKR can't produce the report right now. Wait a few minutes and try again.")
        default:
            let detail = ibkrMessage.map { " IBKR said: \($0)" } ?? ""
            return FlexError(message: "IBKR could not produce the report.\(detail)")
        }
    }
}

private func fetchFlex(_ urlString: String) async throws -> FlexResponse {
    guard let url = URL(string: urlString) else {
        throw FlexError(message: "The token or Query ID contains characters that can't be right. Paste them again.")
    }
    var request = URLRequest(url: url, timeoutInterval: 60)
    request.setValue("stock-overview-interactive", forHTTPHeaderField: "User-Agent")
    let data: Data
    let response: URLResponse
    do {
        (data, response) = try await URLSession.shared.data(for: request)
    } catch {
        throw FlexError(message: "Couldn't reach IBKR. Check your internet connection and try again.")
    }
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw FlexError(message: "The IBKR report service returned an error (HTTP \(http.statusCode)). Try again later.")
    }
    return try parseFlexXML(data)
}

private func encode(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
}

/// Pass `from`/`to` (yyyy-MM-dd, at most 365 days apart) to ask for those dates
/// instead of the Period saved in the query on IBKR.
public func fetchFlexStatement(token: String, queryId: String, from: String? = nil, to: String? = nil) async throws -> FlexStatement {
    var range = ""
    if let from, let to {
        range = "&fd=\(from.replacingOccurrences(of: "-", with: ""))&td=\(to.replacingOccurrences(of: "-", with: ""))"
    }
    let send = try await fetchFlex("\(base)/SendRequest?t=\(encode(token))&q=\(encode(queryId))&v=3\(range)")
    guard case .status(let sendResp) = send, sendResp["Status"] == "Success",
          let refCode = sendResp["ReferenceCode"] else {
        if case .status(let s) = send { throw FlexError.fromIBKR(code: s["ErrorCode"], message: s["ErrorMessage"]) }
        throw FlexError(message: "IBKR sent back an unexpected reply. Try again in a minute.")
    }
    let statementUrl = sendResp["Url"] ?? "\(base)/GetStatement"

    // Poll until the report is generated (usually a few seconds)
    var delay = 2.0
    for _ in 0..<8 {
        try await Task.sleep(for: .seconds(delay))
        let result = try await fetchFlex("\(statementUrl)?t=\(encode(token))&q=\(encode(refCode))&v=3")
        switch result {
        case .statement(let stmt):
            guard let stmt else { throw FlexError(message: "IBKR returned an empty report.") }
            return stmt
        case .status(let status):
            // 1019 = report still being generated
            if status["ErrorCode"] != "1019" {
                throw FlexError.fromIBKR(code: status["ErrorCode"], message: status["ErrorMessage"])
            }
        }
        delay = min(delay * 1.5, 15)
    }
    throw FlexError(message: "IBKR took too long to produce the report. Try again in a few minutes.")
}
