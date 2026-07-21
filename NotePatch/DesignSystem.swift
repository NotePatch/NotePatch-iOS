//
//  DesignSystem.swift
//  NotePatch
//
//  NotePatch Design System — warm neutral palette, brand green accents,
//  Apple HIG-inspired minimalism with unique NotePatch identity.
//
//  Color usage: 90% Neutral / 8% Brand / 2% Accent
//  Spacing: 8pt grid
//  Typography: Apple hierarchy
//  Radius: cards 18, buttons 14, inputs 14, chips 12
//

import SwiftUI

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
}

// MARK: - Color Tokens

struct NPColors {
    // Background — cool-toned subtle grey for depth layering
    static let background = Color(hex: "#F5F7F8")
    static let surface     = Color(hex: "#FFFFFF")

    // Text
    static let textPrimary   = Color(hex: "#171717")
    static let textSecondary = Color(hex: "#6B7280")

    // Dividers & Borders — lighter, almost invisible
    static let divider = Color(hex: "#F0F1F3")
    static let border  = Color(hex: "#E5E7EB")

    // Brand Green — micro‑gradient endpoints
    static let brandLight = Color(hex: "#C6E3C9")
    static let brand      = Color(hex: "#7EB88B")
    static let brandDark  = Color(hex: "#4F8A63")
    static let brandGlow  = Color(hex: "#5CBF7B")  // slightly teal‑tinted for gradient

    // AI bubble tint
    static let aiUserBubble = Color(hex: "#EDF8EF")

    // Semantic
    static let destructive = Color(hex: "#D15A5A")
    static let warning     = Color(hex: "#E8A840")
}

// MARK: - Spacing Tokens (8pt Grid)

struct NPSpacing {
    static let outer   = 24.0
    static let section = 24.0
    static let card    = 18.0
    static let item    = 16.0
    static let small   = 8.0
}

// MARK: - Radius Tokens

struct NPRadius {
    static let card       = 18.0
    static let button     = 14.0
    static let input      = 14.0
    static let sheet      = 20.0
    static let chip       = 12.0
}

// MARK: - Shadow Modifier

struct NPCardShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: Color.black.opacity(0.04), radius: 16, x: 0, y: 4)
    }
}

// MARK: - Card Modifier (no border — floats via shadow alone)

struct NPCardModifier: ViewModifier {
    var radius: CGFloat = NPRadius.card
    var padding: CGFloat = NPSpacing.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NPColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .modifier(NPCardShadow())
    }
}

// MARK: - Button Styles

struct NPPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: NPRadius.button, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [NPColors.brandGlow, NPColors.brandDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct NPSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(NPColors.brandDark)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: NPRadius.button, style: .continuous)
                    .fill(NPColors.brandLight.opacity(0.30))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct NPIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17))
            .foregroundStyle(NPColors.textSecondary)
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Document Card Button Styles

/// 文档卡片主操作按钮：纯浅绿块 + 深绿文字，无边框
struct NPDocumentPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(NPColors.brandDark)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NPColors.brandLight.opacity(0.30))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

/// 文档卡片裸图标按钮：无边框、无背景、深灰 icon
struct NPDocumentIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(NPColors.textSecondary)
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

/// 头部工具栏纯图标按钮：无边框、无背景、品牌绿 icon
struct NPToolbarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(NPColors.brandDark)
            .frame(width: 36, height: 36)
            .background(
                Circle()
                    .fill(NPColors.brandLight.opacity(configuration.isPressed ? 0.40 : 0.20))
            )
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }
}


// MARK: - Typography

extension View {
    func npScreenTitle() -> some View {
        self.font(.system(size: 22, weight: .semibold))
            .foregroundStyle(NPColors.textPrimary)
    }

    func npSectionTitle() -> some View {
        self.font(.system(size: 18, weight: .semibold))
            .foregroundStyle(NPColors.textPrimary)
    }

    func npCardTitle() -> some View {
        self.font(.system(size: 17, weight: .medium))
            .foregroundStyle(NPColors.textPrimary)
    }

    func npBody() -> some View {
        self.font(.system(size: 15, weight: .regular))
            .foregroundStyle(NPColors.textPrimary)
    }

    func npCaption() -> some View {
        self.font(.system(size: 13, weight: .regular))
            .foregroundStyle(NPColors.textSecondary)
    }
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
            case .brand:       return NPColors.brandLight.opacity(0.30)
            case .neutral:     return NPColors.divider.opacity(0.60)
            case .warning:     return NPColors.warning.opacity(0.15)
            case .destructive: return NPColors.destructive.opacity(0.12)
            }
        }
        var fg: Color {
            switch self {
            case .brand:       return NPColors.brandDark
            case .neutral:     return NPColors.textSecondary
            case .warning:     return NPColors.warning
            case .destructive: return NPColors.destructive
            }
        }
    }

    var body: some View {
        Text(localized(text))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(variant.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(variant.bg)
            .clipShape(Capsule())
            .fixedSize()
    }
}

// MARK: - Section Container (replaces old glassly SectionContainer)

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
                .foregroundStyle(NPColors.textSecondary.opacity(0.5))
            Text(localized(title))
                .npSectionTitle()
            Text(localized(message))
                .npCaption()
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Animation Presets

extension Animation {
    static let npInteractive  = Animation.spring(response: 0.28, dampingFraction: 0.78)
    static let npCardEntry    = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let npSheetSpring  = Animation.spring(response: 0.40, dampingFraction: 0.84)
}

// MARK: - Input Field Modifier

/// 标准输入框：白底 + 14px 圆角，聚焦时品牌绿描边，默认无边框仅靠阴影区分
struct NPInputFieldModifier: ViewModifier {
    var isFocused: Bool = false

    func body(content: Content) -> some View {
        content
            .background(NPColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: NPRadius.input, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
            .overlay {
                RoundedRectangle(cornerRadius: NPRadius.input, style: .continuous)
                    .stroke(isFocused ? NPColors.brandGlow : NPColors.divider, lineWidth: isFocused ? 1.5 : 0.5)
            }
    }
}

extension View {
    func npInputField(isFocused: Bool = false) -> some View {
        modifier(NPInputFieldModifier(isFocused: isFocused))
    }
}
