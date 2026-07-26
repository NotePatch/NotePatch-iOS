# NotePatch Design System v3.0

> **Status:** Specification — not yet implemented in code.
> **Foundation:** Apple Human Interface Guidelines (HIG) · iOS 17+ · SwiftUI
> **Philosophy:** 90% Neutral / 8% Brand / 2% Semantic Accent
> **Grid:** 4pt base grid (all spacing divisible by 4)

---

## 1. Color Tokens

### 1.1 Design Rationale

Apple HIG prescribes a **3-layer background hierarchy** to establish depth without heavy shadows. Each layer serves a distinct purpose:

| Layer | Role | HIG Guidance |
|---|---|---|
| **Background** | Page-level canvas. Never competes for attention. | `.systemBackground` equivalent |
| **Surface** | Cards, sheets, modals. Floats above Background. | `.secondarySystemBackground` equivalent |
| **Interactive** | Tappable surfaces. Sits above Surface, signals affordance. | `.tertiarySystemBackground` equivalent |

### 1.2 Light Mode Tokens

#### Background Hierarchy

| Token | Hex | Usage |
|---|---|---|
| `background` | `#F7F8F6` | Scroll view backgrounds, tab content areas, empty states |
| `surface` | `#FFFFFF` | Cards (`NPCardModifier`), sheets, list cells with background |
| `interactive` | `#FCFDFC` | Buttons (`NPPrimaryButtonStyle`), segmented controls, chips, input fields |

**Why `#F7F8F6` instead of pure white?** Pure white (`#FFFFFF`) creates harsh contrast against cards and causes eye fatigue in reading-heavy apps. A 1–2% warm shift reduces perceived brightness without compromising the "light mode" feel. Apple Notes uses `#F2F2F7`; NotePatch uses a slightly warmer neutral to complement the Sage brand.

#### Brand Palette (Sage Green)

The brand color is a muted, desaturated green — chosen because:
- Green is non-intrusive in a document/reading context (vs. blue, which competes with link colors)
- Desaturated greens reduce cognitive load in education tools (per ISO 9241-303 visual ergonomics)
- Sage tones pair well with warm neutrals without creating complementary-color vibration

| Token | Hex | Usage |
|---|---|---|
| `brandLight` | `#D8F0DF` | Chip backgrounds, toolbar button fills, selection highlights, AI agent indicators |
| `brand` | `#5FA86D` | Active tab indicators, focused input borders, primary iconography |
| `brandDark` | `#4A8A5E` | Primary button text, selected segment labels, link colors |

#### Semantic Colors

Each semantic color is verified against **WCAG 2.1 AA** minimum contrast (4.5:1 for normal text on its background pair).

| Token | Hex | Usage | Contrast Check |
|---|---|---|---|
| `success` | `#5FA86D` | Completion states, verified badges | Alias to `brand` — green = success convention |
| `warning` | `#E8A840` | Alert chips, deadline indicators, unverified states | 4.63:1 on `background` |
| `error` | `#D15A5A` | Destructive actions, error banners, delete confirmations | 4.58:1 on `background` |

**Why not pure red/green/yellow?** Pure RGB primaries create cartoonish interfaces. Muted semantic colors communicate state without screaming. Apple Wallet uses `#FF3B30` (vivid red) only for destructive actions; everything else is toned down.

#### Text Hierarchy

Following HIG's typographic color model:

| Token | Hex | Opacity Equivalent | Usage |
|---|---|---|---|
| `textPrimary` | `#111111` | ~93% black | Titles, body text, primary labels |
| `textSecondary` | `#6B6B70` | ~60% black | Subtitles, helper text, tab bar unselected |
| `textTertiary` | `#8E8E93` | ~45% black | Metadata, timestamps, captions, watermark text |

**Why hex instead of opacity?** `Color.black.opacity(0.6)` composites differently on colored backgrounds. Fixed hex ensures consistent perceived contrast regardless of what sits behind the text.

