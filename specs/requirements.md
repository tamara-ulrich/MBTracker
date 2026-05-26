# MBTracker — Requirements Specification

## Overview
MBTracker is an iPhone app for tracking daily Mandarin Blueprint (MB) study activities. It helps maintain the correct time ratios across activity types and visualises learning progress over time.

---

## Activity Tracking

### Activity Types
Four study activities are tracked:
- **Build** — learning new characters and words (70–80% of study time by default)
- **Get** — comprehensible input (15–25% by default)
- **Activate** — active output practice (5–10% by default)
- **Immerse** — unstructured immersion; no target ratio, time shown for reference only

### Timer Behaviour
- One activity can run at a time; only one timer is active at once.
- Start buttons (Build, Get, Activate, Immerse) are hidden while a timer is running.
- Stopping the timer saves the session.
- When **Build** is stopped, a wheel picker appears asking "Which character did you last complete?" — the user selects the last MB character they finished; `lastLearnedIndex` is set to `pickerIndex + 1` (exclusive upper bound).
- Timer state (activity + start time) is persisted to `@AppStorage` so it survives app termination. On relaunch, the timer is restored and elapsed time is computed from the original start time.

### Manual Time Correction
- Each activity row has a prominent blue pencil-circle edit icon.
- Tapping it opens an edit sheet with:
  - **Date picker** — defaults to today; restricted to onboarding date onwards; changing the date loads that day's saved data.
  - **Hours / Minutes** — typed via numeric keyboard (tapping outside or scrolling dismisses the keyboard).
  - **Last character completed** (Build only) — wheel picker showing characters only (not words), bounded by the surrounding days' snapshots: lower = previous day's last character (selecting it means 0 characters done that day), upper = next day's first character minus one.
- The edit replaces all saved sessions for that activity on the selected date with a single corrected entry. For Build, it also updates the daily snapshot (or `lastLearnedIndex` if editing today).
- The edit icon is disabled while that activity's timer is running.

### Daily Reset
- The study day resets at **3:00 AM** (not midnight).
- On app launch, if the current study day key has changed, today's `lastLearnedIndex` is saved as a daily snapshot and `todayStartIndex` is reset.

### Onboarding
- On first launch, a modal sheet appears asking "Which character did you last complete?"
- A wheel picker lets the user scroll to the last character they finished.
- "Start from beginning" sets all indices to 0; "Save" sets them to the selected character's position + 1.
- The sheet cannot be dismissed without making a choice (`interactiveDismissDisabled`).
- On save, `onboardingLearnedIndex` and `onboardingDateKey` are stored once and never changed by any other code.
- Users who installed before this feature was added see a one-time prompt on next launch to enter their starting character (can be skipped, defaulting to 0).

### Index semantics
- `lastLearnedIndex` is always an **exclusive** upper bound: items `0..<lastLearnedIndex` have been learned; item at `lastLearnedIndex` is the next to do.
- All pickers display **characters only** (not words), numbered by their position in the character-only list.
- Pickers store `pickerIndex + 1` (exclusive upper bound).

---

## Ratio Display (Tracker Screen)

- Header shows **current MB level** and **current character number** (total characters completed so far).
- Shows current percentage of total study time for Build, Get, and Activate.
- Each activity shows:
  - Colour-coded percentage (green = in range, orange = above range, red = below range)
  - Target range (e.g. "70–80%")
  - Total minutes today
  - Minutes needed to reach the minimum target (shown in orange when below range)
- Build row additionally shows characters learned today.
- Immerse row shows total minutes only (no ratio target).
- An **ⓘ button** next to the "Today's Ratios" heading opens an info sheet describing each activity type:
  - **Build**: Going through Blueprint lessons · Making movies for new characters · Choosing sets, actors, and props · Generating living links for words · Doing flashcards from the lessons
  - **Get**: Reading Kickstarter or Blueprint sentences · Reading along while listening to the audio
  - **Activate**: Shadowing · Basic recall flashcards (English → Chinese) · Tutoring sessions
  - **Immerse**: Passive listening while doing something else (e.g. driving, household chores) · Usually Blueprint sentences · Goal: 1 hour per day

---

## Learning Items

