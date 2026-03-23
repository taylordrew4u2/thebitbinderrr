# 🏠 BitBinder Homepage — Complete Design Breakdown

> *A comprehensive guide to everything on the BitBinder home screen,
> how it works, why it's laid out the way it is, and where every piece lives in code.*

---

## 📐 High-Level Architecture

The homepage is **not a tab bar app**. It uses a custom navigation system:

```
thebitbinderApp (entry point)
  └─ ContentView
       ├─ LaunchScreenView  (animated splash, fades out in 0.5s)
       └─ MainTabView       (the real shell — no UITabBar)
             ├─ HomeView             ← THE HOMEPAGE
             ├─ BrainstormView
             ├─ JokesView
             ├─ SetListsView
             ├─ RecordingsView
             ├─ NotebookView
             ├─ SettingsView
             └─ ModernSideMenu       (slides in from the right)
```

There is **no bottom tab bar**. Navigation between screens happens via:
1. A **floating FAB button** (top-right) that opens a **side menu** sliding in from the right.
2. Deep links within the homepage sections (e.g., tapping a joke row → `JokeDetailView`).
3. A **back button FAB** (top-left) that appears when navigation history exists.

**Key files:**
| File | Purpose |
|------|---------|
| `ContentView.swift` | Root view — shows launch screen, then `MainTabView` |
| `Views/HomeView.swift` | The homepage itself (~1,260 lines) |
| `Views/LaunchScreenView.swift` | Animated splash screen |
| `Utilities/AppTheme.swift` | Full design system (colors, typography, spacing, shadows) |
| `Utilities/BitBinderComponents.swift` | Shared reusable UI components |

---

## 🎨 Visual Identity — "The Comedian's Notebook"

The entire app is themed to feel like a physical comedy notebook:

| Design Element | Value | Purpose |
|---------------|-------|---------|
| **Background** | `paperCream` — `rgb(0.975, 0.960, 0.920)` | Yellowed notebook paper |
| **Text** | `inkBlack` — `rgb(0.11, 0.09, 0.09)` | Ballpoint pen ink |
| **Primary Action** | `rgb(0.20, 0.40, 0.70)` | Trustworthy blue — evidence-based choice for calm confidence |
| **Typography** | Serif `.display` (34pt bold) for titles | Old-school notebook feel |
| **Cards** | `surfaceElevated` with `sm` shadow | Subtle lift like a sticky note |
| **Spacing** | 8-pt grid system (`xxs`=4, `xs`=8, `sm`=12, `md`=16, `lg`=24) | Consistent rhythm |
| **Corner Radius** | `large` = 14pt for cards, `medium` = 10pt for inputs | Rounded, friendly |

### Launch Screen
Before the homepage appears, there's a **0.5-second animated splash**:
- Paper cream background with faint horizontal rule lines and a red margin line
- A leather-bound book icon that scales in with a spring animation
- "BitBinder" wordmark in serif font
- Tagline: *"shut up and write some jokes"*
- Personalized greeting: "Welcome back, [name]"
- Fades out with `.easeOut(duration: 0.25)`

---

## 📱 Homepage Layout (iPhone)

The homepage is a **single-column vertical scroll**. Here's every section from top to bottom:

### 1️⃣ Header Section
```
┌─────────────────────────────────────┐
│  BitBinder              [← Back] [☰]│  ← FABs float above, not in header
│                                      │
│  🔍 Search jokes, sets, tags...      │  ← Universal search bar
│                                      │
│  (Search results appear inline)      │
└─────────────────────────────────────┘
```

**Title:** "BitBinder" in `AppTheme.Typography.display` (34pt bold serif).

**Search Bar:**
- Full-width, rounded rectangle with `paperAged` background
- Magnifying glass icon + placeholder text
- Typing shows **inline results** below (max 10 results)
- Searches across: **jokes** (title, content, tags), **set lists** (name, notes), **recordings** (title, transcript), **brainstorm ideas** (content)
- Each result is a `NavigationLink` to the appropriate detail view
- Clear button (×) appears when searching
- Results show: type icon → title → type badge + preview text → chevron

