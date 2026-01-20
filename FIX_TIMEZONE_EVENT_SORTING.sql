-- ============================================================================
-- FIX: Timezone-Aware Event Sorting
-- ============================================================================
-- Bug: Today's events incorrectly marked as ended due to timezone mismatch
--
-- Failing Cases:
-- 1. Event today 5 PM - 7 PM (current 12 PM) → Incorrectly marked as ended
-- 2. Event today 11 AM - 3 PM (current 12 PM) → Incorrectly marked as ended
--
-- Root Cause:
-- - NOW() returns timestamp WITH timezone (UTC)
-- - event_date + end_time creates timestamp WITHOUT timezone
-- - Comparing UTC vs local causes incorrect is_ended calculation
--
-- Solution:
-- - Use consistent timezone-aware comparisons
-- - Ensure currentTime < event.endTime logic is preserved
-- ============================================================================

-- ============================================================================
-- STEP 1: Rewrite calculate_event_status() with timezone-aware comparisons
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_event_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    now_ts TIMESTAMPTZ;  -- Timezone-aware (renamed to avoid reserved keyword)
    event_start_datetime TIMESTAMPTZ;  -- Timezone-aware
    event_end_datetime TIMESTAMPTZ;  -- Timezone-aware
BEGIN
    -- Use CURRENT_TIMESTAMP (timezone-aware) instead of NOW()
    now_ts := CURRENT_TIMESTAMP;

    -- Calculate event start datetime (convert to timezone-aware)
    IF NEW.start_time IS NOT NULL THEN
        event_start_datetime := (NEW.event_date + NEW.start_time) AT TIME ZONE 'UTC';
    ELSE
        -- No start time - use beginning of event day
        event_start_datetime := NEW.event_date::TIMESTAMPTZ;
    END IF;

    -- Calculate event end datetime (convert to timezone-aware)
    IF NEW.end_time IS NOT NULL THEN
        event_end_datetime := (NEW.event_date + NEW.end_time) AT TIME ZONE 'UTC';
    ELSE
        -- No end time - use end of event day (23:59:59)
        event_end_datetime := ((NEW.event_date + INTERVAL '1 day' - INTERVAL '1 second') AT TIME ZONE 'UTC');
    END IF;

    -- =========================================================================
    -- CRITICAL LOGIC: currentTime < event.endTime
    -- =========================================================================
    -- An event is categorized as isFuture = true and shown on EventsHomeView
    -- AS LONG AS the end time has NOT passed
    --
    -- is_ended = true ONLY when: now_ts > event_end_datetime
    -- (NOT >=, so events AT their end time are still considered active)

    NEW.is_ended := (now_ts > event_end_datetime);

    -- is_future = true if:
    --   1. NOT ended (is_ended = false)
    --   2. NOT active (is_active = false)
    --   3. End time is still in the future (now_ts < event_end_datetime)
    NEW.is_future := (NOT NEW.is_ended) AND (NOT NEW.is_active) AND (now_ts < event_end_datetime);

    -- =========================================================================
    -- Guard Clause: Force is_upcoming=false if event has ended or is not future
    -- =========================================================================
    IF NEW.is_ended = true OR NEW.is_future = false THEN
        NEW.is_upcoming := false;
    END IF;

    -- Auto-deactivate if outside time range
    IF NEW.is_active = true THEN
        IF now_ts < event_start_datetime OR now_ts > event_end_datetime THEN
            NEW.is_active := false;
        END IF;
    END IF;

    -- =========================================================================
    -- Logging: Print status for every event processed
    -- =========================================================================
    RAISE NOTICE 'Event % | Start: % | End: % | Now: % | isFuture: % | isEnded: % | isUpcoming: %',
        COALESCE(NEW.id::TEXT, 'NEW'),
        event_start_datetime,
        event_end_datetime,
        now_ts,
        NEW.is_future,
        NEW.is_ended,
        COALESCE(NEW.is_upcoming::TEXT, 'NULL');

    RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 2: Recreate triggers (ensure they use the updated function)
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
-- STEP 3: Force recalculation for ALL existing events
-- ============================================================================

DO $$
DECLARE
    event_rec RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🔄 RECALCULATING ALL EVENTS WITH TIMEZONE-AWARE LOGIC...';
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
-- STEP 4: Validation - Show all events with computed datetimes
-- ============================================================================

