# Fitness tracker design system

This guide describes the app's visual language and interaction rules. Use the palette, typography, and component behavior to keep new screens coherent. Layouts can evolve with the product.

The product records exercise results as reps, duration, weight, or weight and reps. It supports historical entries, optional sets, and personal goals.

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

Most content has no container background. Small inputs can have 8–12 unit corners; main action buttons can use 12–16. Reserve fully rounded shapes for the navigation capsule, its selected tab, and the circular Add and Profile buttons. A single subtle shadow may separate floating navigation from content; ordinary rows and charts do not need shadows.

## Navigation

The main tabs are **Overview**, **Progress**, and **History**. The content switches instantly while the selected tab indicator slides. Respect Reduce Motion.

The bottom navigation consists of two physically separate elements:

1. A horizontal capsule using the theme's surface color. The selected tab has a high-contrast indicator.
2. A separate circular light green button containing a centered dark plus sign. It opens activity logging.

Start with a 56-unit height, a 12-unit gap, and approximately 20-unit outer margins. Place both elements above the bottom safe area. Add content padding so the final row can scroll clear of them. Preserve the two-element composition on narrow screens and with larger text; do not replace it with a conventional full-width tab bar.

Overview places the Profile button beside the page heading. Show the saved avatar in a 48-unit circular button with a neutral border. Keep the Profile label for assistive technology and show the bundled Default avatar image while a saved image loads or when no other avatar is set.

Secondary pages use platform navigation. Add entry uses a sheet with a Back action between steps, including exercise creation. The sheet closes on a downward drag or outside tap and asks before discarding a draft. Focused forms have one clear save action.

Full-screen secondary pages use a large heading that gives way to a compact toolbar title as it scrolls offscreen. Back and toolbar actions stay pinned. On Profile, place the compact title and avatar beside Back. Fade the title in as the large heading leaves view, and let the avatar finish shrinking into place as scrolling continues. Let short pages fit naturally. With Reduce Motion, switch each element at its scroll position without fading or moving it across the screen.

## Component rules

### Exercise summaries

Place the exercise name on the left and latest result on the right. Show the result date, personal best, first result, and improvement in subordinate text. A small trend line can support the row. Never use the personal best as if it were the latest result.

Only exercises with recorded results appear as tracked exercises on Overview. Created but unused exercises belong in the exercise library and selection flow. Archiving hides an exercise from active selection while retaining its dated history.

Group Overview's list actions in one More menu beside Your exercises. Label its actions Reorder exercises and Exercise library. Reordering opens a focused sheet with compact exercise rows, trailing drag handles, and pinned Cancel and Done actions. Touching a reorder row immediately shows a soft neutral press highlight without changing its size. Clear that highlight on release, cancellation, scrolling, or pickup. Holding anywhere on a row starts dragging. Confirm pickup with one light haptic, respecting the haptics setting. Tint the picked-up row subtly green and accent its handle for the duration of the drag. Keep these static cues with Reduce Motion and omit the animated shadow. The lifted row keeps balanced inset padding and excludes the separator. Tapping a handle offers Move up, Move down, Move to top, and Move to bottom; screen readers also have move actions. Keep performance charts on Overview. Pin the recent-order status and reset control below the scrolling rows. Reserve the same footer space for both labels, including at larger text sizes, so changing the draft does not resize the sheet. Use recent order changes the draft and takes effect only after Done. Cancel or dismissing the sheet leaves the saved order intact. Keep the draft and offer a retry if saving fails.

### Logging and forms

Give the current result a large, centered number. Use separate fields for minutes and seconds, and show reps beside the load for weighted exercises that track both. When the exercise tracks sets, show the set being edited and list the other sets in compact rows that reopen them for editing. Label the units visibly.

Start with today, but make changing to a past date straightforward. Allow multiple sets and multiple exercises before saving. Keep Add set and Add another exercise distinct. Notes are optional. Show the save action above the keyboard when it is open.

