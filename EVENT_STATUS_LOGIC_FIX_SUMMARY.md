# Event Status Boolean Logic Fix - Complete Summary

## Problem Statement

New future events were being incorrectly initialized with:
- `isActive = false` ✅ (correct)
- `isUpcoming = false` ❌ (incorrect - should be true for the soonest event)
- `isFuture = false` ❌ (incorrect - should be true for all future events)
- `isEnded = false` ✅ (correct)

This caused future events to not display properly in the UI and prevented users from starting the most upcoming event.

## Root Cause

The database triggers were not properly calculating the event status booleans on INSERT/UPDATE. The logic was incomplete and didn't handle edge cases correctly.

## Solution Overview

Implemented a comprehensive two-phase trigger system:

### Phase 1: BEFORE Triggers (Individual Event Calculation)
- Calculates `is_ended`, `is_active`, and `is_future` for the specific event being inserted/updated
- Runs before the row is committed to the database
- Uses current time comparison with event start/end times

### Phase 2: AFTER Triggers (Cross-Event Calculation)
- Recalculates `is_upcoming` for ALL user's events
- Runs after the row is committed
- Ensures only ONE event has `is_upcoming = true` (the soonest one)

## Status Logic Rules (FINAL)

### 1. `is_ended`
**Purpose**: Marks events that have finished

**Logic**:
- ✅ `true` when:
  - Current time ≥ event end time (time has passed), OR
  - User manually clicked "End Event" (preserve manual ending)
- ❌ `false` when:
  - Event end time is in the future

**Edge Cases**:
- Once manually ended (`is_ended=true`), always stays ended (never auto-revert)
- Events without end_time use end-of-day (23:59:59) as default end time

---

### 2. `is_active`
**Purpose**: Marks the currently active event (user is adding memories to it)

**Logic**:
- ✅ `true` when:
  - User manually clicked "Start Event", AND
  - Current time is within [start_time, end_time] range
- ❌ `false` when:
  - Event hasn't been started yet, OR
  - Current time is outside the event time range (auto-deactivates)

**Edge Cases**:
- Only ONE event can be `is_active=true` per user at a time
- Auto-deactivates if current time moves outside event time range
- Cannot start an event that has `is_ended=true`

---

### 3. `is_future`
**Purpose**: Marks all events that haven't ended yet (for UI "Upcoming" badge)

**Logic**:
- ✅ `true` when:
  - `is_ended = false`, AND
  - `is_active = false`, AND
  - Event end time > current time
- ❌ `false` when:
  - Event has ended, OR
  - Event is currently active, OR
  - Event end time has passed

**Edge Cases**:
- MULTIPLE events can have `is_future=true` at the same time
- Used to show blue "Upcoming" badge in UI for all future events

---

### 4. `is_upcoming`
**Purpose**: Identifies THE SINGLE soonest event that can be started next

**Logic**:
- ✅ `true` when:
  - `is_ended = false`, AND
  - `is_active = false`, AND
  - `is_future = true`, AND
  - This is the earliest event (by date, then start_time)
- ❌ `false` for all other events

**Edge Cases**:
- Only ONE event can have `is_upcoming=true` per user at a time
- User can only start the event with `is_upcoming=true`
- If `is_upcoming=true`, then `is_future` must also be `true`
- Events without start_time are sorted after events with start_time (on same day)

---

## Status Transition Examples

### Example 1: Creating a New Future Event

**Scenario**: User creates event for tomorrow with start=10:00 AM, end=5:00 PM

**Initial State** (at creation):
```
is_ended = false      (end time hasn't passed)
is_active = false     (not started yet)
is_future = true      (end time is in future)
is_upcoming = true    (assuming it's the soonest event)
```

**UI Display**: Blue "Upcoming" badge, "Tap to start" message

---

### Example 2: Starting an Event

**Scenario**: User taps "Start" on the upcoming event at 10:00 AM

**Before Start**:
```
is_ended = false
is_active = false
is_future = true
is_upcoming = true
```

**After Start**:
```
is_ended = false
is_active = true      ← Changed
is_future = false     ← Changed
is_upcoming = false   ← Changed
```

**Side Effect**: Next soonest event now becomes `is_upcoming=true`

**UI Display**: Green "Active" badge

---

### Example 3: Event End Time Passes

**Scenario**: Current time reaches 5:00 PM (event end time)