### 2️⃣ Continue Working
```
┌─────────────────────────────────────┐
│  Continue Working                    │
│  ┌─────────────────────────────────┐ │
│  │ 🎭 My Latest Joke   Working 2m │ │  ← NavigationLink → JokeDetailView
│  │ 📋 Weekend Set     In Progress  │ │  ← NavigationLink → SetListDetailView
│  │ 💡 Bit about airline food  1h   │ │  ← Button → navigates to Brainstorm tab
│  │ 📥 notes.txt        3 items     │ │  ← NavigationLink → ImportBatchHistoryView
│  └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

**What it shows (up to 5 items):**
1. **Latest 3 jokes** — sorted by `dateModified` desc, filtered to non-deleted
   - Status dot: 🟢 Working, ⚪ Draft (content < 50 chars), 🟡 Needs Rewrite
2. **Most recent set list** — if one exists
3. **Most recent brainstorm idea** — title is first 60 chars of content
4. **Import batch needing review** — if any `ImportBatch` has `reviewQueueCount > 0`

**Empty state:** "Nothing recent — write something!" with a tray icon.

**Each row shows:**
- Type icon (color-coded to `primaryAction`)
- Title (single line, truncated)
- Status dot + status label
- Optional detail text (e.g., "3 items")
- Relative time ("Just now", "2m ago", "1h ago", "Yesterday", "3d ago")
- Right chevron

**Row design:** `surfaceElevated` background, `large` corner radius, `sm` shadow. Press effect scales to 0.98.

### 3️⃣ Quick Capture
```
┌─────────────────────────────────────┐
│  Quick Capture                       │
│  ┌─────────────────────────────────┐ │
│  │         ＋ New Joke              │ │  ← Full-width primary button (blue)
│  └─────────────────────────────────┘ │
│  ┌──────────┐┌──────────┐┌────────┐ │
│  │ 💡       ││ 🎤       ││ 💬     │ │  ← Three equal-width secondary buttons
│  │Brainstorm││Voice Note││Talk to │ │
│  │          ││          ││ Text   │ │
│  └──────────┘└──────────┘└────────┘ │
└─────────────────────────────────────┘
```

**Primary button:** "＋ New Joke"
- Full width, 14pt vertical padding
- Blue (`primaryAction`) background, white text
- Opens `AddJokeView` as a sheet
- Press: scales to 0.97, light haptic

**Secondary row (3 buttons side-by-side):**
| Button | Icon | Color | Opens |
|--------|------|-------|-------|
| Brainstorm | `lightbulb` | `brainstormAccent` (warm gold) | `AddBrainstormIdeaSheet` (sheet) |
| Voice Note | `mic.fill` | `recordingsAccent` (subtle red) | `StandaloneRecordingView` (sheet) |
| Talk to Text | `text.bubble.fill` | `primaryAction` (blue) | `TalkToTextView` (sheet) |

Each button: icon (22pt) above label (13pt semibold), vertical card layout, `surfaceElevated` bg, `sm` shadow. Press: scale 0.96, light haptic.

### 4️⃣ Sets in Progress
```
┌─────────────────────────────────────┐
│  Sets in Progress                    │
│  ┌─────────────────────────────────┐ │
│  │ Weekend Show        3 jokes 2:15│ │  ← NavigationLink → SetListDetailView
│  │ Open Mic Set        5 jokes 3:45│ │
│  └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

**Shows up to 3 most recent set lists**, sorted by `dateModified`.

**Each row displays:**
- Set list name (serif callout, single line)
- Joke count: `🎭 X jokes`
- Estimated runtime: ~45 seconds per joke, formatted as `M:SS`
- Relative time label
- Right chevron

**Empty state:** "No set lists yet" with list icon.

