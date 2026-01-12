# Privacy Permissions Setup

## Required Privacy Descriptions

You need to add the following privacy usage descriptions to your Info.plist file to fix the build errors.

### How to Add in Xcode:

1. Open the Xcode project
2. Select the **Memory** target in the project navigator
3. Go to the **Info** tab
4. Click the **+** button to add new entries
5. Add the following keys and values:

### Privacy Keys to Add:

| Key | Value |
|-----|-------|
| `NSCameraUsageDescription` | "Memory needs access to your camera to capture photos and videos for your events" |
| `NSMicrophoneUsageDescription` | "Memory needs access to your microphone to record audio memos and videos" |
| `NSPhotoLibraryUsageDescription` | "Memory needs access to your photo library to select photos and videos for your events" |
| `NSPhotoLibraryAddUsageDescription` | "Memory needs permission to save captured photos and videos to your photo library" |

### Alternative: Edit Info.plist Directly

If you have access to the Info.plist file, add these entries:

```xml
<key>NSCameraUsageDescription</key>
<string>Memory needs access to your camera to capture photos and videos for your events</string>

<key>NSMicrophoneUsageDescription</key>
<string>Memory needs access to your microphone to record audio memos and videos</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>Memory needs access to your photo library to select photos and videos for your events</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>Memory needs permission to save captured photos and videos to your photo library</string>
```

## After Adding:

1. Clean build folder (Product > Clean Build Folder in Xcode)
2. Rebuild the project
3. The privacy permission errors should be resolved

---

**Note**: These descriptions will be shown to users when the app first requests access to their camera, microphone, or photo library. Make sure they clearly explain why the app needs these permissions.
