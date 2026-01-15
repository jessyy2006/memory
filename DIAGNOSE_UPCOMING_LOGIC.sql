-- ============================================================================
-- DIAGNOSTIC: Why is Event 6 still isUpcoming = true?
-- ============================================================================

DO $$
DECLARE
    event_rec RECORD;
    now_time TIMESTAMP;
BEGIN
    now_time := NOW();
    RAISE NOTICE '';
    RAISE NOTICE '🔍 DIAGNOSTIC - Current Time: %', now_time;
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';

    FOR event_rec IN
        SELECT
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
            END as computed_end,
            -- Check if event qualifies for is_upcoming
            (is_ended = false AND is_future = true AND is_active = false) as qualifies_for_upcoming
        FROM events
        ORDER BY event_date ASC, COALESCE(start_time, '23:59:59'::TIME) ASC
    LOOP
        RAISE NOTICE '📅 %', event_rec.name;
        RAISE NOTICE '   Event Date: %', event_rec.event_date;
        RAISE NOTICE '   Start Time: %', COALESCE(event_rec.start_time::TEXT, 'NULL');
        RAISE NOTICE '   End Time: %', COALESCE(event_rec.end_time::TEXT, 'NULL');
        RAISE NOTICE '   ---';
        RAISE NOTICE '   Computed Start Datetime: %', event_rec.computed_start;
        RAISE NOTICE '   Computed End Datetime: %', event_rec.computed_end;
        RAISE NOTICE '   Current Time: %', now_time;
        RAISE NOTICE '   ---';
        RAISE NOTICE '   is_ended: %', event_rec.is_ended;
        RAISE NOTICE '   is_future: %', event_rec.is_future;
        RAISE NOTICE '   is_active: %', event_rec.is_active;
        RAISE NOTICE '   is_upcoming: %', event_rec.is_upcoming;
        RAISE NOTICE '   ---';
        RAISE NOTICE '   Qualifies for is_upcoming? %', event_rec.qualifies_for_upcoming;

        -- Time comparisons
        IF now_time < event_rec.computed_start THEN
            RAISE NOTICE '   ⏰ Event starts in the FUTURE';
        ELSIF now_time >= event_rec.computed_start AND now_time < event_rec.computed_end THEN
            RAISE NOTICE '   ⏰ Event is HAPPENING NOW (should be active)';
        ELSE
            RAISE NOTICE '   ⏰ Event ended in the PAST';
        END IF;

        -- Check for violation
        IF event_rec.is_upcoming AND NOT event_rec.qualifies_for_upcoming THEN
            RAISE NOTICE '   ❌❌❌ VIOLATION: isUpcoming=true but does NOT qualify!';
            RAISE NOTICE '   Reason: is_ended=% OR is_future=% OR is_active=%',
                event_rec.is_ended, event_rec.is_future, event_rec.is_active;
        ELSIF event_rec.is_upcoming THEN
            RAISE NOTICE '   ✅ Valid upcoming event';
        END IF;

        RAISE NOTICE '';
    END LOOP;

    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

-- Show the query that SHOULD select the upcoming event
SELECT
    name,
    event_date,
    start_time,
    is_ended,
    is_future,
    is_active,
    is_upcoming,
    (event_date + COALESCE(start_time, '00:00:00'::TIME)) as sort_key,
    'THIS SHOULD BE UPCOMING' as note
FROM events
WHERE is_ended = false
  AND is_future = true
  AND is_active = false
ORDER BY (event_date + COALESCE(start_time, '00:00:00'::TIME)) ASC
LIMIT 1;
