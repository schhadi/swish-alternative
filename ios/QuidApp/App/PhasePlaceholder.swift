import SwiftUI

/// Flows that land in a later phase (docs/SPEC.md section 9). Shown instead of dead buttons while Phase 0 is reviewed.
enum PhasePlaceholder: String, Identifiable {
    case payRequest, request, declineRequest, createCollection, remind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .payRequest: return "Pay a request"
        case .request: return "Request"
        case .declineRequest: return "Decline request"
        case .createCollection: return "New collection"
        case .remind: return "Remind"
        }
    }

    var phase: Int {
        switch self {
        case .payRequest, .request, .declineRequest, .remind: return 3
        case .createCollection: return 4
        }
    }

    var summary: String {
        switch self {
        case .payRequest:
            return "Paying a request prefills the Pay flow and marks the request paid once the money arrives. Built in Phase 3 with requests and splits."
        case .request:
            return "Ask one or several people for money, as an equal or per-person split. Built in Phase 3."
        case .declineRequest:
            return "Declining a request is built in Phase 3 alongside requests and splits."
        case .createCollection:
            return "Set up a collection for a club, society or flat, share a link or QR code and see who has paid. Built in Phase 4."
        case .remind:
            return "Reminders are rate-limited to once per 24 hours per person. Built in Phase 3 for requests and Phase 4 for collections."
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
