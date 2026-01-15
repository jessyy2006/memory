# Testing Guide: Memory-Event Data Isolation Fix

## Quick Start Testing

### Prerequisites
1. Run the SQL migration: `FIX_MEMORY_EVENT_ISOLATION.sql` in Supabase SQL Editor
2. Build the XCode project: `⌘ + B`
3. Launch the app in simulator: `⌘ + R`

---

## Test Scenario 1: Basic Event Isolation

**Goal**: Verify memories from Event A don't appear in Event B

### Steps:
1. **Create and Start Event A**:
   - Tap calendar icon (top right)
   - Tap "Create New Event"
   - Enter name: "Birthday Party"
   - Select today's date
   - Tap "Create"
   - Tap "Start" next to "Birthday Party"
   - Tap "Done"

2. **Add Memories to Event A**:
   - Tap the large "Add Memories" button
   - Verify badge shows "Adding to Event: Birthday Party"
   - Add 3 photos
   - Add 1 note: "Had a great time!"
   - Tap "Play Memories" - should show 4 items

3. **End Event A**:
   - Tap "End Event" (top right)
   - Verify navigates to playback

4. **Create and Start Event B**:
   - Go back to Memories Home
   - Tap calendar icon
   - Create "Graduation" event
   - Start the event

5. **Verify Event B is Empty**:
   - ✅ Memory count should show "0 memories captured"
   - ✅ Photos from "Birthday Party" should NOT appear
   - ✅ Note from "Birthday Party" should NOT appear

6. **Add Memories to Event B**:
   - Add 2 videos
   - Add 1 audio recording
   - ✅ Should show 3 memories (not 7)

7. **Switch Back to Event A**:
   - End "Graduation" event
   - Start "Birthday Party" event again
   - ✅ Should show only 4 memories (3 photos + 1 note)
   - ✅ Videos and audio from "Graduation" should NOT appear

**Expected Result**: ✅ Events are completely isolated - no memory leaks

---

## Test Scenario 2: Deduplication

**Goal**: Verify duplicate memories are prevented

### Steps:
1. Start an event "Test Deduplication"
2. Add a photo (Photo A)
3. Try to add the same photo again (Photo A)
   - ✅ Should show error: "This photo already exists in this event"
4. Add a note: "Hello world"
5. Try to add the same note again
   - ✅ Should show error: "This note already exists in this event"
6. Create a different event "Test 2"
7. Add the same photo (Photo A) to "Test 2"
   - ✅ Should succeed (different event, so not a duplicate)

**Expected Result**: ✅ Duplicates prevented within same event, allowed across events

---

## Test Scenario 3: No Active Event

**Goal**: Verify memories cannot be created without an active event

### Steps:
1. Ensure no event is active (stop any active events)
2. Go to Memories Home screen
3. Observe "Add Memories" button:
   - ✅ Text should say "Start Event First"
   - ✅ Button should be grayed out (50% opacity)
   - ✅ Button should be disabled (tapping does nothing)
4. Tap calendar icon and start an event
5. Observe "Add Memories" button:
   - ✅ Text should change to "Add Memories"
   - ✅ Button should be fully opaque (100%)
   - ✅ Button should be enabled
6. Tap "Add Memories"
   - ✅ Should show media picker
   - ✅ Should display green badge: "Adding to Event: [Event Name]"

**Expected Result**: ✅ Memory creation blocked without active event

---

## Test Scenario 4: Database Verification

**Goal**: Verify database constraints are enforced

### SQL Tests (Run in Supabase SQL Editor):

1. **Verify no NULL event_id**:
```sql
SELECT COUNT(*) as null_count
FROM memories
WHERE event_id IS NULL;
-- Expected: 0
```

2. **Verify unique constraint**:
```sql
-- This should FAIL with unique constraint error
INSERT INTO memories (id, user_id, event_id, type, content, timestamp)
VALUES (
  uuid_generate_v4(),
  '[your-user-id]',
  '[same-event-id]',
  'photo',
  '[same-content-url]',  -- Duplicate content
  NOW()
);
-- Expected: ERROR: duplicate key value violates unique constraint
```

3. **Verify scoped retrieval**:
```sql
-- Get memories for a specific event
SELECT id, type, content, event_id
FROM memories
WHERE user_id = '[your-user-id]'
  AND event_id = '[event-a-id]';
-- Expected: Only memories from Event A

SELECT id, type, content, event_id
FROM memories
WHERE user_id = '[your-user-id]'
  AND event_id = '[event-b-id]';
-- Expected: Only memories from Event B (no overlap with Event A)
```

4. **Verify event ownership validation**:
```sql
-- Try to assign memory to another user's event (should FAIL)
INSERT INTO memories (id, user_id, event_id, type, content, timestamp)
VALUES (
  uuid_generate_v4(),
  '[your-user-id]',
  '[another-users-event-id]',  -- Event owned by different user
  'photo',
  'test.jpg',
  NOW()
);
-- Expected: ERROR: Cannot assign memory to event owned by different user
```

