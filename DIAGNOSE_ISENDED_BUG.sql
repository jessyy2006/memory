-- ============================================================================
-- DIAGNOSTIC: Root Cause Analysis for isEnded Bug
-- ============================================================================
-- Problem: Events with future end times are marked as isEnded=true
-- Hypothesis: TIME format might not be 24-hour, or AM/PM is lost
-- ============================================================================

DO $$
DECLARE
    event_rec RECORD;
    now_local TIMESTAMP;
    computed_end TIMESTAMP;
    comparison_result BOOLEAN;
BEGIN
    now_local := LOCALTIMESTAMP;

    RAISE NOTICE '';
    RAISE NOTICE '🔍 ROOT CAUSE DIAGNOSTIC';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE 'Current LOCALTIMESTAMP: %', now_local;
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';

    FOR event_rec IN
        SELECT
            id,
            name,
            event_date,
            start_time,
            end_time,
            is_ended,
            is_future,
            is_active
        FROM events
        WHERE event_date = CURRENT_DATE  -- Only today's events
        ORDER BY COALESCE(start_time, '00:00:00'::TIME) ASC
    LOOP
        RAISE NOTICE '';
        RAISE NOTICE '📅 Event: %', event_rec.name;
        RAISE NOTICE '   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';

        -- Show raw database values
        RAISE NOTICE '   📊 RAW DATABASE VALUES:';
        RAISE NOTICE '      event_date (DATE): %', event_rec.event_date;
        RAISE NOTICE '      start_time (TIME): %', COALESCE(event_rec.start_time::TEXT, 'NULL');
        RAISE NOTICE '      end_time (TIME):   %', COALESCE(event_rec.end_time::TEXT, 'NULL');
        RAISE NOTICE '';

        -- Show TIME type format
        RAISE NOTICE '   🕐 TIME TYPE ANALYSIS:';
        IF event_rec.end_time IS NOT NULL THEN
            RAISE NOTICE '      end_time as TEXT: "%"', event_rec.end_time::TEXT;
            RAISE NOTICE '      end_time data type: %', pg_typeof(event_rec.end_time);
            RAISE NOTICE '      end_time in 24-hour format: %', to_char(event_rec.end_time, 'HH24:MI:SS');
            RAISE NOTICE '      end_time in 12-hour format: %', to_char(event_rec.end_time, 'HH12:MI:SS AM');
        END IF;
        RAISE NOTICE '';

        -- Calculate event_end_datetime step by step
        RAISE NOTICE '   🧮 CALCULATION BREAKDOWN:';

        IF event_rec.end_time IS NOT NULL THEN
            -- Step 1: Cast event_date to TIMESTAMP
            RAISE NOTICE '      Step 1: event_date::TIMESTAMP = %', event_rec.event_date::TIMESTAMP;

            -- Step 2: Show end_time value
            RAISE NOTICE '      Step 2: end_time = %', event_rec.end_time;

            -- Step 3: Add them together
            computed_end := event_rec.event_date::TIMESTAMP + event_rec.end_time;
            RAISE NOTICE '      Step 3: event_date::TIMESTAMP + end_time = %', computed_end;

            -- Extract components
            RAISE NOTICE '      ├─ Date component: %', DATE(computed_end);
            RAISE NOTICE '      ├─ Time component: %', computed_end::TIME;
            RAISE NOTICE '      └─ Hour (24-hour): %', EXTRACT(HOUR FROM computed_end);
        ELSE
            computed_end := event_rec.event_date::TIMESTAMP + INTERVAL '1 day' - INTERVAL '1 second';
            RAISE NOTICE '      Event has no end_time, using end of day: %', computed_end;
        END IF;
        RAISE NOTICE '';

        -- Compare with current time
        RAISE NOTICE '   ⏰ TIME COMPARISON:';
        RAISE NOTICE '      Current time (LOCALTIMESTAMP): %', now_local;
        RAISE NOTICE '      Event end datetime (computed):  %', computed_end;
        RAISE NOTICE '';

        -- Extract hours for manual comparison
        IF event_rec.end_time IS NOT NULL THEN
            RAISE NOTICE '      Current hour (24-hour): %', EXTRACT(HOUR FROM now_local);
            RAISE NOTICE '      Event end hour (24-hour): %', EXTRACT(HOUR FROM computed_end);
            RAISE NOTICE '';
        END IF;

        -- Do the comparison
        comparison_result := (now_local > computed_end);

        RAISE NOTICE '      Comparison: LOCALTIMESTAMP > computed_end?';
        RAISE NOTICE '      Result: %', comparison_result;
        RAISE NOTICE '';

        -- Show what the database has
        RAISE NOTICE '   💾 DATABASE STORED VALUES:';
        RAISE NOTICE '      is_ended (in DB): %', event_rec.is_ended;
        RAISE NOTICE '      is_future (in DB): %', event_rec.is_future;
        RAISE NOTICE '';

        -- Validation
        RAISE NOTICE '   ✅ VALIDATION:';
        IF comparison_result = event_rec.is_ended THEN
            RAISE NOTICE '      ✅ MATCH: Calculated is_ended (%) matches DB value (%)',
                comparison_result, event_rec.is_ended;
        ELSE
            RAISE NOTICE '      ❌ MISMATCH: Calculated is_ended (%) does NOT match DB value (%)',
                comparison_result, event_rec.is_ended;
        END IF;

        -- Detailed verdict
        IF event_rec.end_time IS NOT NULL THEN
            IF now_local < computed_end THEN
                RAISE NOTICE '      📌 VERDICT: Event end time (%) is AFTER current time (%)',
                    to_char(computed_end, 'HH24:MI:SS'),
                    to_char(now_local, 'HH24:MI:SS');
                RAISE NOTICE '      📌 Therefore: is_ended should be FALSE';

                IF event_rec.is_ended THEN
                    RAISE NOTICE '      ❌❌❌ BUG CONFIRMED: DB shows is_ended=true but should be false!';
                END IF;
            ELSIF now_local > computed_end THEN
                RAISE NOTICE '      📌 VERDICT: Event end time (%) is BEFORE current time (%)',
                    to_char(computed_end, 'HH24:MI:SS'),
                    to_char(now_local, 'HH24:MI:SS');
                RAISE NOTICE '      📌 Therefore: is_ended should be TRUE';

                IF NOT event_rec.is_ended THEN
                    RAISE NOTICE '      ❌❌❌ BUG CONFIRMED: DB shows is_ended=false but should be true!';
                END IF;
            ELSE
                RAISE NOTICE '      📌 VERDICT: Event end time equals current time (edge case)';
            END IF;
        END IF;

        RAISE NOTICE '   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- TIMEZONE SETTINGS CHECK
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🌐 DATABASE TIMEZONE SETTINGS:';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

