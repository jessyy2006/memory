-- ============================================================================
-- EVENTS FEATURE MIGRATION
-- ============================================================================
-- This migration adds the events table and links it to the memories system.
-- Execute this in your Supabase SQL Editor in the order presented.
-- ============================================================================

-- ============================================================================
-- STEP 1: Create events table
-- ============================================================================

CREATE TABLE events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  event_date DATE NOT NULL,
  start_time TIME,
  end_time TIME,
  is_active BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================================================
-- STEP 2: Create Partial Unique Index
-- ============================================================================
-- Ensures only ONE event per user can have is_active = true

CREATE UNIQUE INDEX idx_events_user_active
  ON events(user_id)
  WHERE is_active = true;

-- ============================================================================
-- STEP 3: Create indexes for performance
-- ============================================================================

CREATE INDEX idx_events_user_id ON events(user_id);
CREATE INDEX idx_events_event_date ON events(event_date);
CREATE INDEX idx_events_user_id_event_date ON events(user_id, event_date);

-- ============================================================================
-- STEP 4: Enable Row Level Security (RLS)
-- ============================================================================

ALTER TABLE events ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- STEP 5: Create RLS Policies for events table
-- ============================================================================

-- Users can view their own events
CREATE POLICY "Users can view their own events"
  ON events FOR SELECT
  USING (auth.uid() = user_id);

-- Users can insert their own events
CREATE POLICY "Users can insert their own events"
  ON events FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own events
CREATE POLICY "Users can update their own events"
  ON events FOR UPDATE
  USING (auth.uid() = user_id);

-- Users can delete their own events
CREATE POLICY "Users can delete their own events"
  ON events FOR DELETE
  USING (auth.uid() = user_id);

-- ============================================================================
-- STEP 6: Update memories table to add event_id foreign key
-- ============================================================================

ALTER TABLE memories
  ADD COLUMN event_id UUID REFERENCES events(id) ON DELETE SET NULL;

-- Create index for efficient joins
CREATE INDEX idx_memories_event_id ON memories(event_id);

-- ============================================================================
-- STEP 7: Stored Procedure - Get Most Upcoming Event
-- ============================================================================
-- Returns the "most upcoming" event (minimum event_date >= CURRENT_DATE)

CREATE OR REPLACE FUNCTION get_most_upcoming_event(p_user_id UUID)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  name TEXT,
  event_date DATE,
  start_time TIME,
  end_time TIME,
  is_active BOOLEAN,
  created_at TIMESTAMP WITH TIME ZONE,
  updated_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id,
    e.user_id,
    e.name,
    e.event_date,
    e.start_time,
    e.end_time,
    e.is_active,
    e.created_at,
    e.updated_at
  FROM events e
  WHERE e.user_id = p_user_id
    AND e.event_date >= CURRENT_DATE
  ORDER BY e.event_date ASC
  LIMIT 1;
END;
$$;

-- ============================================================================
-- STEP 8: Stored Procedure - Start Event (with validation)
-- ============================================================================
-- Sets is_active = true ONLY for the most upcoming event

CREATE OR REPLACE FUNCTION start_event(p_event_id UUID, p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_most_upcoming_id UUID;
  v_event_date DATE;
  v_result JSON;
BEGIN
  -- Get the most upcoming event ID for this user
  SELECT id INTO v_most_upcoming_id
  FROM events
  WHERE user_id = p_user_id
    AND event_date >= CURRENT_DATE
  ORDER BY event_date ASC
  LIMIT 1;

  -- Check if the requested event is the most upcoming one
  IF v_most_upcoming_id IS NULL THEN
    v_result := json_build_object(
      'success', false,
      'error', 'No upcoming events found'
    );
    RETURN v_result;
  END IF;

  IF v_most_upcoming_id != p_event_id THEN
    -- Get the event_date of the most upcoming event for the error message
    SELECT event_date INTO v_event_date
    FROM events
    WHERE id = v_most_upcoming_id;

    v_result := json_build_object(
      'success', false,
      'error', 'Can only start the most upcoming event',
      'most_upcoming_event_id', v_most_upcoming_id,
      'most_upcoming_event_date', v_event_date
    );
    RETURN v_result;
  END IF;

  -- Deactivate all events for this user (ensures only one is active)
  UPDATE events
  SET is_active = false,
      updated_at = NOW()
  WHERE user_id = p_user_id;

  -- Activate the most upcoming event
  UPDATE events
  SET is_active = true,
      updated_at = NOW()
  WHERE id = p_event_id
    AND user_id = p_user_id;

  v_result := json_build_object(
    'success', true,
    'event_id', p_event_id
  );

  RETURN v_result;
END;
$$;

-- ============================================================================
-- STEP 9: Stored Procedure - Stop Event
-- ============================================================================
-- Sets is_active = false for the specified event

CREATE OR REPLACE FUNCTION stop_event(p_event_id UUID, p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
  v_rows_updated INT;
BEGIN
  -- Deactivate the event
  UPDATE events
  SET is_active = false,
      updated_at = NOW()
  WHERE id = p_event_id
    AND user_id = p_user_id;

  GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

  IF v_rows_updated = 0 THEN
    v_result := json_build_object(
      'success', false,
      'error', 'Event not found or already inactive'
    );
  ELSE
    v_result := json_build_object(
      'success', true,
      'event_id', p_event_id
    );
  END IF;

  RETURN v_result;
END;
$$;

-- ============================================================================
-- STEP 10: Stored Procedure - Get Events Sorted
-- ============================================================================
-- Returns all events for a user, sorted by event_date (ascending)

CREATE OR REPLACE FUNCTION get_events_sorted(p_user_id UUID)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  name TEXT,
  event_date DATE,
  start_time TIME,
  end_time TIME,
  is_active BOOLEAN,
  is_upcoming BOOLEAN,
  created_at TIMESTAMP WITH TIME ZONE,
  updated_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id,
    e.user_id,
    e.name,
    e.event_date,
    e.start_time,
    e.end_time,
    e.is_active,
    (e.event_date >= CURRENT_DATE) as is_upcoming,
    e.created_at,
    e.updated_at
  FROM events e
  WHERE e.user_id = p_user_id
  ORDER BY e.event_date ASC;
END;
$$;

-- ============================================================================
-- STEP 11: Trigger - Auto-update updated_at timestamp
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_events_updated_at
  BEFORE UPDATE ON events
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- STEP 12: View - Memories with Event Details (for efficient joins)
-- ============================================================================

CREATE OR REPLACE VIEW memories_with_events AS
SELECT
  m.id,
  m.user_id,
  m.type,
  m.content,
  m.thumbnail_url,
  m.duration,
  m.timestamp,
  m.created_at,
  m.updated_at,
  m.event_id,
  e.name as event_name,
  e.event_date,
  e.start_time as event_start_time,
  e.end_time as event_end_time,
  e.is_active as event_is_active
FROM memories m
LEFT JOIN events e ON m.event_id = e.id;

-- ============================================================================
-- MIGRATION COMPLETE!
-- ============================================================================
-- Next steps:
-- 1. Update your Swift models to include Event model
-- 2. Update MemoryRecord/MemoryInsert to include event_id
-- 3. Create EventService in Swift to interact with these functions
-- 4. Update SupabaseConfig.swift to include "events" table name
-- ============================================================================
