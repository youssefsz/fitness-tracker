# Fitness tracker design system

This guide describes the app's visual language and interaction rules. Use the palette, typography, and component behavior to keep new screens coherent. Layouts can evolve with the product.

The product records results whenever someone exercises. It supports repetitions, duration, historical entries, multiple sets, and optional personal goals. It does not prescribe routines, schedules, or streaks.

## Design principles

- Make the latest recorded set easy to find. Keep personal best and total volume separate.
- Put content directly on the page. Use alignment, spacing, and thin separators to group information.
- Use green for meaningful actions, selected chart points, and progress information. Do not color every element.
- Keep logging short. Show additional sets, notes, and exercise selection when needed.
- Preserve actual dates and declines. Missing activity is missing data, never a zero result.
- Keep controls recognizable and labels explicit. Visual restraint must not hide functionality.

Use flat surfaces, quiet separators, and exercise icons with text labels. Keep the focus on recorded activity.

## Color tokens

The [Flutter theme](lib/app/theme.dart) defines the full palette for both appearances.

| Role | Light | Dark |
| --- | --- | --- |
| App background | `#FAFAFA` | `#121212` |
| Surface | `#FFFFFF` | `#1D1D1D` |
| Input surface | `#F0F0F0` | `#262626` |
| Primary text | `#191919` | `#F2F2F2` |
| Supporting text | `#606060` | `#B2B2B2` |
| Primary action and charts | `#176B45` | `#91D8A9` |
| Add button and brand accent | `#B5EC7C` | `#B5EC7C` |

Use neutral surfaces in both appearances. Use the paired foreground from the theme on filled buttons and check text contrast in both modes.

## Typography

Use the platform system sans-serif on iOS and Android. Keep numbers aligned with tabular figures where available.

| Role | Starting size | Weight | Use |
| --- | --- | --- | --- |
| Screen title | 32 | 650–700 | Overview, Progress, History |
| Section title | 22–24 | 600–650 | Your exercises, Recorded sets |
| Primary result | 30–36 | 650–700 | Latest set or editable goal value |
| Exercise name | 18–20 | 600 | Exercise lists and entry groups |
| Body / form label | 16 | 400–500 | Input labels and explanations |
| Supporting text | 13–14 | 400–500 | Dates, units, summaries |
| Navigation label | 14–15 | 500–600 | Floating capsule tabs |

Sizes are logical platform units, not image pixels. Respect system text scaling. Allow rows to grow and supporting text to wrap. Avoid tiny all-caps labels and excessive letter spacing. Keep units visually quieter than values but fully readable.

## Layout and spacing

Use an 8-unit spacing rhythm, with 4-unit adjustments for closely related text.

| Token | Value | Use |
| --- | --- | --- |
| `space.xs` | 4 | Value-to-unit and tightly related labels |
| `space.sm` | 8 | Related controls |
| `space.md` | 16 | Row and form spacing |
| `space.lg` | 24 | Screen side margins and group spacing |
| `space.xl` | 32 | Separation between major sections |
| `space.2xl` | 40 | Occasional larger section separation |

Use 20–24 units of horizontal screen padding, reducing to 16 only when a compact width requires it. Align headings, chart edges, and list content to the same grid. Keep related labels closer to their values than to the next section.

Most content has no container background. Small inputs can have 8–12 unit corners; main action buttons can use 12–16. Reserve fully rounded shapes for the specified navigation capsule, its selected tab, and the circular Add button. A single subtle shadow may separate floating navigation from content; ordinary rows and charts do not need shadows.

## Navigation

The main tabs are **Overview**, **Progress**, and **History**. The content switches instantly while the selected tab indicator slides. Respect Reduce Motion.

The bottom navigation consists of two physically separate elements:

1. A horizontal capsule using the theme's surface color. The selected tab has a high-contrast indicator.
2. A separate circular light green button containing a centered dark plus sign. It opens activity logging.

Start with a 56-unit height, a 12-unit gap, and approximately 20-unit outer margins. Place both elements above the bottom safe area. Add content padding so the final row can scroll clear of them. Preserve the two-element composition on narrow screens and with larger text; do not replace it with a conventional full-width tab bar.

Secondary pages use platform navigation. Add entry uses a sheet with a Back action between steps, including exercise creation. The sheet closes on a downward drag or outside tap and asks before discarding a draft. Focused forms have one clear save action.

## Component rules

### Exercise summaries

Place the exercise name on the left and latest result on the right. Show the result date, personal best, first result, and improvement in subordinate text. A small trend line can support the row. Never use the personal best as if it were the latest result.