SHOW timezone;

SELECT
    'CURRENT_TIMESTAMP (with TZ)' as type,
    CURRENT_TIMESTAMP as value
UNION ALL
SELECT
    'LOCALTIMESTAMP (no TZ)' as type,
    LOCALTIMESTAMP as value
UNION ALL
SELECT
    'NOW()' as type,
    NOW() as value;

-- ============================================================================
-- TEST CASE: Manual TIME arithmetic
-- ============================================================================

DO $$
DECLARE
    test_date DATE := CURRENT_DATE;
    test_time TIME := '15:00:00';  -- 3 PM in 24-hour format
    result TIMESTAMP;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🧪 TEST CASE: Manual DATE + TIME arithmetic';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE 'Test input:';
    RAISE NOTICE '  test_date = %', test_date;
    RAISE NOTICE '  test_time = %', test_time;
    RAISE NOTICE '';

    result := test_date::TIMESTAMP + test_time;

    RAISE NOTICE 'Result: %', result;
    RAISE NOTICE 'Hour extracted: %', EXTRACT(HOUR FROM result);
    RAISE NOTICE '';

    IF EXTRACT(HOUR FROM result) = 15 THEN
        RAISE NOTICE '✅ TIME arithmetic works correctly (24-hour format preserved)';
    ELSE
        RAISE NOTICE '❌ TIME arithmetic is broken! Expected hour 15, got %', EXTRACT(HOUR FROM result);
    END IF;
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

-- ============================================================================
-- SHOW ALL TODAY'S EVENTS IN TABLE FORMAT
-- ============================================================================

SELECT
    name,
    event_date,
    end_time,
    to_char(end_time, 'HH24:MI:SS') as end_time_24h,
    (event_date::TIMESTAMP + end_time) as computed_end_datetime,
    LOCALTIMESTAMP as current_time,
    (LOCALTIMESTAMP > (event_date::TIMESTAMP + end_time)) as should_be_ended,
    is_ended as db_is_ended,
    CASE
        WHEN (LOCALTIMESTAMP > (event_date::TIMESTAMP + end_time)) = is_ended THEN '✅ MATCH'
        ELSE '❌ MISMATCH'
    END as validation
FROM events
WHERE event_date = CURRENT_DATE
  AND end_time IS NOT NULL
ORDER BY end_time ASC;
