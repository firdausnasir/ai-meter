# Kimi Code View Height and Window Display Design

**Date:** 2026-03-25

## Summary

Update Kimi Code's login window height to match other auth windows (Claude, Codex) and improve the usage window display by showing "5-hour Window" instead of "300-minute Window" with reset time visible.

## Goals

1. Make Kimi login window height consistent with other auth windows (640px)
2. Display window duration in hours when appropriate (300 minutes → 5 hours)
3. Show reset time for window limits, matching the Weekly Usage pattern

## Current State

- **KimiAuthManager.swift:90**: Window height is 500px
- **KimiTabView.swift:148**: Shows "{duration}-minute Window" (e.g., "300-minute Window")
- **KimiTabView.swift:142-183**: Window cards don't show reset time

## Proposed Changes

### 1. Window Height (KimiAuthManager.swift)

Change login window height from 500 to 640 to match Claude/Codex auth windows:

```swift
// Line 90
contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
```

### 2. Window Duration Label (KimiTabView.swift)

Update `limitWindowCard` to convert 300 minutes to "5-hour Window":

```swift
// Helper function to format window duration
private func windowDurationText(_ duration: Int) -> String {
    if duration == 300 {
        return "5-hour Window"
    }
    return "\(duration)-minute Window"
}
```

Use in the card header:
```swift
Text(windowDurationText(limit.window.duration))
```

### 3. Reset Time Display (KimiTabView.swift)

Add reset time to window card headers, following Weekly Usage pattern:

```swift
HStack {
    Image(systemName: "clock.fill")
        .font(.system(size: 12))
        .foregroundColor(.secondary)
    Text(windowDurationText(limit.window.duration))
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.white)
    Spacer()
    if let resetTime = limit.detail.resetTime {
        Text("Resets: \(formatResetTime(resetTime))")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
    }
}
```

Add helper for consistent formatting:
```swift
private func formatResetTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
```

## Files to Modify

1. `AIMeter/Sources/App/KimiAuthManager.swift` - Line 90
2. `AIMeter/Sources/App/KimiTabView.swift` - Lines 142-183 (limitWindowCard function)

## Testing

- [ ] Kimi login window opens at 640px height
- [ ] Window cards show "5-hour Window" for 300-minute duration
- [ ] Window cards show "{N}-minute Window" for other durations
- [ ] Reset time displays when available in API response
- [ ] Reset time hidden when not available

## References

- Weekly Usage reset time display: KimiTabView.swift:96-100
- Claude/Codex window height: SessionAuthManager.swift:175, CodexAuthManager.swift:85
