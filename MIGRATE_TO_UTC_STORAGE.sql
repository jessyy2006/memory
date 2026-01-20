-- ============================================================================
-- MIGRATION: Convert TIME fields to TIMESTAMPTZ (UTC Storage)
-- ============================================================================
-- This migration converts start_time and end_time from TIME to TIMESTAMPTZ
-- for proper timezone handling. All times will be stored in UTC.
--
-- BEFORE: start_time TIME, end_time TIME (no timezone info)
-- AFTER:  start_time TIMESTAMPTZ, end_time TIMESTAMPTZ (stored in UTC)
--
-- Strategy:
-- 1. Add new columns (start_time_utc, end_time_utc) as TIMESTAMPTZ
-- 2. Migrate existing data (interpret as Pacific time, convert to UTC)
-- 3. Drop old TIME columns
-- 4. Rename new columns to original names
-- 5. Update triggers to use UTC comparisons
-- ============================================================================

-- ============================================================================
-- STEP 1: Add new TIMESTAMPTZ columns
-- ============================================================================

ALTER TABLE events
ADD COLUMN start_time_utc TIMESTAMPTZ,
ADD COLUMN end_time_utc TIMESTAMPTZ;

-- ============================================================================
-- STEP 2: Migrate existing data
-- ============================================================================
-- Convert existing TIME values to TIMESTAMPTZ
-- Assume existing times are in Pacific timezone, convert to UTC

DO $$
DECLARE
    event_rec RECORD;
    start_datetime_pacific TIMESTAMP;
    end_datetime_pacific TIMESTAMP;
    start_datetime_utc TIMESTAMPTZ;
    end_datetime_utc TIMESTAMPTZ;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🔄 MIGRATING EXISTING TIME DATA TO UTC...';
    RAISE NOTICE '';

    FOR event_rec IN SELECT id, event_date, start_time, end_time FROM events
    LOOP
        -- Convert start_time
        IF event_rec.start_time IS NOT NULL THEN
            -- Combine event_date + start_time (interpreted as Pacific time)
            start_datetime_pacific := event_rec.event_date::TIMESTAMP + event_rec.start_time;

            -- Convert to UTC
            start_datetime_utc := (start_datetime_pacific AT TIME ZONE 'America/Los_Angeles');

            RAISE NOTICE 'Event % | Start Pacific: % → Start UTC: %',
                event_rec.id,
                start_datetime_pacific,
                start_datetime_utc;
        ELSE
            start_datetime_utc := NULL;
        END IF;

        -- Convert end_time
        IF event_rec.end_time IS NOT NULL THEN
            -- Combine event_date + end_time (interpreted as Pacific time)
            end_datetime_pacific := event_rec.event_date::TIMESTAMP + event_rec.end_time;

            -- Convert to UTC
            end_datetime_utc := (end_datetime_pacific AT TIME ZONE 'America/Los_Angeles');

            RAISE NOTICE 'Event % | End Pacific: % → End UTC: %',
                event_rec.id,
                end_datetime_pacific,
                end_datetime_utc;
        ELSE
            end_datetime_utc := NULL;
        END IF;

        -- Update the new columns
        UPDATE events
        SET start_time_utc = start_datetime_utc,
            end_time_utc = end_datetime_utc
        WHERE id = event_rec.id;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '✅ Data migration complete!';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- STEP 3: Drop old TIME columns
-- ============================================================================

ALTER TABLE events
DROP COLUMN start_time,
DROP COLUMN end_time;

-- ============================================================================
-- STEP 4: Rename new columns to original names
-- ============================================================================

ALTER TABLE events
RENAME COLUMN start_time_utc TO start_time;

ALTER TABLE events
RENAME COLUMN end_time_utc TO end_time;

-- ============================================================================
-- STEP 5: Update calculate_event_status() to use UTC
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_event_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    now_utc TIMESTAMPTZ;  -- Current time in UTC
    event_end_datetime TIMESTAMPTZ;  -- Event end in UTC
BEGIN
    -- Get current time (always UTC in PostgreSQL)
    now_utc := NOW();

    -- Determine event end datetime
    IF NEW.end_time IS NOT NULL THEN
        -- end_time is already a TIMESTAMPTZ (stored in UTC)
        event_end_datetime := NEW.end_time;
    ELSE
        -- No end time - use end of event day (in UTC)
        -- Convert event_date to UTC end of day
        event_end_datetime := ((NEW.event_date + INTERVAL '1 day' - INTERVAL '1 second') AT TIME ZONE 'America/Los_Angeles');
    END IF;

    -- =========================================================================
    -- CRITICAL LOGIC: Compare UTC to UTC
    -- =========================================================================
    NEW.is_ended := (now_utc > event_end_datetime);

    -- is_future = true if:
    --   1. NOT ended (is_ended = false)
    --   2. NOT active (is_active = false)
    --   3. End time is still in the future
    NEW.is_future := (NOT NEW.is_ended) AND (NOT NEW.is_active) AND (now_utc < event_end_datetime);

    -- =========================================================================
    -- Guard Clause: Force is_upcoming=false if event has ended or is not future
    -- =========================================================================
    IF NEW.is_ended = true OR NEW.is_future = false THEN
        NEW.is_upcoming := false;
    END IF;

    -- Auto-deactivate if outside time range
    IF NEW.is_active = true THEN
        IF NEW.start_time IS NOT NULL THEN
            IF now_utc < NEW.start_time OR now_utc > event_end_datetime THEN
                NEW.is_active := false;
            END IF;
        ELSE
            -- No start time, check only end
            IF now_utc > event_end_datetime THEN
                NEW.is_active := false;
            END IF;
        END IF;
    END IF;

    -- =========================================================================
    -- Logging: Print status for every event processed (UTC)
    -- =========================================================================
    RAISE NOTICE 'Event % | Start UTC: % | End UTC: % | Now UTC: % | isFuture: % | isEnded: % | isUpcoming: %',
        COALESCE(NEW.id::TEXT, 'NEW'),
        NEW.start_time,
        event_end_datetime,
        now_utc,
        NEW.is_future,
        NEW.is_ended,
        COALESCE(NEW.is_upcoming::TEXT, 'NULL');

    RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 6: Recreate triggers (ensure they use the updated function)
