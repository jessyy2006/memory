-- ============================================================================
-- REVERT TO PACIFIC TIMEZONE SOLUTION
-- ============================================================================
-- This script reverts all UTC migration changes and restores the working
-- Pacific timezone solution from FIX_ISENDED_ROOT_CAUSE.sql
--
-- What this does:
-- 1. No schema changes needed (start_time and end_time are still TIME)
-- 2. Restores calculate_event_status() with Pacific timezone logic
-- 3. Ensures all triggers are set up correctly
-- 4. Recalculates all events with Pacific timezone
--
-- NOTE: If you already ran MIGRATE_TO_UTC_STORAGE_FIXED.sql and columns
-- were changed to TIMESTAMPTZ, scroll down to the "CONVERSION FROM TIMESTAMPTZ"
-- section at the bottom of this file.
-- ============================================================================

-- ============================================================================
-- STEP 1: Drop any UTC-related triggers
-- ============================================================================

DROP TRIGGER IF EXISTS trigger_calculate_event_status_insert ON events;
DROP TRIGGER IF EXISTS trigger_calculate_event_status_update ON events;
DROP TRIGGER IF EXISTS trigger_update_most_upcoming_after_insert ON events;
DROP TRIGGER IF EXISTS trigger_update_most_upcoming_after_update ON events;
DROP TRIGGER IF EXISTS trigger_update_most_upcoming_after_delete ON events;

-- ============================================================================
-- STEP 2: Restore calculate_event_status() with Pacific timezone logic
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_event_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    now_pacific TIMESTAMP;  -- Current time in Pacific timezone
    event_start_datetime TIMESTAMP;  -- Local timestamp
    event_end_datetime TIMESTAMP;  -- Local timestamp
BEGIN
    -- Get current time in Pacific timezone (PST/PDT)
    -- This matches how the user is entering times in the app
    now_pacific := (NOW() AT TIME ZONE 'America/Los_Angeles')::TIMESTAMP;

    -- Calculate event start datetime (interpreted as Pacific time)
    IF NEW.start_time IS NOT NULL THEN
        event_start_datetime := NEW.event_date::TIMESTAMP + NEW.start_time;
    ELSE
        -- No start time - use beginning of event day
        event_start_datetime := NEW.event_date::TIMESTAMP;
    END IF;

    -- Calculate event end datetime (interpreted as Pacific time)
    IF NEW.end_time IS NOT NULL THEN
        event_end_datetime := NEW.event_date::TIMESTAMP + NEW.end_time;
    ELSE
        -- No end time - use end of event day (23:59:59)
        event_end_datetime := NEW.event_date::TIMESTAMP + INTERVAL '1 day' - INTERVAL '1 second';
    END IF;

    -- =========================================================================
    -- CRITICAL LOGIC: Compare Pacific time to Pacific time
    -- =========================================================================
    NEW.is_ended := (now_pacific > event_end_datetime);

    -- is_future = true if:
    --   1. NOT ended (is_ended = false)
    --   2. NOT active (is_active = false)
    --   3. End time is still in the future
    NEW.is_future := (NOT NEW.is_ended) AND (NOT NEW.is_active) AND (now_pacific < event_end_datetime);

    -- =========================================================================
    -- Guard Clause: Force is_upcoming=false if event has ended or is not future
    -- =========================================================================
    IF NEW.is_ended = true OR NEW.is_future = false THEN
        NEW.is_upcoming := false;
    END IF;

    -- Auto-deactivate if outside time range
    IF NEW.is_active = true THEN
        IF now_pacific < event_start_datetime OR now_pacific > event_end_datetime THEN
            NEW.is_active := false;
        END IF;
    END IF;

    -- =========================================================================
    -- Logging: Print status for every event processed (PACIFIC TIME)
    -- =========================================================================
    RAISE NOTICE 'Event % | Start: % | End: % | Now (Pacific): % | isFuture: % | isEnded: % | isUpcoming: %',
        COALESCE(NEW.id::TEXT, 'NEW'),
        event_start_datetime,
        event_end_datetime,
        now_pacific,
        NEW.is_future,
        NEW.is_ended,
        COALESCE(NEW.is_upcoming::TEXT, 'NULL');

    RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 3: Recreate triggers
-- ============================================================================

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

-- Recreate AFTER triggers for update_most_upcoming_event (if function exists)
CREATE TRIGGER trigger_update_most_upcoming_after_insert
    AFTER INSERT ON events
    FOR EACH ROW
    EXECUTE FUNCTION update_most_upcoming_event();

CREATE TRIGGER trigger_update_most_upcoming_after_update
    AFTER UPDATE ON events
    FOR EACH ROW
    WHEN (
        OLD.event_date IS DISTINCT FROM NEW.event_date OR
        OLD.start_time IS DISTINCT FROM NEW.start_time OR
        OLD.end_time IS DISTINCT FROM NEW.end_time OR
        OLD.is_active IS DISTINCT FROM NEW.is_active OR
        OLD.is_ended IS DISTINCT FROM NEW.is_ended OR
        OLD.is_future IS DISTINCT FROM NEW.is_future
    )
    EXECUTE FUNCTION update_most_upcoming_event();

CREATE TRIGGER trigger_update_most_upcoming_after_delete
    AFTER DELETE ON events
    FOR EACH ROW
    EXECUTE FUNCTION update_most_upcoming_event();

-- ============================================================================
-- STEP 4: Force recalculation for ALL existing events
-- ============================================================================

DO $$
DECLARE
    event_rec RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🔄 RECALCULATING ALL EVENTS WITH PACIFIC TIMEZONE...';
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
-- STEP 5: Validation
-- ============================================================================

