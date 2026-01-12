# Fix Event Starting & Memory Schema

## Issue 1: Cannot Start Events

**Problem:** Event starting might fail due to timezone mismatch between client and database.

**Root Cause:**
- Database uses `CURRENT_DATE` (UTC timezone)
- Client sorting uses `TimeZone.current` (user's local timezone)
- This causes "most upcoming event" to differ between client and server

**Example:**
- Time: 11 PM EST on Jan 12, 2026
- Database (UTC): CURRENT_DATE = Jan 13, 2026
- User event date: Jan 13, 2026
- Database thinks this is "today", but client thinks it's "tomorrow"

**When user tries to start:**
- Database: "This is the most upcoming event" ✅
- But timezone calculations might cause unexpected behavior

---

## Issue 2: memories vs memories_with_events

### Current State:
- **`memories` table** - Stores actual memory records
- **`memories_with_events` VIEW** - NOT a table! Just a query that joins memories + events

### Your Point (Correct!):
Every memory SHOULD be linked to ONE and ONLY ONE event.

### Current Problem:
```sql
ALTER TABLE memories
  ADD COLUMN event_id UUID REFERENCES events(id) ON DELETE SET NULL;
```

`event_id` is **NULL**able - memories can exist without an event ❌

### Solution:
Make `event_id` **NOT NULL** and **REQUIRED**.

---

## SQL Fix for Supabase

Run this in your **Supabase SQL Editor**:

```sql
-- Step 1: Ensure all existing memories have an event_id
-- (If you have memories without events, you'll need to assign them first)

-- Step 2: Make event_id NOT NULL
ALTER TABLE memories
  ALTER COLUMN event_id SET NOT NULL;

-- Step 3: Add a comment for clarity
COMMENT ON COLUMN memories.event_id IS 'Every memory must be linked to exactly one event';
```

**⚠️ Warning:** This will FAIL if you have any memories with `event_id = NULL`.

If you get an error, first run:
```sql
-- Check for memories without events
SELECT COUNT(*) FROM memories WHERE event_id IS NULL;
```

If there are any, you need to either:
1. Delete them: `DELETE FROM memories WHERE event_id IS NULL;`
2. Or assign them to an event

---

## Swift Code Changes Needed

### 1. Update MemoryInsert to REQUIRE event_id

**File:** `Memory/Models/Memory.swift`

Find the `MemoryInsert` struct and ensure `event_id` is NOT optional:

```swift
struct MemoryInsert: Encodable {
    let id: String
    let userId: String
    let type: String
    let content: String
    let thumbnailUrl: String?
    let duration: Double?
    let timestamp: String
    let eventId: String  // ✅ NOT optional!

    enum CodingKeys: String, CodingKey {
        // ...
        case eventId = "event_id"
    }
}
```

### 2. Update Memory Creation to Require Event

All memory creation must now include an event_id:

```swift
// Before (optional):
let memory = Memory(type: .photo, content: url, eventId: nil)  // ❌ No longer allowed

// After (required):
let memory = Memory(type: .photo, content: url, eventId: activeEvent.id)  // ✅ Required
```

---

## Testing the Fix

### Test Event Starting:
1. Create an event for tomorrow
2. Try to start it
3. Check console for any errors
4. Should navigate to MemoriesHomeView

### Test Memory Creation:
1. Start an event
2. Add a memory (photo/video/note)
3. Memory should be automatically linked to the active event
4. Verify in Supabase that `event_id` is populated

---

## Next Steps

**Do you want me to:**
1. ✅ Add detailed logging to event starting to diagnose the issue?
2. ✅ Update Memory models to make event_id required?
3. ✅ Check if there are existing memories without events?

Let me know and I'll implement the fixes!
