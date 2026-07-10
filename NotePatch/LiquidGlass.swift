import SwiftUI
import UIKit

// MARK: - Animation presets

extension Animation {
    static let interactiveSpring = Animation.spring(response: 0.28, dampingFraction: 0.78)
    static let cardEntry = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let sheetSpring = Animation.spring(response: 0.45, dampingFraction: 0.84)
    static let statusSpring = Animation.spring(response: 0.35, dampingFraction: 0.80)
}

// MARK: - Compatibility helpers

private enum GlassProminence {
    case clear
    case regular
    case tinted(Color)
}

@available(iOS 26.0, *)
private func resolveGlass(_ prominence: GlassProminence) -> Glass {
    switch prominence {
    case .clear:
        return .clear
    case .regular:
        return .regular
    case .tinted(let tint):
        return .regular.tint(tint)
    }
}

private extension View {
    @ViewBuilder
    func fallbackGlassSurface<S: InsettableShape>(_ shape: S, tint: Color = .clear) -> some View {
        self
            .background(.ultraThinMaterial)
            .background(tint.opacity(tint == .clear ? 0 : 0.12))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.26), lineWidth: 0.5)
            }
    }
}

// MARK: - Haptics

extension View {
    @ViewBuilder
    func hapticImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> some View {
        if #available(iOS 17.0, *) {
            self.sensoryFeedback(
                .impact(flexibility: .solid, intensity: style == .light ? 0.45 : 0.7),
                trigger: UUID()
            )
        } else {
            self
        }
    }

    @ViewBuilder
    func hapticSuccess() -> some View {
        if #available(iOS 17.0, *) {
            self.sensoryFeedback(.success, trigger: UUID())
        } else {
            self
        }
    }

    @ViewBuilder
    func hapticSelection() -> some View {
        if #available(iOS 17.0, *) {
            self.sensoryFeedback(.selection, trigger: UUID())
        } else {
            self
        }
    }
}

// MARK: - Shared motion

struct StaggeredForEach<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let data: Data
    let animation: Animation
    let initialOffset: CGFloat
    @ViewBuilder let content: (Data.Element) -> Content
    @State private var appeared = false

    init(
        _ data: Data,
        animation: Animation = .cardEntry,
        initialOffset: CGFloat = 12,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.animation = animation
        self.initialOffset = initialOffset
        self.content = content
    }

    var body: some View {
        ForEach(Array(data.enumerated().map { ($0.offset, $0.element) }), id: \.1.id) { index, element in
            content(element)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : initialOffset)
                .animation(animation.delay(Double(index) * 0.05), value: appeared)
        }
        .onAppear { appeared = true }
    }
}

struct AnimatedEmptyIcon: View {
    let systemImage: String
    let size: CGFloat
    let tint: Color
    @State private var animate = false

    init(_ systemImage: String, size: CGFloat = 40, tint: Color = .secondary) {
        self.systemImage = systemImage
        self.size = size
        self.tint = tint
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 18.0, *) {
            icon
                .symbolEffect(.bounce.byLayer, options: .repeat(.periodic(delay: 1.8)), value: animate)
                .onAppear { animate = true }
        } else if #available(iOS 17.0, *) {
            icon
                .symbolEffect(.bounce.byLayer, value: animate)
                .onAppear { animate = true }
        } else {
            icon
        }
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: size, weight: .light))
            .foregroundStyle(tint)
    }
}

// MARK: - Glass surfaces

struct LiquidGlassCardModifier: ViewModifier {
    let tint: Color
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            LiquidGlassCard26(content: content, tint: tint)
        } else {
            content.fallbackGlassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), tint: tint)
        }
    }
}

struct LiquidGlassPanelModifier: ViewModifier {
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            LiquidGlassPanel26(content: content, tint: tint)
        } else {
            content.fallbackGlassSurface(RoundedRectangle(cornerRadius: 12, style: .continuous), tint: tint)
        }
    }
}

struct LiquidGlassPillModifier: ViewModifier {
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            LiquidGlassPill26(content: content, tint: tint)
        } else {
            content.fallbackGlassSurface(Capsule(), tint: tint)
        }
    }
}

struct LiquidGlassBannerModifier: ViewModifier {
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            LiquidGlassBanner26(content: content, tint: tint)
        } else {
            content.fallbackGlassSurface(RoundedRectangle(cornerRadius: 14, style: .continuous), tint: tint)
        }
    }
}