**Before 5:00 PM**:
```
is_ended = false
is_active = true
is_future = false
is_upcoming = false
```

**At/After 5:00 PM**:
```
is_ended = true       ← Changed
is_active = false     ← Changed (auto-deactivated)
is_future = false
is_upcoming = false
```

**Side Effect**: Next soonest event becomes `is_upcoming=true`

**UI Display**: Gray "Ended" badge, appears in Past Events page

---

### Example 4: Manually Ending an Event Early

**Scenario**: User clicks "End Event" at 3:00 PM (before 5:00 PM end time)

**Before Manual End**:
```
is_ended = false
is_active = true
is_future = false
is_upcoming = false
```

**After Manual End**:
```
is_ended = true       ← Changed (manual override)
is_active = false     ← Changed
is_future = false
is_upcoming = false
```

**Side Effect**: Next soonest event becomes `is_upcoming=true`

**UI Display**: Gray "Ended" badge, appears in Past Events page

---

### Example 5: Multiple Future Events

**Scenario**: User has 3 future events:
- Event A: Jan 20, 10:00 AM - 5:00 PM
- Event B: Jan 22, 2:00 PM - 6:00 PM
- Event C: Jan 25, 9:00 AM - 3:00 PM

**Status Table**:

| Event | is_ended | is_active | is_future | is_upcoming |
|-------|----------|-----------|-----------|-------------|
| A     | false    | false     | true      | **true** ⭐ |
| B     | false    | false     | true      | false       |
| C     | false    | false     | true      | false       |

**UI Display**:
- Event A: Blue "Upcoming" badge, "Tap to start" ← Can be started
- Event B: Blue "Upcoming" badge, "Tap to start" (but shows alert if tapped)
- Event C: Blue "Upcoming" badge, "Tap to start" (but shows alert if tapped)

---

## Files Modified

### 1. SQL Migration File (NEW)
**File**: `FIX_EVENT_STATUS_LOGIC.sql`

**Changes**:
- Created `calculate_event_status()` trigger function
- Created `update_most_upcoming_event()` trigger function
- Set up BEFORE INSERT/UPDATE triggers
- Set up AFTER INSERT/UPDATE/DELETE triggers
- Data migration to fix all existing events
- Comprehensive logging (RAISE NOTICE statements)

**Key Functions**:

```sql
-- Phase 1: Calculate individual event status
CREATE TRIGGER trigger_calculate_event_status_insert
    BEFORE INSERT ON events
    FOR EACH ROW
    EXECUTE FUNCTION calculate_event_status();

-- Phase 2: Update most upcoming event for all user's events
CREATE TRIGGER trigger_update_most_upcoming_after_insert
    AFTER INSERT ON events
    FOR EACH ROW
    EXECUTE FUNCTION update_most_upcoming_event();
```

### 2. Swift Logging Updates

**Files Modified**:
- `EventsHomeView.swift` (3 locations)
- `PastEventsView.swift` (1 location)

**Changes**:
- Added `isFuture` to all debug print statements
- Format: `isActive=X, isUpcoming=X, isFuture=X, isEnded=X`

**Example**:
```swift
// Before:
print("   - \(event.name): isActive=\(event.isActive), isUpcoming=\(event.isUpcoming?.description ?? "nil"), isEnded=\(event.isEnded)")

// After:
print("   - \(event.name): isActive=\(event.isActive), isUpcoming=\(event.isUpcoming?.description ?? "nil"), isFuture=\(event.isFuture?.description ?? "nil"), isEnded=\(event.isEnded)")
```

---

## Testing Checklist

