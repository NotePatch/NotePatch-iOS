//
//  DesignSystem.swift
//  NotePatch
//
//  NotePatch Design System — Paper-inspired, warm, intelligent.
//  Visual identity: calm premium notebook, not Apple Notes clone.
//
//  Palette: warm paper tones + muted sage accent
//  Depth: one soft overhead light, consistent shadow direction
//  Cards: like premium notebook pages, white + hairline border + generous radius
//  Animation: 220ms ease-out cubic, calm and intentional
//

import SwiftUI
import UIKit

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    static func adaptive(light: String, dark: String) -> Color {
        let lightColor = UIColor(hex: light)
        let darkColor = UIColor(hex: dark)
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

// MARK: - Color Tokens (Paper-inspired warm palette)

struct NPColors {
    // ── 4-layer background hierarchy ──
    /// Page canvas — warm paper tone, never cold white.
    static let background    = Color.adaptive(light: "#F2F4F1", dark: "#0E110F")
    /// Primary surface — layering surface, slightly warm.
    static let surface       = Color.adaptive(light: "#F8F9F6", dark: "#151A17")
    /// Card surface — pure white, like a premium notebook page.
    static let surfaceCard   = Color.adaptive(light: "#FFFFFF", dark: "#1B211D")
    /// Interactive surface — barely perceptible warmth for tappable elements.
    static let interactive   = Color.adaptive(light: "#F6F8F5", dark: "#232A25")
    /// Top-edge highlight used by cards and glass fallbacks.
    static let surfaceHighlight = Color.adaptive(light: "#B3FFFFFF", dark: "#24FFFFFF")

    // ── Text hierarchy (warm near-black base) ──
    /// Primary — warm near-black for body and titles.
    static let textPrimary   = Color.adaptive(light: "#171717", dark: "#F2F5F1")
    /// Secondary — 62% of primary, for labels and helper text.
    static let textSecondary = Color.adaptive(light: "#9E171717", dark: "#B8D7DED8")
    /// Tertiary — 42% of primary, for metadata and captions.
    static let textTertiary  = Color.adaptive(light: "#6B171717", dark: "#8FAEB7AF")

    // ── Dividers & Borders ──
    /// 5% black — subtle separation, paper-like.
    static let border        = Color.adaptive(light: "#0D000000", dark: "#24FFFFFF")
    static let divider       = Color.adaptive(light: "#0D000000", dark: "#1FFFFFFF")

    // ── Brand (Muted Sage Green) ──
    static let brandLight    = Color.adaptive(light: "#E2F0E8", dark: "#20382A")
    static let brand         = Color.adaptive(light: "#5D9972", dark: "#78C68F")
    static let brandDark     = Color.adaptive(light: "#2E6548", dark: "#A0DDB1")

    // ── Semantic ──
    static let aiUserBubble  = Color.adaptive(light: "#EFF5F1", dark: "#1C2B22")
    static let destructive   = Color.adaptive(light: "#D15A5A", dark: "#FF8A8A")
    static let warning       = Color.adaptive(light: "#C9861C", dark: "#F3C263")
    static let successBg     = Color.adaptive(light: "#E7F3EA", dark: "#203629")
    static let successText   = Color.adaptive(light: "#4F8E66", dark: "#8FD1A1")
}

// MARK: - Shadow Tokens (Single overhead light source)

struct NPShadow {
    /// Button — subtle, clickable surfaces.
    static let small: (color: Color, radius: CGFloat, y: CGFloat)  = (.black.opacity(0.05), 10, 4)
    /// Card — premium notebook page floating above desk.
    static let medium: (color: Color, radius: CGFloat, y: CGFloat) = (.black.opacity(0.06), 24, 10)
    /// Sheet — distant surface.
    static let large: (color: Color, radius: CGFloat, y: CGFloat)  = (.black.opacity(0.06), 40, 16)
    /// Hover lift — deeper shadow when interacting.
    static let hover: (color: Color, radius: CGFloat, y: CGFloat)  = (.black.opacity(0.10), 28, 12)
    /// Upload button — green-tinted, distinctive primary action.
    static let upload: (color: Color, radius: CGFloat, y: CGFloat) = (Color(hex: "#5D9972").opacity(0.10), 18, 8)
}

// MARK: - Radius Tokens

struct NPRadius {
    static let xs         = 8.0
    static let small      = 10.0
    static let medium     = 14.0
    static let large      = 20.0
    static let xl         = 22.0
    /// Card — premium notebook page corner.
    static let card: CGFloat       = 24.0
    /// Tab bar — floating dock corner.
    static let tabBar: CGFloat     = 28.0
    // Aliases
    static let button     = medium
    static let input      = medium
    static let sheet      = xl
    static let chip       = small
    static let segmented  = small
}

// MARK: - Spacing Tokens (4pt grid)

struct NPSpacing {
    static let xxs     = 4.0
    static let xs      = 4.0
    static let small   = 8.0
    static let medium  = 12.0
    static let large   = 20.0
    static let xl      = 24.0
    static let xxl     = 32.0
    static let xxxl    = 40.0
    static let huge    = 48.0
    // Legacy aliases
    static let outer   = xl
    static let section = xl
    static let card    = 18.0
    static let item    = 16.0
}

// MARK: - Elevation (Z-axis position)

struct NPElevation {
    static let base: Double     = 0
    static let raised: Double   = 100
    static let card: Double     = 200
    static let sheet: Double    = 300
    static let overlay: Double  = 400
}

// MARK: - Card Modifier (Premium notebook page)

struct NPCardShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(
                color: NPShadow.medium.color,
                radius: NPShadow.medium.radius,
                x: 0,
                y: NPShadow.medium.y
            )
    }
}

