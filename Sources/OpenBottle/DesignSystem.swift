#if os(macOS)
import SwiftUI

/// OpenBottle's original visual language. No proprietary CrossOver artwork or assets.
enum OB {
    static let canvas = Color(hex: 0x0B1018)
    static let sidebar = Color(hex: 0x101823)
    static let panel = Color(hex: 0x151F2B)
    static let panelLight = Color(hex: 0x1A2633)
    static let border = Color(hex: 0x293644)
    static let text = Color(hex: 0xF4F7FB)
    static let muted = Color(hex: 0x9AABBC)
    static let accent = Color(hex: 0x6EE7D3)
    static let accentDeep = Color(hex: 0x168A85)
    static let purple = Color(hex: 0xA29BFE)
    static let amber = Color(hex: 0xF6BD67)
    static let green = Color(hex: 0x80E4AA)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

struct OBPanel<Content: View>: View {
    let padding: CGFloat
    let content: () -> Content

    init(padding: CGFloat = 18, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OB.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(OB.border.opacity(0.75), lineWidth: 1))
    }
}

struct OBIcon: View {
    let name: String
    var tint: Color = OB.accent
    var size: CGFloat = 42
    var body: some View {
        Image(systemName: name)
            .font(.system(size: size * 0.40, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.27))
            .overlay(RoundedRectangle(cornerRadius: size * 0.27).stroke(tint.opacity(0.14)))
    }
}

struct OBTag: View {
    let title: String
    var tint: Color = OB.accent
    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.11), in: Capsule())
    }
}

struct OBSectionTitle: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.system(size: 19, weight: .bold)).foregroundStyle(OB.text)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(OB.muted)
            }
        }
    }
}

struct OBPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(OB.canvas)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(configuration.isPressed ? OB.accent.opacity(0.75) : OB.accent,
                        in: RoundedRectangle(cornerRadius: 10))
    }
}

struct OBSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(OB.text)
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(configuration.isPressed ? OB.panelLight.opacity(0.7) : OB.panelLight,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(OB.border))
    }
}
#endif