Present invalid values next to the affected field with a correction, such as “Enter seconds from 0 to 59.” Preserve valid input after an error. Accept explicit zeros and reject negatives. A blank field does not log a result.

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
- On performance and daily volume charts, tap or drag horizontally across the plot to select the nearest recorded date. Keep the last selection when the gesture ends and let vertical swipes scroll the page.
- Lines connect observations; they do not create intermediate records. Missing dates remain gaps without zero-valued marks.
- Keep y-axis labels readable and use a zero baseline for volume bars. Avoid smoothed curves that exaggerate peaks or declines.
- Apply 7-day, 30-day, 90-day, last-year, all-time, and inclusive custom filters to all range statistics.
- If an all-time personal record is shown beside filtered statistics, label it explicitly as all-time.

## Feedback, motion, and accessibility

Use immediate visual press feedback and restrained native transitions. A short 150–220 ms transition is a starting point for changing views. Respect reduced-motion settings. Haptic feedback can confirm a saved entry, but should not accompany every field tap.

### Loading and refresh

Render headings, navigation, filters, and actions as soon as they are available. Start independent reads together. Reserve space for pending values inside the layout that will display them, including at larger text sizes. Paint quiet static skeletons from the first pending frame. Shape them like the expected rows, chart, avatar, or illustration. When content arrives, show it on the first resolved frame and fade out the skeleton over 180 ms. Overview and Progress render ready content at full opacity and fade the colors of the outgoing skeleton. Use `AsyncPanel` for provider-backed regions and `SkeletonCrossfade` for individual fields or images. Skip the animation when Reduce Motion is enabled.

Keep valid content and the scroll position during refresh and pagination. When the selected date, exercise, or range changes, replace the affected results in place with a placeholder for that query. Keep the controls available and only show values that match the selected query. Skeletons are decorative. Give each pending region a short accessible label.

If the first view needs several reads, keep one placeholder until its content is ready. On Progress, reveal the exercise and date filters with the first result, then keep the filters visible for later reads. Reveal the default avatar with the profile and keep a visible fallback while other avatar images decode.

Use inline progress for actions such as saving or importing. Keep the control in place, give it a status label such as “Saving…”, and prevent duplicate submission. Use a static indicator when Reduce Motion is enabled. Preserve the draft on failure and offer a retry close to the affected content.

On Android, show the optional update dialog after Overview opens. Show the version and download size before the user chooses Update. Show download progress and recovery actions on the App update page. Keep the download running if the user leaves the page. Use a tappable status row below the Overview heading to reopen update details. Draw download progress along the row’s bottom divider, and show a plain divider when the update is ready. Place Check for updates below the version in Android Profile. A manual check can reopen an active update or offer a release again after the user chooses Later. Explain the source permission only when the user chooses Install, and use Android’s own confirmation for the update.

Use the native splash for app startup. Show “Opening your records…” if the app is still opening local storage when the native splash hands off.

### Empty states

Show first-use guidance only after the app confirms there are no records. Explain what will appear and give people one clear next action, such as logging their first result. Overview pairs that action with a dedicated workout illustration in the app’s palette. Keep it decorative and compact so the action stays visible on a small screen. Offer backup import as a secondary action on Overview. Leave personal details and weigh-ins optional.

Align the first-use blocks on Overview and Progress to the same page margin. Progress can sit lower under its heading. Its notebook illustration shows blank graph paper so it cannot be mistaken for recorded activity.

Use compact, contextual messages for an empty day, a date range without activity, or a search with no matches. Offer a relevant action such as adding to the selected day, widening the range, or clearing the search. Keep empty, loading, and error states distinct and show only actual recorded values.

Support screen readers, logical focus order, increased text sizes, and clear focus indicators. State selected tabs and dates programmatically. Never rely on color alone to distinguish selection, progress, or errors.

## Brand assets

The launcher icon uses a charcoal runner with the FT initials on a lime background. The splash screen uses the same mark on the neutral background for each appearance.

[Brand configuration](tool/brand.json) supplies the display name and launch colors. The [icon master](tool/brand_sources/app-icon.png) and [transparent mark master](tool/brand_sources/mark.png) supply the artwork. Run the [asset generator](tool/generate_brand_assets.py) to regenerate the platform assets after changing the artwork or launch colors.
