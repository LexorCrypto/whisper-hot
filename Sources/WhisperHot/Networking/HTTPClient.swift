import Foundation

/// App-wide URLSession used by every cloud provider (STT + LLM
/// post-processing). Configured to fail fast instead of leaving requests
/// stranded — the default `URLSession.shared` has
/// `timeoutIntervalForResource = 7 days`, which means a request whose TCP
/// socket the kernel closes during sleep can outlive the wake by a literal
/// week without ever surfacing an error.
///
/// Hang-investigation Step 4: bound the resource timeout aggressively and
/// disable connectivity waiting so a wake into a transient no-network
/// state fails fast and the menu bar app returns to `.idle` instead of
/// looking frozen.
enum HTTPClient {
    /// Hard ceiling on a single request's total wall-clock time, including
    /// retries and connectivity recovery. Per-request `URLRequest.timeoutInterval`
    /// overrides still apply and are tighter (60s STT OpenAI/Groq, 120s
    /// OpenRouter audio, 60s LLM post-processing); this value is the
    /// safety net that keeps a stuck request from outliving sleep/wake.
    static let resourceTimeout: TimeInterval = 180

    /// Maximum interval between received data packets — effectively the
    /// read timeout. URLSession's default (60s) is reasonable, repeated
    /// here for visibility.
    static let requestTimeout: TimeInterval = 60

    static let shared: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        return URLSession(configuration: config)
    }()
}
