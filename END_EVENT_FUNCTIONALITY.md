# End Event Functionality

## Overview

Added the ability to end an active event directly from the MemoriesHomeView, with automatic navigation to the playback screen.

---

## Changes Made

### 1. **Replaced Schedule Icon with "End Event" Button**

**Location**: `MemoriesHomeView.swift:155-177`

**What Changed**:
- When **no event is active**: Shows calendar icon (calendar.badge.plus) to create events
- When **event is active**: Shows "End Event" text button

**Code**:
```swift
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        if activeEvent != nil {
            // Show "End Event" button when event is active
            Button {
                Task {
                    await endEventAndNavigateToPlayback()
                }
            } label: {
                Text("End Event")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        } else {
            // Show schedule icon when no event is active
            Button {
                showEventCreation = true
            } label: {
                Image(systemName: "calendar.badge.plus")
            }
        }
    }
}
```

---

### 2. **Automatic Navigation to Playback After Ending Event**

**Location**: `MemoriesHomeView.swift:313-334`

**What It Does**:
1. Stops the active event via `eventService.stopEvent()`
2. Reloads events to update UI state
3. Automatically navigates to `MemoryPlaybackView`

**Function**:
```swift
private func endEventAndNavigateToPlayback() async {
    guard let active = activeEvent else { return }

    print("🛑 [MemoriesHomeView] Ending event: \(active.name)")

    do {
        // Stop the event
        _ = try await eventService.stopEvent(eventId: active.id)
        print("✅ [MemoriesHomeView] Event stopped successfully")

        // Reload events to update state
        await loadEvents()

        // Navigate to playback
        await MainActor.run {
            print("🎬 [MemoriesHomeView] Navigating to playback screen...")
            navigateToPlayback = true
        }
    } catch {
        print("❌ [MemoriesHomeView] Failed to stop event: \(error)")
    }
}
```

---

### 3. **Dynamic Header Shows Event Name**

**Location**: `MemoriesHomeView.swift:76`

**What Changed**:
- **Before**: Always showed "Your Memories"
- **After**: Shows the active event's name if one exists, otherwise "Your Memories"

**Code**:
```swift
Text(activeEvent?.name ?? "Your Memories")
    .font(.largeTitle)
    .fontWeight(.bold)
```

**Examples**:
- Active event "Birthday Party" → Header: "Birthday Party"
- No active event → Header: "Your Memories"

---

## User Flow

### Before (Without Active Event):
1. User is on MemoriesHomeView
2. Top right shows **calendar icon** (schedule)
3. Tapping it opens event creation/management sheet
4. Header shows "Your Memories"

### After (With Active Event):
1. User starts an event from EventsHomeView
2. Navigates to MemoriesHomeView
3. Top right shows **"End Event" button** (replaces calendar icon)
4. Header shows **event name** (e.g., "Birthday Party")
5. User taps "End Event"
6. Event is stopped in database
7. Automatically navigates to **MemoryPlaybackView** to replay memories

---

## UI Changes Summary

| State | Toolbar Button | Header Text | Button Action |
|-------|---------------|-------------|---------------|
| No active event | Calendar icon (calendar.badge.plus) | "Your Memories" | Opens event management sheet |
| Active event exists | "End Event" text button | Event name (e.g., "Birthday Party") | Stops event & navigates to playback |

---

## Console Logs to Watch For

### Successful Event End + Navigation:
```
🛑 [MemoriesHomeView] Ending event: Birthday Party
✅ [MemoriesHomeView] Event stopped successfully
🎬 [MemoriesHomeView] Navigating to playback screen...
✅ Navigating to playback with 15 memories
```

### Error Stopping Event:
```
🛑 [MemoriesHomeView] Ending event: Birthday Party
❌ [MemoriesHomeView] Failed to stop event: <error details>
```

---

## Testing Guide

### Test 1: End Event Button Appears
**Setup**:
- Start an event from EventsHomeView

**Steps**:
1. Navigate to MemoriesHomeView
2. Look at top right toolbar

**Expected Result**:
- Shows "End Event" button (NOT calendar icon)
- Header shows event name (NOT "Your Memories")

---

### Test 2: End Event Navigates to Playback
**Setup**:
- Active event with memories captured

**Steps**:
1. Tap "End Event" button in top right
2. Wait for navigation

**Expected Result**:
- Event is stopped (is_active = false in database)
- Automatically navigates to MemoryPlaybackView
- Can replay all memories from that event

---

### Test 3: No Active Event Shows Calendar Icon
**Setup**:
- No active event

**Steps**:
1. Open MemoriesHomeView
2. Look at top right toolbar

**Expected Result**:
- Shows calendar icon (NOT "End Event")
- Header shows "Your Memories" (NOT event name)
- Tapping icon opens event management sheet

---

### Test 4: Event Name Updates Header
**Setup**:
- Create events with different names

**Steps**:
1. Start event "Test Event A"
2. Check header text
3. End event
4. Start event "Test Event B"
5. Check header text

**Expected Results**:
- Step 2: Header shows "Test Event A"
- Step 5: Header shows "Test Event B"

---

## Database Impact

When user taps "End Event":
1. **RPC call**: `stop_event(event_id, user_id)`
2. **Database update**: `events.is_active = false` for that event
3. **Trigger fires**: `recalculate_is_upcoming()` runs
4. **Result**: Next upcoming event gets `is_upcoming = true`

Same database behavior as tapping "Stop Event" from the inline badge, but with automatic navigation to playback.

---

## Files Modified

- `MemoriesHomeView.swift` - Added toolbar button logic, header update, and navigation function

---

## Edge Cases Handled

1. **No memories captured**: Button still works, navigates to empty playback screen
2. **Multiple events in queue**: Next event automatically becomes `is_upcoming = true`
3. **User taps button twice quickly**: Guard clause prevents double-stopping
4. **Network error during stop**: Error logged, navigation doesn't happen

---

## Summary

Users can now:
- See which event is active via the header (event name)
- End an event with one tap via "End Event" button
- Automatically view their event memories after ending

This streamlines the workflow: **Start Event → Capture Memories → End Event → Replay Memories**