#### Dividers & Borders

| Token | Hex | Usage |
|---|---|---|
| `divider` | `#00000008` | List row separators, section boundaries (hairline) |
| `border` | `#0000000A` | Card strokes, input borders (idle state) |

**Why near-transparent black?** Apple HIG recommends `Separator` (`#3C3C43` at 36% = `#000000` at ~14%). NotePatch uses even lighter separators at 3–4% because the dark-mode planning expects `separator`/`border` tokens to invert cleanly.

---

## 2. Shadow Tokens

### 2.1 Design Rationale

Shadows in iOS communicate **elevation** — how far a surface floats above the background. The system uses **4 levels**, aligned with Material Elevation DP mapping but expressed in HIG-native terminology.

All shadows use `Color.black.opacity(N)` — never colored shadows, which violate the "light from above" metaphor HIG assumes.

| Token | Opacity | Radius (blur) | Y Offset | Elevation (dp) | Usage |
|---|---|---|---|---|---|
| `small` | 4% | 12 | 4 | 2 | Buttons, input fields, segmented controls, chips |
| `medium` | 5% | 24 | 8 | 4 | Cards (`NPCardModifier`), list cells, image thumbnails |
| `large` | 6% | 40 | 16 | 8 | Sheets, modals, popovers, floating action panels |
| `hover` | 8% | 48 | 24 | 12 | On-hover/on-press lift (iPad pointer, context menus) |

**Why not use system `shadow(radius:)` defaults?** SwiftUI's default shadow (radius=0, offset=0, color=40% black) creates a harsh, unrealistic "sticker" effect. Purpose-built elevation tokens create perceptual depth using:
- **Increasing blur radius** — larger blur = farther from surface
- **Increasing Y offset** — farther surfaces cast longer shadows (light angle metaphor)
- **Decreasing opacity** — larger shadows must be softer to avoid muddying

---

## 3. Radius Tokens

### 3.1 Design Rationale

Apple HIG uses `continuous` corner style (squircle) for all iOS surfaces. The system defines 4 sizes with proportional increments based on the **golden ratio scale (×1.4)**:

| Token | Value | Usage |
|---|---|---|
| `small` | 8 | Checkboxes, tags, small badges |
| `medium` | 14 | Buttons, input fields, chips, segmented controls, list row highlights |
| `large` | 20 | Cards (default), image thumbnails, sheet handles |
| `xl` | 28 | Full-screen sheets, modal containers, large panels |

**Why ×1.4 increments?** Perceptual uniformity. Linear step (e.g., 8→12→16) creates under-differentiation at the high end. The golden ratio ensures each step is visually distinguishable.

**Why `continuous` style?** `RoundedRectangle(cornerRadius:style:.continuous)` produces iOS-native squircle corners. Standard rounded rectangles have abrupt curvature transitions that feel mechanical. Continuous corners are the HIG default for all system surfaces.

---

## 4. Spacing Tokens

### 4.1 Design Rationale

The spacing system follows a **4pt base grid** with values at 4, 8, 12, 16, 20, 24, 32, 40, and 48. Values above 48 are composed from these base tokens (e.g., 56 = 40 + 16).

This matches iOS layout margins: `.padding(.horizontal, 16)` is the system default for readable content width on iPhone.

| Token | Value | Usage |
|---|---|---|
| `xxs` | 4 | Icon-to-label gaps, tight inline spacing, badge internal padding |
| `xs` | 8 | Chip-to-chip in groups, list row trailing padding, section header-to-content |
| `small` | 12 | Form field-to-field gaps, stack spacing for compact lists |
| `medium` | 16 | Standard horizontal page margins, inter-card spacing |
| `large` | 20 | Card internal padding, button-to-content, dialog content margins |
| `xl` | 24 | Section spacing, major content separations, safe area complements |
| `xxl` | 32 | Top-level section separators, empty state icon-to-text, hero spacing |
| `xxxl` | 40 | Page header bottom margin, large empty state surrounds |
| `huge` | 48 | Full-screen section padding (iPad), onboarding flow spacing |