**Expected Result**: ✅ All database constraints enforced

---

## Test Scenario 5: Edge Cases

### Test 5.1: Rapid Event Switching
1. Create 3 events: A, B, C
2. Start Event A, add 1 photo
3. End Event A, start Event B, add 1 video
4. End Event B, start Event C, add 1 note
5. Switch back to Event A
   - ✅ Should show only 1 photo
6. Switch to Event B
   - ✅ Should show only 1 video
7. Switch to Event C
   - ✅ Should show only 1 note

### Test 5.2: Event Deletion
1. Create Event "Delete Test"
2. Add 5 memories
3. Delete the event from Supabase:
```sql
DELETE FROM events WHERE id = '[delete-test-event-id]';
```
4. Verify memories are cascade deleted:
```sql
SELECT COUNT(*) FROM memories WHERE event_id = '[delete-test-event-id]';
-- Expected: 0 (cascade delete worked)
```

### Test 5.3: New User (No Events)
1. Create a new user account
2. Go to Memories Home
   - ✅ "Add Memories" button should be disabled
   - ✅ Should prompt to create first event
3. Create first event and start it
   - ✅ Button should enable
   - ✅ Can add memories successfully

**Expected Result**: ✅ All edge cases handled correctly

---

## Test Scenario 6: Performance Testing

### Test 6.1: Large Event (100+ Memories)
1. Create event "Large Event"
2. Add 100+ memories (use script or manually)
3. Measure load time for `fetchLocalMemories()`
4. Switch to different event
5. Switch back to "Large Event"
   - ✅ Should load quickly (composite index helps)
   - ✅ Should show all 100+ memories
   - ✅ No memories from other events

### Test 6.2: Multiple Events (10+ Events)
1. Create 10 events
2. Add 10 memories to each event
3. Switch between events rapidly
   - ✅ Each event shows only its 10 memories
   - ✅ No performance degradation
   - ✅ No memory leaks between events

**Expected Result**: ✅ Performance remains good with large datasets

---

## Console Output Verification

### Expected Log Messages:

**When starting an event and loading memories**:
```
🔍 [SupabaseManager] Fetching memories for user [uuid] in event [uuid]
✅ [SupabaseManager] Fetched 4 memories for event [uuid]
✅ Fetched 4 local memories for user [uuid] in event [uuid]
```

**When creating a memory**:
```
🔍 [Photo] Checking Supabase session...
✅ [Photo] Active session found for user: [uuid]
📝 [Photo] Attempting to create memory for user: [uuid]
📤 Uploading Photo to: memories/[filename] (12345 bytes)
✅ Upload complete: https://[url]
✅ Memory created: Photo
✅ Fetched 5 local memories for user [uuid] in event [uuid]
```

**When duplicate is detected**:
```
⚠️ Duplicate memory detected: content '[url]' already exists in event [uuid]
⚠️ [Photo] Duplicate detected - skipping creation
Error: This photo already exists in this event
```

**When no active event**:
```
⚠️ No active or selected event - memories will not be loaded
```

---

## Regression Testing

### Before Deploying, Test:
- [ ] User authentication still works
- [ ] Event creation/deletion still works
- [ ] Media upload/download still works
- [ ] Photo picker still works
- [ ] Video recorder still works
- [ ] Note editor still works
- [ ] Audio recorder still works
- [ ] Memory playback still works
- [ ] Past events view still works
- [ ] Profile management still works

---

## Known Issues & Solutions

### Issue: Build error "Cannot find 'eventId' in scope"
**Solution**: Make sure all view components have been updated to pass `eventId`

### Issue: Runtime error "Unexpectedly found nil while unwrapping Optional"
**Solution**: Check that `activeEvent` exists before accessing `activeEvent.id`

### Issue: SQL migration fails with "event_id cannot be null"
**Solution**: The migration script creates a default "Uncategorized" event first. Run the full script.

### Issue: Duplicate error shows even for different events
**Solution**: Verify deduplication check filters by both `eventId` AND `content`

---

## Success Criteria

All tests must pass before deploying:

- ✅ No memory leaks between events
- ✅ All memories have non-null event_id
- ✅ Duplicates prevented within same event
- ✅ Duplicates allowed across different events
- ✅ Memory creation blocked without active event
- ✅ Database constraints enforced
- ✅ Performance acceptable with large datasets
- ✅ No regression bugs
- ✅ Console logs show correct filtering
- ✅ UI provides clear feedback

---

## Reporting Issues

If tests fail:

1. **Screenshot the error**
2. **Copy console logs**
3. **Note the test scenario**
4. **Check which file was modified**
5. **Verify database migration completed**
6. **Review MEMORY_EVENT_ISOLATION_FIX_COMPLETE.md**

---

**Last Updated**: January 14, 2026
**Tester**: [Your Name]
**Status**: Ready for Testing
