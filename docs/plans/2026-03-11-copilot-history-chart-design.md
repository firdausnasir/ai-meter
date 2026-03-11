# Copilot History Chart — Design Spec

> **Date:** 2026-03-11
> **Status:** Approved
> **Goal:** Add quota snapshot history tracking and burn rate chart to the Copilot tab.

---

## Problem Statement

The Copilot tab shows only the current quota snapshot (chat %, completions %, premium %). There is no way to see how usage has changed over time, making it hard to predict when quotas will run out or understand consumption patterns. Claude already has history tracking (`QuotaHistoryService`) and a trend chart (`QuotaChartView`) — Copilot needs the same.

---

## Chosen Approach

**Overlaid multi-series lines with a metric toggle**, following the existing `QuotaChartView` pattern.

- A segmented control toggles between two views: **Usage %** (0-100 scale) and **Remaining** (absolute count).
- Each view shows up to 3 colored lines (Chat, Completions, Premium) overlaid on the same chart with a legend.
- Unlimited quotas are excluded entirely (no line rendered).
- Time range selector (1h / 6h / 1d / 7d) reuses the existing `QuotaTimeRange` enum.

**Why this approach:**
- Compact — fits in the 320px popover without scrolling issues.
- Follows existing precedent (`QuotaChartView` already overlays Session + Weekly lines).
- Lets users compare burn rates across quota types at a glance.
- The metric toggle avoids mixing % and absolute counts on the same Y axis.

---

## Data Model

### New: `CopilotHistoryDataPoint` (in `AIMeter/Sources/Shared/CopilotHistory.swift`)

```swift
struct CopilotHistoryDataPoint: Codable, Identifiable {
    var id: UUID
    let timestamp: Date
    let chatUtilization: Int?       // nil when unlimited
    let chatRemaining: Int?         // nil when unlimited
    let completionsUtilization: Int?
    let completionsRemaining: Int?
    let premiumUtilization: Int?
    let premiumRemaining: Int?

    init(
        timestamp: Date = Date(),
        chatUtilization: Int? = nil, chatRemaining: Int? = nil,
        completionsUtilization: Int? = nil, completionsRemaining: Int? = nil,
        premiumUtilization: Int? = nil, premiumRemaining: Int? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.chatUtilization = chatUtilization
        self.chatRemaining = chatRemaining
        self.completionsUtilization = completionsUtilization
        self.completionsRemaining = completionsRemaining
        self.premiumUtilization = premiumUtilization
        self.premiumRemaining = premiumRemaining
    }
}
```

**Why nullable fields?** A quota can be unlimited at any point. When unlimited, we store `nil` rather than a meaningless 0. This makes it trivial to skip unlimited series in the chart — if all values for a series are nil, that series is not rendered.

### New: `CopilotHistory` (same file)

```swift
struct CopilotHistory: Codable {
    var dataPoints: [CopilotHistoryDataPoint] = []
}
```

### New: `CopilotChartMetric` (same file)

```swift
enum CopilotChartMetric: String, CaseIterable, Identifiable {
    case utilization = "Usage %"
    case remaining = "Remaining"

    var id: String { rawValue }
}
```

Reuses existing `QuotaTimeRange` enum unchanged.

---

## Service Layer

### New: `CopilotHistoryService` (in `AIMeter/Sources/App/CopilotHistoryService.swift`)

Follows the exact same pattern as `QuotaHistoryService`:

| Aspect | Detail |
|--------|--------|
| Storage | `~/.config/aimeter/copilot-history.json` |
| Retention | 7 days |
| Flush interval | 5 minutes (timer-based) |
| Flush on quit | `NSApplication.willTerminateNotification` |
| Corrupt file handling | Backup to `.bak.json`, reset to empty |
| JSON encoding | Uses `JSONEncoder.appEncoder` / `JSONDecoder.appDecoder` |

**Key methods:**

```swift
func recordSnapshot(_ data: CopilotUsageData)
func downsampledPoints(for range: QuotaTimeRange) -> [CopilotHistoryDataPoint]
```

`recordSnapshot` extracts utilization/remaining from each `CopilotQuota`, storing `nil` for unlimited quotas:

```swift
func recordSnapshot(_ data: CopilotUsageData) {
    let point = CopilotHistoryDataPoint(
        chatUtilization: data.chat.unlimited ? nil : data.chat.utilization,
        chatRemaining: data.chat.unlimited ? nil : data.chat.remaining,
        completionsUtilization: data.completions.unlimited ? nil : data.completions.utilization,
        completionsRemaining: data.completions.unlimited ? nil : data.completions.remaining,
        premiumUtilization: data.premiumInteractions.unlimited ? nil : data.premiumInteractions.utilization,
        premiumRemaining: data.premiumInteractions.unlimited ? nil : data.premiumInteractions.remaining
    )
    history.dataPoints.append(point)
    isDirty = true
    startFlushTimerIfNeeded()
}
```

