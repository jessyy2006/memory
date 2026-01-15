-- =====================================================
-- FIX: Event State Timing Logic Bug
-- =====================================================
-- Problem: Events with start time equal to current time are incorrectly marked as ended
-- Solution: Events should only be marked as ended AFTER end time passes (not AT end time)
--
-- Changes:
-- 1. Use < (less than) instead of <= when comparing times
-- 2. isUpcoming = true as long as end time hasn't passed yet
-- 3. isEnded = true only when end time has passed OR user manually ends event
-- =====================================================

-- Step 1: Update existing events that were incorrectly marked as ended
-- Reset events where end time is in the future but is_ended=true
UPDATE events
SET
    is_ended = false,
    is_active = false  -- Keep inactive unless it was manually started
WHERE
    is_ended = true
    AND (
        -- Case 1: Events with end time in the future
        (end_time IS NOT NULL AND
         (event_date + end_time) > NOW())
        OR
        -- Case 2: Events without end time but event date is today or future
        (end_time IS NULL AND event_date >= CURRENT_DATE)
    );

-- Step 2: Create improved function to calculate event state
CREATE OR REPLACE FUNCTION get_event_state(
    p_event_date DATE,
    p_start_time TIME,
    p_end_time TIME,
    p_is_active BOOLEAN,
    p_is_ended BOOLEAN
)
RETURNS TABLE(
    is_upcoming BOOLEAN,
    is_active_computed BOOLEAN,
    is_ended_computed BOOLEAN
) AS $$
DECLARE
    current_datetime TIMESTAMP := NOW();
    event_start_datetime TIMESTAMP;
    event_end_datetime TIMESTAMP;
BEGIN
    -- Calculate event start datetime
    IF p_start_time IS NOT NULL THEN
        event_start_datetime := p_event_date + p_start_time;
    ELSE
        event_start_datetime := p_event_date::TIMESTAMP;
    END IF;

    -- Calculate event end datetime
    IF p_end_time IS NOT NULL THEN
        event_end_datetime := p_event_date + p_end_time;
    ELSE
        event_end_datetime := (p_event_date + INTERVAL '1 day')::TIMESTAMP;
    END IF;

    -- Determine state based on FIXED logic
    RETURN QUERY SELECT
        -- is_upcoming: true if end time hasn't passed yet
        (current_datetime < event_end_datetime AND NOT p_is_ended) AS is_upcoming,

        -- is_active: respect manual state (user clicked "Start Event")
        p_is_active AS is_active_computed,

        -- is_ended: true only if end time has passed OR user manually ended it
        (current_datetime >= event_end_datetime OR p_is_ended) AS is_ended_computed;
END;
$$ LANGUAGE plpgsql;

-- Step 3: Update start_event function to use correct logic
CREATE OR REPLACE FUNCTION start_event(p_event_id UUID)
RETURNS JSONB AS $$
DECLARE
    event_record RECORD;
    current_datetime TIMESTAMP := NOW();
    event_end_datetime TIMESTAMP;
BEGIN
    -- Get event details
    SELECT * INTO event_record
    FROM events
    WHERE id = p_event_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Event not found: %', p_event_id;
    END IF;

    -- Calculate end datetime
    IF event_record.end_time IS NOT NULL THEN
        event_end_datetime := event_record.event_date + event_record.end_time;
    ELSE
        event_end_datetime := (event_record.event_date + INTERVAL '1 day')::TIMESTAMP;
    END IF;

    -- Check if event has already ended (FIXED: use < instead of <=)
    IF current_datetime >= event_end_datetime THEN
        RAISE EXCEPTION 'Cannot start event - end time has already passed';
    END IF;

    -- Stop any currently active events for this user
    UPDATE events
    SET is_active = false
    WHERE user_id = event_record.user_id
      AND is_active = true
      AND id != p_event_id;

    -- Start this event
    UPDATE events
    SET
        is_active = true,
        is_ended = false,  -- Ensure it's not marked as ended
        updated_at = NOW()
    WHERE id = p_event_id;

    -- Return updated event
    RETURN (
        SELECT jsonb_build_object(
            'id', id,
            'user_id', user_id,
            'name', name,
            'event_date', event_date,
            'start_time', start_time,
            'end_time', end_time,
            'is_active', is_active,
            'is_ended', is_ended,
            'created_at', created_at,
            'updated_at', updated_at
        )
        FROM events
        WHERE id = p_event_id
    );
