import CoreImage.CIFilterBuiltins
import SwiftUI

/// Receive USDT: the address as a QR code in slate, a name the user
/// can give it, copy and share.
struct DepositView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("receive.addressName") private var addressName = ""
    @State private var copied = false
    @State private var editingName = false
    @State private var nameDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let address = app.address {
                    addressCard(address)
                    noteRow
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, 16)
            .readableWidth()
        }
        .background(Theme.Palette.background)
        .navigationTitle("Receive")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if let address = app.address {
                ShareLink(item: address, message: Text("My USDT (TRC-20) address on TRON: \(address)")) {
                    HStack(spacing: 8) {
                        Text("Share")
                        Image(systemName: "square.and.arrow.up")
                    }
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.background)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.primary, in: .capsule)
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, 8)
                .readableWidth()
            }
        }
        .alert("Address name", isPresented: $editingName) {
            TextField("e.g. Savings", text: $nameDraft)
            Button("Save") { addressName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only you see it, on this device.")
        }
    }

    private func addressCard(_ address: String) -> some View {
        VStack(spacing: 12) {
            Text("Tether USDT TRC-20").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)

            TetherQRCode(text: address)
                .frame(width: 224, height: 224)

            Button {
                nameDraft = addressName
                editingName = true
            } label: {
                HStack(spacing: 8) {
                    Text(addressName.isEmpty ? "Address name" : addressName)
                        .foregroundStyle(addressName.isEmpty ? Color.secondary.opacity(0.7) : Color.primary)
                    Image(systemName: "pencil").foregroundStyle(.secondary)
                }
                .font(.body)
            }
            .buttonStyle(.plain)

            Button {
                Clipboard.copy(address)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                HStack(spacing: 12) {
                    Text(address.splitInHalf)
                        .font(.callout.weight(.medium).monospaced())
                        .multilineTextAlignment(.center)
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.title3)
                        .foregroundStyle(copied ? Theme.Palette.positive : Color.primary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Address \(address)")
            .accessibilityHint("Copies to clipboard")

            (Text("Send only ") + Text("USDT on the TRON network").foregroundStyle(Theme.Palette.danger) + Text(" to this address. Other tokens or networks will be lost."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .surface(cornerRadius: Theme.Radius.panel)
    }

    private var noteRow: some View {
        NavigationLink(value: HomeRoute.fees) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.Palette.accent.gradient, in: .rect(cornerRadius: Theme.Radius.s))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Please note").font(.subheadline.weight(.semibold))
                    Text("Receiving is free. Sending needs some TRX for fees.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .surface(cornerRadius: Theme.Radius.card)
        }
        .buttonStyle(.plain)
    }
}

/// The address QR in Tether green with the USDT mark in the middle (high
/// error correction keeps it scannable under the mark).
private struct TetherQRCode: View {
    let text: String

    var body: some View {
        if let image = Self.modules(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(LinearGradient(colors: [Theme.Palette.qrStart, Theme.Palette.qrEnd],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    TokenIcon(token: .usdt, size: 44)
                        .padding(6)
                        .background(Color.white, in: .circle)
                }
                // Dark modules on a white plate in both modes: scanners need the contrast.
                .padding(12)
                .background(Color.white, in: .rect(cornerRadius: Theme.Radius.l, style: .continuous))
                .accessibilityLabel("QR code of your wallet address")
        }
    }

    /// The QR modules as opaque pixels on transparent, ready to tint.
    private static func modules(_ text: String) -> UIImage? {
        let qr = CIFilter.qrCodeGenerator()
        qr.message = Data(text.utf8)
        qr.correctionLevel = "H"
        let invert = CIFilter.colorInvert()
        invert.inputImage = qr.outputImage
        let mask = CIFilter.maskToAlpha()
        mask.inputImage = invert.outputImage
        guard let output = mask.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private extension String {
    /// An address on two even lines.
    var splitInHalf: String {
        let mid = index(startIndex, offsetBy: count / 2)
        return "\(self[..<mid])\n\(self[mid...])"
    }
}
