import AppKit
import Foundation

/// Checks GitHub Releases for new versions of WhisperHot.
/// Caches result for 1 hour to respect API rate limits (60 req/h unauthenticated).
@MainActor
final class UpdateChecker: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate(version: String)
        case updateAvailable(current: String, latest: String, downloadURL: String)
        case failed(message: String)
    }

    @Published private(set) var status: Status = .idle

    private let repoOwner = "LexorCrypto"
    private let repoName = "whisper-hot"
    private var lastCheckDate: Date?

    /// Current app version from Info.plist.
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private var isChecking = false

    /// Check for updates. Respects 1-hour cache.
    func check(force: Bool = false) async {
        // In-flight guard
        guard !isChecking else { return }

        if !force, let lastCheck = lastCheckDate,
           Date().timeIntervalSince(lastCheck) < 3600 {
            return // cached, skip
        }

        isChecking = true
        defer { isChecking = false }
        status = .checking

        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            status = .failed(message: "Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                status = .failed(message: "Invalid response")
                return
            }

            // Cache the attempt time regardless of outcome to avoid
            // hammering the API on repeated taps during errors.
            lastCheckDate = Date()

            if http.statusCode == 403 || http.statusCode == 429 {
                status = .failed(message: L10n.lang == .ru
                    ? "Превышен лимит запросов GitHub API. Попробуйте позже."
                    : "GitHub API rate limit exceeded. Try again later.")
                return
            }

            guard (200..<300).contains(http.statusCode) else {
                status = .failed(message: "HTTP \(http.statusCode)")
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            let latestVersion = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName

            let current = currentVersion

            if compareVersions(current, latestVersion) == .orderedAscending {
                // Find DMG asset
                let dmgAsset = release.assets.first { $0.name.hasSuffix(".dmg") }
                let downloadURL = dmgAsset?.browserDownloadURL ?? release.htmlURL

                status = .updateAvailable(
                    current: current,
                    latest: latestVersion,
                    downloadURL: downloadURL
                )
            } else {
                status = .upToDate(version: current)
            }
        } catch {
            status = .failed(message: error.localizedDescription)
        }
    }

    /// Open the download URL in the default browser.
    func openDownload() {
        guard case .updateAvailable(_, _, let urlString) = status,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Semver comparison

    private func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        let count = max(aParts.count, bParts.count)
        for i in 0..<count {
            let av = i < aParts.count ? aParts[i] : 0
            let bv = i < bParts.count ? bParts[i] : 0
            if av < bv { return .orderedAscending }
            if av > bv { return .orderedDescending }
        }
        return .orderedSame
    }
}

// MARK: - GitHub API model

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}
