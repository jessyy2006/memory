# Events Feature Testing Guide

## Prerequisites

Before testing, make sure you've completed these steps:

### ✅ Step 1: Run the Database Migration

1. Open your Supabase dashboard at https://supabase.com/dashboard
2. Select your Memory app project
3. Click **SQL Editor** in the left sidebar
4. Click **New query**
5. Open the file `EVENTS_MIGRATION.sql` from your project
6. Copy and paste the **entire contents** into the SQL Editor
7. Click **Run** (or press Cmd+Enter)
8. You should see: "Success. No rows returned"

**Verify the migration:**
```sql
-- Run this query to verify:
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'events';
```

You should see the `events` table listed.

---

### ✅ Step 2: Add Files to Xcode

1. Open your project in Xcode
2. Add the new Swift files:
   - Right-click `Models` folder → Add Files → Select `Event.swift`
   - Right-click `Services` folder → Add Files → Select `EventService.swift`
   - Right-click `Views` folder → Add Files → Select `Events/EventsTestView.swift`

---

### ✅ Step 3: Build the Project

1. In Xcode, press **Cmd+B** to build
2. Fix any import errors if they appear
3. Make sure the build succeeds

---

## How to Test

### Option A: Using the Test View (Currently Active)

I've already set up your app to launch `EventsTestView` when you're authenticated.

**To test:**

1. **Run the app** (Cmd+R in Xcode)
2. **Sign in** with your test account
3. You'll see the **Events Test** screen

**What you can do:**

1. **Create an Event:**
   - Tap "Create Event" (top right)
   - Enter event name: "Test Event"
   - Choose a date (try tomorrow's date)
   - Optionally set time range
   - Tap "Create Event"

2. **Start an Event:**
   - You'll see your event in the "Upcoming Events" section
   - Tap the "Start" button
   - The event should move to the top as "Active Event"

3. **Try to Start Another Event:**
   - Create a second event with a later date
   - Try to start it
   - You should see an error: "Cannot start event: Can only start the most upcoming event"

4. **Stop an Event:**
   - Tap "Stop" on the active event
   - It should deactivate

5. **Delete an Event:**
   - Swipe left on any event
   - Tap "Delete"

---

### Option B: Using Xcode Previews

You can also test individual components:

1. Open `EventsTestView.swift`
2. Click the **Preview** button (or press Option+Cmd+Return)
3. The preview will show the test view

---

### Option C: Write a Quick Test in Playground

Create a new Playground and test the service directly:

```swift
import Foundation
import Supabase

// Initialize
let eventService = EventService()

// Test creating an event
Task {
    do {
        // Create event
        let event = Event(
            userId: yourUserId, // Replace with your user ID
            name: "My Birthday",
            eventDate: Date().addingTimeInterval(86400 * 7) // 7 days from now
        )

        let created = try await eventService.createEvent(event)
        print("✅ Event created: \(created.name)")

        // Fetch all events
        let events = try await eventService.fetchEvents()
        print("✅ Total events: \(events.count)")

        // Get most upcoming
        if let upcoming = try await eventService.getMostUpcomingEvent() {
            print("✅ Most upcoming: \(upcoming.name)")

            // Try to start it
            let response = try await eventService.startEvent(eventId: upcoming.id)
            print("✅ Event started!")
        }

        // Get active event
        if let active = try await eventService.getActiveEvent() {
            print("✅ Active event: \(active.name)")
        }

    } catch {
        print("❌ Error: \(error)")
    }
}
```

---

## Testing Checklist

Use this checklist to verify everything works:

- [ ] Database migration ran successfully
- [ ] App builds without errors
- [ ] Can create an event
- [ ] Event appears in "Upcoming Events" section
- [ ] Can start the most upcoming event
- [ ] Event moves to "Active Event" card when started
- [ ] Cannot start non-upcoming events (error shows)
- [ ] Can stop an active event
- [ ] Can delete an event
- [ ] Events are sorted by date
- [ ] Past events appear in "Past Events" section
- [ ] Only one event can be active at a time

---

## Common Issues

### "No authentication found"

**Problem:** User is not signed in.

**Solution:**
- Make sure you're signed in before accessing EventsTestView
- Check that `authService.isAuthenticated` is true

### "Cannot start event: Can only start the most upcoming event"

**Problem:** You're trying to start an event that isn't the next upcoming one.

**Solution:** This is expected behavior! Only the event with the earliest future date can be started.

### Build errors for "Event.self"

**Problem:** Event model not added to Xcode project.

**Solution:**
1. Right-click Models folder
2. Add Files to "Memory"
3. Select Event.swift
4. Make sure "Memory" target is checked

### Events not showing up

**Problem:** Database query failing or RLS blocking access.

**Solution:**
1. Check Supabase logs (Logs → Postgres Logs)
2. Verify the user_id matches your authenticated user
3. Verify RLS policies are enabled

---

## What to Test Next

Once basic CRUD works, test these scenarios:

### Scenario 1: Active Event Constraint

1. Create Event A (tomorrow)
2. Create Event B (next week)
3. Start Event A
4. Try to start Event B → Should fail
5. Stop Event A
6. Now try to start Event B → Should still fail (not most upcoming)

### Scenario 2: Date-Based Activation

1. Create Event A (tomorrow)
2. Create Event B (today or past)
3. Try to start Event B → Should fail (past event)
4. Only Event A should be startable

### Scenario 3: Memory Linking

1. Start an event
2. Create a memory and link it to the active event
3. Fetch memories with events
4. Verify the event name shows up with the memory

---

## Next Steps After Testing

Once you've verified everything works:

1. **Restore your original app:**
   - Go to `MemoryApp.swift`
   - Uncomment `MemoriesHomeView()`
   - Comment out `EventsTestView()`

2. **Integrate events into your main UI:**
   - Add event selection when creating memories
   - Show event badges on memories
   - Add an events management screen

3. **Add UI polish:**
   - Event creation forms
   - Calendar picker
   - Event details view
   - Memory gallery by event

---

## Debugging Tools

### Check Supabase Logs

1. Go to your Supabase dashboard
2. Click **Logs** → **Postgres Logs**
3. You'll see all SQL queries and errors

### Print Event Service Responses

Add print statements in EventService:

```swift
func fetchEvents() async throws -> [EventRecord] {
    let response = try await supabase...
    print("📊 Fetched \(response.count) events")
    return response
}
```

### Use Supabase SQL Editor

Test queries directly:

```sql
-- See all events
SELECT * FROM events;

-- See memories with events
SELECT * FROM memories_with_events;

-- Test stored procedure
SELECT * FROM get_most_upcoming_event('your-user-id');
```

---

## Getting Help

If you run into issues:

1. Check the Supabase logs
2. Verify the SQL migration ran completely
3. Check that user_id matches your authenticated user
4. Review the error messages in EventService
5. Check EVENTS_README.md for detailed API docs

---

Happy Testing! 🎉
