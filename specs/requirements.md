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
- When **Build** is stopped, a wheel picker appears asking "Which item did you last complete?" — the user selects the last MB item they finished; `lastLearnedIndex` is set to `pickerIndex + 1` (exclusive upper bound).

### Manual Time Correction
- Each activity row has a prominent blue pencil-circle edit icon.
- Tapping it opens an edit sheet with:
  - **Date picker** — defaults to today; changing the date loads that day's saved data.
  - **Hours / Minutes** — typed via numeric keyboard (tapping outside or scrolling dismisses the keyboard).
  - **Last item completed** (Build only) — wheel picker bounded by the surrounding days' snapshots: lower = previous day's last item (selecting it means 0 items done that day), upper = next day's first item minus one.
- The edit replaces all saved sessions for that activity on the selected date with a single corrected entry. For Build, it also updates the daily snapshot (or `lastLearnedIndex` if editing today).
- The edit icon is disabled while that activity's timer is running.

### Daily Reset
- The study day resets at **3:00 AM** (not midnight).
- On app launch, if the current study day key has changed, today's `lastLearnedIndex` is saved as a daily snapshot and `todayStartIndex` is reset.

### Onboarding
- On first launch (or after "Clear all data"), a modal sheet appears asking "Which item did you last complete?"
- A wheel picker lets the user scroll to the last item they finished; indices are set to `pickerIndex + 1`.
- "Start from beginning" sets both indices to 0; "Save" sets them to the selected item's position + 1.
- The sheet cannot be dismissed without making a choice (`interactiveDismissDisabled`).

### Index semantics
- `lastLearnedIndex` is always an **exclusive** upper bound: items `0..<lastLearnedIndex` have been learned; item at `lastLearnedIndex` is the next to do.
- All pickers display the **last completed item** (inclusive) and store `pickerIndex + 1`.

---

## Ratio Display (Home Screen)

- Shows current percentage of total study time for Build, Get, and Activate.
- Each activity shows:
  - Colour-coded percentage (green = in range, orange = above range, red = below range)
  - Target range (e.g. "70–80%")
  - Total minutes today
  - Minutes needed to reach the minimum target (shown in orange when below range)
- Build row additionally shows characters and words learned today.
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
- Used to compute characters/words learned per day and per level.

---

## Statistics Screen

Accessible via the **Stats** tab in the bottom tab bar.

### Period Filter
Three options (segmented picker):
- **7 Days** — last 7 days
- **Month** — last 30 days
- **All Time** — since the beginning

### Summary Section
Always shows:
- Current MB level
- Total study time for the selected period (Build + Get + Activate only; Immerse excluded)
- Ratios for the selected period (Build / Get / Act percentages, shown in activity colours)
- Items learned in the period
- Characters learned in the period
- Words learned in the period
- **Avg immersion/day** for the selected period — turns green when ≥ 60 minutes (the daily goal)

### Daily Breakdown
- One row per study day within the selected period.
- Shows date and total study time (Build + Get + Activate only; Immerse excluded).
- First sub-row: per-activity minutes (Build/Get/Activate/Immerse) and characters/words learned.
- Second sub-row: per-activity percentages (Build/Get/Activate only; Immerse excluded from ratio).

### CSV Export
- **Export** toolbar button on the Stats screen opens a menu with two options:
  - **Export daily data as CSV** — one row per day; columns: Date, Level, Build (min), Get (min), Activate (min), Immerse (min), Build%, Get%, Act%, Items Learned, Characters, Words. Level reflects the MB level reached by end of that day.
  - **Export level history as CSV** — one row per MB level; columns: Level, Status, Total Items, Calendar Days, Build (min).
- Both exports contain all historical data (not filtered by selected period).
- Uses native SwiftUI `ShareLink` to open the iOS share sheet (Files, email, AirDrop, etc.).

### Level History
- One row per MB level reached (most recent first).
- Shows level number, "in progress" badge for the current level, total items in the level (with character and word count), number of calendar days spent, and total Build time.

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
- **Load Sample Data** button inserts ~55 days of fake session data and daily snapshots, offset from the current `lastLearnedIndex` so it doesn't conflict with real tracking.
- Includes rest days (no sessions, snapshot unchanged) and no-Build days (Get/Activate only) to verify correct handling of gaps.
- Also sets `todayStartIndex` and `lastLearnedIndex` to consistent values based on the sample offsets.
- For clean testing: Clear all data → skip onboarding → Load Sample Data (gives absolute indices starting from 0).
- Intended for UI preview and testing only; removed via "Clear all data" when done.

---

## Technical Notes
- SwiftUI + SwiftData (iOS).
- Study day boundary: 3:00 AM local time.
- Daily snapshots use `snapshotDateKey(for:)` ("yyyy-MM-dd") for storage and `dateFromSnapshotKey(_:)` to reconstruct 3am `Date` values for comparison.
- Period filtering for items/characters/words is derived from daily snapshots: the snapshot immediately before the period start sets the baseline index.
