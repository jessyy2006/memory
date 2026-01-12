# Events Display Debugging Guide

## Summary of Issues Fixed

### 1. ✅ App Start Flow
**Status**: Already correct
- App starts with `CreateAccountView` when not authenticated
- Shows `EventsHomeView` when authenticated
- **Location**: `MemoryApp.swift:33-39`

### 2. ✅ is_active Filtering
**Status**: Verified NO filtering
- **EventService.fetchEvents()** - Returns ALL events (lines 65-95)
- **RPC Function** `get_events_sorted` - Returns ALL events (EVENTS_MIGRATION.sql:234-267)
- **Direct Query Fallback** - Returns ALL events (EventService.swift:84-93)

### 3. ✅ Enhanced Debug Logging
**Status**: Comprehensive logging added
- EventsHomeView.loadEvents() - Full lifecycle logging
- EventsHomeView.createEvent() - Detailed creation flow
- EventService - RPC and fallback logging

---

## Testing Instructions

### Step 1: Clean Build
1. In Xcode: **Product → Clean Build Folder** (⌘⇧K)
2. **Product → Build** (⌘B)
3. Verify build succeeds

### Step 2: Open Console
1. **View → Debug Area → Show Debug Area** (⌘⇧Y)
2. Make sure you can see console output

### Step 3: Run App
1. **Product → Run** (⌘R)
2. Watch console for session restoration logs:
   - ✅ `"🔄 Checking for existing session..."`
   - ✅ `"✅ Session is valid, restoring authentication..."` OR
   - ℹ️ `"ℹ️ No existing session found"`

### Step 4: Sign Up / Log In (if needed)
If you see the sign-up page:
1. Create account OR log in
2. Complete profile creation
3. You should land on **EventsHomeView**

### Step 5: Create an Event
1. Tap **"Create Event"** button (central button)
2. Enter event details:
   - **Name**: "Test Event 1"
   - **Date**: Tomorrow's date
3. Tap **"Create"**

### Step 6: Check Console for Event Creation Flow

**Expected Console Output** (in order):

```
📝 [EventsHomeView] Creating event: Test Event 1
👤 [EventsHomeView] User ID: <uuid>
📝 [EventsHomeView] Event object created, calling EventService...
📝 [EventService] Creating event: Test Event 1
📝 [EventService] Event date: <date>
📝 [EventService] User ID: <uuid>
📝 [EventService] EventInsert: <details>
✅ [EventService] Event created in Supabase: ID=<uuid>, Name=Test Event 1
✅ [EventsHomeView] Event created successfully!
   - Name: Test Event 1
   - ID: <uuid>
   - Date: <date>
   - is_active: false
🔄 [EventsHomeView] Reloading events list...
🔄 [EventsHomeView] Starting loadEvents()...
✅ [EventsHomeView] User authenticated: <uuid>
🔍 [EventService] Fetching events for user: <uuid>
🔍 [EventService] Calling RPC: get_events_sorted
✅ [EventService] RPC returned 1 events
📥 [EventsHomeView] Received 1 events from EventService
📥 [EventsHomeView] Active event: none
✅ [EventsHomeView] UI Updated - Displaying 1 events
📋 [EventsHomeView] Event List:
   1. Test Event 1
      - ID: <uuid>
      - Date: <date>
      - is_active: false
      - is_upcoming: true
✅ [EventsHomeView] Event creation flow complete
```

---

## Troubleshooting

### Issue 1: RPC Function Not Found
**Console Output:**
```
⚠️ [EventService] RPC failed: function get_events_sorted does not exist
⚠️ [EventService] Falling back to direct query...
✅ [EventService] Direct query returned X events
```

**Solution:**
1. Open **Supabase Dashboard** → SQL Editor
2. Copy the entire contents of `EVENTS_MIGRATION.sql`
3. Run the migration (especially STEP 10)
4. Retry in app

**Note**: Even if RPC fails, the direct query fallback should work!

---

### Issue 2: Events Not Appearing After Creation
**Possible Causes:**

#### A. Authentication Issue
**Console shows:**
```
❌ [EventsHomeView] No user ID found - user not authenticated
```

**Solution:**
- Sign out and sign back in
- Check `AuthenticationService` session restoration

#### B. No Events Returned
**Console shows:**
```
✅ [EventService] RPC returned 0 events
OR
✅ [EventService] Direct query returned 0 events
```

**Diagnosis:**
1. Check **Supabase Dashboard** → Events Table
2. Verify events exist with matching `user_id`
3. Check RLS policies are enabled (EVENTS_MIGRATION.sql STEP 5)

**Solution:**
```sql
-- Run in Supabase SQL Editor to check RLS
SELECT * FROM events WHERE user_id = '<your-user-id>';
```

#### C. Events Returned but Not Displayed
**Console shows:**
```
📥 [EventsHomeView] Received X events from EventService
✅ [EventsHomeView] UI Updated - Displaying X events
📋 [EventsHomeView] Event List:
   1. Test Event 1
      - ID: ...
```

BUT the screen shows empty state.

**Diagnosis**: UI state update issue

**Solution:**
1. Check if `allEvents` array is being set on MainActor
2. Verify SwiftUI view is observing state changes
3. Try force-quitting the app and restarting

---

### Issue 3: Event Shows is_active = true (When It Shouldn't)
**Console shows:**
```
   - is_active: true
```

**Diagnosis**: Database default or previous activation

**Solution:**
```sql
-- Run in Supabase SQL Editor
UPDATE events
SET is_active = false
WHERE user_id = '<your-user-id>';
```

---

## Key Code Locations

### EventsHomeView.swift
- **loadEvents()**: Lines 197-261
- **createEvent()**: Lines 263-300
- **Event card rendering**: Lines 106-115

### EventService.swift
- **fetchEvents()**: Lines 65-95 (RPC + direct query fallback)
- **createEvent()**: Lines 43-61

### EVENTS_MIGRATION.sql
- **get_events_sorted RPC**: Lines 234-267
- **Events table**: Lines 12-22
- **RLS policies**: Lines 52-69

---

## Expected Behavior After Fixes

✅ **App starts with sign-up page** when not logged in
✅ **All events display** regardless of `is_active` status
✅ **Newly created events appear immediately** after creation
✅ **Console shows detailed logs** at every step
✅ **Both RPC and direct query work** (fallback mechanism)

---

## Next Steps

1. **Run the app** and create an event
2. **Copy console output** from event creation
3. **Report results**:
   - ✅ If event appears → Success!
   - ❌ If event doesn't appear → Share console logs

---

## Files Modified in This Session

| File | Changes | Purpose |
|------|---------|---------|
| `EventsHomeView.swift` | Enhanced debug logging | Track event creation and display |
| `EventService.swift` | Already had debug logging | Verify RPC and queries |
| `AuthenticationService.swift` | Fixed session expiration check | Compare TimeIntervals correctly |
| `SupabaseManager.swift` | Simplified initialization | Remove incompatible auth config |

---

## All Debug Log Prefixes

- `[EventsHomeView]` - UI layer logs
- `[EventService]` - Service layer logs
- `[SupabaseManager]` - Database layer logs
- `🔄` - Loading/fetching operations
- `📝` - Creating/inserting operations
- `✅` - Success messages
- `❌` - Error messages
- `⚠️` - Warning messages
- `📥` - Data received
- `📋` - List/array contents

Use these to quickly filter console output!