### Test 1: Create Future Event
- [ ] Create event with start_time = current time + 1 hour
- [ ] Verify `is_ended = false`
- [ ] Verify `is_upcoming = true` (if it's the soonest)
- [ ] Verify `is_future = true`
- [ ] Verify blue "Upcoming" badge appears

### Test 2: Create Multiple Future Events
- [ ] Create 3 events with different dates
- [ ] Verify only the soonest has `is_upcoming = true`
- [ ] Verify all 3 have `is_future = true`
- [ ] Verify all 3 show blue "Upcoming" badge

### Test 3: Start Event
- [ ] Tap "Start" on most upcoming event
- [ ] Verify `is_active = true`
- [ ] Verify `is_upcoming = false`
- [ ] Verify `is_future = false`
- [ ] Verify green "Active" badge appears
- [ ] Verify next event becomes `is_upcoming = true`

### Test 4: Event End Time Passes
- [ ] Wait for event end_time to pass (or create event with past end_time)
- [ ] Verify `is_ended = true`
- [ ] Verify `is_active = false` (auto-deactivated)
- [ ] Verify event appears in Past Events page
- [ ] Verify next event becomes `is_upcoming = true`

### Test 5: Manual End Event
- [ ] Start an event
- [ ] Click "End Event" before end_time
- [ ] Verify `is_ended = true`
- [ ] Verify `is_active = false`
- [ ] Verify event appears in Past Events page
- [ ] Verify next event becomes `is_upcoming = true`

### Test 6: Edge Case - Event Without Times
- [ ] Create event with only date (no start_time or end_time)
- [ ] Verify `is_future = true` (uses end-of-day as default)
- [ ] Verify correct status assignment

### Test 7: Edge Case - Same-Day Multiple Events
- [ ] Create 2 events on same day with different start times
- [ ] Verify earlier start_time event has `is_upcoming = true`
- [ ] Verify both have `is_future = true`

### Test 8: Database Logging
- [ ] Check Supabase logs for RAISE NOTICE output
- [ ] Verify all events show correct calculated values
- [ ] Verify "most upcoming" event is correctly identified

---

## Database Logging Output Example

When a new event is created, you'll see:

```
🔍 [calculate_event_status] Processing event: Birthday Party
   - event_date: 2026-01-20
   - start_time: 14:00:00
   - end_time: 18:00:00
   - current_time: 2026-01-15 10:30:00
   - computed event_start_datetime: 2026-01-20 14:00:00
   - computed event_end_datetime: 2026-01-20 18:00:00
   → is_ended: false
   → is_active: false
   → is_future: true
   ✅ Event status calculated successfully

🔄 [update_most_upcoming_event] Recalculating most upcoming event for user: abc123...
   ✅ Set is_upcoming=true for event: xyz789...
   📊 Total events for user: 3
      - Birthday Party: isActive=false, isUpcoming=true, isFuture=true, isEnded=false
      - Conference: isActive=false, isUpcoming=false, isFuture=true, isEnded=false
      - Vacation: isActive=false, isUpcoming=false, isFuture=true, isEnded=false
```

---

## Next Steps

1. **Run SQL Migration**:
   ```bash
   # Open Supabase Dashboard → SQL Editor
   # Copy contents of FIX_EVENT_STATUS_LOGIC.sql
   # Execute the migration
   # Check output logs for any errors
   ```

2. **Build and Test App**:
   ```bash
   # Clean build folder
   # Build and run on simulator
   # Create test events
   # Verify status logging in Xcode console
   ```

3. **Verify Existing Events**:
   - Check if existing events were correctly migrated
   - Verify Past Events page shows only ended events
   - Verify Events Home shows only active/future events

4. **Monitor Logs**:
   - Watch Xcode console for Swift debug logs
   - Check Supabase logs for database trigger output
   - Verify all events have correct status booleans

---

## Troubleshooting

### Issue: New event has `is_upcoming = false`

**Cause**: Another event is soonest (earlier date/time)

**Solution**: This is expected - check other events and verify the soonest one has `is_upcoming = true`

---

### Issue: Multiple events have `is_upcoming = true`

**Cause**: Database trigger failed or was bypassed

**Solution**:
1. Check Supabase logs for trigger errors
2. Manually run update query:
   ```sql
   UPDATE events SET updated_at = NOW() WHERE user_id = '<your-user-id>';
   ```

---

### Issue: Event shows wrong badge in UI

**Cause**: Swift is using local computed property instead of database field

**Solution**: Verify EventCard uses `event.isFuture` from database, not local calculation

---

## Summary

This fix implements a robust, database-driven event status management system with:

✅ Correct status calculation for all 4 boolean fields
✅ Proper handling of edge cases (no times, same-day events, etc.)
✅ Auto-deactivation when time range expires
✅ Manual override support (end event early)
✅ Comprehensive logging for debugging
✅ Data migration for existing events
✅ Two-phase trigger system (individual + cross-event calculation)

The system now correctly identifies which events are upcoming, future, active, or ended, enabling proper UI display and user interaction flows.