SELECT
    name,
    event_date,
    start_time,
    end_time,
    CASE
        WHEN end_time IS NOT NULL THEN
            (event_date + end_time) AT TIME ZONE 'UTC'
        ELSE
            (event_date + INTERVAL '1 day' - INTERVAL '1 second') AT TIME ZONE 'UTC'
    END as computed_end_datetime_utc,
    CURRENT_TIMESTAMP as current_time_utc,
    CASE
        WHEN end_time IS NOT NULL THEN
            CURRENT_TIMESTAMP < ((event_date + end_time) AT TIME ZONE 'UTC')
        ELSE
            CURRENT_TIMESTAMP < ((event_date + INTERVAL '1 day' - INTERVAL '1 second') AT TIME ZONE 'UTC')
    END as should_be_future,
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
ORDER BY event_date ASC, COALESCE(start_time, '00:00:00'::TIME) ASC;

-- ============================================================================
-- STEP 5: Test Cases Verification
-- ============================================================================

DO $$
DECLARE
    event_rec RECORD;
    current_utc TIMESTAMPTZ;
BEGIN
    current_utc := CURRENT_TIMESTAMP;

    RAISE NOTICE '';
    RAISE NOTICE '🔍 TEST CASES VERIFICATION (current UTC: %)', current_utc;
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';

    FOR event_rec IN
        SELECT
            name,
            event_date,
            start_time,
            end_time,
            is_ended,
            is_future,
            CASE
                WHEN end_time IS NOT NULL THEN
                    (event_date + end_time) AT TIME ZONE 'UTC'
                ELSE
                    (event_date + INTERVAL '1 day' - INTERVAL '1 second') AT TIME ZONE 'UTC'
            END as end_datetime_utc
        FROM events
        WHERE event_date = CURRENT_DATE  -- Only today's events
        ORDER BY COALESCE(start_time, '00:00:00'::TIME) ASC
    LOOP
        RAISE NOTICE '';
        RAISE NOTICE '📅 Event: %', event_rec.name;
        RAISE NOTICE '   Time Range: % - %',
            COALESCE(event_rec.start_time::TEXT, 'no start'),
            COALESCE(event_rec.end_time::TEXT, 'no end');
        RAISE NOTICE '   End Datetime (UTC): %', event_rec.end_datetime_utc;
        RAISE NOTICE '   Current Time (UTC): %', current_utc;
        RAISE NOTICE '   Time Comparison: current < end? %', (current_utc < event_rec.end_datetime_utc);
        RAISE NOTICE '   Database Values: is_ended=%, is_future=%',
            event_rec.is_ended, event_rec.is_future;

        -- Validate logic
        IF current_utc < event_rec.end_datetime_utc THEN
            -- Event end time is in the future - should NOT be ended
            IF event_rec.is_ended THEN
                RAISE NOTICE '   ❌ BUG: Event end is in future but is_ended=true';
            ELSE
                RAISE NOTICE '   ✅ CORRECT: Event has not ended yet';
            END IF;

            IF NOT event_rec.is_future THEN
                RAISE NOTICE '   ❌ BUG: Event should be is_future=true';
            ELSE
                RAISE NOTICE '   ✅ CORRECT: Event is marked as future';
            END IF;
        ELSE
            -- Event end time has passed - should be ended
            IF NOT event_rec.is_ended THEN
                RAISE NOTICE '   ❌ BUG: Event end time passed but is_ended=false';
            ELSE
                RAISE NOTICE '   ✅ CORRECT: Event is marked as ended';
            END IF;
        END IF;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

-- ============================================================================
-- MIGRATION COMPLETE!
-- ============================================================================
--
-- What This Migration Does:
-- 1. Fixes timezone-aware comparisons in calculate_event_status()
-- 2. Ensures currentTime < event.endTime logic is preserved
-- 3. Forces recalculation of all existing events
-- 4. Provides detailed validation and test case verification
--
-- Expected Results:
-- ✅ Event today 5 PM - 7 PM (current 12 PM): is_ended=false, is_future=true
-- ✅ Event today 11 AM - 3 PM (current 12 PM): is_ended=false, is_future=true
-- ✅ Event today 9 AM - 11 AM (current 12 PM): is_ended=true, is_future=false
-- ✅ Events without specific times work correctly (unchanged)
-- ✅ Events on future dates work correctly (unchanged)
--
-- Key Change:
-- - All datetime variables now use TIMESTAMPTZ (timezone-aware)
-- - All comparisons use consistent UTC timezone
-- - Logic preserved: currentTime < event.endTime determines if event shows on homepage
-- ============================================================================
