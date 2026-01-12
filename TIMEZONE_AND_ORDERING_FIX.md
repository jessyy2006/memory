# Timezone and Chronological Ordering Fix ✅

## Issues Fixed

### 1. ✅ Timezone Display Problem
**Problem:** Entered date "2026-01-12" displayed as "2026-01-11"
**Root Cause:** Dates were decoded using UTC timezone instead of user's local timezone (EST)

### 2. ✅ Chronological Ordering
**Problem:** Events not sorted with upcoming events first
**Root Cause:** RPC returned all events in simple ascending date order (past → future)

---

## Changes Made

### Fix 1: Timezone Handling (Event.swift)

**Updated 3 decoders to use local timezone:**

#### EventRecord decoder (lines 118-148)
```swift
// BEFORE (UTC):
dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

// AFTER (Local timezone):
dateFormatter.timeZone = TimeZone.current
```

**Applied to:**
- `event_date` decoding (line 122)
- `start_time` decoding (line 133)
- `end_time` decoding (line 144)

#### EventActionResponse decoder (lines 262-271)
```swift
// Fixed mostUpcomingEventDate to use TimeZone.current
```

#### MemoryWithEvent decoder (lines 347-378)
```swift
// Fixed eventDate, eventStartTime, eventEndTime to use TimeZone.current
```

---

### Fix 2: Chronological Ordering (EventService.swift)

**Added custom sorting logic (lines 96-114):**

```swift
// Sort events: upcoming first (soonest first), then past events (most recent first)
let today = Calendar.current.startOfDay(for: Date())
let sortedEvents = events.sorted { event1, event2 in
    let date1 = Calendar.current.startOfDay(for: event1.eventDate)
    let date2 = Calendar.current.startOfDay(for: event2.eventDate)

    let isEvent1Upcoming = date1 >= today
    let isEvent2Upcoming = date2 >= today

    // Both upcoming or both past - sort by date
    if isEvent1Upcoming == isEvent2Upcoming {
        return isEvent1Upcoming ? date1 < date2 : date1 > date2
    }

    // One upcoming, one past - upcoming comes first
    return isEvent1Upcoming
}
```

**Sorting logic:**
1. **Upcoming events first** (date >= today)
   - Within upcoming: soonest first (ascending date)
2. **Past events last** (date < today)
   - Within past: most recent first (descending date)

---

## How It Works Now

### Example Event List

**Today's date:** 2026-01-12

**Events in database:**
- Event A: 2026-01-10 (past, 2 days ago)
- Event B: 2026-01-11 (past, yesterday)
- Event C: 2026-01-13 (upcoming, tomorrow)
- Event D: 2026-01-20 (upcoming, in 8 days)

**Display order (after fixes):**
1. **Event C** - 2026-01-13 (upcoming, soonest)
2. **Event D** - 2026-01-20 (upcoming, later)
3. **Event B** - 2026-01-11 (past, most recent)
4. **Event A** - 2026-01-10 (past, earlier)

---

## Timezone Behavior

### For EST (UTC-5) Users:

**Input:** 2026-01-12
**Stored in DB:** `"2026-01-12"` (PostgreSQL DATE)
**Decoded as:** `2026-01-12 00:00:00 EST`
**Displayed as:** `Jan 12, 2026` ✅

### Before Fix:
**Input:** 2026-01-12
**Stored in DB:** `"2026-01-12"`
**Decoded as:** `2026-01-12 00:00:00 UTC`
**Displayed in EST:** `Jan 11, 2026 19:00 EST` ❌ (off by 5 hours → shows previous day)

---

## Testing the Fix

### Step 1: Clean Build
```
Product → Clean Build Folder (⌘⇧K)
Product → Build (⌘B)
Product → Run (⌘R)
```

### Step 2: Create Multiple Events
Create events with different dates:
- One past event (e.g., yesterday)
- One today
- One tomorrow
- One next week

### Step 3: Verify Timezone
- Event entered as `2026-01-12` should display as `Jan 12, 2026` (NOT Jan 11)
- Times should show in your local timezone (EST)

### Step 4: Verify Ordering
Events should appear in this order:
1. Tomorrow's event (upcoming, soonest)
2. Next week's event (upcoming, later)
3. Today's event (if past midnight, shows as past)
4. Yesterday's event (past, most recent)

---

## Console Output

When loading events, you should see:
```
🔍 [EventService] Fetching events for user: <uuid>
🔍 [EventService] Calling RPC: get_events_sorted
✅ [EventService] RPC returned 4 events
📅 [EventService] Events sorted: upcoming first (soonest → latest), then past
📥 [EventsHomeView] Received 4 events from EventService
✅ [EventsHomeView] UI Updated - Displaying 4 events
📋 [EventsHomeView] Event List:
   1. Tomorrow Event
      - Date: 2026-01-13 00:00:00 +0000
      - is_upcoming: true
   2. Next Week Event
      - Date: 2026-01-20 00:00:00 +0000
      - is_upcoming: true
   3. Yesterday Event
      - Date: 2026-01-11 00:00:00 +0000
      - is_upcoming: false
```

---

## Files Modified

| File | Lines | What Changed |
|------|-------|--------------|
| Event.swift | 122 | EventRecord: event_date uses TimeZone.current |
| Event.swift | 133 | EventRecord: start_time uses TimeZone.current |
| Event.swift | 144 | EventRecord: end_time uses TimeZone.current |
| Event.swift | 267 | EventActionResponse: mostUpcomingEventDate uses TimeZone.current |
| Event.swift | 352 | MemoryWithEvent: eventDate uses TimeZone.current |
| Event.swift | 363 | MemoryWithEvent: eventStartTime uses TimeZone.current |
| Event.swift | 374 | MemoryWithEvent: eventEndTime uses TimeZone.current |
| EventService.swift | 96-114 | Added custom sorting logic for chronological display |

---

## Why TimeZone.current?

**TimeZone.current** = The user's device timezone setting
- If user is in EST: TimeZone.current = EST (UTC-5)
- If user is in PST: TimeZone.current = PST (UTC-8)
- If user is in GMT: TimeZone.current = GMT (UTC+0)

This ensures dates display correctly regardless of where the user is located.

---

## Expected Behavior After Fix

✅ **Dates match what user enters**
- Enter: Jan 12, 2026 → Display: Jan 12, 2026

✅ **Times match user's timezone**
- If in EST, times show in EST
- If in PST, times show in PST

✅ **Events sorted chronologically**
- Upcoming events first (soonest → latest)
- Past events last (most recent → earliest)

✅ **"Closest to occurring" appears at top**
- The soonest upcoming event is always #1 in the list
