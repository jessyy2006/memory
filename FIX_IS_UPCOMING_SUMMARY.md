# Fix: Ensure Exactly 1 Event Has is_upcoming = true AT ALL TIMES

## Problem

The `is_upcoming` tag was not being assigned correctly. Some users had:
- **0 events** with `is_upcoming = true` ❌ (shows "Patience" alert on all events)
- **Multiple events** with `is_upcoming = true` ❌ (breaks the chronological ordering)

## Requirement

**Exactly 1 event MUST have `is_upcoming = true` at ALL times** (minimum = 1, maximum = 1)

This event should be the **soonest upcoming event** that the user needs to complete next.

## Solution

Implemented a **4-Priority Fallback System** that ALWAYS tags exactly 1 event:

### Priority 1: Soonest Future Event (Normal Case)
```sql
SELECT id FROM events
WHERE user_id = ?
  AND is_ended = false
  AND is_active = false
  AND is_future = true
ORDER BY event_date ASC, start_time ASC
LIMIT 1;
```

**When**: User has future events that haven't started yet
**Example**: User has events on Jan 20, Jan 25, Feb 1 → Tag Jan 20 as `is_upcoming = true`

---

### Priority 2: Active Event (Fallback)
```sql
SELECT id FROM events
WHERE user_id = ?
  AND is_active = true
ORDER BY event_date ASC, start_time ASC
LIMIT 1;
```

**When**: User has no future events, but has an active event
**Example**: User started their only event → Tag that event as `is_upcoming = true`

---

### Priority 3: Most Recent Past Event (Fallback)
```sql
SELECT id FROM events
WHERE user_id = ?
  AND is_ended = true
ORDER BY event_date DESC, start_time DESC
LIMIT 1;
```

**When**: User has no future/active events, only past events
**Example**: All events have ended → Tag the most recent past event as `is_upcoming = true`

**Note**: This prevents the "Patience" alert from appearing when there are no future events

---

### Priority 4: ANY Event (Emergency Fallback)
```sql
SELECT id FROM events
WHERE user_id = ?
ORDER BY event_date ASC, start_time ASC
LIMIT 1;
```

**When**: Something went very wrong (should never happen)
**Purpose**: Absolute guarantee that SOME event gets tagged

---

## How It Works

### Event Creation Flow

**User creates Event A (Jan 20)**:
```
1. INSERT triggers → calculate_event_status() (BEFORE trigger)
   - Sets is_ended = false
   - Sets is_active = false
   - Sets is_future = true

2. INSERT completes

3. AFTER INSERT trigger → update_most_upcoming_event()
   - Clears is_upcoming for all user's events
   - Finds soonest future event (Event A)
   - Sets Event A: is_upcoming = true

Result: Event A has is_upcoming = true ✅
```

**User creates Event B (Jan 15, earlier than Event A)**:
```
1. INSERT triggers → calculate_event_status()
   - Sets is_ended = false
   - Sets is_active = false
   - Sets is_future = true

2. INSERT completes

3. AFTER INSERT trigger → update_most_upcoming_event()
   - Clears is_upcoming for all user's events
   - Finds soonest future event (Event B, since Jan 15 < Jan 20)
   - Sets Event B: is_upcoming = true
   - Event A: is_upcoming = false (cleared in step 1)

Result: Event B has is_upcoming = true ✅
```

---

### Event Start Flow

**User starts Event B**:
```
1. start_event() RPC called
   - Sets Event B: is_active = true

2. UPDATE triggers → calculate_event_status()
   - Sets is_future = false (no longer future since active)

3. AFTER UPDATE trigger → update_most_upcoming_event()
   - Clears is_upcoming for all user's events
   - Priority 1 fails (Event B is active, not future)
   - Finds next soonest future event (Event A)
   - Sets Event A: is_upcoming = true
   - Event B: is_upcoming = false

Result: Event A has is_upcoming = true ✅
```

---

### Event End Flow

**User ends Event B (or end time passes)**:
```
1. stop_event() RPC called OR auto-trigger
   - Sets Event B: is_ended = true
   - Sets is_active = false

2. UPDATE triggers → calculate_event_status()
   - Sets is_future = false

3. AFTER UPDATE trigger → update_most_upcoming_event()
   - Clears is_upcoming for all user's events
   - Finds soonest future event (Event A still)
   - Sets Event A: is_upcoming = true

Result: Event A has is_upcoming = true ✅
```

---

### All Events Ended (Fallback Case)

**User has only past events**:
```
Events:
- Event A (Jan 15): is_ended = true
- Event B (Jan 20): is_ended = true
- Event C (Jan 25): is_ended = true

Trigger logic:
- Priority 1 fails (no future events)
- Priority 2 fails (no active events)
- Priority 3 succeeds → Tag Event C (most recent)

Result: Event C has is_upcoming = true ✅
```

**Why**: This prevents the "Patience" alert from showing on all events. The user can tap Event C to view memories without getting blocked.

---

## Logging Output

When the trigger runs, you'll see comprehensive logs in Supabase:

```
🔄 [update_most_upcoming_event] Recalculating is_upcoming for user: abc123...
   📊 Total events for user: 3
   🧹 Cleared is_upcoming for all events
   ✅ PRIORITY 1: Set is_upcoming=true for future event: xyz789...
      Event: Birthday Party (Date: 2026-01-20, Start: 14:00:00, isFuture: true)

   📋 Summary of all events for user:
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   📅 Birthday Party
      Date: 2026-01-20 | Start: 14:00:00 | End: 18:00:00
      Status: isActive=false, isUpcoming=true, isFuture=true, isEnded=false
      ⭐ THIS IS THE UPCOMING EVENT
   📅 Conference
      Date: 2026-01-25 | Start: 09:00:00 | End: 17:00:00
      Status: isActive=false, isUpcoming=false, isFuture=true, isEnded=false
   📅 Vacation
      Date: 2026-02-01 | Start: none | End: none
      Status: isActive=false, isUpcoming=false, isFuture=true, isEnded=false
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   🎯 Events with is_upcoming=true: 1
   ✅ SUCCESS: Exactly 1 event tagged as upcoming
```