- 10,701 Mandarin Blueprint learning items embedded in the app as a compact CSV (`LearningData.swift`).
- Each item has: index (0-based), simplified Chinese text, type (character or word), MB level (1–88).
- `allCharacters` is a pre-filtered array of character-only items, used for all pickers and character counts.
- Used to compute characters/words learned per day and per level.

---

## Statistics Screen

Accessible via the **Stats** tab in the bottom tab bar.

### Period Filter
Three options (segmented picker):
- **7 Days** — last 7 *completed* study days (excludes today)
- **Month** — last 30 *completed* study days (excludes today)
- **All Time** — since the beginning (includes today)

### Summary Section
- **Study time** — Build + Get + Activate only; Immerse excluded
- **Ratios** — Build / Get / Act percentages shown in activity colours
- **7 Days / Month view:**
  - Characters learned in the period, counted from `max(onboardingLearnedIndex, periodStartIndex)` as floor
  - Avg immersion/day — turns green when ≥ 60 minutes
- **All Time view:**
  - Items learned (from zero)
  - Characters learned (from zero)
  - Words learned (from zero)

### Daily Breakdown
- Only shows days from the onboarding date onwards, regardless of selected period.
- Today is only shown in the All Time view (excluded from 7-day and month views).
- One row per study day. Shows: weekday + date, total study time (Build + Get + Activate only).
- First sub-row: per-activity minutes (Build/Get/Activate/Immerse) and characters learned.
- Second sub-row: per-activity percentages (Build/Get/Activate only).

### CSV Export
- **Export** toolbar button opens a menu with two options:
  - **Export daily data as CSV** — columns: Date, Level, Build (min), Get (min), Activate (min), Immerse (min), Build%, Get%, Act%, Items Learned, Characters, Words.
  - **Export level history as CSV** — columns: Level, Status, Total Items, Calendar Days, Build (min).
- Both exports contain all historical data (not filtered by selected period).
- Uses native SwiftUI `ShareLink` to open the iOS share sheet.

### Level History
- One row per MB level reached (most recent first).
- Completed levels: level number, total items (with character and word count), calendar days, Build time.
- In-progress level: "in progress" badge, chars/words in level, chars learned + progress percentage.

---

## Navigation
- Three-tab bottom tab bar: **Tracker**, **Stats**, **Settings**.

## Settings
- Configurable min/max target percentages for Build, Get, and Activate.
- Stored persistently via `@AppStorage`.
- **Clear all data** button (destructive, with confirmation dialog): deletes all study sessions, clears all daily snapshots, and resets all app state (including re-triggering onboarding on next launch).

---

## Persistence

| Data | Storage |
|---|---|
| Study sessions (activity, duration, date) | SwiftData (`StudySession`) |
| Daily end-of-day learned index snapshots | UserDefaults (JSON dict keyed by "yyyy-MM-dd") |
| Target percentages, lastLearnedIndex, todayStartIndex, todayDateKey | UserDefaults via `@AppStorage` |
| Onboarding value (`onboardingLearnedIndex`, `onboardingDateKey`) | `@AppStorage` — set once, never changed |
| Active timer state (`timerActivity`, `timerStartTime`) | `@AppStorage` — cleared on stop |

---

## App Icon
- Blue-to-indigo gradient background.
- White clock face showing 10:10 in the upper portion.
- "汉字" in white PingFang SC Semibold below the clock.
- Generation scripts in `specs/`:
  - `generate_icon_combined.swift` — current icon (run with `swift specs/generate_icon_combined.swift`)
  - `generate_icon_clock.swift` — clock-only alternative

---

## Developer Utilities (Stats Screen)
- **Load Sample Data** function inserts ~55 days of fake session data and daily snapshots (hidden from UI; accessible via code only).

---

## Technical Notes
- SwiftUI + SwiftData, minimum deployment target **iOS 18.0**.
- Study day boundary: 3:00 AM local time.
- Daily snapshots use `snapshotDateKey(for:)` ("yyyy-MM-dd") for storage and `dateFromSnapshotKey(_:)` to reconstruct 3am `Date` values for comparison.
- Period filtering for items/characters/words is derived from daily snapshots: the snapshot immediately before the period start sets the baseline index.
- 7-day and month periods use `dayStart(for: Date())` as the upper bound (excludes today's partial data) so ratios and averages reflect only completed days.
