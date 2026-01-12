# Event Starting Validation Rules

## Overview

Three new rules have been implemented to control when and how events can be started:

1. **Active events are no longer "upcoming"** - When an event is started, it loses `is_upcoming` status and the next event gets it
2. **No multiple active events** - Users cannot start two events at the same time
3. **Must start events in order** - Users can only start the most upcoming event

---

## Implementation Details

### 1. Active Events Are No Longer "Upcoming"

**Database Change**: `SUPABASE_UPDATE_IS_UPCOMING_ON_ACTIVE.sql`

**What Changed**:
- Updated `recalculate_is_upcoming()` function to **exclude active events** from consideration
- When an event is started (`is_active = true`), it automatically gets `is_upcoming = false`
- The NEXT closest upcoming event gets `is_upcoming = true`

**Example**:
```
Before starting:
- Event A (Jan 12) → is_active: false, is_upcoming: true
- Event B (Jan 13) → is_active: false, is_upcoming: false
- Event C (Jan 14) → is_active: false, is_upcoming: false

After starting Event A:
- Event A (Jan 12) → is_active: true,  is_upcoming: false ✅
- Event B (Jan 13) → is_active: false, is_upcoming: true  ✅
- Event C (Jan 14) → is_active: false, is_upcoming: false
```

**How It Works**:
- The database trigger automatically recalculates `is_upcoming` whenever `is_active` changes
- Active events are skipped when finding the "most upcoming" event
- This ensures only ONE non-active event has `is_upcoming = true`

---

### 2. No Multiple Active Events

**UI Validation**: `EventsHomeView.swift:200-204`

**What Happens**:
When user tries to start an event while another event is already active:
1. System checks: `if activeEvent != nil`
2. Shows alert: "Can't start multiple events at the same time."
3. Does NOT show the start confirmation dialog

**Alert Details**:
- **Title**: "Can't Start Multiple Events"
- **Message**: "Can't start multiple events at the same time."
- **Button**: "OK" (dismisses alert)

**Code**:
```swift
// Check 1: Is there already an active event?
if activeEvent != nil {
    showMultipleEventsAlert = true
    return
}
```

---

### 3. Must Start Events in Order

**UI Validation**: `EventsHomeView.swift:206-210`

**What Happens**:
When user tries to start an event that is NOT the most upcoming:
1. System checks: `if event.isUpcoming == false`
2. Shows alert: "You have other events to go to first"
3. Does NOT show the start confirmation dialog

**Alert Details**:
- **Title**: "Patience!"
- **Message**: "You have other events to go to first"
- **Button**: "OK" (dismisses alert)

**Code**:
```swift
// Check 2: Is this event NOT the most upcoming one?
if event.isUpcoming == false {
    showNotUpcomingAlert = true
    return
}
```

---

## How to Apply the Changes

### Step 1: Run Database Migration

1. **First**, run `SUPABASE_FIX_IS_UPCOMING_CORRECTED.sql` if you haven't already
2. **Then**, run `SUPABASE_UPDATE_IS_UPCOMING_ON_ACTIVE.sql`

Both in your **Supabase SQL Editor**.

### Step 2: Build and Run

1. Clean build in Xcode (⌘⇧K)
2. Build (⌘B)
3. Run (⌘R)

The Swift code changes are already in place!

---

## Testing Guide

### Test 1: Active Events Lose "Upcoming" Status

**Setup**:
- Create 3 events: Jan 12, Jan 13, Jan 14

**Steps**:
1. Start Event A (Jan 12)
2. Check the events list

**Expected Result**:
```
Event A (Jan 12) - Active (green badge)
Event B (Jan 13) - Upcoming (blue badge) ✅
Event C (Jan 14) - Not upcoming (no special badge)
```

**Database Verification**:
```sql
SELECT name, event_date, is_active, is_upcoming
FROM events
ORDER BY event_date ASC;
```

