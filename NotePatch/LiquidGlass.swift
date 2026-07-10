//
//  LiquidGlass.swift
//  NotePatch
//
//  统一液态玻璃样式（iOS 26 Glass API）。
//  所有"边框 / 卡片 / 药丸 / 提示条 / 输入框 / 按钮"都收敛到这一组 modifier 与 style。
//
//  重要：多个玻璃元素必须包在 GlassEffectContainer 内以获得正确的渲染与合并。
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

// MARK: - 卡片（替代所有 secondarySystemGroupedBackground + 描边 + 圆角矩形）

struct LiquidGlassCardModifier: ViewModifier {
    let tint: Color
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

// MARK: - 药丸（StatusPill 用）

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

// MARK: - 提示条（StatusBanner / 错误 / 警告）

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

// MARK: - 输入框（LabeledField 用）

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

// MARK: - 底部粘性操作栏（替代 .regularMaterial + 顶部分隔线）

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
    /// 大卡片：用于 SectionContainer / 上传预览框 / 主要面板
    func liquidGlassCard(tint: Color = .clear) -> some View {
        modifier(LiquidGlassCardModifier(tint: tint))
    }

    /// 紧凑面板：用于 toolbar / 状态条
    func liquidGlassPanel(tint: Color = .clear) -> some View {
        modifier(LiquidGlassPanelModifier(tint: tint))
    }

    /// 药丸：用于 StatusPill
    func liquidGlassPill(tint: Color) -> some View {
        modifier(LiquidGlassPillModifier(tint: tint))
    }

    /// 提示条：用于 StatusBanner / 错误区
    func liquidGlassBanner(tint: Color) -> some View {
        modifier(LiquidGlassBannerModifier(tint: tint))
    }

    /// 输入框：用于 LabeledField
    func liquidGlassField() -> some View {
        modifier(LiquidGlassFieldModifier())
    }

    /// 底部粘性操作栏
    func liquidGlassStickyFooter() -> some View {
        modifier(LiquidGlassStickyFooterModifier())
    }
}

// MARK: - 页面级背景

/// 玻璃材质需要下方有色彩 / 渐变才能折射，纯色页面会失去玻璃感。
struct LiquidGlassBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.06, green: 0.08, blue: 0.16),
                       Color(red: 0.12, green: 0.07, blue: 0.20),
                       Color(red: 0.05, green: 0.14, blue: 0.22)]
                    : [Color(red: 0.82, green: 0.91, blue: 1.00),
                       Color(red: 0.92, green: 0.86, blue: 1.00),
                       Color(red: 0.83, green: 0.95, blue: 0.94)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // 装饰光斑
            Circle()
                .fill(Color.blue.opacity(scheme == .dark ? 0.32 : 0.36))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -120, y: -180)
            Circle()
                .fill(Color.purple.opacity(scheme == .dark ? 0.30 : 0.32))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: 140, y: 260)
            Circle()
                .fill(Color.cyan.opacity(scheme == .dark ? 0.24 : 0.30))
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .offset(x: 80, y: -60)
        }
        .ignoresSafeArea()
    }
}
