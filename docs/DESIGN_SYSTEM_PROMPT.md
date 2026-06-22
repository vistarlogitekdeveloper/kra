# Vistar Premium — Design System Reference

This file captures the **Vistar Premium** design language the app is being
re-skinned with. The brief itself is a build-prompt for a self-contained
HTML/CSS/JS prototype; the Flutter app adapts the tokens, typography, and
signature treatments verbatim. Anything an AI builds against the Vistar
Premium spec should look like a sibling of this app.

## Where each piece landed in the Flutter codebase

| Spec piece | Flutter equivalent |
|---|---|
| `:root` colour tokens (`--bg`, `--surface*`, `--txt*`, `--line*`, `--ok/warn/bad/info`) | [`AppColors`](../lib/core/constants/app_colors.dart) |
| `--ribbon` linear-gradient (the rainbow signature accent) | [`AppGradients.ribbon`](../lib/core/constants/app_gradients.dart) |
| Bricolage Grotesque + Manrope typography | [`AppTheme`](../lib/core/theme/app_theme.dart) via `google_fonts` |
| Ambient page background (aurora glows + faint S watermark + grain) | [`AmbientBackground`](../lib/core/widgets/ambient_background.dart) |
| `.skel` shimmer (rainbow sweep on dark surface) | [`ShimmerBox`](../lib/core/widgets/shimmer_box.dart) |
| `.btn-grad` (gradient primary button) | [`BrandedPrimaryButton`](../lib/features/auth/presentation/widgets/branded_primary_button.dart) |

## Brand assets

The spec calls for two PNGs:

| File | Purpose | Status |
|---|---|---|
| `assets/images/vistar_logo.png` | Existing wordmark / brand glyph (kept) | ✅ in repo |
| `assets/images/vistar_s_mark.png` | "S" rainbow swoosh — loaders, watermark, card corner accents | ⏳ awaiting drop |
| `assets/images/vistar_wordmark.png` | Vistar wordmark — splash + login | ⏳ awaiting drop |

Until the new assets land, [`AppAssets`](../lib/core/constants/app_assets.dart)
points the new constants at the existing `vistar_logo.png` so nothing breaks
visually. `Image.asset` calls use `errorBuilder` defensively.

## The original build prompt

The full spec follows. **Do not change the design tokens or signature
treatments below.** Re-skin specific app screens; never invent new colours,
fonts, or component shapes.

---

# Build Prompt — "Vistar Premium" Design System

You are a senior product designer + frontend engineer. Build a **high-end,
premium, dark-themed** single-file interactive HTML/CSS/JS prototype (no
build step, works offline, opens in any browser). It must look polished
and distinctive — never generic or "default AI." Reuse the **exact design
system** specified below.

## Design tokens

```css
:root{
  /* Vistar brand ribbon */
  --purple:#7A1FB0; --violet:#9B30C9; --magenta:#C018C0; --pink:#E0218A;
  --red:#C8102E; --orange-red:#F0480C; --orange:#F06000; --amber:#F0C000;
  --yellow:#F0E060; --cream:#FFF6CC;
  --ribbon:linear-gradient(115deg,#7A1FB0 0%,#B81FB8 22%,#E0218A 40%,#D11630 56%,#F0480C 70%,#F06000 80%,#F0C000 92%,#F7EE9A 100%);

  /* Surfaces (near-black premium) */
  --bg:#070611; --bg2:#0B0A18;
  --surface:#110F1E; --surface2:#16142A; --surface3:#1D1A33;
  --line:rgba(255,255,255,.08); --line2:rgba(255,255,255,.13);
  --txt:#F2EEFB; --txt2:#B9B2D6; --txt3:#7E769B;
  --ok:#34D399; --warn:#FBBF24; --bad:#FB6F84; --info:#5BA8FF;
}
```

The rainbow `--ribbon` gradient is the signature accent — use it sparingly
and with intent (primary buttons, KPI numbers via `background-clip:text`,
active-nav left bar). Everything else stays in the dark surface/line/text
scale. Never use flat saturated brand colours as large fills.

## Typography

- **Bricolage Grotesque** → display text: h1-h4, page titles, KPI numbers,
  brand name. `letter-spacing:-.4px`.
- **Manrope** → body, labels, table text, inputs. `letter-spacing:.1px`.

## Signature "S" treatments (reproduce all five)

1. **Ambient page background** — aurora radial glows + faint rotated S
   watermark at `opacity:.05` + a noise grain overlay.
2. **Splash orbit loader** — two counter-spinning rings around a breathing
   S mark, with a ribbon progress bar below.
3. **Route-change loader overlay** — `~360ms` darkened backdrop with a
   small breathing S mark, shown on every screen switch.
4. **Skeleton shimmer** — rainbow sweep (pink→orange) across a dark
   `--surface2` base.
5. **Card corner S accent** — a faint S mark anchored to the bottom-right
   of cards at `opacity:.05`.

## Layout / shell

1. **Splash** — dark glow background, orbit loader, wordmark, uppercase
   tagline, ribbon progress bar. Auto-hides after ~2.2s.
2. **Login** — split panel: left "art" panel with a rotated S at
   `opacity:.16` and a pitch headline whose accent word uses the ribbon
   gradient via `background-clip:text`; right "form" panel with `.inp`
   fields and a gradient primary button.
3. **App shell** — 248px sidebar with grouped nav (active item gets a 3px
   ribbon left bar) + 64px blurred topbar + scrollable canvas. Page header:
   breadcrumb (ribbon-accent word), big title, description, right-aligned
   actions.

## Quality bar

- Dark theme only. Generous negative space. Crisp 1px hairline borders.
- Restraint with the rainbow — thin accents and small highlights only; the
  canvas stays dark and quiet so the ribbon pops.
- Realistic, domain-specific demo data — never "Lorem ipsum."
