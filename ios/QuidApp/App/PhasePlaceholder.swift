import SwiftUI

/// Flows that land in a later phase (docs/SPEC.md section 9). Shown instead of dead buttons while Phase 0 is reviewed.
enum PhasePlaceholder: String, Identifiable {
    case createCollection, remind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .createCollection: return "New collection"
        case .remind: return "Remind"
        }
    }

    var phase: Int {
        switch self {
        case .createCollection, .remind: return 4
        }
    }

    var summary: String {
        switch self {
        case .createCollection:
            return "Set up a collection for a club, society or flat, share a link or QR code and see who has paid. Built in Phase 4."
        case .remind:
            return "Collection reminders are rate-limited to once per 24 hours per member, like request nudges. Built in Phase 4 with collections."
        }
    }
}

/// Text scrolls and the sheet can grow to large, so nothing clips at accessibility text sizes.
struct PhasePlaceholderSheet: View {
    let placeholder: PhasePlaceholder
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(placeholder.title)
                            .font(.quidTitle2)
                            .foregroundStyle(Color.quidInk)
                        Spacer()
                        StatusPill(text: "Phase \(placeholder.phase)", tone: .pending)
                    }
                    Text(placeholder.summary)
                        .font(.quidBody)
                        .foregroundStyle(Color.quidMuted)
                }
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            QuidButton(title: "OK", style: .secondary) {
                dismiss()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.quidBackground)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
