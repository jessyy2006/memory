# Events Feature Documentation

## Overview

The Events feature allows users to create events and link memories to them. Each event has a date, optional time range, and can be activated to capture memories during that event. The system ensures only one event can be active at a time and enforces that only the most upcoming event can be started.

---

## Features

### Core Capabilities
- ✅ Create, read, update, and delete events
- ✅ Link memories to events
- ✅ Activate/deactivate events with smart validation
- ✅ Automatic sorting by event date
- ✅ Upcoming vs. past event filtering
- ✅ Single active event constraint (enforced by database)
- ✅ Row Level Security (users only see their own events)

### Smart Event Activation
- Only the **most upcoming event** (event_date >= current date) can be started
- Attempting to start any other event will fail with a clear error message
- Only one event can be active at a time (enforced by partial unique index)

---

## Installation

### Step 1: Run the Database Migration

1. Open your Supabase dashboard
2. Go to **SQL Editor**
3. Open the file `EVENTS_MIGRATION.sql`
4. Copy and paste the entire contents
5. Click **Run** (or press Cmd+Enter)

This will:
- Create the `events` table
- Add `event_id` column to the `memories` table
- Create all indexes and constraints
- Set up Row Level Security policies
- Create stored procedures for event management
- Create a view for efficient joins

### Step 2: Verify Installation

Run this query in the SQL Editor to verify:

```sql
SELECT * FROM events LIMIT 1;
SELECT * FROM memories_with_events LIMIT 1;
```

If both queries succeed (even with 0 rows), the installation is complete.

---

## Database Schema

### Events Table

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `user_id` | UUID | Foreign key to auth.users |
| `name` | TEXT | Event name (required) |
| `event_date` | DATE | Event date (required) |
| `start_time` | TIME | Event start time (optional) |
| `end_time` | TIME | Event end time (optional) |
| `is_active` | BOOLEAN | Whether event is currently active (default: false) |
| `created_at` | TIMESTAMPTZ | When the event was created |
| `updated_at` | TIMESTAMPTZ | Last update timestamp |

### Memories Table (Updated)

The `memories` table now includes:
- `event_id` (UUID, nullable) - Links to events table

### Constraints

- **Partial Unique Index**: `idx_events_user_active`
  - Ensures only ONE event per user can have `is_active = true`

- **Foreign Key**: `memories.event_id` → `events.id`
  - If an event is deleted, linked memories have `event_id` set to NULL

---

## Stored Procedures

### 1. `get_most_upcoming_event(p_user_id UUID)`

Returns the event with the minimum `event_date` that is >= CURRENT_DATE.

**Example:**
```sql
SELECT * FROM get_most_upcoming_event('your-user-id');
```

### 2. `start_event(p_event_id UUID, p_user_id UUID)`

Activates an event ONLY if it's the most upcoming event.

**Returns:**
```json
{
  "success": true,
  "event_id": "..."
}
```

**Or on error:**
```json
{
  "success": false,
  "error": "Can only start the most upcoming event",
  "most_upcoming_event_id": "...",
  "most_upcoming_event_date": "2026-02-15"
}
```

### 3. `stop_event(p_event_id UUID, p_user_id UUID)`

Deactivates an event.

**Returns:**
```json
{
  "success": true,
  "event_id": "..."
}
```

### 4. `get_events_sorted(p_user_id UUID)`

Returns all events for a user, sorted by `event_date` ASC, with an `is_upcoming` flag.

**Example:**
```sql
SELECT * FROM get_events_sorted('your-user-id');
```

---

## Swift Usage

### Creating an Event

```swift
import Foundation

let eventService = EventService()

// Create a new event
let newEvent = Event(
    userId: currentUserId,
    name: "Birthday Party",
    eventDate: Date().addingTimeInterval(86400 * 7), // 7 days from now
    startTime: createTime(hour: 18, minute: 0), // 6:00 PM
    endTime: createTime(hour: 22, minute: 0)    // 10:00 PM
)

do {
    let createdEvent = try await eventService.createEvent(newEvent)
    print("Event created: \(createdEvent.name)")
} catch {
    print("Error creating event: \(error)")
}

// Helper function for creating time
func createTime(hour: Int, minute: Int) -> Date {
    var components = DateComponents()
    components.hour = hour
    components.minute = minute
    return Calendar.current.date(from: components) ?? Date()
}
```

### Fetching Events