### 5️⃣ Needs Attention (conditional — only shows if items exist)
```
┌─────────────────────────────────────┐
│  Needs Attention                     │
│  ┌─────────────────────────────────┐ │
│  │ 🔍 3 imports need review     >  │ │  ← Taps navigate to Jokes screen
│  │ ─────────────────────────────── │ │
│  │ ⚠️ 2 recordings need cleanup >  │ │  ← Taps navigate to Recordings screen
│  │ ─────────────────────────────── │ │
│  │ 🏷️ 5 jokes are untagged      >  │ │  ← Taps navigate to Jokes screen
│  │ ─────────────────────────────── │ │
│  │ ✏️ 1 joke marked Needs Rewrite> │ │  ← Taps navigate to Jokes screen
│  └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

**Alert types (all computed from live data):**
| Alert | Condition | Icon | Variant | Navigates To |
|-------|-----------|------|---------|-------------|
| Imports need review | Any `ImportBatch` with `reviewQueueCount > 0` | `doc.text.magnifyingglass` | ⚠️ warning | Jokes |
| Recordings need cleanup | Any `Recording` where `isProcessed == false` | `waveform.badge.exclamationmark` | ⚠️ warning | Recordings |
| Untagged jokes | Jokes with empty tags AND nil category | `tag.slash` | ℹ️ info | Jokes |
| Needs Rewrite | Jokes where `difficulty == "needs rewrite"` | `pencil.line` | ⚠️ warning | Jokes |

Navigation uses `NotificationCenter` posting `.navigateToScreen` — `MainTabView` observes this and calls its `navigate(to:)` method.

**Card design:** Single `BitBinderCard` with low elevation wrapping all rows. Dividers between rows are indented 46pt from leading.

### 6️⃣ This Week (Insight Strip)
```
┌─────────────────────────────────────┐
│  This Week                           │
│  ┌──────┐ ┌──────┐ ┌────────────┐   │
│  │12    │ │ 3    │ │ 5 awaiting │   │  ← Horizontal scroll of capsule chips
│  │edited│ │ sets │ │   review   │   │
│  └──────┘ └──────┘ └────────────┘   │
└─────────────────────────────────────┘
```

**Chips (horizontal scrolling row):**
| Chip | Data Source |
|------|-------------|
| `X edited` | Jokes modified in the last 7 days |
| `X sets` / `X set` | Total active set lists |
| `X awaiting review` | Sum of `reviewQueueCount` across all import batches (only shown if > 0) |
| `X stage-ready` | Jokes where `isHit == true` |

**Chip design:** `InsightChip` — bold value (14pt rounded, `primaryAction` blue) + label (12pt medium, `textSecondary`), wrapped in a capsule with 8% opacity blue background.

---

## 🖥️ iPad Layout

On iPad (`horizontalSizeClass == .regular`), the homepage switches to a **two-column layout**:

```
┌─────────────────────────────────────────────────────────┐
│  Header (full width)                                     │
│  Search bar (full width)                                 │
├───────────────────────┬─────────────────────────────────┤
│  LEFT COLUMN          │  RIGHT COLUMN                    │
│                       │                                  │
│  Continue Working     │  Quick Capture                   │
│  • Row                │  • New Joke button               │
│  • Row                │  • Brainstorm / Voice / T2T      │
│  • Row                │                                  │
│                       │  Sets in Progress                │
│  Needs Attention      │  • Set row                       │
│  • Alert              │  • Set row                       │
│  • Alert              │                                  │
│                       │  This Week                       │
│                       │  • Insight chips                 │
└───────────────────────┴─────────────────────────────────┘
```

Both columns use `frame(maxWidth: .infinity)` so they share space equally. Spacing between columns: `AppTheme.Spacing.lg` (24pt).

---

## 🔥 Roast Mode

When `roastModeEnabled` is toggled ON (persisted via `@AppStorage`):

- **The homepage is completely hidden.** `MainTabView` redirects to `JokesView` (Roasts).
- Only two screens are accessible: **Roasts** (`.jokes`) and **Settings**.
- The entire app switches to `preferredColorScheme(.dark)`.
- Side menu branding changes to "**RoastBinder**" with fire/ember theming.
- Colors shift to charcoal backgrounds (`roastBackground`), ember orange accents (`roastAccent`), and fire gradients.

The homepage **does not render at all** in roast mode — there's an `EmptyView` + `onAppear` redirect.

---

## ☰ Side Menu (Navigation)

The side menu is a 300pt-wide panel that slides in from the right with a dimmed overlay behind it.

**Structure:**
```
┌──────────────────────┐
│  [X close]           │
│  📕 BitBinder        │
│  "shut up and write  │
│   some jokes"        │
├──────────────────────┤
│  🏠 Home        ●    │  ← Active indicator dot
│  💡 Brainstorm       │
│  🎭 Jokes            │
│  📋 Set Lists        │
│  🎙️ Recordings       │
│  📓 Notebook         │
│  ⚙️ Settings         │
│  ──────────────      │
│  💬 BitBuddy         │  ← AI chat, opens as sheet
├──────────────────────┤
│     ✏️ v9.4          │
└──────────────────────┘
```

**Menu header:**
- Leather gradient background (`leatherGradient`)
- Book icon in white-filled rounded rect
- "BitBinder" in 28pt bold serif
- Tagline in 12pt italic serif

**Menu items:** Each shows icon (18pt, screen's accent color) + label (16pt serif). Selected item gets:
- `primaryAction` color icon
- Semibold weight
- 10% opacity blue background fill
- Small circle indicator dot on the right

**Navigation history:** `MainTabView` maintains a `screenHistory` stack. The back FAB pops from this stack.

---

## 📦 File Import Pipeline (from Homepage)

The homepage has a **hidden but powerful import system**. While there's no visible "Import" button on the homepage itself, the import pipeline is deeply integrated:

1. `DocumentPickerView` can be triggered (via `showImportPicker` state)
2. Selected files go through `processDocuments(_:)` which:
   - Shows a processing overlay with `ProgressView` + status message
   - Tries the AI-powered `FileImportService.shared.importWithPipeline()`
   - Falls back to local `SmartTextSplitter` if AI fails
   - Supports: **PDF** (OCR per page), **DOC/DOCX**, **images** (OCR), **plain text**, **ASCII**
   - Memory-managed: images are downscaled, PDFs rendered at max 1000px, autoreleasepool used
3. Results open `SmartImportReviewView` as a full-screen cover

Import batches that need review appear in both **Continue Working** and **Needs Attention** sections.

---

## ⚡ Performance Optimizations

The homepage uses several techniques to stay fast:

1. **Cached derived data** — `cachedContinueItems`, `cachedAttentionItems`, `cachedEditedThisWeek`, `cachedStageReadyCount` are `@State` vars rebuilt only when data counts change (via `onChange`), NOT on every `body` render.

2. **Lightweight computed properties** — `activeJokes`, `activeSets`, `importsNeedingReview` are simple filters/sorts, not heavy computations.

3. **`rebuildCachedData()` triggers:**
   - `.onAppear`
   - `.onChange(of: allJokes.count)`
   - `.onChange(of: allSets.count)`
   - `.onChange(of: allIdeas.count)`
   - `.onChange(of: allRecordings.count)`
   - `.onChange(of: allImports.count)`

4. **Touch animations** use `.easeOut(duration: 0.12)` — fast and simple, no springs on press states.

5. **PDF processing** — renders pages sequentially with `Task.yield()` between pages, checks memory pressure via `MemoryManager`, skips remaining pages if pressure is high.

---

## 🧩 Reusable Components Used on Homepage

| Component | File | Usage |
|-----------|------|-------|
| `BitBinderSectionHeader` | `BitBinderComponents.swift` | Section titles ("Continue Working", etc.) |
| `BitBinderCard` | `BitBinderComponents.swift` | Elevated card wrapper for attention items, empty states |
| `ContinueWorkingRow` | `HomeView.swift` (private) | Row in the Continue Working section |
| `QuickCaptureButton` | `HomeView.swift` (private) | The three secondary capture buttons |
| `SetProgressRow` | `HomeView.swift` (private) | Row in the Sets in Progress section |
| `InsightChip` | `HomeView.swift` (private) | Capsule stats in the This Week strip |
| `TouchReactiveStyle` | `AppTheme.swift` | Press-to-scale button style used everywhere |
| `FABButtonStyle` | `AppTheme.swift` | Bouncy scale for the floating action buttons |

---

## 🗺️ Navigation Map from Homepage

Every tappable element on the homepage and where it goes:

| Element | Destination | Method |
|---------|-------------|--------|
| Continue → Joke row | `JokeDetailView(joke:)` | `NavigationLink` |
| Continue → Set row | `SetListDetailView(setList:)` | `NavigationLink` |
| Continue → Brainstorm row | Brainstorm tab | `NotificationCenter` post |
| Continue → Import row | `ImportBatchHistoryView()` | `NavigationLink` |
| Quick Capture → New Joke | `AddJokeView()` | `.sheet` |
| Quick Capture → Brainstorm | `AddBrainstormIdeaSheet()` | `.sheet` |
| Quick Capture → Voice Note | `StandaloneRecordingView()` | `.sheet` |
| Quick Capture → Talk to Text | `TalkToTextView(selectedFolder: nil)` | `.sheet` |
| Sets → Set row | `SetListDetailView(setList:)` | `NavigationLink` |
| Attention → Any alert | Target screen (Jokes/Recordings) | `NotificationCenter` post |
| Search → Joke result | `JokeDetailView(joke:)` | `NavigationLink` |
| Search → Set result | `SetListDetailView(setList:)` | `NavigationLink` |
| Search → Recording result | `RecordingDetailView(recording:)` | `NavigationLink` |
| Search → Brainstorm result | Brainstorm tab | `NotificationCenter` post |
| FAB (top-right) | Side menu | `showMenu = true` |
| FAB (top-left) | Previous screen | `goBack()` from history stack |
| Side Menu → BitBuddy | `BitBuddyChatView()` | `.sheet` |

---

## 📊 Data Queries (SwiftData)

The homepage pulls live data with these `@Query` declarations:

```swift
@Query(sort: \Joke.dateModified, order: .reverse)           var allJokes: [Joke]
@Query(sort: \SetList.dateModified, order: .reverse)        var allSets: [SetList]
@Query(sort: \BrainstormIdea.dateCreated, order: .reverse)  var allIdeas: [BrainstormIdea]
@Query(sort: \Recording.dateCreated, order: .reverse)       var allRecordings: [Recording]
@Query(sort: \ImportBatch.importTimestamp, order: .reverse)  var allImports: [ImportBatch]
```

All queries are sorted most-recent-first. No predicates — filtering happens in computed properties and `rebuildCachedData()`.

---

## 🎯 Design Philosophy

1. **"Writer's desk" metaphor** — Everything the comedian needs is one scroll away. No buried menus for daily actions.
2. **Continue where you left off** — The most recently touched items surface automatically.
3. **Proactive nudges** — The "Needs Attention" section tells you what's falling behind without being naggy.
4. **Zero-tap capture** — Three ways to capture a joke idea without navigating away: write it, speak it, or dictate it.
5. **Evidence-based color** — Blue for trust/action, green for success, amber for warnings, red only for errors. No gratuitous color.
6. **Responsive** — Adapts to iPad with a two-column layout. Same data, better use of space.
7. **Fast** — Cached computations, no heavy body re-renders, memory-safe file processing.

---

*Last updated: March 2026*
*Source: `Views/HomeView.swift` · `ContentView.swift` · `Views/LaunchScreenView.swift` · `Utilities/AppTheme.swift`*
