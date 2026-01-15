-- ============================================================================
-- COMPLETE FIX: Recalculate is_ended, is_future, AND is_upcoming
-- ============================================================================
-- Problem: Event 6 has isUpcoming=true but isEnded=true and isFuture=false
-- Root Cause: The status fields (is_ended, is_future) are not being recalculated
-- Solution:
--   1. Force trigger ALL events to recalculate is_ended and is_future
--   2. Then recalculate is_upcoming based on the CORRECT values
-- ============================================================================

-- ============================================================================
-- STEP 1: Touch event_date to force BOTH triggers to fire
-- ============================================================================
-- This will trigger:
--   - BEFORE UPDATE trigger: calculate_event_status() - Recalculates is_ended, is_future
--   - AFTER UPDATE trigger: update_most_upcoming_event() - Recalculates is_upcoming

DO $$
DECLARE
    event_rec RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🔄 FORCING TRIGGER RECALCULATION FOR ALL EVENTS...';
    RAISE NOTICE '';

    -- Loop through all events and touch event_date to trigger BOTH triggers
    FOR event_rec IN SELECT id, name, event_date FROM events ORDER BY user_id, event_date ASC
    LOOP
        RAISE NOTICE '📅 Triggering recalculation for: %', event_rec.name;

        -- Touch event_date to trigger BEFORE UPDATE (calculate_event_status)
        -- which will then trigger AFTER UPDATE (update_most_upcoming_event)
        UPDATE events
        SET event_date = event_date  -- No actual change, just triggers the trigger
        WHERE id = event_rec.id;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '✅ All triggers fired!';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- STEP 2: Verify Event 6 and Event 10
-- ============================================================================

DO $$
DECLARE
    event_rec RECORD;
    violation_found BOOLEAN := false;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🔍 VERIFICATION - Event 6 & Event 10:';
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
            (event_date + COALESCE(start_time, '00:00:00'::TIME)) as computed_start,
            CASE
                WHEN end_time IS NOT NULL THEN (event_date + end_time)
                ELSE (event_date + INTERVAL '1 day' - INTERVAL '1 second')
            END as computed_end
        FROM events
        WHERE name ILIKE '%Event 6%' OR name ILIKE '%Event 10%'
        ORDER BY name
    LOOP
        RAISE NOTICE '';
        RAISE NOTICE '📌 %', event_rec.name;
        RAISE NOTICE '   Date: % | Start: % | End: %',
            event_rec.event_date,
            COALESCE(event_rec.start_time::TEXT, 'NULL'),
            COALESCE(event_rec.end_time::TEXT, 'NULL');
        RAISE NOTICE '   Computed Start: %', event_rec.computed_start;
        RAISE NOTICE '   Computed End: %', event_rec.computed_end;
        RAISE NOTICE '   Current Time: %', NOW();
        RAISE NOTICE '   ---';
        RAISE NOTICE '   is_ended: %', event_rec.is_ended;
        RAISE NOTICE '   is_future: %', event_rec.is_future;
        RAISE NOTICE '   is_active: %', event_rec.is_active;
        RAISE NOTICE '   is_upcoming: %', event_rec.is_upcoming;

        -- Check for violation
        IF event_rec.is_upcoming AND (event_rec.is_ended OR NOT event_rec.is_future) THEN
            RAISE NOTICE '   ❌❌❌ VIOLATION! isUpcoming=true but isEnded=% or isFuture=%',
                event_rec.is_ended, event_rec.is_future;
            violation_found := true;
        ELSIF event_rec.is_upcoming THEN
            RAISE NOTICE '   ✅ VALID: Correctly tagged as upcoming';
        ELSE
            RAISE NOTICE '   ✅ VALID: Correctly NOT tagged as upcoming';
        END IF;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';

    IF violation_found THEN
        RAISE NOTICE '❌ VALIDATION FAILED: Violations detected!';
    ELSE
        RAISE NOTICE '✅ VALIDATION PASSED: No violations!';
    END IF;

    RAISE NOTICE '';
END $$;

-- ============================================================================
-- STEP 3: Show ALL events status
-- ============================================================================

SELECT
    name,
    event_date,
    start_time,
    end_time,
    is_ended,
    is_future,
    is_active,
    is_upcoming,
    CASE
        WHEN is_upcoming AND (is_ended OR NOT is_future) THEN '❌ VIOLATION'
        WHEN is_upcoming THEN '✅ UPCOMING'
        WHEN is_future THEN '🔵 FUTURE'
        WHEN is_ended THEN '⚪ ENDED'
        ELSE '⏸️ OTHER'
    END as status
FROM events
ORDER BY event_date ASC, COALESCE(start_time, '23:59:59'::TIME) ASC;