Expected:
```
Event A | 2026-01-12 | true  | false
Event B | 2026-01-13 | false | true  ✅
Event C | 2026-01-14 | false | false
```

---

### Test 2: Cannot Start Multiple Events

**Setup**:
- Event A is already started and active

**Steps**:
1. Try to tap Event B to start it

**Expected Result**:
- Alert appears with title "Can't Start Multiple Events"
- Message: "Can't start multiple events at the same time."
- Tap "OK" to dismiss
- Event B does NOT start

---

### Test 3: Must Start Events in Order

**Setup**:
- Event A (Jan 12) - is_upcoming: true
- Event B (Jan 13) - is_upcoming: false
- Event C (Jan 14) - is_upcoming: false

**Steps**:
1. Try to tap Event C (Jan 14) to start it

**Expected Result**:
- Alert appears with title "Patience!"
- Message: "You have other events to go to first"
- Tap "OK" to dismiss
- Event C does NOT start

**Correct Behavior**:
1. Start Event A first (works because is_upcoming = true)
2. Event A becomes active
3. Event B becomes the most upcoming (is_upcoming = true)
4. Now you can start Event B

---

## Validation Flow

When a user taps an **inactive** event:

```
1. Check: Is there already an active event?
   ├─ YES → Show "Can't start multiple events" alert ❌
   └─ NO  → Continue to step 2

2. Check: Is this event the most upcoming (is_upcoming = true)?
   ├─ NO  → Show "Patience! Other events first" alert ❌
   └─ YES → Continue to step 3

3. Show confirmation dialog: "Do you want to start 'Event Name'?"
   ├─ Cancel → Do nothing
   └─ Start  → Call startEvent() API ✅
```

---

## Console Logs to Watch For

### Successful Start:
```
🎬 [EventsHomeView] Starting event: Test Event
📞 [EventService] Calling RPC: start_event
📬 [EventService] RPC Response received:
   - success: true
   - is_upcoming: false (for the event that was started)
✅ [EventService] Event started successfully!
🔄 [EventsHomeView] Reloading events after start...
📋 [EventsHomeView] Event List:
   1. Test Event
      - is_active: true
      - is_upcoming: false ✅
   2. Next Event
      - is_active: false
      - is_upcoming: true ✅
```

### Blocked: Multiple Events
```
🚫 User tapped event, but another is already active
→ Showing "Can't start multiple events" alert
```

### Blocked: Not Upcoming
```
🚫 User tapped event with is_upcoming = false
→ Showing "Patience!" alert
```

---

## Summary

| Scenario | Validation | Alert Shown | Result |
|----------|-----------|-------------|--------|
| Event already active | activeEvent != nil | "Can't start multiple events at the same time." | ❌ Blocked |
| Event not most upcoming | is_upcoming == false | "You have other events to go to first" | ❌ Blocked |
| Event is most upcoming & no active event | Both checks pass | "Do you want to start '[name]'?" | ✅ Allowed |

---

## Edge Cases Handled

1. **User starts Event A, then taps Event A again**
   - Result: Navigates to MemoriesHomeView (no validation)

2. **User starts Event A, waits for it to end, then starts Event B**
   - Result: Allowed (Event A is no longer active)

3. **User creates Event D after starting Event A**
   - Result: is_upcoming recalculates automatically
   - If Event D is before Event B, it gets is_upcoming = true

4. **User deletes the most upcoming event**
   - Result: Trigger recalculates, next event gets is_upcoming = true

---

## Files Modified

### Database (SQL):
- `SUPABASE_UPDATE_IS_UPCOMING_ON_ACTIVE.sql` - Updated recalculate function

### Swift:
- `EventsHomeView.swift` - Added validation logic and alerts

---

## Next Steps

After testing:
1. ✅ Verify only ONE event has is_upcoming = true at a time
2. ✅ Verify active events have is_upcoming = false
3. ✅ Test all three validation scenarios
4. ✅ Ensure alerts appear with correct messages

All set! Your event starting logic is now fully validated and controlled.
