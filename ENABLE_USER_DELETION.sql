-- ============================================================================
-- ENABLE USER DELETION IN SUPABASE DASHBOARD
-- ============================================================================
-- Problem: "Failed to delete user: Database error deleting user"
-- Root Cause: Supabase's user deletion process needs proper permissions
--
-- Solution:
-- 1. Create a function that handles CASCADE deletion properly
-- 2. Grant necessary permissions to auth schema
-- 3. Ensure RLS policies don't block deletion
-- ============================================================================

-- ============================================================================
-- STEP 1: Verify foreign key constraints have CASCADE
-- ============================================================================

-- Check current foreign key constraints
SELECT
    conname AS constraint_name,
    conrelid::regclass AS table_name,
    confrelid::regclass AS referenced_table,
    confdeltype AS on_delete_action,
    CASE confdeltype
        WHEN 'c' THEN 'CASCADE'
        WHEN 'n' THEN 'SET NULL'
        WHEN 'r' THEN 'RESTRICT'
        WHEN 'a' THEN 'NO ACTION'
        ELSE confdeltype::text
    END as on_delete_action_readable
FROM pg_constraint
WHERE confrelid = 'auth.users'::regclass
ORDER BY conrelid::regclass::text;

-- ============================================================================
-- STEP 2: Ensure CASCADE delete is set for all user-related tables
-- ============================================================================

-- Drop and recreate foreign key constraints with CASCADE (if not already set)

-- For events table
DO $$
BEGIN
    -- Drop existing constraint if it exists
    ALTER TABLE events DROP CONSTRAINT IF EXISTS events_user_id_fkey;

    -- Add constraint with CASCADE delete
    ALTER TABLE events
        ADD CONSTRAINT events_user_id_fkey
        FOREIGN KEY (user_id)
        REFERENCES auth.users(id)
        ON DELETE CASCADE;

    RAISE NOTICE 'Updated events foreign key constraint';
END $$;

-- For memories table
DO $$
BEGIN
    -- Drop existing constraint if it exists
    ALTER TABLE memories DROP CONSTRAINT IF EXISTS memories_user_id_fkey;

    -- Add constraint with CASCADE delete
    ALTER TABLE memories
        ADD CONSTRAINT memories_user_id_fkey
        FOREIGN KEY (user_id)
        REFERENCES auth.users(id)
        ON DELETE CASCADE;

    RAISE NOTICE 'Updated memories foreign key constraint';
END $$;

-- ============================================================================
-- STEP 3: Grant necessary permissions for deletion
-- ============================================================================

-- Grant DELETE permission on all tables to authenticated users
GRANT DELETE ON events TO authenticated;
GRANT DELETE ON memories TO authenticated;

-- Grant usage on schemas
GRANT USAGE ON SCHEMA public TO authenticated;

-- ============================================================================
-- STEP 4: Update RLS policies to allow deletion by user
-- ============================================================================

-- Drop existing DELETE policies if they exist
DROP POLICY IF EXISTS "Users can delete their own events" ON events;
DROP POLICY IF EXISTS "Users can delete their own memories" ON memories;

-- Create new DELETE policies
CREATE POLICY "Users can delete their own events"
    ON events
    FOR DELETE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own memories"
    ON memories
    FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================================================
-- STEP 5: Create helper function for admin user deletion (optional)
-- ============================================================================

-- This function allows admins to delete users programmatically
CREATE OR REPLACE FUNCTION delete_user_and_data(user_id_to_delete UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Delete memories (should cascade via foreign key)
    DELETE FROM memories WHERE user_id = user_id_to_delete;

    -- Delete events (should cascade via foreign key)
    DELETE FROM events WHERE user_id = user_id_to_delete;

    -- Delete from auth.users (if you have permission)
    -- Note: This usually requires service role, not available in normal functions
    -- DELETE FROM auth.users WHERE id = user_id_to_delete;

    RAISE NOTICE 'Deleted all data for user: %', user_id_to_delete;
END;
$$;

-- Grant execute permission to authenticated users (optional - restrict as needed)
-- GRANT EXECUTE ON FUNCTION delete_user_and_data(UUID) TO authenticated;

-- ============================================================================
-- STEP 6: Verify setup
-- ============================================================================

-- Check foreign key constraints are CASCADE
SELECT
    conname AS constraint_name,
    conrelid::regclass AS table_name,
    CASE confdeltype
        WHEN 'c' THEN '✅ CASCADE'
        WHEN 'n' THEN 'SET NULL'
        WHEN 'r' THEN '❌ RESTRICT'
        WHEN 'a' THEN '❌ NO ACTION'
        ELSE confdeltype::text
    END as on_delete_action
FROM pg_constraint
WHERE confrelid = 'auth.users'::regclass
ORDER BY conrelid::regclass::text;

-- Check RLS policies
SELECT
    schemaname,
    tablename,
    policyname,
    cmd AS command,
    qual AS using_expression
FROM pg_policies
WHERE tablename IN ('events', 'memories')
  AND cmd = 'DELETE'
ORDER BY tablename, policyname;

-- ============================================================================
-- MIGRATION COMPLETE!
-- ============================================================================
--
-- What This Does:
-- 1. Ensures all foreign keys use ON DELETE CASCADE
-- 2. Grants DELETE permissions to authenticated users
-- 3. Creates RLS policies allowing users to delete their own data
-- 4. Provides a helper function for programmatic deletion
--
-- How to Delete a User from Supabase Dashboard:
-- 1. Go to Authentication → Users
-- 2. Click the user you want to delete
-- 3. Click "Delete user"
-- 4. The CASCADE will automatically delete all events and memories
--
-- If you still get errors:
-- - Make sure you're using the service role key (not anon key)
-- - Check Supabase logs for specific error messages
-- - Try using the delete_user_and_data() function as a workaround
-- ============================================================================
