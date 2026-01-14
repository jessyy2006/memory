# Event State Management Fix - Instructions

## Problem Summary

When creating a new event, it appears as "ended" even though it hasn't been started yet. The event should appear as "upcoming" or "active" depending on its state.

## Root Cause

The issue occurs because when a new event is created:
1. It gets `is_active = false` (correct - not started yet)
2. It gets `is_ended = false` (correct - not ended yet)
3. BUT `is_upcoming` is **not calculated** automatically

Without `is_upcoming` being set, the event filtering logic fails and events appear in the wrong sections.

## Current Event State Rules

An event should follow these states:

### When Creating a New Event
- `is_active = false` (not started yet)
- `is_ended = false` (not ended yet)
- `is_upcoming = true` **ONLY IF** it's the closest upcoming event for this user

### When Clicking "Start Event"
- `is_active = true`
- `is_ended = false`
- `is_upcoming = false`

### When Clicking "End Event"
- `is_active = false`
- `is_ended = true`
- `is_upcoming = false`
- The **next** event should automatically get `is_upcoming = true`

## The Fix

### Step 1: Run the Database Migration

Execute the SQL file `FIX_EVENT_CREATION_STATE.sql` in your Supabase SQL Editor.

This migration will:
1. Create a function to recalculate `is_upcoming` for a user
2. Add a trigger that runs after every INSERT to update `is_upcoming`
3. Fix all existing events to have the correct `is_upcoming` value

### Step 2: Verify the Fix

After running the migration:

1. **Check existing events**: Run this query in Supabase SQL Editor:
   ```sql
   SELECT name, event_date, is_active, is_upcoming, is_ended
   FROM events
   ORDER BY event_date ASC;
   ```

2. **Create a new event** in your app

3. **Verify it shows as "upcoming"** on the home page (not "ended")

### Step 3: Test the Complete Lifecycle

1. **Create Event**: Should appear as "upcoming" with blue badge
2. **Click "Start Event"**: Should become "active" with green badge
3. **Click "End Event"**: Should move to "Past Events" list
4. **Create Another Event**: Should automatically become "upcoming"

## Files Modified

- ✅ Database: Added trigger in `FIX_EVENT_CREATION_STATE.sql`
- ✅ Swift Model: Already has `isEnded` field (Event.swift:122, 135, 149)
- ✅ Swift Service: Already calls correct stored procedures
- ✅ Swift UI: Already filters by `isEnded` (EventsHomeView.swift:34, PastEventsView.swift:156)

## What Was Already Correct

The following was already implemented correctly:

1. **Event Model**: Has all three boolean fields (`is_active`, `is_upcoming`, `is_ended`)
2. **Event Insert**: Sets `is_ended = false` for new events (Event.swift:254)
3. **Start Event**: Stored procedure sets states correctly (COMPLETE_EVENT_STATE_FIX.sql:101-188)
4. **Stop Event**: Stored procedure sets states correctly and calculates next upcoming (COMPLETE_EVENT_STATE_FIX.sql:198-274)
5. **UI Filtering**: Correctly filters by `isEnded` field

## The Only Missing Piece

The **ONLY** missing piece was: **When creating a new event, `is_upcoming` was not being recalculated.**

The `FIX_EVENT_CREATION_STATE.sql` migration adds a database trigger to automatically recalculate `is_upcoming` whenever a new event is inserted.

## After Applying the Fix

Once you run the SQL migration:

- ✅ New events will automatically get `is_upcoming = true` if they're the next upcoming
- ✅ Events will show in the correct section (Home vs Past Events)
- ✅ The complete lifecycle (Create → Start → End) will work as expected
- ✅ Only ONE event per user will have `is_upcoming = true` at a time

## Questions?

If events still appear as "ended" after running the migration:

1. Check that the migration ran successfully (no errors in SQL Editor)
2. Verify the trigger was created: `SELECT * FROM pg_trigger WHERE tgname = 'trigger_after_event_insert';`
3. Check the event states directly: `SELECT * FROM events WHERE user_id = 'YOUR_USER_ID';`
4. Try creating a brand new event and check if `is_upcoming` is set correctly