-- ============================================================================

-- Drop existing triggers
DROP TRIGGER IF EXISTS trigger_calculate_event_status_insert ON events;
DROP TRIGGER IF EXISTS trigger_calculate_event_status_update ON events;

-- Create BEFORE INSERT trigger
CREATE TRIGGER trigger_calculate_event_status_insert
    BEFORE INSERT ON events
    FOR EACH ROW
    EXECUTE FUNCTION calculate_event_status();

-- Create BEFORE UPDATE trigger
CREATE TRIGGER trigger_calculate_event_status_update
    BEFORE UPDATE ON events
    FOR EACH ROW
    WHEN (
        OLD.event_date IS DISTINCT FROM NEW.event_date OR
        OLD.start_time IS DISTINCT FROM NEW.start_time OR
        OLD.end_time IS DISTINCT FROM NEW.end_time OR
        OLD.is_active IS DISTINCT FROM NEW.is_active OR
        OLD.is_ended IS DISTINCT FROM NEW.is_ended
    )
    EXECUTE FUNCTION calculate_event_status();

-- ============================================================================
-- STEP 7: Force recalculation for ALL existing events
-- ============================================================================

DO $$
DECLARE
    event_rec RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🔄 RECALCULATING ALL EVENTS WITH UTC LOGIC...';
    RAISE NOTICE '';

    -- Touch event_date to trigger the BEFORE UPDATE trigger
    FOR event_rec IN SELECT id, name FROM events ORDER BY event_date ASC
    LOOP
        RAISE NOTICE 'Recalculating: %', event_rec.name;

        UPDATE events
        SET event_date = event_date  -- This triggers calculate_event_status()
        WHERE id = event_rec.id;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '✅ Recalculation complete!';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- STEP 8: Validation - Show all events with UTC times
-- ============================================================================

SELECT
    name,
    event_date,
    start_time as start_time_utc,
    end_time as end_time_utc,
    start_time AT TIME ZONE 'America/Los_Angeles' as start_time_pacific,
    end_time AT TIME ZONE 'America/Los_Angeles' as end_time_pacific,
    NOW() as current_time_utc,
    NOW() AT TIME ZONE 'America/Los_Angeles' as current_time_pacific,
    is_ended,
    is_future,
    is_active,
    is_upcoming,
    CASE
        WHEN is_future AND NOT is_ended THEN '✅ ON EVENTS HOME (correct)'
        WHEN is_ended AND NOT is_future THEN '✅ ON PAST EVENTS (correct)'
        WHEN is_future AND is_ended THEN '❌ LOGIC ERROR'
        WHEN NOT is_future AND NOT is_ended THEN '⚠️  CHECK MANUALLY'
        ELSE '⏸️  OTHER'
    END as validation_status
FROM events
ORDER BY event_date ASC, COALESCE(start_time, '1970-01-01 00:00:00+00'::TIMESTAMPTZ) ASC;

-- ============================================================================
-- STEP 9: Debug output
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🌐 TIMEZONE DEBUG INFO (after UTC migration):';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'Database timezone: %', CURRENT_SETTING('timezone');
    RAISE NOTICE 'NOW() (always UTC): %', NOW();
    RAISE NOTICE 'NOW() as Pacific: %', NOW() AT TIME ZONE 'America/Los_Angeles';
    RAISE NOTICE '';
    RAISE NOTICE 'Schema change: start_time and end_time are now TIMESTAMPTZ (stored in UTC)';
    RAISE NOTICE 'Client must: Convert user local time to UTC before sending to DB';
    RAISE NOTICE 'Client must: Convert UTC from DB to user local time for display';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- MIGRATION COMPLETE!
-- ============================================================================
--
-- What This Migration Does:
-- 1. Converts start_time and end_time from TIME to TIMESTAMPTZ
-- 2. Migrates existing data (interprets as Pacific, stores as UTC)
-- 3. Updates triggers to compare UTC times
-- 4. All database operations now use UTC internally
--
-- Next Steps for Swift Code:
-- 1. Update EventInsert to convert local times to UTC before sending
-- 2. Update EventRecord decoder to convert UTC times to local for display
-- 3. Remove Pacific timezone hardcoding from SQL
--
-- Benefits:
-- ✅ Works for all timezones (not just Pacific)
-- ✅ No timezone confusion in database
-- ✅ DST changes handled automatically
-- ✅ Database logic is timezone-agnostic
-- ============================================================================
