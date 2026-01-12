# Fix: is_upcoming Field - Only One Event Should Be True

## Problem Identified

From your error logs:
```
📋 [EventsHomeView] Event List:
   1. Test1 Event1
      - is_upcoming: true  ❌ Wrong!
   2. Test1 Event2
      - is_upcoming: true  ❌ Wrong!

Error: Can only start the most upcoming event
Most upcoming event ID: 54AE5713-2545-4B65-8EDD-042818DD6C34 (Test1 Event1)
```

**Issue**: ALL future events have `is_upcoming = true` in the database, but only ONE event (the closest to now) should have it.

**Result**: You cannot start events because the database knows Test1 Event1 (Jan 12) is the most upcoming, but both events are marked as upcoming.

---

## Solution Applied

### 1. Database Fix (SQL) ✅

Created `SUPABASE_FIX_IS_UPCOMING.sql` with database triggers that:

- **Automatically recalculate** `is_upcoming` whenever events are created, updated, or deleted
- **Ensure only ONE event** per user has `is_upcoming = true` (the most upcoming one)
- **Set all other events** to `is_upcoming = false`

**What it does**:
1. Creates a function `recalculate_is_upcoming(user_id)` that finds the most upcoming event
2. Sets that event's `is_upcoming = true`
3. Sets all other events' `is_upcoming = false`
4. Triggers automatically run whenever events are modified

### 2. Swift Code Fix ✅

Updated `EventService.swift` methods that were filtering by `isUpcoming`:

**Before** (broken with new logic):
```swift
func getUpcomingEvents() async throws -> [EventRecord] {
    let allEvents = try await fetchEvents()
    return allEvents.filter { $0.isUpcoming == true }  // Would only return 1 event!
}
```

**After** (correctly filters events that haven't ended):
```swift
func getUpcomingEvents() async throws -> [EventRecord] {
    let allEvents = try await fetchEvents()
    return allEvents.filter { event in
        // Calculate if event has ended based on end_time or event_date
        // Returns multiple events that are still in the future
    }
}
```

### 3. Documentation ✅

Updated `Event.swift` to clarify the semantic difference:

- **Database `is_upcoming`**: Only true for THE SINGLE most upcoming event (only one)
- **Event model `isUpcoming` property**: True for ANY event that hasn't ended (multiple)

---

## How to Apply the Fix

### Step 1: Run SQL Migration in Supabase

1. Open your **Supabase SQL Editor**
2. Copy and paste the contents of `SUPABASE_FIX_IS_UPCOMING_CORRECTED.sql`
3. Click **Run**

Expected output:
```
Success. No rows returned
```

**Note**: Use `SUPABASE_FIX_IS_UPCOMING_CORRECTED.sql`, not the original file. The corrected version creates the `is_upcoming` column first before setting up triggers.

### Step 2: Verify the Fix

Run this query in Supabase SQL Editor:
```sql
SELECT
  name,
  event_date,
  is_active,
  is_upcoming
FROM events
WHERE user_id = 'YOUR_USER_ID_HERE'
ORDER BY event_date ASC;
```

**Expected result**:
```
name           | event_date | is_active | is_upcoming
---------------|------------|-----------|------------
Test1 Event1   | 2026-01-12 | false     | true       ← Only this one!
Test1 Event2   | 2026-01-13 | false     | false
Test1 Event3   | 2026-01-14 | false     | false
```

Only ONE event should have `is_upcoming = true` (the one with the earliest date/time).

### Step 3: Test in Your App

1. **Clean Build** in Xcode (⌘⇧K)
2. **Run** the app (⌘R)
3. Go to Events page
4. Try to start **Test1 Event1** (the most upcoming one)
5. It should work now!

Expected console output:
```
🎬 [EventsHomeView] Starting event: Test1 Event1
📞 [EventService] Calling RPC: start_event
📬 [EventService] RPC Response received:
   - success: true  ✅
   - event_id: 54AE5713-2545-4B65-8EDD-042818DD6C34
✅ [EventService] Event started successfully!
🧭 [EventsHomeView] Navigating to MemoriesHomeView...
```

---

## What Changed

### Database Behavior

**Before**:
- `is_upcoming = true` for ALL events with `event_date >= CURRENT_DATE`
- Multiple events could have `is_upcoming = true`

**After**:
- `is_upcoming = true` for ONLY the single event with the earliest date/time in the future
- Automatically updated when events are created/modified/deleted

### Swift Code Behavior

**Before**:
- `getUpcomingEvents()` relied on database's `isUpcoming` field
- Would have broken after SQL fix (only 1 event returned)

**After**:
- `getUpcomingEvents()` calculates which events haven't ended yet
- Returns ALL future events correctly
- Database's `is_upcoming` is only used by the RPC `start_event` function

---

## Why This Fix Works

### The Two Meanings of "Upcoming"

1. **"Most Upcoming" (singular)**: The NEXT event to occur
   - Used by: Database `is_upcoming` field
   - Used for: Determining which event can be started
   - Only ONE event can have this

2. **"In the Future" (plural)**: Events that haven't ended yet
   - Used by: Swift filtering methods
   - Used for: Displaying future events in the UI
   - Multiple events can have this

### How Event Starting Works

1. User taps an event
2. UI shows confirmation dialog
3. User taps "Start"
4. App calls `startEvent(eventId)`
5. RPC function checks: "Is this event THE most upcoming?"
   - If YES: Set `is_active = true` ✅
   - If NO: Return error with the correct event ID ❌
6. Now the database's `is_upcoming` field is correct, so validation passes!

---

## Testing Checklist

After applying the SQL fix:

- [ ] Run SQL migration in Supabase
- [ ] Verify only ONE event has `is_upcoming = true` in database
- [ ] Clean build in Xcode
- [ ] Create multiple future events
- [ ] Verify only the earliest one has `is_upcoming = true` in logs
- [ ] Try to start the most upcoming event → Should work ✅
- [ ] Try to start a different event → Should show error ❌
- [ ] Start the correct event → Should navigate to MemoriesHomeView

---

## Next Steps

Once event starting works:
1. ✅ Events will activate correctly
2. ✅ You can navigate to MemoriesHomeView
3. ✅ You can add memories to active events
4. 🔄 Still need to make `event_id NOT NULL` in memories table (separate task)

Let me know after you run the SQL migration and test event starting!
