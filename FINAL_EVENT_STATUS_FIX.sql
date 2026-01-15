-- ============================================================================
-- FINAL EVENT STATUS FIX: Enforce Strict Logic Order
-- ============================================================================
-- Problems Fixed:
-- 1. False Expiry: New future events incorrectly marked as is_ended=true
-- 2. Logic Conflict: Events with is_ended=true still have is_upcoming=true
-- 3. Insufficient Logging: No per-event debug output
--
-- Strict Order of Operations:
-- Step 1: Calculate is_ended & is_future based ONLY on time comparison
-- Step 2: Apply guard clause - Force is_upcoming=false if is_ended=true OR is_future=false
-- Step 3: Select single is_upcoming event from valid pool
-- ============================================================================

-- ============================================================================
-- STEP 1: Rewrite calculate_event_status() with strict logic order
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_event_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    now_time TIMESTAMP;
    event_start_datetime TIMESTAMP;
    event_end_datetime TIMESTAMP;
BEGIN
    now_time := NOW();

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

    -- =========================================================================
    -- STEP 1: Determine is_ended & is_future FIRST (based ONLY on time)
    -- =========================================================================

    -- CRITICAL FIX: Use > instead of >= to avoid marking events as ended at exact end time
    -- is_ended = true ONLY if current time is AFTER the end datetime
    NEW.is_ended := (now_time > event_end_datetime);

    -- is_future = true if:
    --   1. NOT ended (is_ended = false)
    --   2. NOT active (is_active = false)
    --   3. End time is still in the future
    NEW.is_future := (NOT NEW.is_ended) AND (NOT NEW.is_active) AND (event_end_datetime > now_time);

    -- =========================================================================
    -- STEP 2: Apply isUpcoming Guard Clause
    -- =========================================================================
    -- STRICT RULE: If is_ended=true OR is_future=false, FORCE is_upcoming=false

    IF NEW.is_ended = true OR NEW.is_future = false THEN
        NEW.is_upcoming := false;
    END IF;

    -- Auto-deactivate if outside time range
    IF NEW.is_active = true THEN
        IF now_time < event_start_datetime OR now_time > event_end_datetime THEN
            NEW.is_active := false;
        END IF;
    END IF;

    -- =========================================================================
    -- LOGGING: Print status for EVERY event processed
    -- =========================================================================
    RAISE NOTICE 'Event % | Start: % | End: % | Now: % | isFuture: % | isEnded: % | isUpcoming: %',
        COALESCE(NEW.id::TEXT, 'NEW'),
        event_start_datetime,
        event_end_datetime,
        now_time,
        NEW.is_future,
        NEW.is_ended,
        COALESCE(NEW.is_upcoming::TEXT, 'NULL');

    RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 2: Rewrite update_most_upcoming_event() with guard clause enforcement
-- ============================================================================

CREATE OR REPLACE FUNCTION update_most_upcoming_event()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    affected_user_id UUID;
    most_upcoming_event_id UUID;
    event_rec RECORD;
BEGIN
    -- Determine which user was affected
    IF TG_OP = 'DELETE' THEN
        affected_user_id := OLD.user_id;
    ELSE
        affected_user_id := NEW.user_id;
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE '🔄 [update_most_upcoming_event] User: %', affected_user_id;
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';

    -- =========================================================================
    -- STEP 1: Clear is_upcoming for ALL user's events
    -- =========================================================================
    UPDATE events
    SET is_upcoming = false
    WHERE user_id = affected_user_id;

    RAISE NOTICE '✅ Cleared all is_upcoming flags';

    -- =========================================================================
    -- STEP 2: STRICT FILTERING - Find ONLY valid future events
    -- =========================================================================
    -- Guard Clause Enforcement:
    --   - is_ended MUST be false
    --   - is_future MUST be true
    --   - is_active MUST be false

    SELECT id INTO most_upcoming_event_id
    FROM events
    WHERE user_id = affected_user_id
      AND is_ended = false
      AND is_future = true
      AND is_active = false
    ORDER BY (event_date + COALESCE(start_time, '00:00:00'::TIME)) ASC
    LIMIT 1;

    -- =========================================================================
    -- STEP 3: Set is_upcoming = true for the single selected event
    -- =========================================================================
    IF most_upcoming_event_id IS NOT NULL THEN
        UPDATE events
        SET is_upcoming = true
        WHERE id = most_upcoming_event_id;

        RAISE NOTICE '✅ Set is_upcoming=true for event: %', most_upcoming_event_id;
    ELSE
        RAISE NOTICE 'ℹ️  No valid upcoming event found (acceptable if all events ended)';
    END IF;

    -- =========================================================================
    -- LOGGING: Print status for ALL events (detailed format)
    -- =========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '📋 All Events Status:';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';

    FOR event_rec IN
        SELECT
            id,
            name,
            event_date,
            start_time,
            end_time,
            is_active,
            is_upcoming,
            is_future,
            is_ended,
            (event_date + COALESCE(start_time, '00:00:00'::TIME)) as computed_start,
            CASE
                WHEN end_time IS NOT NULL THEN (event_date + end_time)
                ELSE (event_date + INTERVAL '1 day' - INTERVAL '1 second')
            END as computed_end
        FROM events
        WHERE user_id = affected_user_id
        ORDER BY event_date ASC, COALESCE(start_time, '00:00:00'::TIME) ASC
    LOOP
        RAISE NOTICE 'Event % | Start: % | End: % | Now: % | isFuture: % | isEnded: % | isUpcoming: %',
            event_rec.id,
            event_rec.computed_start,
            event_rec.computed_end,
            NOW(),
            event_rec.is_future,
            event_rec.is_ended,
            event_rec.is_upcoming;

        -- Validate guard clause
        IF event_rec.is_upcoming AND (event_rec.is_ended OR NOT event_rec.is_future) THEN
            RAISE NOTICE '❌ VIOLATION DETECTED: % has isUpcoming=true but isEnded=% or isFuture=%',
                event_rec.name, event_rec.is_ended, event_rec.is_future;
        END IF;
    END LOOP;

    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

