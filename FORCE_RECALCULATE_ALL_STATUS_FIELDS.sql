-- ============================================================================
-- FORCE RECALCULATION OF ALL EVENT STATUS FIELDS
-- ============================================================================
-- Problem: Event 6 has isUpcoming=true but isEnded=true and isFuture=false
-- Root Cause: is_ended and is_future fields are stale/incorrect
-- Solution: Force recalculation of is_ended and is_future for ALL events
--
-- This will trigger BOTH:
-- 1. calculate_event_status() - Recalculates is_ended, is_future, is_active
-- 2. update_most_upcoming_event() - Recalculates is_upcoming based on NEW values
-- ============================================================================

DO $$
DECLARE
    event_rec RECORD;
    current_time TIMESTAMP := NOW();
    event_start_datetime TIMESTAMP;
    event_end_datetime TIMESTAMP;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🔄 FORCE RECALCULATING ALL STATUS FIELDS FOR ALL EVENTS...';
    RAISE NOTICE '   Current Time: %', current_time;
    RAISE NOTICE '';

    -- Loop through ALL events and manually recalculate their status
    FOR event_rec IN SELECT * FROM events ORDER BY user_id, event_date ASC
    LOOP
        RAISE NOTICE '📅 Processing: %', event_rec.name;
        RAISE NOTICE '   Date: %', event_rec.event_date;
        RAISE NOTICE '   Start: %', COALESCE(event_rec.start_time::TEXT, 'NULL');
        RAISE NOTICE '   End: %', COALESCE(event_rec.end_time::TEXT, 'NULL');

        -- Calculate event start datetime
        IF event_rec.start_time IS NOT NULL THEN
            event_start_datetime := event_rec.event_date + event_rec.start_time;
        ELSE
            event_start_datetime := event_rec.event_date::TIMESTAMP;
        END IF;

        -- Calculate event end datetime
        IF event_rec.end_time IS NOT NULL THEN
            event_end_datetime := event_rec.event_date + event_rec.end_time;
        ELSE
            event_end_datetime := (event_rec.event_date + INTERVAL '1 day' - INTERVAL '1 second')::TIMESTAMP;
        END IF;

        RAISE NOTICE '   Computed Start: %', event_start_datetime;
        RAISE NOTICE '   Computed End: %', event_end_datetime;

        -- Manually update is_ended and is_future based on time calculations
        UPDATE events
        SET
            is_ended = CASE
                -- If user manually ended it, keep it ended
                WHEN is_ended = true AND is_active = false THEN true
                -- Otherwise, check if end time has passed
                ELSE current_time >= event_end_datetime
            END,
            is_future = CASE
                -- is_future = true if:
                --   1. NOT ended
                --   2. NOT active
                --   3. End time is in the future
                WHEN is_active = false
                     AND current_time < event_end_datetime
                     AND NOT (is_ended = true AND is_active = false)
                THEN true
                ELSE false
            END,
            updated_at = NOW()
        WHERE id = event_rec.id;

        -- Log the NEW values after update
        FOR event_rec IN
            SELECT is_ended, is_future, is_active, is_upcoming
            FROM events
            WHERE id = event_rec.id
        LOOP
            RAISE NOTICE '   → NEW: isEnded=%, isFuture=%, isActive=%, isUpcoming=%',
                event_rec.is_ended,
                event_rec.is_future,
                event_rec.is_active,
                event_rec.is_upcoming;
        END LOOP;

        RAISE NOTICE '';
    END LOOP;

    RAISE NOTICE '✅ All events status fields recalculated!';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- VERIFICATION: Show Event 6 and Event 10 status AFTER recalculation
-- ============================================================================

DO $$
DECLARE
    event_rec RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🔍 EVENT 6 & EVENT 10 STATUS AFTER RECALCULATION:';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';

    FOR event_rec IN
        SELECT
            id,
            name,
            event_date,
            start_time,
            end_time,
            is_ended,
            is_future,
            is_active,
            is_upcoming,
            (event_date + COALESCE(start_time, '00:00:00'::TIME)) as computed_start_datetime,
            CASE
                WHEN end_time IS NOT NULL THEN (event_date + end_time)
                ELSE (event_date + INTERVAL '1 day' - INTERVAL '1 second')
            END as computed_end_datetime
        FROM events
        WHERE name ILIKE '%Event 6%' OR name ILIKE '%Event 10%'
        ORDER BY name
    LOOP
        RAISE NOTICE '';
        RAISE NOTICE '📌 %', event_rec.name;
        RAISE NOTICE '   Event Date: %', event_rec.event_date;
        RAISE NOTICE '   Start Time: %', COALESCE(event_rec.start_time::TEXT, 'NULL');
        RAISE NOTICE '   End Time: %', COALESCE(event_rec.end_time::TEXT, 'NULL');
        RAISE NOTICE '   Computed Start Datetime: %', event_rec.computed_start_datetime;
        RAISE NOTICE '   Computed End Datetime: %', event_rec.computed_end_datetime;
        RAISE NOTICE '   Current Time: %', NOW();
        RAISE NOTICE '   ---';
        RAISE NOTICE '   is_ended: %', event_rec.is_ended;
        RAISE NOTICE '   is_future: %', event_rec.is_future;
        RAISE NOTICE '   is_active: %', event_rec.is_active;
        RAISE NOTICE '   is_upcoming: %', event_rec.is_upcoming;

        -- Validate mutual exclusivity
        IF event_rec.is_upcoming AND (event_rec.is_ended OR NOT event_rec.is_future) THEN
            RAISE NOTICE '   ❌❌❌ VIOLATION DETECTED! ❌❌❌';
            RAISE NOTICE '   Event has isUpcoming=true but isEnded=% or isFuture=%',
                event_rec.is_ended, event_rec.is_future;
        ELSIF event_rec.is_upcoming THEN
            RAISE NOTICE '   ✅ CORRECTLY TAGGED AS UPCOMING';
        ELSE
            RAISE NOTICE '   ✅ Correctly NOT tagged as upcoming';
        END IF;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- Show ALL events for debugging
-- ============================================================================

SELECT
    name,
    event_date,
    start_time,
    end_time,
    is_active,
    is_upcoming,
    is_future,
    is_ended,
    (event_date + COALESCE(start_time, '00:00:00'::TIME)) as computed_start_datetime,
    CASE
        WHEN end_time IS NOT NULL THEN (event_date + end_time)
        ELSE (event_date + INTERVAL '1 day' - INTERVAL '1 second')
    END as computed_end_datetime,
    NOW() as current_time,
    CASE
        WHEN is_upcoming AND (is_ended OR NOT is_future) THEN '❌ VIOLATION'
        WHEN is_upcoming THEN '✅ VALID UPCOMING'
        ELSE '  Normal'
    END as validation_status
FROM events
ORDER BY event_date ASC, COALESCE(start_time, '23:59:59'::TIME) ASC;
