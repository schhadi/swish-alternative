import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// A QR code for a collection's pay link, generated on the phone (Core Image, no network, no dependency).
enum QRCode {
    static func image(for text: String, scale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        guard let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// "Scan to pay": the code people point their camera at, the link under it, Copy and Share.
struct QRCodeSheet: View {
    let url: URL
    let title: String
    let subtitle: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text(title)
                            .font(.quidTitle2)
                            .foregroundStyle(Color.quidInk)
                            .multilineTextAlignment(.center)
                        Text(subtitle)
                            .font(.quidSubheadline)
                            .foregroundStyle(Color.quidMuted)
                            .multilineTextAlignment(.center)
                    }
                    // Dark modules on white in both appearances: cameras read that reliably.
                    Group {
                        if let image = QRCode.image(for: url.absoluteString) {
                            Image(uiImage: image)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Text("Couldn't make the code. Share the link instead.")
                                .font(.quidSubheadline)
                                .foregroundStyle(Color.quidMuted)
                        }
                    }
                    .frame(maxWidth: 260, maxHeight: 260)
                    .padding(20)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.quidHairline, lineWidth: 1))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("QR code that opens the pay page")
                    .accessibilityIdentifier("collection.qr")
                    Text("People without Quid scan this with their camera and pay from their own banking app.")
                        .font(.quidFootnote)
                        .foregroundStyle(Color.quidMuted)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 10) {
                        Text(url.absoluteString)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Color.quidInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        QuidPillButton(title: copied ? "Copied" : "Copy", style: .neutral) {
                            UIPasteboard.general.string = url.absoluteString
                            copied = true
                            AccessibilityNotification.Announcement("Link copied").post()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.quidSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(20)
            }
            .background(Color.quidBackground)
            .safeAreaInset(edge: .bottom) {
                ShareLink(item: url, message: Text("\(title): \(subtitle)")) {
                    Label("Share link", systemImage: "square.and.arrow.up")
                        .font(.quidHeadline)
                        .foregroundStyle(Color.quidOnAccent)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(Color.quidAccent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.quidBackground)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.quidSubheadline)
                        .accessibilityIdentifier("collection.qr.done")
                }
            }
        }
        .tint(Color.quidAccentText)
        .presentationDetents([.large])
    }
}
