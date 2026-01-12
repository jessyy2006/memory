# REQUIRED: Add Privacy Permissions

## ⚠️ CRITICAL - App Will Not Work Without These

Your Xcode shows 4 privacy permission errors. These MUST be added for the app to function:

1. NSPhotoLibraryUsageDescription
2. NSPhotoLibraryAddUsageDescription
3. NSCameraUsageDescription
4. NSMicrophoneUsageDescription

---

## How to Add (Step-by-Step)

### Step 1: Open Target Settings
1. In Xcode's left sidebar, click the **Memory** project (the blue icon at the top)
2. In the main editor, select the **Memory** target (under TARGETS)
3. Click the **Info** tab at the top

### Step 2: Add Each Permission
For each of the 4 permissions below:

1. Hover over any existing key in the list
2. Click the **+** button that appears
3. Start typing the key name (Xcode will autocomplete)
4. Select the correct key from the dropdown
5. Double-click the "Value" column
6. Paste the description text

---

## The 4 Required Permissions

### Permission 1: Photo Library Usage
- **Key:** `Privacy - Photo Library Usage Description`
  - (Xcode autocomplete: start typing "photo library usage")
- **Value:** `Memory needs access to your photo library to upload profile pictures and capture memories`

### Permission 2: Photo Library Additions Usage
- **Key:** `Privacy - Photo Library Additions Usage Description`
  - (Xcode autocomplete: start typing "photo library additions")
- **Value:** `Memory needs permission to save photos to your library`

### Permission 3: Camera Usage
- **Key:** `Privacy - Camera Usage Description`
  - (Xcode autocomplete: start typing "camera usage")
- **Value:** `Memory needs camera access to capture photos and videos for your memories`

### Permission 4: Microphone Usage
- **Key:** `Privacy - Microphone Usage Description`
  - (Xcode autocomplete: start typing "microphone usage")
- **Value:** `Memory needs microphone access to record audio and video memories`

---

## Visual Guide

When you're done, your Info tab should look like this:

```
Privacy - Photo Library Usage Description        Memory needs access to your photo library...
Privacy - Photo Library Additions Usage...       Memory needs permission to save photos...
Privacy - Camera Usage Description               Memory needs camera access to capture...
Privacy - Microphone Usage Description           Memory needs microphone access to record...
```

---

## After Adding Permissions

1. **Clean Build:**
   - Product → Clean Build Folder (⌘⇧K)
   - Product → Build (⌘B)
   - **Verify:** The 4 yellow warnings should disappear

2. **Run the App:**
   - Product → Run (⌘R)
   - The app should now work without crashes

---

## Why These Are Required

| Permission | Used In | Why It's Needed |
|-----------|---------|-----------------|
| Photo Library Usage | ProfileCompletionView | User uploads profile picture |
| Photo Library Additions | Future features | Save captured memories to Photos app |
| Camera Usage | MemoriesHomeView | Capture photo/video memories |
| Microphone Usage | MemoriesHomeView | Record audio/video memories |

**Without these:** The app will crash or fail silently when trying to access photos/camera.

---

## Troubleshooting

### "I added them but warnings still show"
- Clean Build Folder (⌘⇧K)
- Quit Xcode completely
- Reopen project
- Build again

### "I can't find the Info tab"
- Make sure you clicked the **TARGET** (not the PROJECT)
- Look for tabs: General, Signing & Capabilities, Resource Tags, **Info**, Build Settings...

### "The autocomplete doesn't show the key"
- Just start typing "Privacy"
- All privacy keys start with "Privacy -"
- Select from the dropdown that appears

---

## Next Steps After Adding Permissions

1. ✅ Add all 4 permissions
2. ✅ Clean build
3. ✅ Run the app
4. ✅ Watch console for new debug logs:
   ```
   📝 [MemoryApp] CreateAccountView appeared
   🔐 [MemoryApp] Authentication changed: false → true
   🏠 [MemoryApp] EventsHomeView appeared
   👁️ [EventsHomeView] View appeared!
   🔄 [EventsHomeView] Starting loadEvents()...
   ```

Once you see these logs, we'll know if events are loading correctly!