`downsampledPoints` uses the same bucket-averaging algorithm as `QuotaHistoryService.downsampledPoints`. For nullable fields, averaging only considers non-nil values in the bucket; if all values in a bucket are nil for a field, the downsampled point gets nil for that field. Int averages are rounded to nearest integer.

### Integration point

`CopilotService.fetch()` calls `copilotHistoryService?.recordSnapshot(data)` after a successful fetch — same pattern as `UsageService` calling `historyService?.recordDataPoint(...)`.

`CopilotService` gets a weak reference to `CopilotHistoryService` via its `start()` method, matching the existing `UsageService` pattern:

```swift
func start(interval: TimeInterval = 60, copilotHistoryService: CopilotHistoryService? = nil)
```

---

## Chart View

### New: `CopilotChartView` (in `AIMeter/Sources/App/CopilotChartView.swift`)

Layout (top to bottom):
1. **Header row:** "Trend" label + time range picker (1h/6h/1d/7d segmented control)
2. **Metric toggle:** `CopilotChartMetric` segmented control ("Usage %" / "Remaining")
3. **Chart area:** Swift Charts `LineMark` with up to 3 series, 80pt height
4. **Legend:** Auto-generated by Swift Charts `.chartLegend(.visible)`

**Usage % view:**
- Y axis: 0–100 with marks at 0, 50, 100 (labeled as "0%", "50%", "100%")
- Lines: Chat (blue), Completions (green), Premium (purple) — only rendered if series has non-nil data

**Remaining view:**
- Y axis: auto-scaled to max value across visible series
- Lines: same colors and filtering as Usage % view

**Empty state:** "No history yet" centered text (same as `QuotaChartView`)

**Series filtering:** A series is hidden if ALL downsampled points have nil for that series' field. This handles the common case where Chat and Completions are unlimited — only Premium shows.

**Color scale:**

```swift
.chartForegroundStyleScale([
    "Chat": Color.blue,
    "Completions": Color.green,
    "Premium": Color.purple
])
```

**Styling:** Matches `QuotaChartView` exactly — same font sizes (12pt header, 9pt axis labels), grid line styles (0.5pt dashed at 0.1 opacity), background (`Color.white.opacity(0.05)`), corner radius (10), padding (12h/10v).

---

## Wiring

### `AIMeterApp.swift` changes:
- Add `@StateObject private var copilotHistoryService = CopilotHistoryService()`
- Pass to `copilotService.start(interval:copilotHistoryService:)`
- Pass `copilotHistoryService` to `PopoverView`
- Handle in `onChange(of: refreshInterval)` — restart `copilotService` with history service ref

### `PopoverView.swift` changes:
- Add `@ObservedObject var copilotHistoryService: CopilotHistoryService` to `PopoverView`
- Pass to `CopilotTabView`

### `CopilotTabView` changes (in `PopoverView.swift`):
- Accept `@ObservedObject var copilotHistoryService: CopilotHistoryService`
- Add `CopilotChartView(historyService: copilotHistoryService)` below the reset date text, above the quota rows

---

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `AIMeter/Sources/Shared/CopilotHistory.swift` | **Create** | `CopilotHistoryDataPoint`, `CopilotHistory`, `CopilotChartMetric` |
| `AIMeter/Sources/App/CopilotHistoryService.swift` | **Create** | History service (record, downsample, persist, prune) |
| `AIMeter/Sources/App/CopilotChartView.swift` | **Create** | Chart view with metric toggle and multi-series lines |
| `AIMeter/Sources/App/CopilotService.swift` | **Modify** | Add `copilotHistoryService` weak ref, call `recordSnapshot` on fetch |
| `AIMeter/Sources/App/AIMeterApp.swift` | **Modify** | Instantiate `CopilotHistoryService`, wire into service and view |
| `AIMeter/Sources/App/PopoverView.swift` | **Modify** | Thread `copilotHistoryService` through to `CopilotTabView`, add chart |

---

## Key Decisions

1. **Separate history file** (`copilot-history.json`) — avoids coupling with Claude's `history.json` and keeps file sizes manageable.
2. **Nullable fields** for unlimited quotas — cleaner than sentinel values, natural filtering in chart.
3. **Metric toggle** (% vs remaining) rather than dual charts — keeps vertical space compact in the 320px popover.
4. **Observer via weak ref** (same as Claude pattern) — no Combine subscription overhead, explicit call site.
5. **Reuse `QuotaTimeRange`** — no new enum needed, consistent time ranges across providers.
