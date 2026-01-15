# is_upcoming Assignment Logic - Visual Flowchart

## 🎯 Rule: Exactly 1 Event Must Have is_upcoming = true

```
┌─────────────────────────────────────────────────────────────┐
│  TRIGGER: After INSERT/UPDATE/DELETE on events table        │
│  Function: update_most_upcoming_event()                     │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Step 1: Clear is_upcoming for ALL user's events            │
│  UPDATE events SET is_upcoming = false WHERE user_id = ?    │
└─────────────────────────────────────────────────────────────┘
                            ↓
                   ┌────────────────┐
                   │  Does user     │
                   │  have events?  │
                   └────────┬───────┘
                            │
                    ┌───────┴────────┐
                    │ NO             │ YES
                    ↓                ↓
           ┌─────────────┐     ┌────────────────────────┐
           │   EXIT      │     │  PRIORITY 1:           │
           │  (nothing   │     │  Find soonest          │
           │   to tag)   │     │  FUTURE event          │
           └─────────────┘     │                        │
                               │  WHERE:                │
                               │  • is_ended = false    │
                               │  • is_active = false   │
                               │  • is_future = true    │
                               │                        │
                               │  ORDER BY:             │
                               │  • event_date ASC      │
                               │  • start_time ASC      │
                               │                        │
                               │  LIMIT 1               │
                               └────────┬───────────────┘
                                        │
                               ┌────────┴────────┐
                               │   Found event?  │
                               └────────┬────────┘
                                        │
                        ┌───────────────┼───────────────┐
                        │ YES           │               │ NO
                        ↓               │               ↓
        ┌───────────────────────┐       │    ┌────────────────────────┐
        │  Set is_upcoming=true │       │    │  PRIORITY 2:           │
        │  on this event        │       │    │  Find ACTIVE event     │
        │                       │       │    │                        │
        │  ✅ SUCCESS!          │       │    │  WHERE:                │
        │  (Normal case)        │       │    │  • is_active = true    │
        └───────────────────────┘       │    │                        │
                                        │    │  ORDER BY:             │
                                        │    │  • event_date ASC      │
                                        │    │  • start_time ASC      │
                                        │    │                        │
                                        │    │  LIMIT 1               │
                                        │    └────────┬───────────────┘
                                        │             │
                                        │    ┌────────┴────────┐
                                        │    │   Found event?  │
                                        │    └────────┬────────┘
                                        │             │
                                        │   ┌─────────┼─────────┐
                                        │   │ YES     │         │ NO
                                        │   ↓         │         ↓
                        ┌───────────────────────┐     │  ┌────────────────────────┐
                        │  Set is_upcoming=true │     │  │  PRIORITY 3:           │
                        │  on active event      │     │  │  Find most recent      │
                        │                       │     │  │  PAST event            │
                        │  ✅ SUCCESS!          │     │  │                        │
                        │  (Fallback)           │     │  │  WHERE:                │
                        └───────────────────────┘     │  │  • is_ended = true     │
                                                      │  │                        │
                                                      │  │  ORDER BY:             │
                                                      │  │  • event_date DESC     │
                                                      │  │  • start_time DESC     │
                                                      │  │                        │
                                                      │  │  LIMIT 1               │
                                                      │  └────────┬───────────────┘
                                                      │           │
                                                      │  ┌────────┴────────┐
                                                      │  │   Found event?  │
                                                      │  └────────┬────────┘
                                                      │           │
                                                      │   ┌───────┼───────┐
                                                      │   │ YES   │       │ NO
                                                      │   ↓       │       ↓
                                      ┌───────────────────────┐   │  ┌────────────────────────┐
                                      │  Set is_upcoming=true │   │  │  PRIORITY 4:           │
                                      │  on most recent       │   │  │  Find ANY event        │
                                      │  past event           │   │  │                        │
                                      │                       │   │  │  ORDER BY:             │
                                      │  ✅ SUCCESS!          │   │  │  • event_date ASC      │
                                      │  (Fallback)           │   │  │  • start_time ASC      │
                                      └───────────────────────┘   │  │                        │
                                                                  │  │  LIMIT 1               │
                                                                  │  └────────┬───────────────┘
                                                                  │           │
                                                                  │  ┌────────┴────────┐
                                                                  │  │   Found event?  │
                                                                  │  └────────┬────────┘
                                                                  │           │
                                                                  │   ┌───────┼────────┐
                                                                  │   │ YES   │        │ NO
                                                                  │   ↓       │        ↓
                                                  ┌───────────────────────┐   │   ┌─────────────────┐
                                                  │  Set is_upcoming=true │   │   │  ❌ ERROR       │
                                                  │  on ANY event         │   │   │  This should    │
                                                  │                       │   │   │  never happen   │
                                                  │  ⚠️ WARNING!          │   │   └─────────────────┘
                                                  │  (Should not happen)  │   │
                                                  └───────────────────────┘   │
                                                                              │
                                        ┌─────────────────────────────────────┘
                                        ↓
                        ┌───────────────────────────────────────┐
                        │  Log all events status                │
                        │  (Summary with ⭐ on upcoming event)  │
                        └───────────────────────────────────────┘
                                        ↓
                        ┌───────────────────────────────────────┐
                        │  Validate: Exactly 1 event has        │
                        │  is_upcoming = true                   │
                        └───────────────────────────────────────┘
                                        ↓
                                   ┌────────┐
                                   │  DONE  │
                                   └────────┘
```

