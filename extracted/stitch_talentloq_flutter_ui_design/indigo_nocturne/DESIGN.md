---
name: Indigo Nocturne
colors:
  surface: '#13121b'
  surface-dim: '#13121b'
  surface-bright: '#393842'
  surface-container-lowest: '#0e0d16'
  surface-container-low: '#1b1b24'
  surface-container: '#1f1f28'
  surface-container-high: '#2a2933'
  surface-container-highest: '#35343e'
  on-surface: '#e4e1ee'
  on-surface-variant: '#c7c4d8'
  inverse-surface: '#e4e1ee'
  inverse-on-surface: '#302f39'
  outline: '#918fa1'
  outline-variant: '#464555'
  surface-tint: '#c3c0ff'
  primary: '#c3c0ff'
  on-primary: '#1d00a5'
  primary-container: '#4f46e5'
  on-primary-container: '#dad7ff'
  inverse-primary: '#4d44e3'
  secondary: '#bdc2ff'
  on-secondary: '#131e8c'
  secondary-container: '#2f3aa3'
  on-secondary-container: '#a8afff'
  tertiary: '#ffb695'
  on-tertiary: '#571f00'
  tertiary-container: '#a44100'
  on-tertiary-container: '#ffd2be'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#e2dfff'
  primary-fixed-dim: '#c3c0ff'
  on-primary-fixed: '#0f0069'
  on-primary-fixed-variant: '#3323cc'
  secondary-fixed: '#e0e0ff'
  secondary-fixed-dim: '#bdc2ff'
  on-secondary-fixed: '#000767'
  on-secondary-fixed-variant: '#2f3aa3'
  tertiary-fixed: '#ffdbcc'
  tertiary-fixed-dim: '#ffb695'
  on-tertiary-fixed: '#351000'
  on-tertiary-fixed-variant: '#7b2f00'
  background: '#13121b'
  on-background: '#e4e1ee'
  surface-variant: '#35343e'
typography:
  headline-xl:
    fontFamily: Plus Jakarta Sans
    fontSize: 48px
    fontWeight: '800'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
  title-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 4px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 40px
  2xl: 64px
  gutter: 24px
  margin-mobile: 16px
  margin-desktop: 48px
---

## Brand & Style
The design system is a sophisticated, high-performance dark mode environment tailored for modern SaaS and deep-focus applications. The brand personality is professional yet energetic, utilizing high-contrast Indigo accents against a deep, structural background to create a sense of depth and focus. 

The aesthetic blends **Modern Corporate** reliability with **Glassmorphic** nuances. It prioritizes clarity and visual hierarchy through tonal layering rather than heavy shadows, ensuring that the interface feels light and responsive despite its dark foundation. The target audience is power users who appreciate refined, low-strain interfaces that maintain a premium, cutting-edge feel.

## Colors
The palette is anchored by a deep charcoal-navy (`#0f172a`) for the primary background, providing a stable, low-light foundation. The primary indigo (`#4f46e5`) serves as the functional driver for actions, while its lighter counterpart (`#818cf8`) is used for subtle accents and hover states to maintain visibility against dark surfaces.

Semantic colors:
- **Background**: `#0f172a` (Deep Charcoal)
- **Surface**: `#1e293b` (Elevated Navy)
- **Primary**: `#4f46e5` (Indigo)
- **Text (High Emphasis)**: `#f8fafc` (Slate 50)
- **Text (Medium Emphasis)**: `#94a3b8` (Slate 400)
- **Border/Divider**: `#334155` (Slate 700)

## Typography
This design system utilizes **Plus Jakarta Sans** across all levels to maintain a friendly yet precise geometric character. Headlines feature tight letter-spacing and heavy weights to command attention, while body text is optimized with generous line heights to ensure long-form readability on dark backgrounds. 

To prevent "ink bleed" or visual vibration of white text on dark surfaces, font weights for body copy are kept at a standard 400, while labels and buttons use 600 to ensure they remain legible at smaller sizes.

## Layout & Spacing
The layout follows a **Fluid Grid** system based on an 8px base unit. 
- **Desktop**: 12-column grid, 24px gutters, and 48px side margins.
- **Tablet**: 8-column grid, 16px gutters, and 24px side margins.
- **Mobile**: 4-column grid, 16px gutters, and 16px side margins.

Spacing is used to create visual grouping. Larger gaps (`xl` or `2xl`) are reserved for separating distinct content sections, while smaller increments (`sm` or `md`) manage the internal relationship of components.

## Elevation & Depth
In this dark mode environment, depth is communicated through **Tonal Layers** and subtle **Glassmorphism**. 
- **Level 0 (Base)**: `#0f172a` — The foundation layer.
- **Level 1 (Cards/Navigation)**: `#1e293b` — Primary containers.
- **Level 2 (Overlays/Modals)**: `#334155` — Highest elevation.

Instead of traditional black shadows, use semi-transparent Indigo-tinted glows for active states. For modals, apply a `backdrop-filter: blur(12px)` with a 60% opacity surface to maintain context of the background while focusing the user's attention. Low-contrast borders (`1px solid #334155`) should be used on all cards to define boundaries without adding visual clutter.

## Shapes
The design system adopts a **Rounded** shape language to soften the industrial feel of the dark palette. 
- **Standard components** (Buttons, Inputs): `0.5rem` (rounded-md).
- **Primary containers** (Cards, Sections): `1.5rem` (rounded-xl) as per the design requirement.
- **Interactive chips/pills**: Full radius (9999px).

This variation in radii helps distinguish between structural layout elements and functional interactive elements.

## Components
- **Buttons**: Primary buttons use the Indigo background with white text. Secondary buttons should use a ghost style with a Slate 700 border and Slate 50 text.
- **Cards**: Use the `rounded-xl` (1.5rem) radius. Backgrounds should be `#1e293b` with a subtle `1px` border of `#334155` to ensure separation from the `#0f172a` base.
- **Input Fields**: Backgrounds should be slightly darker than the surface (`#0f172a`) with a focus state that illuminates the Indigo border and adds a soft Indigo outer glow.
- **Chips**: Use a high-transparency Indigo fill (`rgba(79, 70, 229, 0.1)`) with Indigo text for a "tag" appearance that doesn't compete with primary actions.
- **Lists**: Items are separated by `#334155` dividers. Hover states should use a subtle background shift to `#334155` with a transition of 200ms.
- **Checkboxes/Radios**: When active, these use the primary Indigo. When inactive, they use a Slate 700 stroke to remain visible but secondary.