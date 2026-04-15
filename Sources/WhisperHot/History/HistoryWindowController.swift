import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by HistoryWindowController's show() so the hosted SwiftUI
    /// view re-reads the store every time the window appears.
    static let whisperHotHistoryWillShow = Notification.Name("WhisperHot.historyWillShow")
}

@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private let store: HistoryStore
    private var window: NSWindow?
    private var previousApp: NSRunningApplication?

    init(store: HistoryStore) {
        self.store = store
        super.init()
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }

        if window == nil {
            buildWindow()
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .whisperHotHistoryWillShow, object: nil)
    }

    private func buildWindow() {
        let hosting = NSHostingView(rootView: HistoryView(store: store))
        hosting.frame = NSRect(x: 0, y: 0, width: 640, height: 520)

        let w = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "WhisperHot History"
        w.isReleasedWhenClosed = false
        w.contentView = hosting
        w.center()
        w.delegate = self
        self.window = w
    }

    func windowWillClose(_ notification: Notification) {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ourPID {
            previousApp?.activate(options: [])
        }
        previousApp = nil
    }
}

private struct HistoryView: View {
    let store: HistoryStore
    @State private var records: [TranscriptRecord] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar

            Divider()

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            if records.isEmpty {
                emptyState
            } else {
                List(records) { record in
                    rowView(for: record)
                        .contextMenu {
                            Button("Copy to clipboard") { copy(record) }
                        }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 600, minHeight: 480)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .whisperHotHistoryWillShow)) { _ in
            reload()
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Text("\(records.count) transcript\(records.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button("Reload") { reload() }
            Button("Clear all…") { confirmClear() }
                .foregroundColor(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No transcripts yet")
                .font(.title3)
            Text("Enable history in Settings, then record something.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rowView(for record: TranscriptRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(record.providerModel)
                    .font(.caption2)
                    .foregroundColor(.tertiaryLabelColor)
                Spacer()
                Button("Copy") { copy(record) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
            // `.lineLimit(3)` alone would bound visual wrap rather than
            // newline-delimited lines, so we slice by newlines first.
            Text(record.preview(lines: 3))
                .font(.system(size: 12))
                .lineLimit(3)
                .truncationMode(.tail)
                .foregroundColor(.primary)
            if let model = record.postProcessingModel, let preset = record.postProcessingPreset {
                Text("post-processed via \(model) (\(preset))")
                    .font(.caption2)
                    .foregroundColor(.tertiaryLabelColor)
            } else if record.postProcessingFailed == true {
                Text("post-processing failed: \(record.postProcessingFailureReason ?? "unknown")")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func reload() {
        do {
            try store.loadIfNeeded()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        records = store.records
    }

    private func copy(_ record: TranscriptRecord) {
        let pb = NSPasteboard.general
        pb.clearContents()
        _ = pb.setString(record.text, forType: .string)
    }

    private func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "Clear all transcripts?"
        alert.informativeText = "This deletes the encrypted history file. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try store.clear()
                records = []
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private extension Color {
    static var tertiaryLabelColor: Color {
        Color(nsColor: NSColor.tertiaryLabelColor)
    }
}