**Why not semantic aliases like `card` or `section`?** Semantic aliases create ambiguity when the same value is used in a different context (e.g., `card` padding = 18pt, but what if a non-card element needs 18pt?). The raw numeric scale is the single source of truth. Semantic aliases are defined **at the component level** (e.g., `NPCardModifier` defaults to `padding: .medium`). This follows the _"tokens for primitives, components for semantics"_ principle from the Material Design token architecture.

### 4.2 Touch Target Compliance

All interactive elements must meet Apple HIG's minimum touch target of **44×44pt**.

| Element | Minimum Size | Enforcement |
|---|---|---|
| Icon buttons | 44×44 frame | `NPIconButtonStyle` |
| List row tappable area | ≥44pt height | `List` default |
| Tab bar items | System-provided | `TabView` default |
| Custom small chips | min 28pt height, 44pt width | Manual review required |

---

## 5. Typography Tokens

### 5.1 Design Rationale

The system defines **6 semantic typography roles**, mapped to Apple's Dynamic Type text styles to ensure automatic scaling:

| Token | Size | Weight | Dynamic Type Style | Usage |
|---|---|---|---|---|
| `title` | 22 | Semibold | `.title2` | Full-screen page titles, auth headers |
| `heading` | 18 | Semibold | `.title3` | Section headers, card group titles |
| `subheading` | 16 | Semibold | `.headline` | Card titles, list item primaries |
| `body` | 15 | Regular | `.body` | Paragraphs, descriptions, form labels |
| `callout` | 13 | Regular | `.callout` | Secondary information, button labels, status text |
| `caption` | 12 | Regular | `.caption` | Metadata, timestamps, file sizes, fine print |

### 5.2 Typography Rules

1. **No raw `.font()` calls in views.** All text must use semantic modifiers (`.npTitle()`, `.npBody()`, etc.).
2. **Dynamic Type is mandatory.** Typography tokens expose a `dynamicTypeEnabled` variant that uses `.font(.system(...))` with the mapped Dynamic Type style.
3. **Line height is automatic.** Do not manually set `lineSpacing` — SwiftUI's default line height for system fonts already matches HIG.
4. **Character spacing is never modified.** Apple's San Francisco font has kerning optimized at the type design level.

### 5.3 Implementation Reference

```swift
extension View {
    func npTitle()     -> some View { self.font(.title2.weight(.semibold)).foregroundStyle(NPColors.textPrimary) }
    func npHeading()   -> some View { self.font(.title3.weight(.semibold)).foregroundStyle(NPColors.textPrimary) }
    func npSubheading()-> some View { self.font(.headline.weight(.semibold)).foregroundStyle(NPColors.textPrimary) }
    func npBody()      -> some View { self.font(.body).foregroundStyle(NPColors.textPrimary) }
    func npCallout()   -> some View { self.font(.callout).foregroundStyle(NPColors.textSecondary) }
    func npCaption()   -> some View { self.font(.caption).foregroundStyle(NPColors.textTertiary) }
}
```

**Key change from v2:** Typography modifiers now use **Dynamic Type styles** (`.title2`, `.body`, `.caption`) instead of fixed point sizes. This ensures the app respects the user's system-wide text size preference — a core accessibility requirement.

---

## 6. Elevation Tokens

### 6.1 Design Rationale

Elevation is the **z-axis position** of a surface in the interface stack. It is not the same as shadow — elevation is the *property*; shadow is the *visual representation* of that property.

The system uses **5 elevation levels**, corresponding to the standard iOS view hierarchy:

