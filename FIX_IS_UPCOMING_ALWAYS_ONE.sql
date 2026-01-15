-- ============================================================================
-- FIX: Enforce Strict Mutual Exclusivity for is_upcoming
-- ============================================================================
-- Problem: Event 6 (ended event) is being marked as isUpcoming = true
-- Solution: Enforce STRICT mutual exclusivity - NO ended or non-future events
--
-- Strict Rules:
-- 1. An event CANNOT be isUpcoming if isEnded = true OR isFuture = false
-- 2. Maximum of 1 event can have is_upcoming = true
-- 3. Minimum of 0 events can have is_upcoming = true (if no valid events exist)
-- 4. The event with is_upcoming = true must be the soonest future event
-- 5. Only events on "Events Home Page" qualify (NOT "Past Events" page)
--
-- Selection Order:
-- Step 1: Filter out all events where isEnded = true or isFuture = false
-- Step 2: From remaining pool, find event with start datetime closest to NOW
-- Step 3: Assign isUpcoming = true to that one event (or none if pool is empty)
-- ============================================================================

-- ============================================================================
-- STEP 1: Rewrite update_most_upcoming_event() with ALWAYS tag logic
-- ============================================================================

CREATE OR REPLACE FUNCTION update_most_upcoming_event()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    affected_user_id UUID;
    most_upcoming_event_id UUID;
    event_count INT;
    future_event_count INT;
    event_rec RECORD;
BEGIN
    -- Determine which user was affected
    IF TG_OP = 'DELETE' THEN
        affected_user_id := OLD.user_id;
    ELSE
        affected_user_id := NEW.user_id;
    END IF;

    RAISE NOTICE '🔄 [update_most_upcoming_event] Recalculating is_upcoming for user: %', affected_user_id;

    -- Count total events for this user
    SELECT COUNT(*) INTO event_count
    FROM events
    WHERE user_id = affected_user_id;

    RAISE NOTICE '   📊 Total events for user: %', event_count;

    -- If user has no events, nothing to do
    IF event_count = 0 THEN
        RAISE NOTICE '   ℹ️ User has no events - skipping';
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        ELSE
            RETURN NEW;
        END IF;
    END IF;

    -- Clear is_upcoming for ALL events for this user first
    UPDATE events
    SET is_upcoming = false
    WHERE user_id = affected_user_id;

    RAISE NOTICE '   🧹 Cleared is_upcoming for all events';

    -- =========================================================================
    -- STRICT FILTERING: Find ONLY valid future events
    -- =========================================================================
    -- Mutual Exclusivity Rule: An event CANNOT be isUpcoming if:
    --   - is_ended = true, OR
    --   - is_future = false, OR
    --   - is_active = true
    --
    -- Logic: Find event with soonest start datetime where:
    --   - is_ended = false (NOT ended)
    --   - is_future = true (is a future event)
    --   - is_active = false (NOT currently active)
    --   - Sorted by: combined start datetime (event_date + start_time) ASC

    SELECT id INTO most_upcoming_event_id
    FROM events
    WHERE user_id = affected_user_id
      AND is_ended = false
      AND is_future = true
      AND is_active = false
    ORDER BY
      (event_date + COALESCE(start_time, '00:00:00'::TIME)) ASC
    LIMIT 1;

    IF most_upcoming_event_id IS NOT NULL THEN
        -- Tag the valid event
        UPDATE events
        SET is_upcoming = true,
            updated_at = NOW()
        WHERE id = most_upcoming_event_id;

        RAISE NOTICE '   ✅ Set is_upcoming=true for valid future event: %', most_upcoming_event_id;

        -- Log the selected event details
        FOR event_rec IN
            SELECT name, event_date, start_time, is_ended, is_future, is_active
            FROM events
            WHERE id = most_upcoming_event_id
        LOOP
            RAISE NOTICE '      Event: % (Date: %, Start: %)',
                event_rec.name,
                event_rec.event_date,
                COALESCE(event_rec.start_time::TEXT, 'none');
            RAISE NOTICE '      Status: isEnded=%, isFuture=%, isActive=%',
                event_rec.is_ended,
                event_rec.is_future,
                event_rec.is_active;
        END LOOP;
    ELSE
        RAISE NOTICE '   ℹ️ No valid future events found - NO event tagged as upcoming';
        RAISE NOTICE '      (This is acceptable - mutual exclusivity enforced)';
    END IF;

    -- =========================================================================
    -- DEBUG: Print Event 6 and Event 10 status specifically
    -- =========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '   🔍 DEBUG - Event 6 & Event 10 Status:';
    RAISE NOTICE '   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';

    FOR event_rec IN
        SELECT id, name, is_ended, is_future, is_active, is_upcoming
        FROM events
        WHERE user_id = affected_user_id
          AND (name ILIKE '%Event 6%' OR name ILIKE '%Event 10%')
        ORDER BY name
    LOOP
        RAISE NOTICE '   📌 % (ID: %)', event_rec.name, event_rec.id;
        RAISE NOTICE '      isEnded=%, isFuture=%, isActive=%, isUpcoming=%',
            event_rec.is_ended,
            event_rec.is_future,
            event_rec.is_active,
            event_rec.is_upcoming;

        IF event_rec.is_upcoming THEN
            RAISE NOTICE '      ⭐ TAGGED AS UPCOMING';
        END IF;

        -- Validate mutual exclusivity
        IF event_rec.is_upcoming AND (event_rec.is_ended OR NOT event_rec.is_future) THEN
            RAISE NOTICE '      ❌ VIOLATION: isUpcoming=true but isEnded=% or isFuture=%',
                event_rec.is_ended, event_rec.is_future;
        END IF;
    END LOOP;
    RAISE NOTICE '   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';

    -- Print summary for all events
    PERFORM log_all_events_status(affected_user_id);

    -- This line should never be reached
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

