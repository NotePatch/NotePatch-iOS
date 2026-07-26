//
//  DesignSystem.swift
//  NotePatch
//
//  NotePatch Design System — light/dark dual theme, premium pink accent in dark mode.
//  Apple HIG-inspired minimalism with unique NotePatch identity.
//
//  Color usage: 90% Neutral / 8% Brand / 2% Accent
//  Spacing: 8pt grid
//  Typography: Apple hierarchy
//  Radius: cards 20, buttons 14, inputs 14, chips 10
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
    static let background    = Color(hex: "#FAFAF8")
    static let surface       = Color(hex: "#FFFFFF")
    static let surfaceAlt    = Color(hex: "#F7F7F7")
    static let textPrimary   = Color(hex: "#111111")
    static let textSecondary = Color(hex: "#6E6E73")
    static let divider       = Color(hex: "#EEEEEC")
    static let border        = Color(hex: "#E5E5E0")
    static let brandLight    = Color(hex: "#D8F0DF")
    static let brand         = Color(hex: "#5FA86D")
    static let brandDark     = Color(hex: "#4A8A5E")
    static let brandGlow     = Color(hex: "#A3D7AC")
    static let aiUserBubble  = Color(hex: "#EEF7F0")
    static let destructive   = Color(hex: "#D15A5A")
    static let warning       = Color(hex: "#E8A840")
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
    static let card       = 20.0
    static let button     = 14.0
    static let input      = 14.0
    static let sheet      = 22.0
    static let chip       = 10.0
    static let segmented  = 10.0
}

// MARK: - Shadow Modifier

struct NPCardShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: Color.black.opacity(0.03), radius: 12, x: 0, y: 2)
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

// MARK: - Button Styles

struct NPPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .default))
            .foregroundStyle(Color(hex: "#184A36"))
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.90), Color(hex: "#F0FAF5").opacity(0.50)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.0))
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule(style: .continuous))
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.80), lineWidth: 1)
            }
            .overlay {
                Capsule(style: .continuous)
                    .inset(by: 1)
                    .stroke(Color.white.opacity(1.0), lineWidth: 1)
                    .mask(VStack(spacing: 0) { Color.white.frame(height: 2); Color.clear })
            }
            .shadow(color: .black.opacity(0.04), radius: 16, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct NPSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold, design: .default))
            .foregroundStyle(Color(hex: "#184A36"))
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.90), Color(hex: "#F0FAF5").opacity(0.50)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.0))
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule(style: .continuous))
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.80), lineWidth: 1)
            }
            .overlay {
                Capsule(style: .continuous)
                    .inset(by: 1)
                    .stroke(Color.white.opacity(1.0), lineWidth: 1)
                    .mask(VStack(spacing: 0) { Color.white.frame(height: 2); Color.clear })
            }
            .shadow(color: .black.opacity(0.03), radius: 12, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
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

/// Document card action button: ice glass, compact
struct NPDocumentPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .default))
            .foregroundStyle(Color(hex: "#184A36"))
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.90), Color(hex: "#F0FAF5").opacity(0.50)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.0))
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule(style: .continuous))
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.75), lineWidth: 1)
            }
            .overlay {
                Capsule(style: .continuous)
                    .inset(by: 0.8)
                    .stroke(Color.white.opacity(1.0), lineWidth: 0.8)
                    .mask(VStack(spacing: 0) { Color.white.frame(height: 1.5); Color.clear })
            }
            .shadow(color: .black.opacity(0.03), radius: 10, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
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
        self.font(.system(size: 16, weight: .semibold))
            .foregroundStyle(NPColors.textPrimary)
    }

    func npBody() -> some View {
        self.font(.system(size: 15, weight: .regular))
            .foregroundStyle(NPColors.textPrimary)
    }

    func npCaption() -> some View {
        self.font(.system(size: 12, weight: .regular))
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
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(variant.fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
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
                    .stroke(isFocused ? NPColors.brand : NPColors.divider, lineWidth: isFocused ? 1.5 : 0.5)
            }
    }
}

extension View {
    func npInputField(isFocused: Bool = false) -> some View {
        modifier(NPInputFieldModifier(isFocused: isFocused))
    }
}