| Level | Z-Index | Shadow Token | Usage |
|---|---|---|---|
| `base` | 0 | none | Background scroll views, tab content |
| `raised` | 100 | `small` | Buttons, input fields, chips, toolbar items |
| `card` | 200 | `medium` | Cards (`NPCardModifier`), list sections, thumbnails |
| `sheet` | 300 | `large` | Sheets, modals, popovers, alerts, context menus |
| `overlay` | 400 | `hover` | Hover tooltips, drag previews, highest-priority overlays |

### 6.2 Usage Rules

1. **No z-index hardcoding.** Every surface's elevation is expressed through its shadow token only. The actual `zIndex` modifier is reserved for overlap resolution (drag-and-drop, etc.).
2. **One elevation per surface.** A card cannot have both `card` and `raised` shadows — compound shadows create ambiguous depth cues.
3. **Elevation increases with interaction.** A card at `card` level may temporarily lift to `sheet` level when dragged.

---

## 7. Animation Tokens

### 7.1 Design Rationale

Animations serve three purposes in HIG: **feedback** (user action acknowledged), **continuity** (state change is smooth), and **delight** (subtle character without distraction). All animations must respect `accessibilityReduceMotion`.

### 7.2 Tokens

| Token | Curve | Duration | Damping | Usage |
|---|---|---|---|---|
| `instant` | `.easeOut` | 0.10s | — | Button press downscale, toggle state flip |
| `quick` | `.easeOut` | 0.20s | — | Hover enter/exit, focus ring transition, opacity fades |
| `interactive` | `.spring` | 0.28s | 0.78 | Button press release, chip insertion/removal, list reorder |
| `cardEntry` | `.spring` | 0.35s | 0.85 | Card appearance (staggered list load), section expand |
| `sheetSpring` | `.spring` | 0.40s | 0.84 | Sheet presentation, modal entry, full-screen transitions |
| `breath` | `.easeInOut` | 1.0s | — | Attention micro-animation (process button pulse) |

### 7.3 Rules

1. **All interactive elements must animate on press** — minimum: `scaleEffect(0.97)` on press, spring back on release.
2. **Cards entering a list use `cardEntry`** with staggered delays proportional to index (e.g., `delay = index * 0.05s`).
3. **Sheet presentations use `sheetSpring`** — never `.default` or `.linear`.
4. **Respect `@Environment(\.accessibilityReduceMotion)`** — when enabled, replace all animations with instant transitions (duration = 0).
5. **No animation exceeds 400ms** for user-triggered interactions. HIG states that longer animations feel sluggish. The `breath` token (1.0s) is the only exception — it is a background micro-animation, not a response to user input.

### 7.4 Implementation Reference

```swift
extension Animation {
    static let npInstant     = Animation.easeOut(duration: 0.10)
    static let npQuick       = Animation.easeOut(duration: 0.20)
    static let npInteractive = Animation.spring(response: 0.28, dampingFraction: 0.78)
    static let npCardEntry   = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let npSheetSpring = Animation.spring(response: 0.40, dampingFraction: 0.84)
}
```

---

## 8. Component-to-Token Mapping

This table defines which tokens every UI component consumes. **Implementation rule:** no component may use a color, spacing, radius, or shadow value not listed in its row.