```swift
// Get all events (sorted by date)
let events = try await eventService.fetchEvents()

// Get upcoming events only
let upcomingEvents = try await eventService.getUpcomingEvents()

// Get past events only
let pastEvents = try await eventService.getPastEvents()

// Get most upcoming event
if let nextEvent = try await eventService.getMostUpcomingEvent() {
    print("Next event: \(nextEvent.name) on \(nextEvent.formattedDate)")
}

// Get currently active event
if let activeEvent = try await eventService.getActiveEvent() {
    print("Currently capturing memories for: \(activeEvent.name)")
}
```

### Starting an Event

```swift
do {
    let response = try await eventService.startEvent(eventId: event.id)
    print("Event started successfully!")
} catch EventServiceError.cannotStartEvent(let reason, let mostUpcomingId) {
    print("Cannot start event: \(reason)")
    if let upcomingId = mostUpcomingId {
        print("Try starting event: \(upcomingId)")
    }
} catch {
    print("Error: \(error)")
}
```

### Stopping an Event

```swift
do {
    let response = try await eventService.stopEvent(eventId: event.id)
    print("Event stopped successfully!")
} catch {
    print("Error stopping event: \(error)")
}
```

### Checking if Event Can Be Started

```swift
let canStart = try await eventService.canStartEvent(eventId: event.id)
if canStart {
    // Show "Start Event" button
} else {
    // Disable button or show message
}
```

### Creating Memories Linked to Events

```swift
// Get the active event
guard let activeEvent = try await eventService.getActiveEvent() else {
    print("No active event")
    return
}

// Create a memory linked to the event
let memory = Memory(
    userId: currentUserId,
    eventId: activeEvent.id, // Link to event
    type: .photo,
    content: "https://storage.supabase.co/..."
)

let memoryService = MemoryService()
try await memoryService.createMemory(memory)
```

### Fetching Memories with Event Details

```swift
// Get all memories with their event information
let memoriesWithEvents = try await eventService.fetchMemoriesWithEvents()

for memory in memoriesWithEvents {
    print("Memory: \(memory.type)")
    if let eventName = memory.eventName {
        print("  Event: \(eventName)")
        print("  Date: \(memory.eventDate?.formatted() ?? "N/A")")
    }
}

// Get memories for a specific event
let eventMemories = try await eventService.fetchMemories(forEvent: eventId)
print("Found \(eventMemories.count) memories for this event")
```

### Updating an Event

```swift
let update = EventUpdate(
    name: "Updated Birthday Party",
    eventDate: nil, // Don't change the date
    startTime: nil,
    endTime: nil,
    isActive: nil
)

let updatedEvent = try await eventService.updateEvent(id: eventId, update: update)
```

### Deleting an Event

```swift
try await eventService.deleteEvent(id: eventId)
// Note: Linked memories will have their event_id set to NULL (not deleted)
```

---

## UI Examples

### Event List View

```swift
struct EventsListView: View {
    @State private var events: [EventRecord] = []
    private let eventService = EventService()

    var body: some View {
        List {
            Section("Upcoming") {
                ForEach(upcomingEvents, id: \.id) { event in
                    EventRow(event: event)
                }
            }

            Section("Past") {
                ForEach(pastEvents, id: \.id) { event in
                    EventRow(event: event)
                }
            }
        }
        .task {
            await loadEvents()
        }
    }

    var upcomingEvents: [EventRecord] {
        events.filter { $0.isUpcoming == true }
    }

    var pastEvents: [EventRecord] {
        events.filter { $0.isUpcoming == false }
    }

    func loadEvents() async {
        do {
            events = try await eventService.fetchEvents()
        } catch {
            print("Error loading events: \(error)")
        }
    }
}
```

### Event Row with Start Button

```swift
struct EventRow: View {
    let event: EventRecord
    @State private var canStart = false
    private let eventService = EventService()

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(event.name)
                    .font(.headline)
                Text(event.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if event.isActive {
                Text("Active")
                    .foregroundColor(.green)
                    .fontWeight(.semibold)
            } else if canStart {
                Button("Start") {
                    Task {
                        await startEvent()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .task {
            canStart = (try? await eventService.canStartEvent(eventId: event.id)) ?? false
        }
    }

    func startEvent() async {
        do {
            _ = try await eventService.startEvent(eventId: event.id)
        } catch EventServiceError.cannotStartEvent(let reason, _) {
            print("Cannot start: \(reason)")
        } catch {
            print("Error: \(error)")
        }
    }
}
```

---

## Best Practices

### 1. Always Check Active Event Before Creating Memories

```swift
if let activeEvent = try await eventService.getActiveEvent() {
    memory.eventId = activeEvent.id
} else {
    // No active event - show event picker or create memory without event
}
```

### 2. Handle Start Event Errors Gracefully

