//
//  LiquidGlass.swift
//  NotePatch
//
//  iOS 26 Liquid Glass 设计系统 — 2026 美学基础层。
//  所有卡片 / 面板 / 药丸 / 提示条 / 输入框 / 按钮 + 全局动画 / 触觉反馈 / 排版增益 统一由此提供。
//

import SwiftUI

// MARK: - 内部辅助

private enum GlassProminence {
    case clear
    case regular
    case tinted(Color)
}

private func resolveGlass(_ prominence: GlassProminence) -> Glass {
    switch prominence {
    case .clear: return .clear
    case .regular: return .regular
    case .tinted(let color): return .regular.tint(color)
    }
}

// MARK: - 全局动画预设 (2026 美学：所有动画用 spring，拒绝 .default)

extension Animation {
    /// 交互反馈：快弹簧，用于按钮按压 / toggle
    static let interactiveSpring = Animation.spring(response: 0.28, dampingFraction: 0.78)
    /// 卡片入场：稍慢弹簧，用于列表项 stagger
    static let cardEntry = Animation.spring(response: 0.42, dampingFraction: 0.82)
    /// Sheet / 全屏过渡
    static let sheetSpring = Animation.spring(response: 0.45, dampingFraction: 0.84)
    /// 状态变化（banner 显隐）
    static let statusSpring = Animation.spring(response: 0.35, dampingFraction: 0.80)
}

// MARK: - 触觉反馈 (2026 美学：关键操作必须有物理反馈)

extension View {
    /// 轻触反馈用于按钮点击
    func hapticImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> some View {
        self.sensoryFeedback(.impact(flexibility: .solid, intensity: style == .light ? 0.45 : 0.7), trigger: UUID())
    }
    /// 成功反馈
    func hapticSuccess() -> some View {
        self.sensoryFeedback(.success, trigger: UUID())
    }
    /// 选择反馈
    func hapticSelection() -> some View {
        self.sensoryFeedback(.selection, trigger: UUID())
    }
}

// MARK: - Stagger 入场 (2026 美学：逐项弹入)

struct StaggeredForEach<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let data: Data
    let animation: Animation
    let initialOffset: CGFloat
    @ViewBuilder let content: (Data.Element) -> Content
    @State private var appeared = false

    init(_ data: Data, animation: Animation = .cardEntry, initialOffset: CGFloat = 12,
         @ViewBuilder content: @escaping (Data.Element) -> Content) {
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

// MARK: - 空状态 SF Symbol 动效 (2026 美学：空状态不再是静态占位)

struct AnimatedEmptyIcon: View {
    let systemImage: String
    let size: CGFloat
    let tint: Color

    init(_ systemImage: String, size: CGFloat = 40, tint: Color = .secondary) {
        self.systemImage = systemImage
        self.size = size
        self.tint = tint
    }

    @State private var animate = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size, weight: .light))
            .foregroundStyle(tint)
            .symbolEffect(.bounce.byLayer, options: .repeat(.periodic(delay: 1.8)), value: animate)
            .onAppear { animate = true }
    }
}

// MARK: - 卡片

struct LiquidGlassCardModifier: ViewModifier {
    let tint: Color
    let interactive: Bool
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let prominence: GlassProminence = (tint == .clear) ? .regular : .tinted(tint)
        return content
            .background {
                shape
                    .fill(.clear)
                    .glassEffect(resolveGlass(prominence), in: shape)
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.32)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
            }
    }
}

// MARK: - 紧凑面板

struct LiquidGlassPanelModifier: ViewModifier {
    let tint: Color
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let prominence: GlassProminence = (tint == .clear) ? .regular : .tinted(tint)
        return content
            .background {
                shape
                    .fill(.clear)
                    .glassEffect(resolveGlass(prominence), in: shape)
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), Color.white.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            }
    }
}

// MARK: - 药丸

struct LiquidGlassPillModifier: ViewModifier {
    let tint: Color
    func body(content: Content) -> some View {
        content
            .background {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular.tint(tint), in: Capsule())
            }
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
            }
    }
}

// MARK: - 提示条

struct LiquidGlassBannerModifier: ViewModifier {
    let tint: Color
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return content
            .background {
                shape
                    .fill(.clear)
                    .glassEffect(.regular.tint(tint), in: shape)
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.50), Color.white.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            }
    }
}

// MARK: - 输入框

struct LiquidGlassFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return content
            .background {
                shape
                    .fill(.clear)
                    .glassEffect(.regular, in: shape)
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.40), Color.white.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            }
    }
}

// MARK: - 底部粘性操作栏

struct LiquidGlassStickyFooterModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 18, topTrailing: 18),
            style: .continuous
        )
        return content
            .background {
                shape
                    .fill(.clear)
                    .glassEffect(.regular, in: shape)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.45), Color.white.opacity(0.0)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(height: 0.6)
            }
    }
}

// MARK: - 公开 View 扩展

extension View {
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

// MARK: - 页面级背景 (2026 美学版：更深邃的渐变，更大的光斑)

struct LiquidGlassBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            // 2026 美学：从双端渐变变成三区渐变 + 大半径光斑，营造深邃空间感
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.04, green: 0.06, blue: 0.14),
                       Color(red: 0.09, green: 0.05, blue: 0.18),
                       Color(red: 0.03, green: 0.12, blue: 0.20)]
                    : [Color(red: 0.76, green: 0.88, blue: 1.00),
                       Color(red: 0.90, green: 0.82, blue: 1.00),
                       Color(red: 0.80, green: 0.94, blue: 0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 顶部光斑 — 大而柔和
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue.opacity(scheme == .dark ? 0.38 : 0.42),
                                 Color.blue.opacity(0.0)],
                        center: .center, startRadius: 0, endRadius: 160
                    )
                )
                .frame(width: 360, height: 360)
                .blur(radius: 30)
                .offset(x: -100, y: -200)

            // 底部光斑 — 暖色
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.purple.opacity(scheme == .dark ? 0.34 : 0.36),
                                 Color.purple.opacity(0.0)],
                        center: .center, startRadius: 0, endRadius: 140
                    )
                )
                .frame(width: 300, height: 300)
                .blur(radius: 30)
                .offset(x: 120, y: 250)

            // 中间偏右 — 青色点缀
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.cyan.opacity(scheme == .dark ? 0.28 : 0.34),
                                 Color.cyan.opacity(0.0)],
                        center: .center, startRadius: 0, endRadius: 110
                    )
                )
                .frame(width: 240, height: 240)
                .blur(radius: 30)
                .offset(x: 70, y: -80)
        }
        .ignoresSafeArea()
    }
}

// MARK: - GlassEffectContainer 实用包装 (2026 美学：多玻璃必须合并渲染)

/// 把多个玻璃视图包进 GlassEffectContainer，获得正确合并 + 形变过渡能力。
struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

// MARK: - 排版增益 (2026 美学：looser leading + 一致的 hierarchy)

extension View {
    /// Hero 标题：用于 Auth / 品牌名，比 largeTitle 更有呼吸感
    func heroTitle() -> some View {
        self.font(.system(.largeTitle, design: .default, weight: .bold))
            .tracking(-0.5)
            .lineSpacing(4)
    }

    /// Section 标题：title3 + comfortable leading
    func sectionTitle() -> some View {
        self.font(.title3.weight(.semibold))
            .tracking(-0.2)
    }

    /// 卡片标题
    func cardTitle() -> some View {
        self.font(.headline)
            .lineSpacing(2)
    }
}