struct LiquidGlassFieldModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            LiquidGlassField26(content: content)
        } else {
            content.fallbackGlassSurface(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct LiquidGlassStickyFooterModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            LiquidGlassStickyFooter26(content: content)
        } else {
            content.fallbackGlassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

@available(iOS 26.0, *)
private struct LiquidGlassCard26<Content: View>: View {
    let content: Content
    let tint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let prominence: GlassProminence = tint == .clear ? .regular : .tinted(tint)
        content
            .background { shape.fill(.clear).glassEffect(resolveGlass(prominence), in: shape) }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.34), lineWidth: 0.6)
            }
    }
}

@available(iOS 26.0, *)
private struct LiquidGlassPanel26<Content: View>: View {
    let content: Content
    let tint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let prominence: GlassProminence = tint == .clear ? .regular : .tinted(tint)
        content
            .background { shape.fill(.clear).glassEffect(resolveGlass(prominence), in: shape) }
            .overlay { shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5) }
    }
}

@available(iOS 26.0, *)
private struct LiquidGlassPill26<Content: View>: View {
    let content: Content
    let tint: Color

    var body: some View {
        content
            .background { Capsule().fill(.clear).glassEffect(.regular.tint(tint), in: Capsule()) }
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5) }
    }
}

@available(iOS 26.0, *)
private struct LiquidGlassBanner26<Content: View>: View {
    let content: Content
    let tint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .background { shape.fill(.clear).glassEffect(.regular.tint(tint), in: shape) }
            .overlay { shape.strokeBorder(Color.white.opacity(0.34), lineWidth: 0.5) }
    }
}

@available(iOS 26.0, *)
private struct LiquidGlassField26<Content: View>: View {
    let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        content
            .background { shape.fill(.clear).glassEffect(.regular, in: shape) }
            .overlay { shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5) }
    }
}

@available(iOS 26.0, *)
private struct LiquidGlassStickyFooter26<Content: View>: View {
    let content: Content

    var body: some View {
        let shape = UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 18, topTrailing: 18),
            style: .continuous
        )
        content
            .background { shape.fill(.clear).glassEffect(.regular, in: shape) }
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.32)).frame(height: 0.6)
            }
    }
}

extension View {
    @ViewBuilder
    func notePatchGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    func liquidGlassCard(tint: Color = .clear, interactive: Bool = false) -> some View {
        modifier(LiquidGlassCardModifier(tint: tint, interactive: interactive))
    }

    func liquidGlassPanel(tint: Color = .clear) -> some View {
        modifier(LiquidGlassPanelModifier(tint: tint))
    }

    func liquidGlassPill(tint: Color) -> some View {
        modifier(LiquidGlassPillModifier(tint: tint))
    }

    func liquidGlassBanner(tint: Color) -> some View {
        modifier(LiquidGlassBannerModifier(tint: tint))
    }

    func liquidGlassField() -> some View {
        modifier(LiquidGlassFieldModifier())
    }

    func liquidGlassStickyFooter() -> some View {
        modifier(LiquidGlassStickyFooterModifier())
    }
}

// MARK: - Page-level presentation

struct LiquidGlassBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.04, green: 0.06, blue: 0.14), Color(red: 0.03, green: 0.12, blue: 0.20)]
                : [Color(red: 0.76, green: 0.88, blue: 1.00), Color(red: 0.80, green: 0.94, blue: 0.92)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder
    func heroTitle() -> some View {
        if #available(iOS 16.0, *) {
            self
                .font(.system(.largeTitle, design: .default, weight: .bold))
                .tracking(-0.5)
                .lineSpacing(4)
        } else {
            self
                .font(.largeTitle.bold())
                .lineSpacing(4)
        }
    }

    @ViewBuilder
    func sectionTitle() -> some View {
        if #available(iOS 16.0, *) {
            self.font(.title3.weight(.semibold)).tracking(-0.2)
        } else {
            self.font(.title3.weight(.semibold))
        }
    }

    func cardTitle() -> some View {
        self.font(.headline).lineSpacing(2)
    }
}

struct GlassAppIcon: View {
    let systemImage: String
    let size: CGFloat
    let symbolSize: CGFloat
    let bounce: Bool
    @State private var appeared = false

    init(systemImage: String = "doc.text.viewfinder", size: CGFloat, symbolSize: CGFloat, bounce: Bool = false) {
        self.systemImage = systemImage
        self.size = size
        self.symbolSize = symbolSize
        self.bounce = bounce
    }

    @ViewBuilder
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                .fill(Color.clear)
                .liquidGlassPanel(tint: .accentColor)
                .frame(width: size, height: size)
            symbol
        }
    }

    @ViewBuilder
    private var symbol: some View {
        if bounce, #available(iOS 17.0, *) {
            Image(systemName: systemImage)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(.white)
                .symbolEffect(.bounce.byLayer, value: appeared)
                .onAppear { appeared = true }
        } else {
            Image(systemName: systemImage)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}
