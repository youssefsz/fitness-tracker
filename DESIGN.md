# Fitness tracker design system

This system defines the visual direction and interaction rules for a personal exercise progress tracker. The accompanying images show the intended layouts. Use the tokens and rules below to make the implementation consistent where generated images differ slightly in spacing, color, or control shape.

The product records results whenever someone exercises. It supports repetitions, duration, historical entries, multiple sets, and optional personal goals. It does not prescribe routines, schedules, or streaks.

## Design principles

- Make the latest recorded set easy to find. Keep personal best and total volume separate.
- Put content directly on the page. Use alignment, spacing, and thin separators to group information.
- Use green for meaningful actions, selected chart points, and progress information. Do not color every element.
- Keep logging short. Show additional sets, notes, and exercise selection when needed.
- Preserve actual dates and declines. Missing activity is missing data, never a zero result.
- Keep controls recognizable and labels explicit. Visual restraint must not hide functionality.

Avoid gradients, glows, decorative glass, stacked rounded cards, nested cards, decorative icon backgrounds, unnecessary illustrations, motivational pressure, and invented dashboard metrics.

## Color tokens

These are the intended implementation values. Generated PNG pixels can vary slightly.

| Token | Value | Use |
| --- | --- | --- |
| `background` | `#FAFBF8` | Main app background |
| `surface` | `#FFFFFF` | Floating navigation and focused controls |
| `text.primary` | `#19271F` | Headings, results, primary labels |
| `text.secondary` | `#637067` | Supporting labels and dates |
| `border.subtle` | `#DFE5DD` | Row separators and form boundaries |
| `surface.input` | `#EEF2EA` | Editable fields and search |
| `action.primary` | `#176B45` | Main actions and chart strokes |
| `action.add` | `#B5EC7C` | Separate floating Add button and app icon |
| `selection.soft` | `#E7EFDF` | Subtle selected rows |
| `danger` | `#B42318` | Delete and remove actions |
| `chart.grid` | `#D9E1D8` | Sparse chart reference lines |

Use dark text on the light green Add button. Use white text on dark green or charcoal buttons. Do not use light green as small text on a white background. Verify contrast in the implemented interface rather than judging the raster mockups alone.

Only light appearance is illustrated in this package. Settings includes a system appearance preference; a dark palette still needs to be designed and checked before that option is implemented.

## Typography

Use the platform system sans-serif for the native app: San Francisco on iOS and the system font on Android. The images establish the hierarchy, not a licensed or identified font file. Keep numbers aligned with tabular figures where available.

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

The app has exactly three main tabs: **Overview**, **Progress**, and **History**.

The bottom navigation consists of two physically separate elements:

1. A white horizontal capsule containing the three text tabs. The selected tab sits in a smaller charcoal pill with white text. Inactive labels are dark.
2. A separate circular light green button containing a centered dark plus sign. It opens activity logging.

Start with a 56-unit height, a 12-unit gap, and approximately 20-unit outer margins. Place both elements above the bottom safe area. Add content padding so the final row can scroll clear of them. Preserve the two-element composition on narrow screens and with larger text; do not replace it with a conventional full-width tab bar.

Secondary pages use a back action. Focused forms use Cancel and one clear save action. Support platform back gestures and keyboard dismissal. Protect an unsaved draft when a dismissal would lose entered data.

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

Use **Latest set** and **Best set** as two views of the same performance chart. Normalize their control style across screens to plain text tabs with a dark underline on the selected view. The generated images vary slightly here; this rule takes precedence.

- Space points according to actual calendar dates, not equally spaced record indices.
- Plot the last set per recorded date in Latest set mode and the day's maximum in Best set mode. Keep all individual attempts accessible in History.
- Use a thin solid green line and visible recorded points. Do not fill the area with a gradient.
- A selected point shows the exact date, value, and unit. Provide an accessible text/list alternative to touch selection.
- Lines connect observations; they do not create intermediate records. Missing dates remain gaps without zero-valued marks.
- Keep y-axis labels readable and use a zero baseline for volume bars. Avoid smoothed curves that exaggerate peaks or declines.
- Apply 7-day, 30-day, 90-day, last-year, all-time, and inclusive custom filters to all range statistics.
- If an all-time personal record is shown beside filtered statistics, label it explicitly as all-time.

The sample push-up data totals **129 reps across 8 sets on 6 dates**. The latest set is **18**, the personal best **22**, and the first set **10**. On 12 November, the sets **22, 20, 18** total **60 reps**. Raster chart positions are illustrative; implementation must calculate exact coordinates from the recorded dates.

