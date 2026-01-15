# Event Status Boolean Logic - Quick Reference Card

## 🎯 Status Fields at a Glance

| Field | Purpose | Count | Set By |
|-------|---------|-------|--------|
| `is_ended` | Event has finished | Many | Time OR User |
| `is_active` | User is adding memories | 1 max | User only |
| `is_future` | Event hasn't ended yet | Many | Time only |
| `is_upcoming` | Next event to start | 1 max | Database |

---

## 📊 Status Truth Table

| Scenario | is_ended | is_active | is_future | is_upcoming | UI Badge | Can Start? |
|----------|----------|-----------|-----------|-------------|----------|------------|
| **Soonest future event** | false | false | true | true | 🔵 Upcoming | ✅ Yes |
| **Other future events** | false | false | true | false | 🔵 Upcoming | ❌ No |
| **Currently active** | false | true | false | false | ✅ Active | N/A |
| **Ended (time passed)** | true | false | false | false | ⚪ Ended | ❌ No |
| **Ended (manually)** | true | false | false | false | ⚪ Ended | ❌ No |

---

## 🔄 Status Transitions

### Creating a Future Event
```
Initial State:
├─ is_ended = false
├─ is_active = false
├─ is_future = true
└─ is_upcoming = true (if soonest)
```

### Starting an Event
```
Before:                    After:
├─ is_active = false  →   ├─ is_active = true
├─ is_future = true   →   ├─ is_future = false
└─ is_upcoming = true →   └─ is_upcoming = false
```

### Event Time Expires
```
Before:                    After:
├─ is_ended = false   →   ├─ is_ended = true
├─ is_active = true   →   ├─ is_active = false (auto)
└─ is_future = false  →   └─ is_future = false
```

### Manually Ending Event
```
Before:                    After:
├─ is_ended = false   →   ├─ is_ended = true (manual)
└─ is_active = true   →   └─ is_active = false
```

---

## 🧮 Calculation Formulas

### is_ended
```
is_ended = (current_time >= end_time) OR (manually_ended)
```

### is_active
```
is_active = (user_started) AND (current_time within [start_time, end_time])
```

### is_future
```
is_future = (NOT is_ended) AND (NOT is_active) AND (end_time > current_time)
```

### is_upcoming
```
is_upcoming = (is_future = true) AND (earliest event by date/time)
```

---

## ⚠️ Important Rules

1. **Only ONE** event can have `is_upcoming = true` per user
2. **Only ONE** event can have `is_active = true` per user
3. **Multiple** events can have `is_future = true` per user
4. **Multiple** events can have `is_ended = true` per user
5. Once `is_ended = true`, it **never** reverts to false
6. If `is_upcoming = true`, then `is_future` must also be `true`
7. If `is_active = true`, then `is_upcoming` must be `false`

---

## 🐛 Debugging Checklist

When an event has unexpected status:

- [ ] Check current time vs event start/end times
- [ ] Check if user manually ended the event
- [ ] Check if another event is soonest (for is_upcoming)
- [ ] Check if another event is active (for is_active)
- [ ] Check Supabase logs for trigger output
- [ ] Check Xcode console for Swift debug logs

---

## 📝 Log Format

### Swift Console (Xcode)
```
📋 [EventsHomeView] Event List:
   1. Birthday Party
      - is_active: false
      - is_upcoming: true
      - is_future: true
      - is_ended: false
```

### Database Logs (Supabase)
```
🔍 [calculate_event_status] Processing event: Birthday Party
   → is_ended: false
   → is_active: false
   → is_future: true

🔄 [update_most_upcoming_event] Recalculating...
   ✅ Set is_upcoming=true for event: abc123
```

---

## 🎨 UI Display Logic

```swift
// EventCard.swift
private var isUpcoming: Bool {
    event.isUpcoming == true || event.isFuture == true
}

// Display logic:
if isActive {
    // Show: Green "Active" badge
} else if isUpcoming {
    // Show: Blue "Upcoming" badge
} else {
    // Show: Gray "Ended" badge
}
```

---

## 🔧 Common Fixes

### Problem: Event shows wrong badge
**Fix**: Verify using database fields (`event.isFuture`), not local calculation

### Problem: Can't start event
**Fix**: Check `is_upcoming` - only the soonest event can be started

### Problem: Event stuck as active
**Fix**: Check if current time is still within event time range

### Problem: Multiple events show as "most upcoming"
**Fix**: Run SQL migration to recalculate `is_upcoming`

---

## 📚 Related Files

- **SQL Migration**: `FIX_EVENT_STATUS_LOGIC.sql`
- **Swift Views**: `EventsHomeView.swift`, `PastEventsView.swift`
- **Swift Model**: `Event.swift` (EventRecord struct)
- **Full Documentation**: `EVENT_STATUS_LOGIC_FIX_SUMMARY.md`

---

## ⏱️ Default Time Values

| Missing Field | Default Value |
|---------------|---------------|
| No start_time | 00:00:00 (midnight) |
| No end_time | 23:59:59 (end of day) |
| No event_date | N/A (required field) |

---

**Last Updated**: January 15, 2026
**Version**: 2.0 (Two-Phase Trigger System)