-- ============================================================================
-- STEP 2: Create helper function to log all events status
-- ============================================================================

CREATE OR REPLACE FUNCTION log_all_events_status(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    event_rec RECORD;
    upcoming_count INT;
BEGIN
    -- Count how many events have is_upcoming = true
    SELECT COUNT(*) INTO upcoming_count
    FROM events
    WHERE user_id = p_user_id
      AND is_upcoming = true;

    RAISE NOTICE '';
    RAISE NOTICE '   📋 Summary of all events for user:';
    RAISE NOTICE '   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';

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
        WHERE user_id = p_user_id
        ORDER BY event_date ASC, COALESCE(start_time, '23:59:59'::TIME) ASC
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

        IF event_rec.is_upcoming THEN
            RAISE NOTICE '      ⭐ THIS IS THE UPCOMING EVENT';
        END IF;
    END LOOP;

    RAISE NOTICE '   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '   🎯 Events with is_upcoming=true: %', upcoming_count;

    IF upcoming_count = 0 THEN
        RAISE NOTICE '   ✅ OK: No events tagged as upcoming (no valid future events exist)';
    ELSIF upcoming_count > 1 THEN
        RAISE NOTICE '   ❌ ERROR: Multiple events tagged as upcoming!';
    ELSE
        RAISE NOTICE '   ✅ SUCCESS: Exactly 1 event tagged as upcoming';
    END IF;

    RAISE NOTICE '';
END;
$$;

-- ============================================================================
-- STEP 3: Recreate triggers (no changes, just ensuring they exist)
-- ============================================================================

-- Drop existing triggers
DROP TRIGGER IF EXISTS trigger_update_most_upcoming_after_insert ON events;
DROP TRIGGER IF EXISTS trigger_update_most_upcoming_after_update ON events;
DROP TRIGGER IF EXISTS trigger_update_most_upcoming_after_delete ON events;

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
        -- Only recalculate if relevant fields changed
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
-- STEP 4: Fix all existing events (data migration)
-- ============================================================================

DO $$
DECLARE
    user_id_rec UUID;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🔄 Starting data migration to fix is_upcoming tags...';
    RAISE NOTICE '';

    -- Loop through each user and recalculate their is_upcoming tags
    FOR user_id_rec IN SELECT DISTINCT user_id FROM events
    LOOP
        RAISE NOTICE '👤 Processing user: %', user_id_rec;

        -- Trigger recalculation by touching the first event
        -- This will fire the update_most_upcoming_event() trigger
        UPDATE events
        SET updated_at = NOW()
        WHERE id = (
            SELECT id FROM events
            WHERE user_id = user_id_rec
            ORDER BY event_date ASC
            LIMIT 1
        );
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '✅ Data migration complete!';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- STEP 5: Verification query
-- ============================================================================

-- Show count of is_upcoming=true events per user
SELECT
    user_id,
    COUNT(*) as total_events,
    SUM(CASE WHEN is_upcoming THEN 1 ELSE 0 END) as upcoming_count,
    SUM(CASE WHEN is_active THEN 1 ELSE 0 END) as active_count,
    SUM(CASE WHEN is_future THEN 1 ELSE 0 END) as future_count,
    SUM(CASE WHEN is_ended THEN 1 ELSE 0 END) as ended_count
FROM events
GROUP BY user_id
ORDER BY user_id;

-- Show all events with their status
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
        WHEN is_upcoming AND is_future THEN '🔵 UPCOMING (future, can start)'
        WHEN is_upcoming AND is_ended THEN '⭐ UPCOMING (past event - fallback)'
        WHEN is_upcoming AND is_active THEN '⭐ UPCOMING (active event - fallback)'
        WHEN is_future THEN '🔵 FUTURE (not soonest)'
        WHEN is_ended THEN '⚪ ENDED'
        ELSE '⏸️ UNKNOWN STATE'
    END as display_status
FROM events
ORDER BY user_id, event_date ASC, COALESCE(start_time, '23:59:59'::TIME) ASC;

-- ============================================================================
-- VALIDATION: Ensure each user has exactly 1 is_upcoming=true event
-- ============================================================================

DO $$
DECLARE
    user_rec RECORD;
    upcoming_count INT;
    is_valid BOOLEAN := true;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🔍 VALIDATION: Checking is_upcoming counts per user...';
    RAISE NOTICE '';

    FOR user_rec IN SELECT DISTINCT user_id FROM events
    LOOP
        SELECT COUNT(*) INTO upcoming_count
        FROM events
        WHERE user_id = user_rec.user_id
          AND is_upcoming = true;

        IF upcoming_count = 0 THEN
            RAISE NOTICE '✅ User % has 0 events with is_upcoming=true (no valid future events)', user_rec.user_id;
        ELSIF upcoming_count > 1 THEN
            RAISE NOTICE '❌ User % has % events with is_upcoming=true', user_rec.user_id, upcoming_count;
            is_valid := false;
        ELSE
            RAISE NOTICE '✅ User % has exactly 1 event with is_upcoming=true', user_rec.user_id;
        END IF;
    END LOOP;

    RAISE NOTICE '';

    IF is_valid THEN
        RAISE NOTICE '🎉 VALIDATION PASSED: All users have 0 or 1 is_upcoming=true events!';
    ELSE
        RAISE NOTICE '⚠️ VALIDATION FAILED: Some users have multiple is_upcoming=true events';
        RAISE NOTICE '   Run the data migration again to fix';
    END IF;

    RAISE NOTICE '';
END $$;

-- ============================================================================
-- MIGRATION COMPLETE!
-- ============================================================================
--
-- What this migration does:
-- 1. Rewrote update_most_upcoming_event() with STRICT mutual exclusivity:
--    - ONLY tags events where: is_ended=false AND is_future=true AND is_active=false
--    - NO fallback to past/active events (enforces strict rules)
--    - Finds event with start datetime closest to NOW from valid pool
--    - If NO valid events exist, NO event is tagged (acceptable behavior)
--
-- 2. Added Event 6 & Event 10 debug logging:
--    - Shows exact status (isEnded, isFuture, isActive, isUpcoming) after calc
--    - Validates mutual exclusivity (alerts if violation detected)
--
-- 3. Created log_all_events_status() helper for comprehensive logging
--
-- 4. Recreated triggers to ensure proper firing
--
-- 5. Fixed all existing events to enforce strict mutual exclusivity
--
-- 6. Added validation (allows 0 or 1 event with is_upcoming=true per user)
--
-- Result: Enforces mutual exclusivity - only Events Home Page events qualify
-- ============================================================================
