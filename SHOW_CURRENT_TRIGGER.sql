-- ============================================================================
-- SHOW CURRENT TRIGGER FUNCTION
-- ============================================================================
-- This will display the actual function currently running in the database
-- ============================================================================

-- Show the current calculate_event_status() function definition
SELECT
    p.proname AS function_name,
    pg_get_functiondef(p.oid) AS function_definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'calculate_event_status'
  AND n.nspname = 'public';

-- Show all triggers on the events table
SELECT
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'events'
  AND trigger_schema = 'public'
ORDER BY trigger_name;