## Feedback, motion, and accessibility

Use immediate visual press feedback and restrained native transitions. A short 150–220 ms transition is a starting point for changing views. Respect reduced-motion settings. Haptic feedback can confirm a saved entry, but should not accompany every field tap.

Use honest empty, loading, and error states. Empty history should say there are no records for that date or range and offer an appropriate action. A save failure retains the draft and offers Retry. Do not display sample values in a real empty account.

Support screen readers, logical focus order, increased text sizes, and clear focus indicators. State selected tabs and dates programmatically. Never rely on color alone to distinguish selection, progress, or errors.

## Brand assets

The identity uses a substantial V with a slightly higher right arm. The app's full name is not finalized; this package does not invent a wordmark.

| File | Format | Use |
| --- | --- | --- |
| [Primary V logo](docs/reference/brand/v-logo-dark.png) | 1254 × 1254 RGBA PNG | Transparent charcoal mark on light surfaces |
| [App icon](docs/reference/brand/v-app-icon.png) | 1254 × 1254 RGB PNG | Opaque green square with charcoal V |
| [Favicon](docs/reference/brand/v-favicon.png) | 1254 × 1254 RGB PNG | Opaque charcoal square with green V |

Preserve aspect ratio and keep the supplied clear space. Do not stretch, rotate, add shadows, or add gradient fills. Let the platform apply its own app-icon mask; the supplied icon has square outer corners. These are raster source assets, not SVG masters or complete native icon catalogs. Platform build tooling should create its required output sizes.

The light/inverse-logo experiments are excluded because their transparent edges were not suitable for delivery.

## Screen inventory

Each screen is its own PNG. Measurements and dates shown in the mockups are illustrative.

| Screen | Image | Purpose |
| --- | --- | --- |
| Overview | [01-overview.png](docs/reference/screens/01-overview.png) | Latest results and recent activity |
| Progress | [02-progress.png](docs/reference/screens/02-progress.png) | Performance, comparison, and volume |
| History | [03-history.png](docs/reference/screens/03-history.png) | Calendar and dated sets |
| Exercise details | [04-exercise-details.png](docs/reference/screens/04-exercise-details.png) | Individual history and optional goal |
| Choose exercise | [05-choose-exercise.png](docs/reference/screens/05-choose-exercise.png) | Search, recents, and creation entry point |
| Log repetitions | [06-log-repetitions.png](docs/reference/screens/06-log-repetitions.png) | Multiple sets and exercises |
| Log duration | [07-log-duration.png](docs/reference/screens/07-log-duration.png) | Minute/second entry with keyboard |
| Manage exercises | [08-manage-exercises.png](docs/reference/screens/08-manage-exercises.png) | Edit, archive, and restore |
| Create exercise | [09-create-exercise.png](docs/reference/screens/09-create-exercise.png) | Name and measurement type |
| Set a goal | [10-set-goal.png](docs/reference/screens/10-set-goal.png) | Optional best-set target |
| Settings | [11-settings.png](docs/reference/screens/11-settings.png) | Appearance, units, export, and import |
| Date range | [12-date-range.png](docs/reference/screens/12-date-range.png) | Presets and custom dates |
| Edit entry | [13-edit-entry.png](docs/reference/screens/13-edit-entry.png) | Correct sets, date, notes, or delete |
| Empty Overview | [14-overview-empty.png](docs/reference/screens/14-overview-empty.png) | First result or backup import |

## Local gallery

The gallery is available at [http://127.0.0.1:4173/fitness-gallery/](http://127.0.0.1:4173/fitness-gallery/) while the local server is running. Its sidebar groups main pages, logging, exercises, goals/preferences, states, and brand assets. Search, individual downloads, full-size viewing, and previous/next navigation are available.

The gallery is a separate browsing tool. Its desktop sidebar is not part of the mobile app's navigation system.

## Reference patterns

The design study used [Hevy's set-entry layout](https://mobbin.com/screens/7178a6f5-fe6b-4b20-9e1b-909af6cd8382), [Gymshark's chart selection](https://mobbin.com/screens/9e5ab8b6-48c8-4025-b2f0-4d251f925256), and [Fitbit's activity calendar](https://mobbin.com/screens/fde27a89-f4ce-4811-82d1-be58d7db98b4). These are iOS references for specific interaction patterns. The app retains its own layout, colors, scope, and required floating navigation.
