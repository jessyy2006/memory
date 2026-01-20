# Testing the UTC Migration

## What Was Changed

### Database Changes
- Converted `start_time` and `end_time` from `TIME` (no timezone) to `TIMESTAMPTZ` (with timezone, stored in UTC)
- Updated `calculate_event_status()` trigger to use UTC comparisons
- Removed Pacific timezone hardcoding

### Swift Changes
- `EventRecord` decoder now expects ISO8601 timestamps instead of "HH:mm:ss" strings
- `EventInsert` encoder now converts local times to UTC before sending
- `MemoryWithEvent` decoder updated to handle TIMESTAMPTZ

## Testing Steps

### IMPORTANT: Before Running Migration

**Current State**:
- Database uses `FIX_ISENDED_ROOT_CAUSE.sql` (Pacific timezone hardcoded)
- Swift code expects TIME format ("HH:mm:ss")
- **Events are working correctly right now**

### Step 1: Run Database Migration

1. Go to Supabase SQL Editor
2. Open `MIGRATE_TO_UTC_STORAGE.sql`
3. Click **Run**
4. Check output for any errors
5. Verify migration completed successfully

Expected output:
```
🔄 MIGRATING EXISTING TIME DATA TO UTC...
Event <uuid> | Start Pacific: 2026-01-20 15:00:00 → Start UTC: 2026-01-20 23:00:00+00
Event <uuid> | End Pacific: 2026-01-20 17:00:00 → End UTC: 2026-01-21 01:00:00+00
✅ Data migration complete!
...
🔄 RECALCULATING ALL EVENTS WITH UTC LOGIC...
✅ Recalculation complete!
```

### Step 2: Verify Database Schema

Run this query in Supabase:
```sql
\d events
```

Expected: `start_time` and `end_time` should be type `timestamp with time zone`

### Step 3: Check Stored Data

Run this query:
```sql
SELECT
    name,
    start_time as start_utc,
    end_time as end_utc,
    start_time AT TIME ZONE 'America/Los_Angeles' as start_pacific,
    end_time AT TIME ZONE 'America/Los_Angeles' as end_pacific
FROM events
WHERE start_time IS NOT NULL
ORDER BY event_date ASC
LIMIT 5;
```

Expected: Pacific times should match what you remember creating

### Step 4: Build and Run iOS App

**CRITICAL**: The Swift code changes are already in place. Once you run the migration, the app should:

1. Open Xcode:
   ```bash
   open Memory.xcodeproj
   ```

2. Build the project (⌘B)
   - Should compile without errors

3. Run on simulator (⌘R)

### Step 5: Test Existing Events

1. Open Events Home page
2. Verify all existing events display correct times
3. Check that:
   - Events with times in the future show on Events Home
   - Events with times in the past show on Past Events
   - Times display in 12-hour format (e.g., "3:00 PM")

### Step 6: Create New Event

1. Create a new event for today
2. Set time to 3:00 PM (current time must be before 3 PM)
3. Save event

**Verify**:
1. Event appears on Events Home (not Past Events)
2. Time displays as "3:00 PM"
3. Event status shows correctly

**Check in Database**:
```sql
SELECT
    name,
    start_time,
    end_time,
    start_time AT TIME ZONE 'America/Los_Angeles' as start_pacific,
    end_time AT TIME ZONE 'America/Los_Angeles' as end_pacific,
    is_ended,
    is_future
FROM events
ORDER BY created_at DESC
LIMIT 1;
```

Expected:
- `start_time`: Should be UTC (e.g., 23:00:00+00 for 3 PM PST)
- `start_pacific`: Should be 15:00:00 (3 PM)
- `is_ended`: Should be `false`
- `is_future`: Should be `true`

### Step 7: Test Event Status Updates

Wait for an event to pass its end time, or:

1. Create an event for today with end time 1 minute from now
2. Wait for it to end
3. Pull to refresh Events Home

**Expected**:
- Event should move from Events Home to Past Events
- `is_ended` should be `true`
- `is_future` should be `false`

## What to Watch For

### ✅ Success Indicators
- Existing events display correct times
- New events are created with correct times
- Event status (is_ended, is_future) calculated correctly
- Times automatically adjust if you change device timezone
- No crashes or errors in Xcode console

### ❌ Potential Issues

**Issue**: Events display wrong times (off by hours)
**Cause**: Migration didn't interpret existing times correctly
**Fix**: Check that migration used correct timezone (Pacific)

**Issue**: New events not appearing
**Cause**: EventInsert might not be converting times correctly
**Fix**: Check Xcode console for errors, verify ISO8601 format

**Issue**: Build errors in Xcode
**Cause**: Swift syntax error
**Fix**: Check error message, verify all changes were applied

**Issue**: App crashes when loading events
**Cause**: Decoder mismatch (expecting TIME but getting TIMESTAMPTZ)
**Fix**: Verify migration completed, check database schema

## Rollback Plan

If anything goes wrong:

1. **Swift Code**:
   ```bash
   git checkout HEAD -- Memory/Models/Event.swift
   ```

2. **Database**: Run rollback SQL (see UTC_MIGRATION_GUIDE.md)

3. **Re-run current working migration**:
   ```sql
   -- Run FIX_ISENDED_ROOT_CAUSE.sql again
   ```

## Expected Timeline

- Database migration: 1-2 minutes
- Swift build: 30 seconds
- Testing: 5-10 minutes
- **Total: ~15 minutes**

## Success Criteria

- [ ] Database migration completed without errors
- [ ] Schema shows TIMESTAMPTZ for start_time and end_time
- [ ] Existing events display correct times in app
- [ ] New events can be created successfully
- [ ] Event times display correctly (3:00 PM format)
- [ ] Event status calculation works (is_ended, is_future)
- [ ] Events move to Past Events when ended
- [ ] No crashes or build errors

## Notes

- **Swift Date objects**: Always store UTC internally, display in local timezone automatically
- **Database NOW()**: Always UTC
- **Times in app**: Always display in user's device timezone
- **This is a breaking change**: You must run both database migration AND use new Swift code together

## Questions to Answer

After testing:
1. Do all existing events show correct times? ✓ / ✗
2. Can you create new events successfully? ✓ / ✗
3. Do new events display correct times? ✓ / ✗
4. Does event status update correctly? ✓ / ✗
5. Are times stored in UTC in the database? ✓ / ✗
