# Fix: isUpcoming Sorting Logic Bug

## Problem

Event 6 was incorrectly tagged as `isUpcoming = true` instead of Event 10, even though Event 10's start datetime was closer to the current time.

**Example**:
- Current time: Jan 19, 2026 3:00 PM
- Event 6: Jan 15, no start_time → Treated as Jan 15 00:00:00
- Event 10: Jan 20, start_time 10:00 AM → Treated as Jan 20 10:00:00
- **Wrong Result**: Event 6 tagged as upcoming (Jan 15 < Jan 20)
- **Correct Result**: Event 10 should be upcoming (closest to current time)

## Root Cause

The SQL sorting logic in both migration files was sorting by `event_date` first, then `start_time` separately:

```sql
ORDER BY
  event_date ASC,
  COALESCE(start_time, '23:59:59'::TIME) ASC
```

**Problem with this approach**:
1. PostgreSQL compares `event_date` first
2. Only if dates are equal does it compare `start_time`
3. This picks the **earliest date**, not the **earliest datetime closest to NOW**

**Why events without start_time were problematic**:
- `COALESCE(start_time, '23:59:59'::TIME)` defaulted NULL start times to end-of-day
- This made events without times sort LAST on the same day
- But for different days, the date comparison still happened first

## Solution

Changed the sorting logic to combine `event_date + start_time` into a single TIMESTAMP before sorting:

```sql
ORDER BY
  (event_date + COALESCE(start_time, '00:00:00'::TIME)) ASC
```

**Why this works**:
1. Creates a proper TIMESTAMP by adding date + time
2. Events without start_time default to midnight (00:00:00) of that day
3. PostgreSQL now sorts by actual chronological datetime
4. Picks the event whose start datetime is **soonest** (closest to future from NOW)

## Comparison

### Before (Wrong Logic)

| Event | Date | Start Time | Sort Key (Date, Time) | Selected? |
|-------|------|------------|----------------------|-----------|
| Event 6 | Jan 15 | NULL | (Jan 15, 23:59:59) | ✅ WRONG |
| Event 10 | Jan 20 | 10:00 AM | (Jan 20, 10:00:00) | ❌ |

**Result**: Event 6 wins because PostgreSQL compares Jan 15 vs Jan 20 first.

### After (Correct Logic)

| Event | Date | Start Time | Sort Key (Combined Datetime) | Distance from NOW | Selected? |
|-------|------|------------|------------------------------|-------------------|-----------|
| Event 6 | Jan 15 | NULL | 2026-01-15 00:00:00 | 4 days ago | ❌ |
| Event 10 | Jan 20 | 10:00 AM | 2026-01-20 10:00:00 | 1 day ahead | ✅ CORRECT |

**Result**: Event 10 wins because its combined datetime is soonest in the future.

## Files Modified

### 1. `FIX_IS_UPCOMING_ALWAYS_ONE.sql`
**Line 78**: Changed sorting logic in Priority 1

**Before**:
```sql
ORDER BY
  event_date ASC,
  COALESCE(start_time, '23:59:59'::TIME) ASC
```

**After**:
```sql
ORDER BY
  (event_date + COALESCE(start_time, '00:00:00'::TIME)) ASC
```

### 2. `FIX_EVENT_STATUS_LOGIC.sql`
**Line 172**: Changed sorting logic (same fix)

**Before**:
```sql
ORDER BY
  event_date ASC,
  COALESCE(start_time, '23:59:59'::TIME) ASC
```

**After**:
```sql
ORDER BY
  (event_date + COALESCE(start_time, '00:00:00'::TIME)) ASC
```

## Testing

### Test Case 1: Events on Different Days
```sql
-- Current time: 2026-01-19 15:00:00

Event A: 2026-01-15, start_time = NULL
  → Combined datetime: 2026-01-15 00:00:00
  → 4 days ago (past)

Event B: 2026-01-20, start_time = 10:00:00
  → Combined datetime: 2026-01-20 10:00:00
  → 1 day ahead (future)

Result: Event B gets isUpcoming = true ✅
```

### Test Case 2: Events on Same Day
```sql
-- Current time: 2026-01-20 09:00:00

Event A: 2026-01-20, start_time = NULL
  → Combined datetime: 2026-01-20 00:00:00
  → 9 hours ago (past)

Event B: 2026-01-20, start_time = 10:00:00
  → Combined datetime: 2026-01-20 10:00:00
  → 1 hour ahead (future)

Result: Event B gets isUpcoming = true ✅
```

### Test Case 3: All Events in Past
```sql
-- Current time: 2026-01-25 15:00:00

Event A: 2026-01-15, start_time = NULL
  → Combined datetime: 2026-01-15 00:00:00
  → 10 days ago

Event B: 2026-01-20, start_time = 10:00:00
  → Combined datetime: 2026-01-20 10:00:00
  → 5 days ago

Result: Priority 1 fails (no future events)
Falls back to Priority 3: Event B gets isUpcoming = true (most recent past) ✅
```

## Impact

### Before Fix
- ❌ Event with earliest DATE got tagged, even if it was in the past
- ❌ Events without start_time had unpredictable behavior
- ❌ Users saw "Patience" alert on the wrong events

### After Fix
- ✅ Event with soonest future START DATETIME gets tagged
- ✅ Events without start_time default to midnight (start of day)
- ✅ Users can start the chronologically next event

## Next Steps

1. **Run the updated SQL migration**:
   - Open Supabase Dashboard → SQL Editor
   - Copy contents of `FIX_IS_UPCOMING_ALWAYS_ONE.sql`
   - Execute the migration

2. **Verify in app**:
   - Check which event has `isUpcoming = true`
   - Should be Event 10 now (not Event 6)
   - Tap Event 10 → Should show "Start Event" dialog
   - Tap Event 6 → Should show "Patience" alert

3. **Check logs**:
   - Supabase logs should show Event 10 tagged as upcoming
   - Xcode console should reflect the correct event

## Technical Details

### PostgreSQL Date/Time Addition

When you add a DATE + TIME in PostgreSQL:
```sql
SELECT '2026-01-20'::DATE + '10:00:00'::TIME;
-- Result: 2026-01-20 10:00:00 (TIMESTAMP)
```

This creates a proper TIMESTAMP that can be sorted chronologically.

### NULL Start Time Handling

```sql
COALESCE(start_time, '00:00:00'::TIME)
```

- If `start_time` is NULL → Uses `00:00:00` (midnight)
- If `start_time` exists → Uses the actual time
- This ensures events without start_time are treated as starting at midnight

### Why 00:00:00 instead of 23:59:59?

**Before**: NULL start_time → 23:59:59 (end of day)
- Made events without time sort LAST on same day
- Intended to deprioritize events without specific times
- **Problem**: Didn't work across different dates

**After**: NULL start_time → 00:00:00 (start of day)
- Events without time are treated as "all-day" events starting at midnight
- Works correctly with datetime comparison
- More intuitive: "Event on Jan 20" means "starting Jan 20 00:00:00"

## Summary

The fix changes the sorting logic from a two-column comparison (date, then time) to a single combined datetime comparison. This ensures the event whose start datetime is chronologically soonest (closest to the future from NOW) gets tagged as `isUpcoming = true`.

**Key Change**:
```sql
-- BEFORE: Compare date first, then time
ORDER BY event_date ASC, COALESCE(start_time, '23:59:59'::TIME) ASC

-- AFTER: Compare combined datetime
ORDER BY (event_date + COALESCE(start_time, '00:00:00'::TIME)) ASC
```

This simple change fixes the incorrect tagging behavior and ensures users can always start the chronologically next event.