struct NPCardModifier: ViewModifier {
    var radius: CGFloat = NPRadius.card
    var padding: CGFloat = NPSpacing.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NPColors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(NPColors.surfaceHighlight, lineWidth: 0.5)
            }
            .modifier(NPCardShadow())
    }
}

struct NPListItemModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NPColors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(NPColors.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.025), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Primary Button Style (220ms cubic, calm)

struct NPPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium, design: .default))
            .foregroundStyle(NPColors.brandDark)
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            .background {
                Capsule(style: .continuous)
                    .fill(NPColors.interactive)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(NPColors.border, lineWidth: 0.5)
            }
            .shadow(
                color: NPShadow.small.color,
                radius: NPShadow.small.radius,
                x: 0,
                y: NPShadow.small.y
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(Animation.npButton, value: configuration.isPressed)
    }
}

// MARK: - Secondary Button Style

struct NPSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .default))
            .foregroundStyle(NPColors.brandDark)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background {
                Capsule(style: .continuous)
                    .fill(NPColors.interactive)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(NPColors.border, lineWidth: 0.5)
            }
            .shadow(
                color: NPShadow.small.color,
                radius: NPShadow.small.radius,
                x: 0,
                y: NPShadow.small.y
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(Animation.npButton, value: configuration.isPressed)
    }
}

// MARK: - Icon Button Style

struct NPIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17))
            .foregroundStyle(NPColors.textSecondary)
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(Animation.npButton, value: configuration.isPressed)
    }
}

// MARK: - Upload Button Style (Visual anchor, primary action)

struct NPUploadButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium, design: .default))
            .foregroundStyle(NPColors.brandDark)
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .background {
                Capsule(style: .continuous)
                    .fill(NPColors.interactive)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(NPColors.brand.opacity(0.16), lineWidth: 1)
            }
            .shadow(
                color: NPShadow.upload.color,
                radius: NPShadow.upload.radius,
                x: 0,
                y: NPShadow.upload.y
            )
            .scaleEffect(isHovering ? 1.02 : configuration.isPressed ? 0.98 : 1.0)
            .offset(y: isHovering ? -3 : 0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(Animation.npButton, value: isHovering)
            .animation(Animation.npButton, value: configuration.isPressed)
            .onHover { h in
                withAnimation(Animation.npButton) { isHovering = h }
            }
    }
}

// MARK: - Reprocess Button Style (Card action, no glow)

struct NPDocumentPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium, design: .default))
            .foregroundStyle(NPColors.brandDark)
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background {
                Capsule(style: .continuous)
                    .fill(isHovering ? NPColors.surfaceCard : NPColors.interactive)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(NPColors.border, lineWidth: 0.5)
            }
            .shadow(
                color: isHovering ? .black.opacity(0.08) : .black.opacity(0.05),
                radius: isHovering ? 18 : 8,
                x: 0,
                y: isHovering ? 8 : 3
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .offset(y: isHovering && !configuration.isPressed ? -2 : 0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(Animation.npButton, value: isHovering)
            .animation(Animation.npButton, value: configuration.isPressed)
            .onHover { h in
                withAnimation(Animation.npButton) { isHovering = h }
            }
    }
}

// MARK: - Document Icon Button Style

struct NPDocumentIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(NPColors.textSecondary)
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(Animation.npButton, value: configuration.isPressed)
    }
}

// MARK: - Toolbar Icon Button Style

struct NPToolbarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(NPColors.brandDark)
            .frame(width: 36, height: 36)
            .background(
                Circle()
                    .fill(NPColors.brandLight.opacity(configuration.isPressed ? 0.45 : 0.25))
            )
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(Animation.npButton, value: configuration.isPressed)
    }
}

// MARK: - Typography (Dynamic Type-native)