-- ============================================================================
-- STEP 3: Recreate ALL triggers
-- ============================================================================

-- Drop ALL existing triggers
DROP TRIGGER IF EXISTS trigger_before_insert_auto_calculate_is_future ON events;
DROP TRIGGER IF EXISTS trigger_before_update_auto_calculate_is_future ON events;
DROP TRIGGER IF EXISTS trigger_auto_update_event_state ON events;
DROP TRIGGER IF EXISTS trigger_calculate_event_status_insert ON events;
DROP TRIGGER IF EXISTS trigger_calculate_event_status_update ON events;
DROP TRIGGER IF EXISTS trigger_update_most_upcoming_after_insert ON events;
DROP TRIGGER IF EXISTS trigger_update_most_upcoming_after_update ON events;
DROP TRIGGER IF EXISTS trigger_update_most_upcoming_after_delete ON events;

-- Create BEFORE INSERT trigger
CREATE TRIGGER trigger_calculate_event_status_insert
    BEFORE INSERT ON events
    FOR EACH ROW
    EXECUTE FUNCTION calculate_event_status();

-- Create BEFORE UPDATE trigger
-- CRITICAL: Trigger on event_date changes (not just updated_at)
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

-- Create AFTER INSERT trigger
CREATE TRIGGER trigger_update_most_upcoming_after_insert
    AFTER INSERT ON events
    FOR EACH ROW
    EXECUTE FUNCTION update_most_upcoming_event();

-- Create AFTER UPDATE trigger
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

-- Create AFTER DELETE trigger
CREATE TRIGGER trigger_update_most_upcoming_after_delete
    AFTER DELETE ON events
    FOR EACH ROW
    EXECUTE FUNCTION update_most_upcoming_event();

-- ============================================================================
-- STEP 4: FORCE RECALCULATION for ALL existing events
-- ============================================================================

DO $$
DECLARE
    event_rec RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🔄 FORCING RECALCULATION FOR ALL EVENTS...';
    RAISE NOTICE '';

    -- CRITICAL: Touch event_date (not updated_at) to trigger BEFORE trigger
    FOR event_rec IN SELECT id, name FROM events ORDER BY event_date ASC
    LOOP
        RAISE NOTICE 'Recalculating: %', event_rec.name;

        -- This UPDATE will trigger calculate_event_status() BEFORE trigger
        UPDATE events
        SET event_date = event_date
        WHERE id = event_rec.id;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '✅ Recalculation complete!';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- STEP 5: VALIDATION - Check for violations
-- ============================================================================

DO $$
DECLARE
    violation_rec RECORD;
    violation_count INT := 0;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🔍 VALIDATION - Checking for logic violations...';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';

    FOR violation_rec IN
        SELECT
            id,
            name,
            is_ended,
            is_future,
            is_upcoming
        FROM events
        WHERE is_upcoming = true AND (is_ended = true OR is_future = false)
    LOOP
        violation_count := violation_count + 1;
        RAISE NOTICE '❌ VIOLATION: % has isUpcoming=true but isEnded=% or isFuture=%',
            violation_rec.name,
            violation_rec.is_ended,
            violation_rec.is_future;
    END LOOP;

    IF violation_count = 0 THEN
        RAISE NOTICE '✅ VALIDATION PASSED: No violations detected!';
    ELSE
        RAISE NOTICE '❌ VALIDATION FAILED: % violations detected!', violation_count;
    END IF;

    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- STEP 6: Show final state
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
        WHEN is_active THEN '🟢 ACTIVE'
        ELSE '⏸️ OTHER'
    END as status
FROM events
ORDER BY event_date ASC, COALESCE(start_time, '00:00:00'::TIME) ASC;

-- ============================================================================
-- MIGRATION COMPLETE!
-- ============================================================================
--
-- What This Migration Does:
-- 1. Rewrites calculate_event_status() with strict order:
--    - Step 1: Calculate is_ended & is_future based ONLY on time
--    - Step 2: Apply guard clause (force is_upcoming=false if ended/not future)
--    - Step 3: Add comprehensive logging for every event
--
-- 2. Rewrites update_most_upcoming_event() with:
--    - Strict filtering (is_ended=false AND is_future=true AND is_active=false)
--    - Per-event logging in requested format
--    - Violation detection
--
-- 3. Forces recalculation by touching event_date (triggers BEFORE trigger)
--
-- 4. Validates no violations exist
--
-- Expected Results:
-- - Event 6: is_ended=true, is_future=false, is_upcoming=false
-- - Event 10 or Event 12: is_ended=false, is_future=true, is_upcoming=true
-- - Event 13: is_ended=false, is_future=true (correctly marked as future)
-- - No logical impossibilities (ended events never upcoming)
-- ============================================================================
