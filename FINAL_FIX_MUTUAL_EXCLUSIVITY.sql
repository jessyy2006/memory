-- ============================================================================
-- FINAL FIX: Enforce Strict Mutual Exclusivity for is_upcoming
-- ============================================================================
-- Problem: Event 6 (ended event) is STILL being marked as isUpcoming = true
-- Root Cause: Multiple migration files exist with conflicting logic
-- Solution: This is the FINAL, DEFINITIVE fix - run ONLY this file
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
-- STEP 1: Rewrite update_most_upcoming_event() with STRICT mutual exclusivity
-- ============================================================================

CREATE OR REPLACE FUNCTION update_most_upcoming_event()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    affected_user_id UUID;
    most_upcoming_event_id UUID;
    event_count INT;
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
        SELECT id, name, event_date, start_time, is_ended, is_future, is_active, is_upcoming
        FROM events
        WHERE user_id = affected_user_id
          AND (name ILIKE '%Event 6%' OR name ILIKE '%Event 10%')
        ORDER BY name
    LOOP
        RAISE NOTICE '   📌 % (ID: %)', event_rec.name, event_rec.id;
        RAISE NOTICE '      Date: % | Start: %',
            event_rec.event_date,
            COALESCE(event_rec.start_time::TEXT, 'none');
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

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

-- ============================================================================
-- STEP 2: Ensure helper function exists
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
-- STEP 3: Force recalculation for all users NOW
-- ============================================================================

DO $$
DECLARE
    user_id_rec RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🔄 FORCING recalculation of is_upcoming tags for ALL users...';
    RAISE NOTICE '';

    -- Loop through each user and recalculate their is_upcoming tags
    FOR user_id_rec IN SELECT DISTINCT user_id FROM events
    LOOP
        RAISE NOTICE '👤 Processing user: %', user_id_rec.user_id;

        -- Trigger recalculation by touching the first event
        -- This will fire the update_most_upcoming_event() trigger
        UPDATE events
        SET updated_at = NOW()
        WHERE id = (
            SELECT id FROM events
            WHERE user_id = user_id_rec.user_id
            ORDER BY event_date ASC
            LIMIT 1
        );
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '✅ Recalculation complete!';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- STEP 4: Show current state of Event 6 and Event 10
-- ============================================================================

DO $$
DECLARE
    event_rec RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '🔍 CURRENT STATE - Event 6 & Event 10:';
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
        RAISE NOTICE '📌 % (ID: %)', event_rec.name, event_rec.id;
        RAISE NOTICE '   Date: %', event_rec.event_date;
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

        IF event_rec.is_upcoming THEN
            RAISE NOTICE '   ⭐ THIS EVENT IS TAGGED AS UPCOMING';

            -- Check for violation
            IF event_rec.is_ended OR NOT event_rec.is_future THEN
                RAISE NOTICE '   ❌❌❌ VIOLATION DETECTED! ❌❌❌';
                RAISE NOTICE '   This event should NOT be upcoming!';
                RAISE NOTICE '   Reason: isEnded=% OR isFuture=%',
                    event_rec.is_ended, event_rec.is_future;
            END IF;
        END IF;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- MIGRATION COMPLETE!
-- ============================================================================
--
-- This migration:
-- 1. Rewrites update_most_upcoming_event() with STRICT mutual exclusivity
-- 2. Forces immediate recalculation for all users
-- 3. Shows detailed debug output for Event 6 and Event 10
-- 4. Validates mutual exclusivity rules
--
-- Expected Result:
-- - Event 6 (ended): isUpcoming = false
-- - Event 10 (future): isUpcoming = true
-- ============================================================================
