-- ============================================================================
-- FIX MEMORY-EVENT DATA ISOLATION BUG
-- ============================================================================
-- This migration fixes the critical data isolation bug where memories leak
-- between events by making event_id mandatory and adding deduplication.
--
-- IMPORTANT: Run this migration in your Supabase SQL Editor
-- ============================================================================

-- ============================================================================
-- STEP 1: Create a default "Uncategorized" event for orphaned memories
-- ============================================================================
-- Before we can make event_id NOT NULL, we need to handle existing memories
-- that don't have an event_id assigned.

DO $$
DECLARE
    v_user_id UUID;
    v_default_event_id UUID;
BEGIN
    -- For each user who has memories without event_id, create a default event
    FOR v_user_id IN
        SELECT DISTINCT user_id
        FROM memories
        WHERE event_id IS NULL
    LOOP
        -- Create a default "Uncategorized Memories" event for this user
        INSERT INTO events (user_id, name, event_date, is_active, created_at, updated_at)
        VALUES (
            v_user_id,
            'Uncategorized Memories (Auto-Created)',
            CURRENT_DATE,
            false,
            NOW(),
            NOW()
        )
        RETURNING id INTO v_default_event_id;

        -- Assign all orphaned memories to this default event
        UPDATE memories
        SET event_id = v_default_event_id
        WHERE user_id = v_user_id AND event_id IS NULL;

        RAISE NOTICE 'Created default event % for user %', v_default_event_id, v_user_id;
    END LOOP;
END $$;

-- ============================================================================
-- STEP 2: Make event_id NOT NULL (enforce relational integrity)
-- ============================================================================

-- First, verify there are no NULL event_ids remaining
DO $$
DECLARE
    v_null_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_null_count
    FROM memories
    WHERE event_id IS NULL;

    IF v_null_count > 0 THEN
        RAISE EXCEPTION 'Cannot make event_id NOT NULL: % memories still have NULL event_id', v_null_count;
    END IF;
END $$;

-- Make the column NOT NULL
ALTER TABLE memories
ALTER COLUMN event_id SET NOT NULL;

COMMENT ON COLUMN memories.event_id IS 'Required foreign key to events table. Every memory must belong to an event.';

-- ============================================================================
-- STEP 3: Add unique constraint to prevent duplicate memories per event
-- ============================================================================
-- This prevents the same media from being added twice to the same event

-- Create a unique index on (event_id, content) to prevent duplicates
-- Note: content contains the file URL, so this prevents the same file from being added twice
CREATE UNIQUE INDEX idx_memories_event_content_unique
ON memories(event_id, content);

COMMENT ON INDEX idx_memories_event_content_unique IS 'Prevents duplicate memories (same content) within a single event';

-- ============================================================================
-- STEP 4: Update fetchMemories function to require event_id filtering
-- ============================================================================
-- Create a new function to fetch memories for a specific event

CREATE OR REPLACE FUNCTION get_memories_for_event(p_user_id UUID, p_event_id UUID)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  event_id UUID,
  type TEXT,
  content TEXT,
  thumbnail_url TEXT,
  duration NUMERIC,
  "timestamp" TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE,
  updated_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    m.id,
    m.user_id,
    m.event_id,
    m.type,
    m.content,
    m.thumbnail_url,
    m.duration,
    m."timestamp",
    m.created_at,
    m.updated_at
  FROM memories m
  WHERE m.user_id = p_user_id
    AND m.event_id = p_event_id
  ORDER BY m."timestamp" ASC;
END;
$$;

COMMENT ON FUNCTION get_memories_for_event IS 'Fetches memories scoped to a specific event only';

-- ============================================================================
-- STEP 5: Update the memories_with_events view
-- ============================================================================
-- The view now uses INNER JOIN since event_id is always required

DROP VIEW IF EXISTS memories_with_events;

CREATE OR REPLACE VIEW memories_with_events AS
SELECT
  m.id,
  m.user_id,
  m.type,
  m.content,
  m.thumbnail_url,
  m.duration,
  m."timestamp",
  m.created_at,
  m.updated_at,
  m.event_id,
  e.name as event_name,
  e.event_date,
  e.start_time as event_start_time,
  e.end_time as event_end_time,
  e.is_active as event_is_active
FROM memories m
INNER JOIN events e ON m.event_id = e.id;  -- Changed from LEFT JOIN to INNER JOIN

COMMENT ON VIEW memories_with_events IS 'View joining memories with their required event. Every memory has an event.';

