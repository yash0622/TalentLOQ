---
name: TalentLOQ Modern Professional
colors:
  surface: '#f7f9fb'
  surface-dim: '#d8dadc'
  surface-bright: '#f7f9fb'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f4f6'
  surface-container: '#eceef0'
  surface-container-high: '#e6e8ea'
  surface-container-highest: '#e0e3e5'
  on-surface: '#191c1e'
  on-surface-variant: '#464555'
  inverse-surface: '#2d3133'
  inverse-on-surface: '#eff1f3'
  outline: '#777587'
  outline-variant: '#c7c4d8'
  surface-tint: '#4d44e3'
  primary: '#1e00a9'
  on-primary: '#ffffff'
  primary-container: '#3525cd'
  on-primary-container: '#b1afff'
  inverse-primary: '#c3c0ff'
  secondary: '#4648d4'
  on-secondary: '#ffffff'
  secondary-container: '#6063ee'
  on-secondary-container: '#fffbff'
  tertiary: '#400091'
  on-tertiary: '#ffffff'
  tertiary-container: '#5c00c9'
  on-tertiary-container: '#c5a9ff'
  error: '#EF4444'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#e2dfff'
  primary-fixed-dim: '#c3c0ff'
  on-primary-fixed: '#0f0069'
  on-primary-fixed-variant: '#3323cc'
  secondary-fixed: '#e1e0ff'
  secondary-fixed-dim: '#c0c1ff'
  on-secondary-fixed: '#06006c'
  on-secondary-fixed-variant: '#2e2ebe'
  tertiary-fixed: '#eaddff'
  tertiary-fixed-dim: '#d2bbff'
  on-tertiary-fixed: '#25005a'
  on-tertiary-fixed-variant: '#5a00c6'
  background: '#f7f9fb'
  on-background: '#191c1e'
  surface-variant: '#e0e3e5'
  surface-glass: rgba(255, 255, 255, 0.7)
  success: '#22C55E'
  warning: '#F59E0B'
  text-primary: '#111827'
  text-secondary: '#475569'
typography:
  display-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  title-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 26px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.05em
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  gutter: 16px
  container-padding: 20px
  card-gap: 12px
  section-margin: 32px
---

## Brand & Style
The brand personality is **Professional, Efficient, and Approachable**. It targets career-driven individuals looking for high-quality opportunities in tech and finance. 

The design style is **Corporate Modern with Glassmorphic touches**. It utilizes a clean, systematic layout inspired by Material Design 3 but elevated with subtle backdrop blurs and a sophisticated indigo-centric palette. The emotional response should be one of "calm productivity"—the interface feels reliable and high-end without being overly sterile.

## Colors
The palette is built around a deep, trustworthy **Indigo Primary (#3525cd)**. 

- **Primary & Secondary:** Use varying shades of Indigo and Violet to establish hierarchy.
- **Glassmorphism:** The `surface-glass` color is critical for headers and bottom navigation, providing a sense of depth and modernism when combined with a `backdrop-blur-xl`.
- **Functional Colors:** Use standard semantic colors for status (Success Green, Warning Amber, Error Red) but ensure they are slightly desaturated to match the professional tone.
- **Surfaces:** Utilize a tiered neutral system (`f7f9fb` to `eceef0`) to separate content areas without relying solely on borders.

## Typography
The system uses a two-font pairing strategy:
- **Plus Jakarta Sans** is reserved for high-level headings and brand moments. It provides a welcoming, optimistic character.
- **Inter** handles all functional, body, and label text. Its utilitarian nature ensures maximum readability for data-dense job listings and application forms.
- **Scalability:** On mobile devices, `display-lg` should be avoided in favor of `headline-md` for main page titles to maintain a comfortable information density.

## Layout & Spacing
The system employs a **Fixed Content-Width Grid** on larger screens (max-width 4xl/896px) and a **Fluid Margin Grid** on mobile.

- **Rhythm:** Use an 8px base unit for all internal spacing.
- **Container:** Mobile views should maintain a 20px `container-padding` on left/right edges.
- **Scrolling:** Horizontal filter areas should use "bleeding" layouts that extend to the edge of the screen while maintaining internal alignment with the content grid via negative margins and matching padding.
- **Verticality:** Use `section-margin` to separate distinct logical groups (e.g., Search from Listings).

## Elevation & Depth
Hierarchy is established through **Ambient Shadows and Tonal Layering**:

- **Level 0 (Background):** `background` (#f7f9fb) color.
- **Level 1 (Cards):** Use `surface-container-lowest` (#ffffff) with a soft, indigo-tinted shadow: `0 4px 20px -4px rgba(79,70,229,0.08)`.
- **Level 2 (Interactive/Floating):** Use a more pronounced shadow for headers and navigation bars to indicate they sit above the content during scroll.
- **Interaction:** Cards should "lift" on hover, increasing the shadow spread and opacity slightly to provide tactile feedback.

## Shapes
The shape language is **Rounded and Modern**, avoiding the playfulness of full pills for primary containers but utilizing them for secondary interactive elements.

- **Standard Containers:** Cards and inputs use `rounded-xl` (0.75rem / 12px) to feel substantial.
- **Interactive Pills:** Search bars, category chips, and filter buttons use `rounded-full` to distinguish them from content cards.
- **Small Elements:** Small badges and labels use a tighter `rounded-md` (0.375rem / 6px) to maintain clarity at small scales.

## Components
- **Buttons:** 
  - *Primary:* Solid Indigo background, White text, 10px vertical padding. 
  - *Icon buttons:* Rounded-full, 8px padding, transparent background with subtle hover states.
- **Chips/Filters:** 
  - *Active:* Primary color background with white text.
  - *Inactive:* `surface-container` background with `outline-variant` border and `on-surface-variant` text.
- **Inputs:** 
  - Search inputs should be `rounded-full`, featuring a 1px `outline-variant` border that transitions to `primary` on focus. Use 16px horizontal padding for text.
- **Cards:** 
  - Job cards are the primary container. They must feature a 1px `outline-variant` border and a subtle Indigo-tinted shadow. Content inside should be structured with clear vertical spacing (16px) and a divider (`surface-variant`) before the final CTA.
- **Badges:** 
  - Use low-opacity semantic backgrounds (e.g., `success/10%`) with high-contrast text for status labels like "Remote" or salary ranges.