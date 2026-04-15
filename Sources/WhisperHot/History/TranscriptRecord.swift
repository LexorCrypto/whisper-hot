import Foundation

/// A single transcript entry persisted to the encrypted history file.
/// Flattened on purpose: flat fields survive schema evolution better than
/// associated-value enums inside a JSON blob.
struct TranscriptRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let text: String
    let providerModel: String
    let postProcessingModel: String?
    let postProcessingPreset: String?
    let postProcessingFailed: Bool?
    let postProcessingFailureReason: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        text: String,
        providerModel: String,
        postProcessing: PostProcessingOutcome? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.providerModel = providerModel
        switch postProcessing {
        case .succeeded(let model, let preset):
            self.postProcessingModel = model
            self.postProcessingPreset = preset
            self.postProcessingFailed = false
            self.postProcessingFailureReason = nil
        case .failed(let reason):
            self.postProcessingModel = nil
            self.postProcessingPreset = nil
            self.postProcessingFailed = true
            self.postProcessingFailureReason = reason
        case .none:
            self.postProcessingModel = nil
            self.postProcessingPreset = nil
            self.postProcessingFailed = nil
            self.postProcessingFailureReason = nil
        }
    }

    var firstLine: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let newlineRange = trimmed.range(of: "\n") {
            return String(trimmed[..<newlineRange.lowerBound])
        }
        return trimmed
    }

    /// First N newline-delimited lines joined back with newlines, for list
    /// row previews. SwiftUI's `.lineLimit` only bounds layout wrap, not
    /// semantic lines — so we compute the real lines here.
    func preview(lines: Int = 3) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let chunks = trimmed.components(separatedBy: "\n").prefix(lines)
        return chunks.joined(separator: "\n")
    }
}