-- ============================================================================
-- STEP 6: Add validation trigger to ensure event_id matches user_id
-- ============================================================================
-- This prevents accidentally assigning a memory to another user's event

CREATE OR REPLACE FUNCTION validate_memory_event_ownership()
RETURNS TRIGGER AS $$
DECLARE
    v_event_user_id UUID;
BEGIN
    -- Get the user_id of the event
    SELECT user_id INTO v_event_user_id
    FROM events
    WHERE id = NEW.event_id;

    -- Check if event exists
    IF v_event_user_id IS NULL THEN
        RAISE EXCEPTION 'Event with id % does not exist', NEW.event_id;
    END IF;

    -- Check if event belongs to the same user as the memory
    IF v_event_user_id != NEW.user_id THEN
        RAISE EXCEPTION 'Cannot assign memory to event owned by different user. Memory user: %, Event user: %',
            NEW.user_id, v_event_user_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_memory_event_ownership_trigger
    BEFORE INSERT OR UPDATE ON memories
    FOR EACH ROW
    EXECUTE FUNCTION validate_memory_event_ownership();

COMMENT ON FUNCTION validate_memory_event_ownership IS 'Ensures memories can only be assigned to events owned by the same user';

-- ============================================================================
-- STEP 7: Create helper function to check for duplicate memories
-- ============================================================================

CREATE OR REPLACE FUNCTION memory_exists_in_event(p_event_id UUID, p_content TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_exists BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1
        FROM memories
        WHERE event_id = p_event_id
          AND content = p_content
    ) INTO v_exists;

    RETURN v_exists;
END;
$$;

COMMENT ON FUNCTION memory_exists_in_event IS 'Checks if a memory with the given content already exists in the event';

-- ============================================================================
-- STEP 8: Update RLS policies for memories to include event validation
-- ============================================================================
-- Users can only view memories from their own events

DROP POLICY IF EXISTS "Users can view their own memories" ON memories;
DROP POLICY IF EXISTS "Users can insert their own memories" ON memories;
DROP POLICY IF EXISTS "Users can update their own memories" ON memories;
DROP POLICY IF EXISTS "Users can delete their own memories" ON memories;

-- View policy: user must own both the memory AND the associated event
CREATE POLICY "Users can view memories from their events"
  ON memories FOR SELECT
  USING (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM events
      WHERE events.id = memories.event_id
        AND events.user_id = auth.uid()
    )
  );

-- Insert policy: user must own the event
CREATE POLICY "Users can insert memories to their events"
  ON memories FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM events
      WHERE events.id = event_id
        AND events.user_id = auth.uid()
    )
  );

-- Update policy: user must own the memory and the event
CREATE POLICY "Users can update their event memories"
  ON memories FOR UPDATE
  USING (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM events
      WHERE events.id = event_id
        AND events.user_id = auth.uid()
    )
  );

-- Delete policy: user must own the memory and the event
CREATE POLICY "Users can delete their event memories"
  ON memories FOR DELETE
  USING (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM events
      WHERE events.id = event_id
        AND events.user_id = auth.uid()
    )
  );

-- ============================================================================
-- STEP 9: Create index for efficient event-scoped queries
-- ============================================================================

-- Composite index for efficient filtering by user_id + event_id
CREATE INDEX IF NOT EXISTS idx_memories_user_event
ON memories(user_id, event_id);

COMMENT ON INDEX idx_memories_user_event IS 'Optimizes queries filtering memories by user and event';

-- ============================================================================
-- MIGRATION COMPLETE!
-- ============================================================================
-- Summary of changes:
-- 1. ✅ event_id is now NOT NULL (mandatory foreign key)
-- 2. ✅ Unique constraint prevents duplicate memories per event
-- 3. ✅ New function get_memories_for_event() for scoped retrieval
-- 4. ✅ Validation trigger ensures event ownership matches
-- 5. ✅ Updated RLS policies enforce event-level isolation
-- 6. ✅ Helper function to check for duplicates
--
-- Next steps:
-- 1. Update Swift Memory model to make eventId non-optional
-- 2. Update all MemoryService methods to require eventId
-- 3. Update UI to only allow memory creation when event is active
-- 4. Update fetch operations to filter by event_id
-- ============================================================================

-- Verification query to check the migration worked
SELECT
    'Memories without event_id' as check_name,
    COUNT(*) as count
FROM memories
WHERE event_id IS NULL

UNION ALL

SELECT
    'Total memories' as check_name,
    COUNT(*) as count
FROM memories

UNION ALL

SELECT
    'Events created' as check_name,
    COUNT(*) as count
FROM events;