```swift
do {
    try await eventService.startEvent(eventId: eventId)
} catch EventServiceError.cannotStartEvent(let reason, let suggestedId) {
    // Show user-friendly error
    showAlert(
        title: "Cannot Start Event",
        message: reason,
        suggestedEventId: suggestedId
    )
}
```

### 3. Use the View for Efficient Queries

Instead of manually joining events and memories, use the `memories_with_events` view:

```swift
let memoriesWithEvents = try await eventService.fetchMemoriesWithEvents()
// All event data is already joined - no extra queries needed!
```

### 4. Validate Event Dates in UI

```swift
// Don't allow creating events in the far past
if eventDate < Calendar.current.date(byAdding: .day, value: -30, to: Date()) {
    showError("Event date cannot be more than 30 days in the past")
}
```

---

## Security

### Row Level Security (RLS)

All RLS policies are enabled. Users can only:
- View their own events
- Create events for themselves
- Update their own events
- Delete their own events

**Stored procedures** run with `SECURITY DEFINER`, meaning they execute with the privileges of the function owner, but still respect RLS policies through explicit `user_id` checks.

### Authentication

All EventService methods check authentication:

```swift
guard let userId = try await supabase.auth.session.user.id else {
    throw EventServiceError.notAuthenticated
}
```

---

## Troubleshooting

### Error: "Can only start the most upcoming event"

**Cause:** You're trying to activate an event that isn't the next upcoming one.

**Solution:**
1. Check the error response for `most_upcoming_event_id`
2. Start that event instead
3. Or update the event's date to make it the most upcoming

### Error: "duplicate key value violates unique constraint"

**Cause:** Trying to set `is_active = true` when another event is already active.

**Solution:** This should be handled by the `start_event()` function. If you're manually updating, first deactivate other events:

```sql
UPDATE events SET is_active = false WHERE user_id = 'your-user-id';
UPDATE events SET is_active = true WHERE id = 'event-id';
```

### Memories Not Showing Event Data

**Cause:** Memory was created before events feature was added.

**Solution:** Update existing memories to link them to events:

```sql
UPDATE memories
SET event_id = 'some-event-id'
WHERE id = 'memory-id';
```

---

## Migration Notes

### Existing Memories

After running the migration, all existing memories will have `event_id = NULL`. This is expected and safe. You can:
1. Leave them unlinked
2. Manually assign them to events
3. Create a UI to let users tag old memories to events

### Making event_id Required (Optional)

If you want to **require** every memory to have an event, run this after the initial migration:

```sql
-- First, create a "default" event for orphaned memories
INSERT INTO events (user_id, name, event_date, is_active)
SELECT DISTINCT user_id, 'General Memories', CURRENT_DATE, false
FROM memories
WHERE event_id IS NULL;

-- Update orphaned memories to link to the default event
UPDATE memories m
SET event_id = (
  SELECT e.id FROM events e
  WHERE e.user_id = m.user_id
  AND e.name = 'General Memories'
  LIMIT 1
)
WHERE m.event_id IS NULL;

-- Now make it NOT NULL
ALTER TABLE memories
ALTER COLUMN event_id SET NOT NULL;
```

---

## API Reference

See `EventService.swift` for complete API documentation. Key methods:

| Method | Description |
|--------|-------------|
| `createEvent(_:)` | Create a new event |
| `fetchEvents()` | Get all events (sorted) |
| `fetchEvent(id:)` | Get single event |
| `updateEvent(id:update:)` | Update event fields |
| `deleteEvent(id:)` | Delete an event |
| `getMostUpcomingEvent()` | Get next upcoming event |
| `startEvent(eventId:)` | Activate an event (validated) |
| `stopEvent(eventId:)` | Deactivate an event |
| `getActiveEvent()` | Get currently active event |
| `fetchMemoriesWithEvents()` | Get all memories with event data |
| `fetchMemories(forEvent:)` | Get memories for specific event |
| `canStartEvent(eventId:)` | Check if event can be activated |
| `getUpcomingEvents()` | Get future events |
| `getPastEvents()` | Get past events |

---

## Support

For issues or questions:
1. Check the SQL migration ran successfully
2. Verify RLS policies are enabled
3. Check authentication state
4. Review Supabase logs in the dashboard

---

## Summary

You now have a complete events system with:
- ✅ Full CRUD operations
- ✅ Smart activation logic
- ✅ Database constraints ensuring data integrity
- ✅ Efficient queries with views and stored procedures
- ✅ Row Level Security
- ✅ Swift service layer ready to use

Start building your event-based memory capture UI!