extension View {
    func npTitle()      -> some View { self.font(.title2.weight(.semibold)).foregroundStyle(NPColors.textPrimary) }
    func npHeading()    -> some View { self.font(.title3.weight(.semibold)).foregroundStyle(NPColors.textPrimary) }
    func npSubheading() -> some View { self.font(.headline.weight(.semibold)).foregroundStyle(NPColors.textPrimary) }
    func npBody()       -> some View { self.font(.body).foregroundStyle(NPColors.textPrimary) }
    func npCallout()    -> some View { self.font(.callout).foregroundStyle(NPColors.textSecondary) }
    func npCaption()    -> some View { self.font(.caption).foregroundStyle(NPColors.textTertiary) }
}

// MARK: - Legacy Typography (backward compatibility)

extension View {
    @available(*, deprecated, message: "Use npTitle()")
    func npScreenTitle() -> some View { npTitle() }
    @available(*, deprecated, message: "Use npHeading()")
    func npSectionTitle() -> some View { npHeading() }
    @available(*, deprecated, message: "Use npSubheading()")
    func npCardTitle() -> some View { npSubheading() }
}

// MARK: - Status Chip

struct NPStatusChip: View {
    let text: String
    let variant: NPStatusChipVariant

    enum NPStatusChipVariant {
        case brand
        case neutral
        case warning
        case destructive

        var bg: Color {
            switch self {
            case .brand:       return NPColors.successBg
            case .neutral:     return NPColors.interactive
            case .warning:     return NPColors.warning.opacity(0.15)
            case .destructive: return NPColors.destructive.opacity(0.12)
            }
        }
        var fg: Color {
            switch self {
            case .brand:       return NPColors.successText
            case .neutral:     return NPColors.textSecondary
            case .warning:     return NPColors.warning
            case .destructive: return NPColors.destructive
            }
        }
    }

    var body: some View {
        Text(localized(text))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(variant.fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(variant.bg)
            .clipShape(Capsule())
            .fixedSize()
    }
}

// MARK: - Section Container

struct NPSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .modifier(NPCardModifier())
    }
}

// MARK: - Empty State

struct NPEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: NPSpacing.small) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(NPColors.textTertiary.opacity(0.5))
            Text(localized(title))
                .npHeading()
            Text(localized(message))
                .npCaption()
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NPSpacing.xxxl)
    }
}

// MARK: - Animation Presets (Calm cubic-based, no bounce)

extension Animation {
    /// 220ms ease-out cubic — primary interaction curve.
    static let npButton      = Animation.timingCurve(0.2, 0.8, 0.2, 1.0, duration: 0.22)
    /// Quick fade transitions.
    static let npQuick       = Animation.easeOut(duration: 0.20)
    /// Instant response.
    static let npInstant     = Animation.easeOut(duration: 0.10)
    /// Gentle surface transition.
    static let npCardEntry   = Animation.timingCurve(0.2, 0.8, 0.2, 1.0, duration: 0.25)
    /// Sheet presentation.
    static let npSheetSpring = Animation.spring(response: 0.40, dampingFraction: 0.84)
    /// Button breath — subtle attention draw.
    static let npBreath      = Animation.easeInOut(duration: 1.0)
    /// Legacy spring — kept for compatibility.
    static let npInteractive = Animation.timingCurve(0.2, 0.8, 0.2, 1.0, duration: 0.22)
}

// MARK: - Input Field Modifier

struct NPInputFieldModifier: ViewModifier {
    var isFocused: Bool = false

    func body(content: Content) -> some View {
        content
            .background(NPColors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: NPRadius.input, style: .continuous))
            .shadow(
                color: NPShadow.small.color,
                radius: NPShadow.small.radius,
                x: 0,
                y: NPShadow.small.y
            )
            .overlay {
                RoundedRectangle(cornerRadius: NPRadius.input, style: .continuous)
                    .stroke(isFocused ? NPColors.brand : NPColors.divider, lineWidth: isFocused ? 1.5 : 0.5)
            }
    }
}

extension View {
    func npInputField(isFocused: Bool = false) -> some View {
        modifier(NPInputFieldModifier(isFocused: isFocused))
    }
}

// MARK: - Segmented Control Styling

enum NPSegmentedControl {
    static let background    = Color.adaptive(light: "#E7EAE5", dark: "#121613")
    static let selectedBg    = NPColors.surfaceCard
    static let selectedShadow: (color: Color, radius: CGFloat, y: CGFloat) = (.black.opacity(0.04), 6, 2)
}

// MARK: - Tab Bar Styling (Floating Dock)

enum NPTabBar {
    static let background    = NPColors.surfaceCard
    static let shadow: (color: Color, radius: CGFloat, y: CGFloat) = (.black.opacity(0.08), 30, 12)
}
