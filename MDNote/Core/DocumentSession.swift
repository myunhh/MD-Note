import SwiftUI
import UIKit

/// A single orphaned-ink entry shown in the tray, with a rendered thumbnail and
/// a human-readable label so it's distinguishable (incl. to VoiceOver).
struct OrphanItem: Identifiable {
    let id: UUID
    let image: UIImage
    let label: String
}

/// What a transient status message means — drives its icon/affordance.
enum ToastKind: Equatable { case info, progress, success, error }

struct Toast: Equatable {
    var text: String
    var kind: ToastKind
}

/// Shared state between the SwiftUI shell and the UIKit document canvas.
/// The canvas pushes status + orphans up; the tray UI calls back down for
/// delete / restore actions.
@MainActor
final class DocumentSession: ObservableObject {
    @Published var toast: Toast?
    @Published var orphans: [OrphanItem] = []
    @Published var toolsVisible = true
    @Published var paperStyle: String = UserDefaults.standard.string(forKey: "paperStyle") ?? "plain"
    @Published var textScale: Double = UserDefaults.standard.object(forKey: "textScale") as? Double ?? 1.0
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var fingerDrawing = UserDefaults.standard.bool(forKey: "fingerDrawing")
    @Published var outline: [OutlineItem] = []
    @Published var docStats: DocStats?

    /// Monotonic haptic triggers — bumped by the controller, consumed by
    /// `.sensoryFeedback` in the document view.
    @Published private(set) var selectionTick = 0
    @Published private(set) var successTick = 0
    @Published private(set) var impactTick = 0

    weak var controller: DocumentCanvasViewController?
    private var statusDismiss: DispatchWorkItem?

    var orphanCount: Int { orphans.count }

    /// Show a transient status capsule. `.progress` stays until explicitly
    /// cleared (e.g. a long export); the rest auto-dismiss.
    func flash(_ text: String, kind: ToastKind = .info, duration: TimeInterval = 4) {
        toast = Toast(text: text, kind: kind)
        statusDismiss?.cancel()
        statusDismiss = nil
        guard kind != .progress else { return }
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        statusDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// Clear the status capsule AND tear down any pending auto-dismiss timer, so
    /// a stale timer can't later clobber a fresh message.
    func clearStatus() {
        statusDismiss?.cancel()
        statusDismiss = nil
        toast = nil
    }

    func hapticSelection() { selectionTick &+= 1 }
    func hapticSuccess() { successTick &+= 1 }
    func hapticImpact() { impactTick &+= 1 }

    func deleteOrphan(_ id: UUID) { controller?.deleteOrphan(id) }
    func restoreOrphan(_ id: UUID) { controller?.restoreOrphan(id) }

    func toggleTools() { controller?.toggleToolPicker() }
    func undo() { controller?.undo() }
    func redo() { controller?.redo() }
    func setPaper(_ style: String) { controller?.setPaper(style) }
    func setTextScale(_ scale: Double) { controller?.setTextScale(scale) }
    func setFingerDrawing(_ enabled: Bool) { controller?.setFingerDrawing(enabled) }
    func scroll(to item: OutlineItem) { controller?.scroll(toDocumentY: item.y) }
    func exportPDF() { controller?.exportPDF() }
    func shareSource() { controller?.shareSource() }
}

/// The bottom-sheet tray listing handwriting that lost its anchor block after an
/// external markdown edit. Nothing is ever auto-deleted — the user decides.
struct OrphanTrayView: View {
    @ObservedObject var session: DocumentSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if session.orphans.isEmpty {
                    ContentUnavailableView(
                        "보관함이 비어 있어요",
                        systemImage: "tray",
                        description: Text("문서가 바뀌어 자리를 잃은 필기가 여기에 모입니다.")
                    )
                } else {
                    List {
                        Section("자리를 잃은 필기 \(session.orphans.count)개") {
                            ForEach(session.orphans) { item in
                                HStack(spacing: 14) {
                                    Image(uiImage: item.image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 84, height: 60)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(item.label)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Spacer()
                                    Button {
                                        session.restoreOrphan(item.id)
                                    } label: {
                                        Label("복원", systemImage: "arrow.uturn.backward")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    Button(role: .destructive) {
                                        session.deleteOrphan(item.id)
                                    } label: {
                                        Label("삭제", systemImage: "trash")
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .padding(.vertical, 4)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(item.label)
                            }
                        }
                    }
                }
            }
            .navigationTitle("보관함")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