Only exercises with recorded results appear as tracked exercises on Overview. Created but unused exercises belong in the exercise library and selection flow. Archiving hides an exercise from active selection while retaining its dated history.

### Logging and forms

Use an open table for repeated sets. Each row has a set number, an editable value, and a remove action. Use a numeric keyboard for repetition counts and separate minute/second fields for duration. Label the units visibly.

Start with today, but make changing to a past date straightforward. Allow multiple sets and multiple exercises before saving. Keep Add set and Add another exercise distinct. Notes are optional. Show the save action above the keyboard when it is open.

Present invalid values next to the affected field with a correction, such as “Enter seconds from 0 to 59.” Preserve valid input after an error. Use positive whole repetitions and a positive total duration. Do not prefill fabricated results.

### Buttons and destructive actions

Use one primary save action per form. Secondary actions are plain text or quiet outlined controls. Keep Delete entry and Remove goal visually separate from Save. Confirm destructive deletion with wording that names what will be removed. Archive and restore are distinct from deleting data.

All tappable controls should have at least a 48-by-48 logical-unit hit area, including small-looking icons. Give icon-only controls accessible names.

### Calendar

Mark dates containing records with a small dot. Use a filled dark circle for the selected day. Provide month navigation and a month/year chooser. Do not connect dots into streaks or label unrecorded days as failures. Always show the selected date above its entries.

### Goals

Support one optional best-set goal per exercise. Show the target, current personal best, and remaining amount. A simple horizontal progress indicator is sufficient. The target date is optional and can stay unset. Do not add schedules, reminders, or missed-goal pressure by default.

## Analytics and chart behavior

The latest set leads the summary, as requested. For multiple sets recorded on one date, preserve their entered order and use the last set for that date's latest-result display. Activity dates determine historical placement; adding an older record must not make it appear to have happened today.

| Metric | Definition |
| --- | --- |
| First result | First recorded set in the selected date range |
| Latest result | Last recorded set on the latest activity date in the range |
| Best result | Maximum individual set value in the range |
| Absolute improvement | Latest result minus first result |
| Percentage improvement | `(latest - first) / first × 100`, when comparison is meaningful |
| Total volume | Sum of the recorded repetitions or duration in the range |
| Set count | Number of individual recorded sets or attempts |
| Recorded dates | Number of distinct dates with actual entries |

For a single set, show its result and date, with “Not enough history to compare.” Do not invent a percentage. Handle any imported zero baseline without division by zero. Show negative improvement honestly. Do not sum repetitions and seconds into one cross-exercise number.

Use **Latest set** and **Best set** as two views of the same performance chart. Show the selected view with an underline.

- Space points according to actual calendar dates, not equally spaced record indices.
- Plot the last set per recorded date in Latest set mode and the day's maximum in Best set mode. Keep all individual attempts accessible in History.
- Use a thin solid green line and visible recorded points. Do not fill the area with a gradient.
- A selected point shows the exact date, value, and unit. Provide an accessible text/list alternative to touch selection.
- Lines connect observations; they do not create intermediate records. Missing dates remain gaps without zero-valued marks.
- Keep y-axis labels readable and use a zero baseline for volume bars. Avoid smoothed curves that exaggerate peaks or declines.
- Apply 7-day, 30-day, 90-day, last-year, all-time, and inclusive custom filters to all range statistics.
- If an all-time personal record is shown beside filtered statistics, label it explicitly as all-time.

## Feedback, motion, and accessibility

Use immediate visual press feedback and restrained native transitions. A short 150–220 ms transition is a starting point for changing views. Respect reduced-motion settings. Haptic feedback can confirm a saved entry, but should not accompany every field tap.

Use honest empty, loading, and error states. Empty history should say there are no records for that date or range and offer an appropriate action. A save failure retains the draft and offers Retry. Do not display sample values in a real empty account.

Support screen readers, logical focus order, increased text sizes, and clear focus indicators. State selected tabs and dates programmatically. Never rely on color alone to distinguish selection, progress, or errors.

## Brand assets

The launcher icon uses a charcoal runner with the FT initials on a lime background. The splash screen uses the same mark on the neutral background for each appearance.

[Brand configuration](tool/brand.json) supplies the display name and launch colors. The [icon master](tool/brand_sources/app-icon.png) and [transparent mark master](tool/brand_sources/mark.png) supply the artwork. Run the [asset generator](tool/generate_brand_assets.py) to regenerate the platform assets after changing the artwork or launch colors.