END;
$$ LANGUAGE plpgsql;

-- Step 4: Update stop_event function to use correct logic
CREATE OR REPLACE FUNCTION stop_event(p_event_id UUID)
RETURNS JSONB AS $$
DECLARE
    event_record RECORD;
    current_datetime TIMESTAMP := NOW();
    event_end_datetime TIMESTAMP;
    should_mark_ended BOOLEAN;
BEGIN
    -- Get event details
    SELECT * INTO event_record
    FROM events
    WHERE id = p_event_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Event not found: %', p_event_id;
    END IF;

    -- Calculate end datetime
    IF event_record.end_time IS NOT NULL THEN
        event_end_datetime := event_record.event_date + event_record.end_time;
    ELSE
        event_end_datetime := (event_record.event_date + INTERVAL '1 day')::TIMESTAMP;
    END IF;

    -- Determine if event should be marked as ended
    -- FIXED: Only mark as ended if end time has PASSED (>=)
    should_mark_ended := current_datetime >= event_end_datetime;

    -- Stop the event
    UPDATE events
    SET
        is_active = false,
        is_ended = should_mark_ended,
        updated_at = NOW()
    WHERE id = p_event_id;

    -- Return updated event
    RETURN (
        SELECT jsonb_build_object(
            'id', id,
            'user_id', user_id,
            'name', name,
            'event_date', event_date,
            'start_time', start_time,
            'end_time', end_time,
            'is_active', is_active,
            'is_ended', is_ended,
            'created_at', created_at,
            'updated_at', updated_at
        )
        FROM events
        WHERE id = p_event_id
    );
END;
$$ LANGUAGE plpgsql;

-- Step 5: Create trigger to auto-update event state based on time
CREATE OR REPLACE FUNCTION auto_update_event_state()
RETURNS TRIGGER AS $$
DECLARE
    current_datetime TIMESTAMP := NOW();
    event_end_datetime TIMESTAMP;
BEGIN
    -- Calculate end datetime
    IF NEW.end_time IS NOT NULL THEN
        event_end_datetime := NEW.event_date + NEW.end_time;
    ELSE
        event_end_datetime := (NEW.event_date + INTERVAL '1 day')::TIMESTAMP;
    END IF;

    -- Auto-mark as ended if end time has passed (FIXED: use >= instead of >)
    IF current_datetime >= event_end_datetime AND NOT NEW.is_ended THEN
        NEW.is_ended := true;
        NEW.is_active := false;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS trigger_auto_update_event_state ON events;

-- Create trigger that runs on INSERT and UPDATE
CREATE TRIGGER trigger_auto_update_event_state
    BEFORE INSERT OR UPDATE ON events
    FOR EACH ROW
    EXECUTE FUNCTION auto_update_event_state();

-- =====================================================
-- Verification Queries
-- =====================================================

-- Show all events with their computed states
SELECT
    name,
    event_date,
    start_time,
    end_time,
    is_active,
    is_ended,
    CASE
        WHEN end_time IS NOT NULL THEN event_date + end_time
        ELSE (event_date + INTERVAL '1 day')::TIMESTAMP
    END as event_end_datetime,
    NOW() as current_time,
    CASE
        WHEN end_time IS NOT NULL THEN
            NOW() < (event_date + end_time)
        ELSE
            NOW() < (event_date + INTERVAL '1 day')::TIMESTAMP
    END as should_be_upcoming
FROM events
ORDER BY event_date DESC, start_time DESC;
