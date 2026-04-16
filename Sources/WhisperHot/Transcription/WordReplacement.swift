import Foundation

/// A single find-and-replace rule applied to transcripts after STT.
/// Case-insensitive matching, preserves surrounding whitespace.
struct WordReplacement: Codable, Identifiable, Equatable {
    var id: UUID
    var from: String
    var to: String

    init(id: UUID = UUID(), from: String, to: String) {
        self.id = id
        self.from = from
        self.to = to
    }

    /// Apply this replacement to text (case-insensitive).
    func apply(to text: String) -> String {
        guard !from.isEmpty else { return text }
        return text.replacingOccurrences(
            of: from,
            with: self.to,
            options: [.caseInsensitive],
            range: nil
        )
    }

    /// Built-in defaults for common tech terms that STT often misrecognizes.
    static let defaults: [WordReplacement] = [
        WordReplacement(from: "коммит", to: "commit"),
        WordReplacement(from: "деплой", to: "deploy"),
        WordReplacement(from: "пуш", to: "push"),
        WordReplacement(from: "пул", to: "pull"),
        WordReplacement(from: "мёрж", to: "merge"),
        WordReplacement(from: "мерж", to: "merge"),
        WordReplacement(from: "кодекс", to: "Codex"),
        WordReplacement(from: "опенклоу", to: "OpenClaw"),
        WordReplacement(from: "клауд", to: "Claude"),
        WordReplacement(from: "гитхаб", to: "GitHub"),
        WordReplacement(from: "докер", to: "Docker"),
        WordReplacement(from: "кубернетес", to: "Kubernetes"),
        WordReplacement(from: "эндпоинт", to: "endpoint"),
        WordReplacement(from: "бэкенд", to: "backend"),
        WordReplacement(from: "фронтенд", to: "frontend"),
        WordReplacement(from: "фреймворк", to: "framework"),
    ]

    /// Apply all replacements in order.
    static func applyAll(_ replacements: [WordReplacement], to text: String) -> String {
        var result = text
        for r in replacements {
            result = r.apply(to: result)
        }
        return result
    }
}