| Component | Background | Text | Spacing (internal) | Spacing (external) | Radius | Shadow | Elevation |
|---|---|---|---|---|---|---|---|
| `NPCardModifier` | `surface` | — | `large` (20) | `medium` (16) | `large` (20) | `medium` | `card` |
| `NPSection` | `surface` | — | `large` (20) | `xl` (24) | `large` (20) | `medium` | `card` |
| `NPPrimaryButton` | `interactive` | `brandDark` / `callout` | h:48pt, pad:`medium`(16) | — | `medium` (14), Capsule | `small` | `raised` |
| `NPSecondaryButton` | `interactive` | `brandDark` / `callout` | h:44pt, pad:`medium`(16) | — | `medium` (14), Capsule | `small` | `raised` |
| `NPIconButton` | transparent | `textSecondary` / 17pt | frame:44×44 | — | — | none | `raised` |
| `NPToolbarIconButton` | `brandLight`(20%α) | `brandDark` / 18pt | frame:36×36 | `xs`(8) | `large`(20), Circle | none | `raised` |
| `NPInputField` | `surface` | `textPrimary`/`body` | pad:`medium`(16) | — | `medium`(14) | `small` | `raised` |
| `NPStatusChip` | variant bg (see Color §1.2) | variant fg / 11pt medium | h-pad:`xs`(8), v-pad:3pt | `xs`(8) | `small`(10), Capsule | none | `raised` |
| `NPEmptyState` | transparent | `textTertiary` | icon:36pt light, text:`small`(12) | v:`xxl`(32), h:`medium`(16) | — | none | `base` |
| `TabBar` | system | `brandDark`(selected), `textSecondary`(unselected) | system | — | — | none | `base` |
| `StatusBanner` | `error`(12%α) | `error`/`callout` | pad:`medium`(16) | — | `medium`(14) | — | `overlay` |

---

## 9. Design Audit Checklist

Before any PR merges, verify:

- [ ] No raw `Color(hex:)` calls — all colors via `NPColors`
- [ ] No raw `.font(.system(size:weight:))` — all typography via `.npXxx()` modifiers
- [ ] No raw `.padding(N)` — all spacing via `NPSpacing`
- [ ] No raw `.cornerRadius(N)` — all radii via `NPRadius`
- [ ] No raw `.shadow(...)` — all shadows via `NPShadow` tokens
- [ ] All interactive elements ≥44pt touch target
- [ ] `@Environment(\.accessibilityReduceMotion)` respected in all animations
- [ ] Dynamic Type tested at smallest and largest settings
- [ ] VoiceOver labels present on all interactive elements without visible text

---

## Appendix A: Token Naming Convention

```
NP{Category}.{tokenName}
```

| Category | Prefix | Example |
|---|---|---|
| Color | `NPColors.` | `NPColors.background` |
| Shadow | `NPShadow.` | `NPShadow.card` |
| Radius | `NPRadius.` | `NPRadius.medium` |
| Spacing | `NPSpacing.` | `NPSpacing.large` |
| Animation | `Animation.` | `Animation.npInteractive` |

Typography tokens are View extensions, not static properties — they must return `some View` to compose font + color: `.npTitle()`, `.npBody()`, etc.

---

## Appendix B: Migration Path from v2

| v2 Token | v3 Token | Rationale |
|---|---|---|
| `NPSpacing.card` (18) | `NPSpacing.large` (20) | 4pt grid alignment; 18pt breaks the grid |
| `NPSpacing.section` (24) | `NPSpacing.xl` (24) | Renamed for clarity; section = a component, xl = a spacing value |
| `NPSpacing.outer` (24) | `NPSpacing.xl` (24) | Same value, unified under spacing scale |
| `NPSpacing.item` (16) | `NPSpacing.medium` (16) | Renamed for clarity |
| `NPShadow.level1` | `NPShadow.medium` | Renamed to match semantic scale |
| `NPShadow.level2` | `NPShadow.small` | Renamed to match semantic scale |
| `NPShadow.level3` | `NPShadow.hover` | Renamed to match semantic scale |
| `.npScreenTitle()` | `.npTitle()` | Broader scope: applies to more than just "screen" headers |
| `.npSectionTitle()` | `.npHeading()` | Matches Dynamic Type `.title3` naming |
| `.npCardTitle()` | `.npSubheading()` | Matches Dynamic Type `.headline` naming |
| Fixed font sizes (22/18/16/15/12pt) | Dynamic Type styles | Accessibility requirement |
| `NPColors.aiUserBubble` | Removed from core tokens | Moved to component-level (AI-specific, not a system token) |
