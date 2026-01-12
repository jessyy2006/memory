# Diagnostic Logging Added for Event Starting Issue

## What I Added

### 1. EventsHomeView.swift (lines 305-335)
Added detailed logging to `startEvent()` function:
- Event details being started
- Service call tracking
- Response logging
- Navigation tracking
- Error details if failure

### 2. EventService.swift (lines 180-213)
Added comprehensive logging to `startEvent()` function:
- RPC call parameters
- Response details (success, error, event_id)
- Success/failure status

---

## What To Do Now

### Step 1: Clean Build & Run
```
Product → Clean Build Folder (⌘⇧K)
Product → Build (⌘B)
Product → Run (⌘R)
```

### Step 2: Try to Start an Event
1. Go to Events page
2. Tap on an upcoming event
3. Tap "Start" in the confirmation dialog
4. **Watch the Xcode console**

### Step 3: Share Console Output

**Expected console output (SUCCESS):**
```
🎬 [EventsHomeView] Starting event: Test Event
   - Event ID: <uuid>
   - Event Date: 2026-01-13 00:00:00 +0000
   - Is Upcoming: true
📞 [EventsHomeView] Calling EventService.startEvent()...
🎬 [EventService] startEvent() called
   - Event ID: <uuid>
   - User ID: <uuid>
📞 [EventService] Calling RPC: start_event
📬 [EventService] RPC Response received:
   - success: true
   - error: none
   - event_id: <uuid>
   - most_upcoming_event_id: nil
✅ [EventService] Event started successfully!
✅ [EventsHomeView] Event started successfully!
🔄 [EventsHomeView] Reloading events after start...
🧭 [EventsHomeView] Navigating to MemoriesHomeView...
✅ [EventsHomeView] Navigation triggered
```

**Possible console output (FAILURE):**
```
🎬 [EventsHomeView] Starting event: Test Event
   - Event ID: <uuid>
📞 [EventsHomeView] Calling EventService.startEvent()...
🎬 [EventService] startEvent() called
📞 [EventService] Calling RPC: start_event
📬 [EventService] RPC Response received:
   - success: false
   - error: Can only start the most upcoming event
   - event_id: nil
   - most_upcoming_event_id: <different-uuid>
❌ [EventService] Event start FAILED!
   - Reason: Can only start the most upcoming event
   - Most upcoming event ID: <different-uuid>
❌ [EventsHomeView] Failed to start event: Cannot start event: Can only start the most upcoming event
```

---

## Understanding The Issue

### Scenario A: Event Starts Successfully ✅
If you see:
```
- success: true
✅ [EventsHomeView] Navigation triggered
```

**Then event starting works!** The issue might be with navigation or MemoriesHomeView not displaying properly.

### Scenario B: "Can only start the most upcoming event" ❌
If you see:
```
- success: false
- error: Can only start the most upcoming event
- most_upcoming_event_id: <different-uuid>
```

**Root Cause:** The database thinks a DIFFERENT event is the "most upcoming" one.

**Why this happens:**
- Database uses UTC timezone for `CURRENT_DATE`
- Client sorting uses local timezone (EST)
- An event you think is "tomorrow" might be "today" in UTC

**Example:**
- Current time: 11 PM EST on Jan 12
- Database (UTC): CURRENT_DATE = Jan 13
- Event A: Jan 13 → Database thinks this is "today" and most upcoming
- Event B: Jan 14 → You think this is tomorrow and try to start it
- Result: FAIL - database says "Event A is most upcoming, not Event B"

### Scenario C: "No upcoming events found" ❌
If you see:
```
- success: false
- error: No upcoming events found
```

**Root Cause:** All your events are in the past (according to database timezone).

---

## Fixing The Issue

### If Scenario B Happens:

**Option 1: Start the CORRECT event** ✅
The console will show:
```
- most_upcoming_event_id: <uuid>
```

Find the event with this ID in your events list and start THAT one instead.

### Option 2: Fix timezone mismatch in database
Update the `start_event` RPC function to use local date comparison:

```sql
-- In Supabase SQL Editor
CREATE OR REPLACE FUNCTION start_event(p_event_id UUID, p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_most_upcoming_id UUID;
  v_event_date DATE;
  v_result JSON;
BEGIN
  -- Get the most upcoming event ID for this user
  SELECT id INTO v_most_upcoming_id
  FROM events
  WHERE user_id = p_user_id
    AND event_date >= CURRENT_DATE  -- This uses database timezone (UTC)
  ORDER BY event_date ASC, start_time ASC NULLS LAST
  LIMIT 1;

  -- Rest of function...
END;
$$;
```

**Problem:** `CURRENT_DATE` is in UTC, but user's events are in EST.

**Possible Fix:** Remove the "most upcoming" restriction and allow starting any upcoming event:

```sql
CREATE OR REPLACE FUNCTION start_event_any_upcoming(p_event_id UUID, p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
  v_event_date DATE;
BEGIN
  -- Get the event date
  SELECT event_date INTO v_event_date
  FROM events
  WHERE id = p_event_id AND user_id = p_user_id;

  IF v_event_date IS NULL THEN
    v_result := json_build_object(
      'success', false,
      'error', 'Event not found'
    );
    RETURN v_result;
  END IF;

  -- Check if event is at least today or in the future
  IF v_event_date < CURRENT_DATE THEN
    v_result := json_build_object(
      'success', false,
      'error', 'Cannot start past events'
    );
    RETURN v_result;
  END IF;

  -- Deactivate all events for this user
  UPDATE events
  SET is_active = false, updated_at = NOW()
  WHERE user_id = p_user_id;

  -- Activate the requested event
  UPDATE events
  SET is_active = true, updated_at = NOW()
  WHERE id = p_event_id AND user_id = p_user_id;

  v_result := json_build_object(
    'success', true,
    'event_id', p_event_id
  );

  RETURN v_result;
END;
$$;
```

---

## Next Steps

1. ✅ **Try to start an event** and copy the console logs
2. ✅ **Share the logs** so we can see exactly what's failing
3. ✅ **I'll fix the specific issue** based on the logs

---

## About memories_with_events

As explained in `FIX_EVENT_START_AND_MEMORY_SCHEMA.md`:

- `memories` = TABLE (actual data storage)
- `memories_with_events` = VIEW (just a query, not duplicate data)

**Current issue:** `event_id` in memories table is NULLABLE

**Your requirement:** Every memory MUST be linked to an event

**Fix needed:** Make `event_id NOT NULL` in the memories table

**Do you want me to:**
1. Add SQL migration to make event_id required?
2. Update Swift Memory models to enforce event_id?
3. Ensure memory creation always includes an event_id?

Let me know after you try starting an event and share the console logs!
