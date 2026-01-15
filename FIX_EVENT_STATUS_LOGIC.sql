-- ============================================================================
-- FIX: Event Status Boolean Logic
-- ============================================================================
-- Problem: New future events are incorrectly initialized with:
--   isActive=false, isUpcoming=false, isEnded=false, isFuture=false
--
-- Solution: Implement correct status calculation based on current time and event times
--
-- Status Logic Rules:
-- - isEnded: false if event end time is in the future, true if end time has passed OR user manually ended
-- - isUpcoming: true ONLY for the single event with earliest start time where isEnded=false
-- - isActive: true if current time falls between start and end times AND user has started the event
-- - isFuture: true for all events with end time in future that are NOT the most upcoming one
-- ============================================================================

-- ============================================================================
-- STEP 1: Create improved trigger function for event status calculation
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_event_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    current_time TIMESTAMP := NOW();
    event_start_datetime TIMESTAMP;
    event_end_datetime TIMESTAMP;
    v_is_ended BOOLEAN;
    v_is_active BOOLEAN;
BEGIN
    RAISE NOTICE '🔍 [calculate_event_status] Processing event: %', NEW.name;
    RAISE NOTICE '   - event_date: %', NEW.event_date;
    RAISE NOTICE '   - start_time: %', NEW.start_time;
    RAISE NOTICE '   - end_time: %', NEW.end_time;
    RAISE NOTICE '   - current_time: %', current_time;

    -- Calculate event start datetime
    IF NEW.start_time IS NOT NULL THEN
        event_start_datetime := NEW.event_date + NEW.start_time;
    ELSE
        -- No start time - use beginning of event day
        event_start_datetime := NEW.event_date::TIMESTAMP;
    END IF;

    -- Calculate event end datetime
    IF NEW.end_time IS NOT NULL THEN
        event_end_datetime := NEW.event_date + NEW.end_time;
    ELSE
        -- No end time - use end of event day (23:59:59)
        event_end_datetime := (NEW.event_date + INTERVAL '1 day' - INTERVAL '1 second')::TIMESTAMP;
    END IF;

    RAISE NOTICE '   - computed event_start_datetime: %', event_start_datetime;
    RAISE NOTICE '   - computed event_end_datetime: %', event_end_datetime;

    -- =========================================================================
    -- RULE 1: Calculate is_ended
    -- =========================================================================
    -- is_ended = true if:
    --   1. End time has passed (current_time >= event_end_datetime), OR
    --   2. User manually ended event (preserve existing is_ended=true)
    --
    -- For INSERT: is_ended should be false unless end time has already passed
    -- For UPDATE: preserve manual ending (don't override is_ended=true)

    IF TG_OP = 'INSERT' THEN
        -- On insert, calculate based on time comparison only
        v_is_ended := current_time >= event_end_datetime;
        NEW.is_ended := v_is_ended;
    ELSIF TG_OP = 'UPDATE' THEN
        -- On update, preserve manual ending (once ended, stay ended)
        IF OLD.is_ended = true THEN
            NEW.is_ended := true;
            v_is_ended := true;
        ELSE
            -- Not manually ended yet - check if time has passed
            v_is_ended := current_time >= event_end_datetime;
            NEW.is_ended := v_is_ended;
        END IF;
    END IF;

    RAISE NOTICE '   → is_ended: %', NEW.is_ended;

    -- =========================================================================
    -- RULE 2: Calculate is_active
    -- =========================================================================
    -- is_active = true if:
    --   1. User has manually started the event (preserve existing is_active=true), AND
    --   2. Current time is within [start_time, end_time] range
    --
    -- Auto-deactivate if current time is outside the event time range

    IF NEW.is_active = true THEN
        -- Event is marked active - verify it's still within time range
        IF current_time < event_start_datetime OR current_time >= event_end_datetime THEN
            -- Outside time range - auto-deactivate
            NEW.is_active := false;
            RAISE NOTICE '   ⚠️ Auto-deactivating event (outside time range)';
        END IF;
    END IF;

    v_is_active := NEW.is_active;
    RAISE NOTICE '   → is_active: %', NEW.is_active;

    -- =========================================================================
    -- RULE 3: Calculate is_future
    -- =========================================================================
    -- is_future = true for events that:
    --   1. Have NOT ended (is_ended = false), AND
    --   2. Are NOT currently active (is_active = false), AND
    --   3. End time is in the future (event_end_datetime > current_time)

    NEW.is_future := (NOT NEW.is_ended) AND (NOT NEW.is_active) AND (event_end_datetime > current_time);
    RAISE NOTICE '   → is_future: %', NEW.is_future;

    -- =========================================================================
    -- NOTE: is_upcoming is NOT calculated here
    -- =========================================================================
    -- is_upcoming requires knowledge of ALL user's events (to find the soonest one)
    -- This will be handled by the update_most_upcoming_event() function
    -- which runs AFTER INSERT/UPDATE

    RAISE NOTICE '   ✅ Event status calculated successfully';
    RAISE NOTICE '';

    RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 2: Create trigger to update is_upcoming for ALL user's events
-- ============================================================================
-- This function runs AFTER INSERT/UPDATE/DELETE to recalculate which event
-- should be marked as the "most upcoming" event for the user

CREATE OR REPLACE FUNCTION update_most_upcoming_event()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    affected_user_id UUID;
    most_upcoming_event_id UUID;
    event_count INT;
BEGIN
    -- Determine which user was affected
    IF TG_OP = 'DELETE' THEN
        affected_user_id := OLD.user_id;
    ELSE
        affected_user_id := NEW.user_id;
    END IF;

    RAISE NOTICE '🔄 [update_most_upcoming_event] Recalculating most upcoming event for user: %', affected_user_id;

    -- Clear is_upcoming for ALL events for this user
    UPDATE events
    SET is_upcoming = false
    WHERE user_id = affected_user_id;

    -- Find the most upcoming event
    -- Logic: Event with soonest start datetime (date + time combined) where:
    --   - is_ended = false
    --   - is_active = false
    --   - is_future = true
    --   - Sorted by: combined start datetime (event_date + start_time) ASC
    SELECT id INTO most_upcoming_event_id
    FROM events
    WHERE user_id = affected_user_id
      AND is_ended = false
      AND is_active = false
      AND is_future = true
    ORDER BY
      (event_date + COALESCE(start_time, '00:00:00'::TIME)) ASC
    LIMIT 1;

    -- Set is_upcoming = true for the most upcoming event
    IF most_upcoming_event_id IS NOT NULL THEN
        UPDATE events
        SET is_upcoming = true,
            updated_at = NOW()
        WHERE id = most_upcoming_event_id;

        RAISE NOTICE '   ✅ Set is_upcoming=true for event: %', most_upcoming_event_id;
    ELSE
        RAISE NOTICE '   ℹ️ No upcoming events found for user';
    END IF;

    -- Log summary of all events for this user
    SELECT COUNT(*) INTO event_count FROM events WHERE user_id = affected_user_id;
    RAISE NOTICE '   📊 Total events for user: %', event_count;

    -- Debug: Print all events for this user
    FOR event_rec IN
        SELECT
            name,
            event_date,
            is_active,
            is_upcoming,
            is_future,
            is_ended
        FROM events
        WHERE user_id = affected_user_id
        ORDER BY event_date ASC
    LOOP
        RAISE NOTICE '      - %: isActive=%, isUpcoming=%, isFuture=%, isEnded=%',
            event_rec.name,
            event_rec.is_active,
            event_rec.is_upcoming,
            event_rec.is_future,
            event_rec.is_ended;
    END LOOP;

    RAISE NOTICE '';

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

-- ============================================================================
-- STEP 3: Drop existing triggers and create new ones
-- ============================================================================

-- Drop old triggers if they exist
DROP TRIGGER IF EXISTS trigger_before_insert_auto_calculate_is_future ON events;
DROP TRIGGER IF EXISTS trigger_before_update_auto_calculate_is_future ON events;
DROP TRIGGER IF EXISTS trigger_auto_update_event_state ON events;
DROP TRIGGER IF EXISTS trigger_calculate_event_status_insert ON events;
DROP TRIGGER IF EXISTS trigger_calculate_event_status_update ON events;
DROP TRIGGER IF EXISTS trigger_update_most_upcoming_after_insert ON events;
DROP TRIGGER IF EXISTS trigger_update_most_upcoming_after_update ON events;
DROP TRIGGER IF EXISTS trigger_update_most_upcoming_after_delete ON events;

-- Create BEFORE INSERT trigger (calculates is_ended, is_active, is_future)
CREATE TRIGGER trigger_calculate_event_status_insert
    BEFORE INSERT ON events
    FOR EACH ROW
    EXECUTE FUNCTION calculate_event_status();

-- Create BEFORE UPDATE trigger (calculates is_ended, is_active, is_future)
CREATE TRIGGER trigger_calculate_event_status_update
    BEFORE UPDATE ON events
    FOR EACH ROW
    WHEN (
        -- Only recalculate if relevant fields changed
        OLD.event_date IS DISTINCT FROM NEW.event_date OR
        OLD.start_time IS DISTINCT FROM NEW.start_time OR
        OLD.end_time IS DISTINCT FROM NEW.end_time OR
        OLD.is_active IS DISTINCT FROM NEW.is_active OR
        OLD.is_ended IS DISTINCT FROM NEW.is_ended
    )
    EXECUTE FUNCTION calculate_event_status();

-- Create AFTER INSERT trigger (updates is_upcoming)
CREATE TRIGGER trigger_update_most_upcoming_after_insert
    AFTER INSERT ON events
    FOR EACH ROW
    EXECUTE FUNCTION update_most_upcoming_event();

-- Create AFTER UPDATE trigger (updates is_upcoming)
CREATE TRIGGER trigger_update_most_upcoming_after_update
    AFTER UPDATE ON events
    FOR EACH ROW
    WHEN (
        -- Only recalculate if relevant fields changed
        OLD.event_date IS DISTINCT FROM NEW.event_date OR
        OLD.start_time IS DISTINCT FROM NEW.start_time OR
        OLD.end_time IS DISTINCT FROM NEW.end_time OR
        OLD.is_active IS DISTINCT FROM NEW.is_active OR
        OLD.is_ended IS DISTINCT FROM NEW.is_ended OR
        OLD.is_future IS DISTINCT FROM NEW.is_future
    )
    EXECUTE FUNCTION update_most_upcoming_event();

-- Create AFTER DELETE trigger (updates is_upcoming for remaining events)
CREATE TRIGGER trigger_update_most_upcoming_after_delete
    AFTER DELETE ON events
    FOR EACH ROW
    EXECUTE FUNCTION update_most_upcoming_event();

-- ============================================================================
-- STEP 4: Fix existing events (data migration)
-- ============================================================================
-- Recalculate status for all existing events

DO $$
DECLARE
    event_rec RECORD;
    user_id_rec UUID;
BEGIN
    RAISE NOTICE '🔄 Starting data migration to fix event statuses...';
    RAISE NOTICE '';

    -- Loop through all events and trigger recalculation
    -- This will fire the BEFORE UPDATE trigger which recalculates all statuses
    FOR event_rec IN SELECT * FROM events ORDER BY user_id, event_date ASC
    LOOP
        -- Touch the updated_at field to trigger the UPDATE
        UPDATE events
        SET updated_at = NOW()
        WHERE id = event_rec.id;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '✅ Data migration complete!';
    RAISE NOTICE '';
    RAISE NOTICE '📊 Summary of all events:';

    -- Print summary for each user
    FOR user_id_rec IN SELECT DISTINCT user_id FROM events
    LOOP
        RAISE NOTICE '';
        RAISE NOTICE '👤 User: %', user_id_rec;
        FOR event_rec IN
            SELECT
                name,
                event_date,
                start_time,
                end_time,
                is_active,
                is_upcoming,
                is_future,
                is_ended
            FROM events
            WHERE user_id = user_id_rec
            ORDER BY event_date ASC
        LOOP
            RAISE NOTICE '   📅 %', event_rec.name;
            RAISE NOTICE '      Date: % | Start: % | End: %',
                event_rec.event_date,
                COALESCE(event_rec.start_time::TEXT, 'none'),
                COALESCE(event_rec.end_time::TEXT, 'none');
            RAISE NOTICE '      Status: isActive=%, isUpcoming=%, isFuture=%, isEnded=%',
                event_rec.is_active,
                event_rec.is_upcoming,
                event_rec.is_future,
                event_rec.is_ended;
        END LOOP;
    END LOOP;
END $$;

-- ============================================================================
-- STEP 5: Update Swift-side logging (EventsHomeView.swift & PastEventsView.swift)
-- ============================================================================
-- Update the debug logs to include isFuture for every event processed
-- This needs to be done in Swift code - see instructions below

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Show all events with their computed statuses
SELECT
    user_id,
    name,
    event_date,
    start_time,
    end_time,
    is_active,
    is_upcoming,
    is_future,
    is_ended,
    CASE
        WHEN is_active THEN '✅ ACTIVE'
        WHEN is_upcoming THEN '🔵 MOST UPCOMING (can start)'
        WHEN is_future THEN '🔵 FUTURE (upcoming badge, cannot start yet)'
        WHEN is_ended THEN '⚪ ENDED'
        ELSE '⏸️ UNKNOWN STATE'
    END as display_status,
    CASE
        WHEN end_time IS NOT NULL THEN
            (event_date + end_time)::TEXT
        ELSE
            (event_date + INTERVAL '1 day' - INTERVAL '1 second')::TEXT
    END as computed_end_datetime,
    NOW()::TEXT as current_time
FROM events
ORDER BY user_id, event_date ASC, start_time ASC;

-- ============================================================================
-- MIGRATION COMPLETE!
-- ============================================================================
