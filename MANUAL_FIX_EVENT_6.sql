-- ============================================================================
-- MANUAL FIX: Force Event 6 to have isUpcoming = false
-- ============================================================================
-- The triggers are not working correctly, so we'll manually fix this
-- ============================================================================

-- STEP 1: Manually set Event 6 to isUpcoming = false
UPDATE events
SET is_upcoming = false
WHERE name ILIKE '%Event 6%';

-- STEP 2: Find the CORRECT upcoming event and set it
DO $$
DECLARE
    correct_upcoming_id UUID;
    user_id_var UUID;
BEGIN
    -- Get Event 6's user_id
    SELECT user_id INTO user_id_var
    FROM events
    WHERE name ILIKE '%Event 6%'
    LIMIT 1;

    RAISE NOTICE 'User ID: %', user_id_var;

    -- Clear ALL is_upcoming for this user first
    UPDATE events
    SET is_upcoming = false
    WHERE user_id = user_id_var;

    RAISE NOTICE 'Cleared all is_upcoming flags';

    -- Find the correct upcoming event:
    -- STRICT RULE: is_ended = false AND is_future = true AND is_active = false
    SELECT id INTO correct_upcoming_id
    FROM events
    WHERE user_id = user_id_var
      AND is_ended = false
      AND is_future = true
      AND is_active = false
    ORDER BY (event_date + COALESCE(start_time, '00:00:00'::TIME)) ASC
    LIMIT 1;

    IF correct_upcoming_id IS NOT NULL THEN
        UPDATE events
        SET is_upcoming = true
        WHERE id = correct_upcoming_id;

        RAISE NOTICE 'Set is_upcoming=true for event ID: %', correct_upcoming_id;

        -- Show which event was selected
        FOR event_rec IN
            SELECT name, event_date, start_time, is_ended, is_future, is_active
            FROM events
            WHERE id = correct_upcoming_id
        LOOP
            RAISE NOTICE 'Selected Event: %', event_rec.name;
            RAISE NOTICE '  Date: %, Start: %', event_rec.event_date, COALESCE(event_rec.start_time::TEXT, 'NULL');
            RAISE NOTICE '  is_ended=%', event_rec.is_ended;
            RAISE NOTICE '  is_future=%', event_rec.is_future;
            RAISE NOTICE '  is_active=%', event_rec.is_active;
        END LOOP;
    ELSE
        RAISE NOTICE 'No valid upcoming event found (this is acceptable)';
    END IF;
END $$;

-- STEP 3: Verify the fix
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