SELECT
    name,
    event_date,
    start_time,
    end_time,
    CASE
        WHEN end_time IS NOT NULL THEN
            event_date::TIMESTAMP + end_time
        ELSE
            event_date::TIMESTAMP + INTERVAL '1 day' - INTERVAL '1 second'
    END as computed_end_datetime_pacific,
    (NOW() AT TIME ZONE 'America/Los_Angeles')::TIMESTAMP as current_time_pacific,
    is_ended,
    is_future,
    is_active,
    is_upcoming,
    CASE
        WHEN is_future AND NOT is_ended THEN '✅ ON EVENTS HOME'
        WHEN is_ended AND NOT is_future THEN '✅ ON PAST EVENTS'
        WHEN is_future AND is_ended THEN '❌ LOGIC ERROR'
        ELSE '⏸️  OTHER'
    END as validation_status
FROM events
ORDER BY event_date ASC, COALESCE(start_time, '00:00:00'::TIME) ASC;

-- ============================================================================
-- REVERT COMPLETE!
-- ============================================================================
--
-- What this script did:
-- 1. Restored calculate_event_status() with Pacific timezone logic
-- 2. Recreated all triggers to use Pacific timezone
-- 3. Recalculated all events with Pacific timezone
-- 4. Everything now works as it did before UTC migration attempt
--
-- Expected Results (using PACIFIC time):
-- ✅ Event today 5 PM - 7 PM (current 12 PM PST): is_ended=false, is_future=true
-- ✅ Event today 11 AM - 3 PM (current 12 PM PST): is_ended=false, is_future=true
-- ✅ Event today 9 AM - 11 AM (current 12 PM PST): is_ended=true, is_future=false
-- ============================================================================










-- ============================================================================
-- ============================================================================
-- ALTERNATIVE: IF YOU ALREADY RAN UTC MIGRATION (COLUMNS ARE TIMESTAMPTZ)
-- ============================================================================
-- ============================================================================
--
-- If you already converted columns to TIMESTAMPTZ, run this section instead
-- to convert them back to TIME and restore Pacific timezone logic.
--
-- UNCOMMENT THE SECTION BELOW IF NEEDED:
-- ============================================================================

/*

-- ============================================================================
-- CONVERSION FROM TIMESTAMPTZ BACK TO TIME
-- ============================================================================

-- Drop all triggers first
DROP TRIGGER IF EXISTS trigger_calculate_event_status_insert ON events;
DROP TRIGGER IF EXISTS trigger_calculate_event_status_update ON events;
DROP TRIGGER IF EXISTS trigger_update_most_upcoming_after_insert ON events;
DROP TRIGGER IF EXISTS trigger_update_most_upcoming_after_update ON events;
DROP TRIGGER IF EXISTS trigger_update_most_upcoming_after_delete ON events;

-- Drop view
DROP VIEW IF EXISTS memories_with_events;

-- Add new TIME columns
ALTER TABLE events
ADD COLUMN start_time_local TIME,
ADD COLUMN end_time_local TIME;

-- Convert TIMESTAMPTZ back to TIME (Pacific timezone)
DO $$
DECLARE
    event_rec RECORD;
    pacific_time TIME;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🔄 CONVERTING TIMESTAMPTZ BACK TO TIME (Pacific)...';
    RAISE NOTICE '';

    FOR event_rec IN SELECT id, start_time, end_time FROM events
    LOOP
        -- Convert start_time from UTC to Pacific, extract time component
        IF event_rec.start_time IS NOT NULL THEN
            pacific_time := (event_rec.start_time AT TIME ZONE 'America/Los_Angeles')::TIME;

            RAISE NOTICE 'Event % | Start UTC: % → Pacific TIME: %',
                event_rec.id,
                event_rec.start_time,
                pacific_time;

            UPDATE events
            SET start_time_local = pacific_time
            WHERE id = event_rec.id;
        END IF;

        -- Convert end_time from UTC to Pacific, extract time component
        IF event_rec.end_time IS NOT NULL THEN
            pacific_time := (event_rec.end_time AT TIME ZONE 'America/Los_Angeles')::TIME;

            RAISE NOTICE 'Event % | End UTC: % → Pacific TIME: %',
                event_rec.id,
                event_rec.end_time,
                pacific_time;

            UPDATE events
            SET end_time_local = pacific_time
            WHERE id = event_rec.id;
        END IF;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '✅ Conversion complete!';
    RAISE NOTICE '';
END $$;

-- Drop old TIMESTAMPTZ columns
ALTER TABLE events
DROP COLUMN start_time CASCADE,
DROP COLUMN end_time CASCADE;

-- Rename TIME columns to original names
ALTER TABLE events
RENAME COLUMN start_time_local TO start_time;

ALTER TABLE events
RENAME COLUMN end_time_local TO end_time;

-- Recreate memories_with_events view
CREATE OR REPLACE VIEW memories_with_events AS
SELECT
  m.id,
  m.user_id,
  m.type,
  m.content,
  m.thumbnail_url,
  m.duration,
  m.timestamp,
  m.created_at,
  m.updated_at,
  m.event_id,
  e.name as event_name,
  e.event_date,
  e.start_time as event_start_time,
  e.end_time as event_end_time,
  e.is_active as event_is_active
FROM memories m
LEFT JOIN events e ON m.event_id = e.id;

-- Now run the Pacific timezone restoration from the top of this file
-- (Steps 2-5: Restore function, triggers, recalculate, validate)

*/

-- ============================================================================
-- END OF TIMESTAMPTZ CONVERSION SECTION
-- ============================================================================
