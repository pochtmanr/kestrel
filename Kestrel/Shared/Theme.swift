import SwiftUI
import UIKit

/// Design tokens: every colour, corner radius, spacing step and type choice
/// the app and its widget draw with. Views read these instead of literals, so
/// a redesign is mostly a change here and in `UI/Components.swift`.
/// Lives in `Shared/` because the widget uses it too (UIColor is fine there).
enum Theme {
    /// Cool blue-grey slate, a blue-grey slate-steel accent, and a small
    /// ember-orange touch for warmth.
    /// Designed dark-first; every text pair is WCAG AA on `surface` and `background`.
    /// Colours live in code (not asset catalogs) so the app and widget can't drift apart.
    enum Palette {
        /// Blue-grey steel fill: the Send card, primary buttons, tabs, the system tint.
        /// White text on it: ≥ 4.5:1.
        static let accent = dynamic(light: 0x55677F, dark: 0x62779A)
        /// The accent as text or an icon on a surface (≥ 4.5:1).
        static let accentText = dynamic(light: 0x4A5B74, dark: 0xA9BAD3)
        /// Ember orange: a secondary warm touch (small glyphs, the currency sign), never a fill for text.
        static let ember = dynamic(light: 0xA65428, dark: 0xE8935E)

        /// Screen background.
        static let background = dynamic(light: 0xEEF1F5, dark: 0x0E131A)
        /// Cards and grouped surfaces.
        static let surface = dynamic(light: 0xFFFFFF, dark: 0x18202A)
        /// A surface inside a surface, or pressed.
        static let surfaceRaised = dynamic(light: 0xF5F7FA, dark: 0x222B37)
        /// Hairlines and card edges.
        static let separator = Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.08) : UIColor(red: 0.07, green: 0.09, blue: 0.13, alpha: 0.10) })

        /// Text tiers.
        static let textPrimary = dynamic(light: 0x111821, dark: 0xEDF1F5)
        static let textSecondary = dynamic(light: 0x4F5A68, dark: 0x9AA5B3)
        static let textTertiary = dynamic(light: 0x727D8C, dark: 0x76818F)

        /// Money in, success, "copied".
        static let positive = dynamic(light: 0x1E7563, dark: 0x5CC4A4)
        /// Money out: deliberately neutral slate, so it never competes with the accent.
        static let outgoing = dynamic(light: 0x4F5A68, dark: 0x9AA5B3)
        /// Errors and blocking problems; an empty fee balance.
        static let danger = dynamic(light: 0xB23A3E, dark: 0xF07A7A)
        /// Cautions: low TRX for fees, backup reminders.
        static let warning = dynamic(light: 0x86601A, dark: 0xE3B565)
        /// A transfer still confirming.
        static let pending = warning

        /// Token colours: Tether green and TRON red, muted toward the slate so
        /// they read as the coins without shouting over the palette.
        static let usdt = Color(UIColor(hex: 0x3F8F7A))
        static let trx = Color(UIColor(hex: 0xB8504E))

        /// Brand: the logo's pale sky blue, and the night navy it sits on
        /// (the launch screen, the splash and the welcome screen). Fixed in
        /// both appearances: those screens are always dark.
        static let brandSky = Color(UIColor(hex: 0xBBD8FF))
        static let brandNight = Color(UIColor(hex: 0x0B1424))

        /// The receive QR: deep slate to steel (dark modules stay scannable on white).
        static let qrStart = Color(UIColor(hex: 0x2B3747))
        static let qrEnd = Color(UIColor(hex: 0x55677F))

        private static func dynamic(light: UInt32, dark: UInt32) -> Color {
            Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
        }
    }

    /// Corner radii, smallest to largest.
    enum Radius {
        static let xxs: CGFloat = 5
        static let xs: CGFloat = 9
        static let s: CGFloat = 12
        static let m: CGFloat = 14
        static let l: CGFloat = 16
        static let xl: CGFloat = 18
        /// Cards and grouped surfaces.
        static let card: CGFloat = 20
        /// Home cards.
        static let tile: CGFloat = 26
        static let panel: CGFloat = 24
        static let hero: CGFloat = 28
    }

    /// Spacing steps for padding and stacks.
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        /// Screen edge inset.
        static let screen: CGFloat = 20
        static let xl: CGFloat = 24
    }

    enum Typography {
        /// Design for balances and amounts.
        static let numeric: Font.Design = .rounded

        /// A balance or amount at a fixed size, in the numeric design.
        static func amount(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
            .system(size: size, weight: weight, design: numeric)
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
