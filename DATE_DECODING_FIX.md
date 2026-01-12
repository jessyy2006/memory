# Date Decoding Fix - Events Display Issue

## Problem

**Error**: `dataCorrupted(Swift.DecodingError.Context(codingPath: [CodingKeys(stringValue: "event_date", intValue: nil)], debugDescription: "Invalid date format: 2026-01-12", underlyingError: nil))`

**Root Cause**:
Supabase returns different date/time formats depending on the PostgreSQL column type:
- `DATE` columns → `"2026-01-12"` (just the date)
- `TIME` columns → `"13:54:00"` (just the time)
- `TIMESTAMP` columns → `"2026-01-12T13:54:00Z"` (ISO8601 full timestamp)

Swift's default `Codable` decoder expects all `Date` fields to be in ISO8601 format, but our `event_date`, `start_time`, and `end_time` columns use DATE and TIME types.

---

## Solution

Added custom `init(from decoder:)` implementations to handle Supabase's date/time formats:

### 1. EventRecord (Event.swift:107-161)
**Custom decoding for:**
- ✅ `event_date` - DATE format: `"yyyy-MM-dd"`
- ✅ `start_time` - TIME format: `"HH:mm:ss"`
- ✅ `end_time` - TIME format: `"HH:mm:ss"`
- ✅ `created_at` - TIMESTAMP format: ISO8601
- ✅ `updated_at` - TIMESTAMP format: ISO8601

### 2. EventActionResponse (Event.swift:249-267)
**Custom decoding for:**
- ✅ `most_upcoming_event_date` - DATE format: `"yyyy-MM-dd"`

### 3. MemoryWithEvent (Event.swift:286-350)
**Custom decoding for:**
- ✅ `event_date` - DATE format: `"yyyy-MM-dd"`
- ✅ `event_start_time` - TIME format: `"HH:mm:ss"`
- ✅ `event_end_time` - TIME format: `"HH:mm:ss"`
- ✅ `timestamp` - TIMESTAMP format: ISO8601
- ✅ `created_at` - TIMESTAMP format: ISO8601
- ✅ `updated_at` - TIMESTAMP format: ISO8601

---

## Code Example

Before (automatic Codable):
```swift
struct EventRecord: Codable {
    let eventDate: Date  // ❌ Fails to decode "2026-01-12"
}
```

After (custom decoder):
```swift
struct EventRecord: Codable {
    let eventDate: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let eventDateString = try container.decode(String.self, forKey: .eventDate)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        guard let date = dateFormatter.date(from: eventDateString) else {
            throw DecodingError.dataCorruptedError(...)
        }

        eventDate = date  // ✅ Successfully decodes "2026-01-12"
    }
}
```

---

## Testing

### Before Fix
```
❌ [EventsHomeView] Failed to create event: dataCorrupted(...)
❌ [EventsHomeView] Error details: The data couldn't be read because it isn't in the correct format.
```

### After Fix (Expected Output)
```
✅ [EventService] Event created in Supabase: ID=..., Name=Test3
✅ [EventsHomeView] Event created successfully!
   - Name: Test3
   - ID: 51B9D31E-5D86-4F3A-912B-1998C10A14D7
   - Date: 2026-01-12 00:00:00 +0000
   - is_active: false
🔄 [EventsHomeView] Reloading events list...
✅ [EventService] RPC returned 1 events
📥 [EventsHomeView] Received 1 events from EventService
✅ [EventsHomeView] UI Updated - Displaying 1 events
📋 [EventsHomeView] Event List:
   1. Test3
      - ID: 51B9D31E-5D86-4F3A-912B-1998C10A14D7
      - Date: 2026-01-12 00:00:00 +0000
      - is_active: false
      - is_upcoming: true
```

---

## Files Modified

| File | Lines | Change |
|------|-------|--------|
| `Event.swift` | 107-161 | Added custom decoder to EventRecord |
| `Event.swift` | 249-267 | Added custom decoder to EventActionResponse |
| `Event.swift` | 286-350 | Added custom decoder to MemoryWithEvent |

---

## Next Steps

1. **Clean build** in Xcode (⌘⇧K)
2. **Run the app** (⌘R)
3. **Create an event** - should now succeed without decoding errors
4. **Verify event appears** in the Events list immediately after creation

---

## Why This Happened

PostgreSQL's DATE and TIME types are more precise than Swift's Date type:
- PostgreSQL `DATE` stores only year-month-day
- PostgreSQL `TIME` stores only hour-minute-second
- Swift `Date` is always a full timestamp (date + time)

When Supabase returns these values as JSON, they're formatted according to their PostgreSQL type, not as full timestamps. Our custom decoders bridge this gap.

---

## Alternative Solutions (Not Used)

1. **Change database schema** - Convert DATE → TIMESTAMP
   - ❌ Would lose semantic meaning (we want dates, not timestamps)
   - ❌ Would break existing data

2. **Use String for dates** - Store as `String` in Swift
   - ❌ Loses type safety
   - ❌ Can't use Date operations (comparisons, formatting, etc.)

3. **Use JSONDecoder.dateDecodingStrategy**
   - ❌ Can't handle multiple formats in one response
   - ❌ Supabase returns different formats for different columns

**Custom decoders** are the cleanest solution that preserves type safety and semantic meaning.
