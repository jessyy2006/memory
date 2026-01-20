# UTC Storage Migration Guide

## Overview

This migration converts the event time storage from `TIME` (no timezone) to `TIMESTAMPTZ` (with timezone), storing all times in UTC and converting to/from local timezone on the client side.

## Why This Change?

### Previous Issue (Hardcoded Pacific Timezone)
- Times were stored as `TIME` type (no timezone information)
- Database trigger used `NOW() AT TIME ZONE 'America/Los_Angeles'` to compare times
- **Problem**: Only works for Pacific timezone users
- **Problem**: Breaks for users in other timezones

### New Approach (UTC Storage)
- Times are stored as `TIMESTAMPTZ` (timestamp with timezone) in UTC
- Client converts local times to UTC before sending to database
- Database stores everything in UTC
- Client converts UTC back to local time for display
- **Benefit**: Works for all timezones automatically
- **Benefit**: Database logic is timezone-agnostic

## Migration Steps

### 1. Run Database Migration

Execute `MIGRATE_TO_UTC_STORAGE.sql` in your Supabase SQL Editor:

```bash
# Navigate to Supabase Dashboard
https://supabase.com/dashboard/project/YOUR_PROJECT_ID/sql/new

# Copy and paste MIGRATE_TO_UTC_STORAGE.sql
# Click "Run"
```

This will:
1. Add new `start_time_utc` and `end_time_utc` columns as `TIMESTAMPTZ`
2. Migrate existing data (interpreting as Pacific, converting to UTC)
3. Drop old `TIME` columns
4. Rename new columns to original names
5. Update triggers to use UTC comparisons

### 2. Updated Swift Code

The Swift models have been updated to handle UTC conversion automatically:

#### EventRecord Decoder (Reading from Database)
```swift
// OLD: Decoded TIME as local time string
let timeFormatter = DateFormatter()
timeFormatter.dateFormat = "HH:mm:ss"
timeFormatter.timeZone = TimeZone.current
startTime = timeFormatter.date(from: startTimeString)

// NEW: Decodes TIMESTAMPTZ as ISO8601 UTC, converts to local automatically
let iso8601Formatter = ISO8601DateFormatter()
iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
startTime = iso8601Formatter.date(from: startTimeString)
// Swift Date automatically converts to user's local timezone for display
```

#### EventInsert Encoder (Writing to Database)
```swift
// OLD: Sent time as string in local timezone
let timeFormatter = DateFormatter()
timeFormatter.dateFormat = "HH:mm:ss"
self.startTime = event.startTime.map { timeFormatter.string(from: $0) }

// NEW: Combines date + time in local timezone, converts to UTC ISO8601
let calendar = Calendar.current
let eventDay = calendar.startOfDay(for: event.eventDate)
let hour = calendar.component(.hour, from: startTime)
let minute = calendar.component(.minute, from: startTime)
if let localDateTime = calendar.date(bySettingHour: hour, minute: minute, second: second, of: eventDay) {
    self.startTime = iso8601Formatter.string(from: localDateTime)
}
// Converts local 3 PM PST → UTC 11 PM
```

## How It Works

### Example: Creating an Event

**User Action**: User in PST creates event on Jan 20, 2026 at 3:00 PM

**Swift Processing**:
1. User selects time: `3:00 PM` in local time
2. EventInsert combines date + time: `2026-01-20 15:00:00 PST`
3. Converts to UTC: `2026-01-20 23:00:00 UTC`
4. Sends to database as ISO8601: `"2026-01-20T23:00:00.000Z"`

**Database Storage**:
```sql
start_time: 2026-01-20 23:00:00+00  -- Stored in UTC
```

**Swift Display**:
1. Database returns: `"2026-01-20T23:00:00.000Z"`
2. ISO8601Formatter decodes to Swift Date (UTC internally)
3. DateFormatter displays in user's local timezone: `3:00 PM`

### Example: Event Status Calculation

**Database Trigger** (runs in UTC):
```sql
-- Current time in UTC
now_utc := NOW();  -- 2026-01-20 20:00:00+00 (12 PM PST = 8 PM UTC)

-- Event end time (already in UTC)
event_end_datetime := NEW.end_time;  -- 2026-01-20 23:00:00+00 (3 PM PST)

-- Compare UTC to UTC
NEW.is_ended := (now_utc > event_end_datetime);
-- 20:00 > 23:00 = FALSE ✅ (event not ended)
```

## Testing

### Before Migration
1. Note current events and their times
2. Screenshot events display in app

### After Migration
1. Run `MIGRATE_TO_UTC_STORAGE.sql`
2. Verify in Supabase that times are stored as TIMESTAMPTZ
3. Check validation query output in SQL editor
4. Test in app:
   - Existing events still display correct times
   - Create new event at 3 PM local time
   - Verify it's stored as UTC in database
   - Verify it displays as 3 PM in app
   - Verify event status (is_ended, is_future) is correct

### Validation Query (Run After Migration)
```sql
SELECT
    name,
    start_time AT TIME ZONE 'America/Los_Angeles' as start_time_pacific,
    end_time AT TIME ZONE 'America/Los_Angeles' as end_time_pacific,
    is_ended,
    is_future
FROM events
ORDER BY event_date ASC;
```

Expected: All times should match what users see in the app

## Files Changed

### Database
- `MIGRATE_TO_UTC_STORAGE.sql` - Complete migration script

### Swift
- `Memory/Models/Event.swift`:
  - `EventRecord.init(from:)` - Updated decoder for TIMESTAMPTZ
  - `EventInsert.init(event:)` - Updated encoder to convert local→UTC
  - `MemoryWithEvent.init(from:)` - Updated decoder for TIMESTAMPTZ

## Rollback Plan

If issues occur, you can rollback by:

1. Reverting Swift code changes
2. Running this SQL:
```sql
-- Add TIME columns back
ALTER TABLE events
ADD COLUMN start_time_local TIME,
ADD COLUMN end_time_local TIME;

-- Convert TIMESTAMPTZ back to TIME (Pacific timezone)
UPDATE events
SET start_time_local = (start_time AT TIME ZONE 'America/Los_Angeles')::TIME,
    end_time_local = (end_time AT TIME ZONE 'America/Los_Angeles')::TIME;

-- Drop TIMESTAMPTZ columns
ALTER TABLE events
DROP COLUMN start_time,
DROP COLUMN end_time;

-- Rename TIME columns
ALTER TABLE events
RENAME COLUMN start_time_local TO start_time;

ALTER TABLE events
RENAME COLUMN end_time_local TO end_time;
```

## Benefits of UTC Storage

✅ **Multi-timezone support**: Users in any timezone can use the app
✅ **Daylight Saving Time**: Automatically handled by timezone conversion
✅ **Database simplicity**: All comparisons are UTC to UTC
✅ **No hardcoded timezones**: Database doesn't need to know user's timezone
✅ **Future-proof**: Easy to add timezone selection feature later

## Important Notes

- **Swift Date**: Always stores UTC internally, displays in local timezone automatically
- **DateFormatter**: Respects `TimeZone.current` for display
- **ISO8601Formatter**: Always uses UTC (trailing `Z` in timestamp)
- **Database NOW()**: Always returns UTC
- **Display**: All times automatically show in user's local timezone

## Testing Checklist

- [ ] Run database migration successfully
- [ ] Existing events display correct times
- [ ] Create new event, verify UTC storage
- [ ] Event status (is_ended, is_future) calculated correctly
- [ ] Events without times still work
- [ ] Past events shown on Past Events page
- [ ] Future events shown on Events Home page
- [ ] Active event functionality works
- [ ] Multi-day events work correctly