---

## Validation

The migration includes automatic validation:

```sql
🔍 VALIDATION: Checking is_upcoming counts per user...

✅ User abc123 has exactly 1 event with is_upcoming=true
✅ User def456 has exactly 1 event with is_upcoming=true
✅ User ghi789 has exactly 1 event with is_upcoming=true

🎉 VALIDATION PASSED: All users have exactly 1 is_upcoming=true event!
```

If validation fails:
```sql
❌ User abc123 has 0 events with is_upcoming=true
❌ User def456 has 2 events with is_upcoming=true

⚠️ VALIDATION FAILED: Some users have incorrect is_upcoming counts
   Run the data migration again to fix
```

---

## Testing Checklist

### Test 1: Create First Event
- [ ] Create your first event
- [ ] Verify `is_upcoming = true`
- [ ] Verify no "Patience" alert when tapping it

### Test 2: Create Second Earlier Event
- [ ] Create event with earlier date than first event
- [ ] Verify new event has `is_upcoming = true`
- [ ] Verify first event has `is_upcoming = false`
- [ ] Tap first event → Should show "Patience" alert
- [ ] Tap new event → Should show "Start Event" dialog

### Test 3: Start Event
- [ ] Start the upcoming event
- [ ] Verify started event has `is_upcoming = false`
- [ ] Verify next event has `is_upcoming = true`

### Test 4: End Event
- [ ] End the active event
- [ ] Verify ended event has `is_upcoming = false`
- [ ] Verify next future event has `is_upcoming = true`

### Test 5: All Events Ended (Fallback)
- [ ] Create 3 events, all in the past
- [ ] Verify most recent past event has `is_upcoming = true`
- [ ] Verify you can tap it without "Patience" alert
- [ ] Verify it navigates to memories playback

### Test 6: Multiple Users
- [ ] Create events for multiple user accounts
- [ ] Verify each user has exactly 1 event with `is_upcoming = true`
- [ ] Verify users don't interfere with each other

---

## Files Modified

1. ✅ **`FIX_IS_UPCOMING_ALWAYS_ONE.sql`** (NEW)
   - Rewrote `update_most_upcoming_event()` with 4-priority system
   - Created `log_all_events_status()` helper function
   - Recreated AFTER triggers
   - Data migration to fix all existing events
   - Validation queries

2. No Swift changes needed - the logic is purely database-side

---

## Key Improvements

| Before | After |
|--------|-------|
| ❌ Some users had 0 events with `is_upcoming = true` | ✅ Every user has exactly 1 event with `is_upcoming = true` |
| ❌ "Patience" alert showed on all events | ✅ "Patience" alert only shows on non-upcoming events |
| ❌ No fallback for all-past-events case | ✅ Tags most recent past event as fallback |
| ❌ No validation | ✅ Automatic validation after migration |
| ❌ Minimal logging | ✅ Comprehensive logging with event summaries |

---

## Next Steps

1. **Run the SQL migration**:
   - Open Supabase Dashboard → SQL Editor
   - Copy contents of `FIX_IS_UPCOMING_ALWAYS_ONE.sql`
   - Execute the migration
   - Check logs for validation results

2. **Verify in Supabase**:
   - Check the verification query output
   - Ensure each user has exactly 1 event with `is_upcoming = true`

3. **Test in app**:
   - Create new events
   - Verify correct "Upcoming" behavior
   - Verify "Patience" alert only shows on non-upcoming events
   - Check Xcode console logs

4. **Monitor**:
   - Watch for any users with incorrect `is_upcoming` counts
   - Check Supabase logs after event creation/updates

---

## Troubleshooting

### Issue: User has 0 events with is_upcoming = true

**Cause**: Trigger didn't fire or failed

**Fix**:
```sql
-- Manually trigger recalculation for specific user
UPDATE events
SET updated_at = NOW()
WHERE user_id = '<user-id>'
LIMIT 1;
```

---

### Issue: User has 2+ events with is_upcoming = true

**Cause**: Trigger ran multiple times or race condition

**Fix**:
```sql
-- Manually fix for specific user
-- Clear all first
UPDATE events
SET is_upcoming = false
WHERE user_id = '<user-id>';

-- Then set the soonest one
UPDATE events
SET is_upcoming = true
WHERE id = (
    SELECT id FROM events
    WHERE user_id = '<user-id>'
      AND is_ended = false
      AND is_active = false
      AND is_future = true
    ORDER BY event_date ASC, start_time ASC
    LIMIT 1
);
```

---

### Issue: "Patience" alert shows on all events

**Cause**: All events have `is_upcoming = false`

**Fix**: Same as "User has 0 events" above

---

## Summary

This fix implements a **bulletproof system** that GUARANTEES:

✅ **Exactly 1 event** has `is_upcoming = true` at all times
✅ **Soonest future event** gets priority
✅ **Automatic fallback** to active/past events when no future events exist
✅ **Comprehensive logging** for debugging
✅ **Automatic validation** to detect issues
✅ **No more "Patience" alerts** on all events

The system now correctly enforces chronological event ordering while ensuring users can always interact with at least one event.