## 📊 Priority Breakdown

| Priority | Condition | When Used | Example |
|----------|-----------|-----------|---------|
| **1** | Future event exists | Normal case | User has events on Jan 20, Jan 25 → Tag Jan 20 |
| **2** | Active event exists, no future | User started only event | User started "Birthday Party" → Tag it |
| **3** | Past event exists, no future/active | All events ended | Events on Jan 10, Jan 15 ended → Tag Jan 15 |
| **4** | ANY event exists | Emergency fallback | Should never happen |

## 🔄 State Transitions

### Scenario 1: Creating Events in Order

```
Timeline: Jan 15 → Jan 20 → Jan 25

Step 1: Create Event A (Jan 20)
├─ Events: [A(Jan 20)]
└─ Result: A.is_upcoming = true ✅

Step 2: Create Event B (Jan 25)
├─ Events: [A(Jan 20), B(Jan 25)]
└─ Result: A.is_upcoming = true, B.is_upcoming = false ✅

Step 3: Create Event C (Jan 15) ← Earlier!
├─ Events: [C(Jan 15), A(Jan 20), B(Jan 25)]
└─ Result: C.is_upcoming = true, A.is_upcoming = false, B.is_upcoming = false ✅
```

### Scenario 2: Starting Events

```
Events: [C(Jan 15), A(Jan 20), B(Jan 25)]
Initial: C.is_upcoming = true

Step 1: Start Event C
├─ C becomes active
└─ Result: C.is_upcoming = false, A.is_upcoming = true ✅

Step 2: End Event C
├─ C becomes ended
└─ Result: C.is_upcoming = false, A.is_upcoming = true ✅ (stays same)

Step 3: Start Event A
├─ A becomes active
└─ Result: A.is_upcoming = false, B.is_upcoming = true ✅
```

### Scenario 3: All Events Ended (Fallback)

```
Events: [C(Jan 15, ended), A(Jan 20, ended), B(Jan 25, ended)]

Priority 1: ❌ No future events
Priority 2: ❌ No active events
Priority 3: ✅ Tag most recent past event

Result: B.is_upcoming = true ✅ (Jan 25 is most recent)
```

## 🎨 UI Behavior Based on is_upcoming

```
┌─────────────────────────────────────────────────────────┐
│  Event Card Display Logic                               │
└─────────────────────────────────────────────────────────┘

is_upcoming = true + is_future = true
  ├─ Badge: 🔵 "Upcoming"
  ├─ Text: "Tap to start this event"
  └─ Action: Show "Start Event" dialog ✅

is_upcoming = false + is_future = true
  ├─ Badge: 🔵 "Upcoming"
  ├─ Text: "Tap to start this event"
  └─ Action: Show "Patience! You have other events to go to first" ❌

is_upcoming = true + is_ended = true (Fallback)
  ├─ Badge: ⚪ "Ended"
  ├─ Text: "Tap to view memories"
  └─ Action: Navigate to memories playback ✅

is_upcoming = false + is_ended = true
  ├─ Badge: ⚪ "Ended"
  ├─ Text: "Tap to view memories"
  └─ Action: Navigate to memories playback ✅
```

## 🐛 Debugging Decision Tree

```
Problem: "Patience" alert shows on all events
    ↓
Check: How many events have is_upcoming = true?
    ├─ 0 events
    │   └─ Fix: Run UPDATE to trigger recalculation
    ├─ 1 event (correct)
    │   └─ Check: Is user tapping the right event?
    └─ 2+ events
        └─ Fix: Clear all, then run UPDATE to recalculate

Problem: Wrong event has is_upcoming = true
    ↓
Check: Event dates and times
    ├─ Database has wrong data
    │   └─ Fix: Update event dates
    └─ Database is correct
        └─ Fix: Run UPDATE to trigger recalculation

Problem: User can't start any event
    ↓
Check: is_upcoming status
    ├─ Correct event has is_upcoming = true
    │   └─ Check: Is there already an active event?
    └─ Wrong event has is_upcoming = true
        └─ Fix: Run UPDATE to trigger recalculation
```

## 📝 SQL Commands for Manual Fixes

### Check is_upcoming count per user
```sql
SELECT
    user_id,
    COUNT(*) as total_events,
    SUM(CASE WHEN is_upcoming THEN 1 ELSE 0 END) as upcoming_count
FROM events
GROUP BY user_id;
```

### Fix specific user
```sql
-- Trigger recalculation
UPDATE events
SET updated_at = NOW()
WHERE user_id = '<user-id>'
LIMIT 1;
```

### Check which event has is_upcoming = true
```sql
SELECT name, event_date, is_upcoming
FROM events
WHERE user_id = '<user-id>'
ORDER BY event_date ASC;
```

---

**Last Updated**: January 15, 2026
**Version**: 3.0 (4-Priority Fallback System)
