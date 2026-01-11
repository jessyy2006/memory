# Setup Instructions for Authentication Feature

## Files Added

The following files have been created for the authentication system:

### Models
- `Memory/Models/User.swift` - User data model with SwiftData

### Services
- `Memory/Services/AuthenticationService.swift` - Authentication logic and validation

### Views
- `Memory/Views/Auth/CreateAccountView.swift` - Main account creation page
- `Memory/Views/Auth/VerificationCodeView.swift` - 2FA verification page
- `Memory/Views/Auth/Components/AuthTextField.swift` - Reusable text field component
- `Memory/Views/Auth/Components/AuthButton.swift` - Reusable button component

### Modified Files
- `Memory/MemoryApp.swift` - Updated to use authentication flow

## How to Add Files to Xcode

1. Open `Memory.xcodeproj` in Xcode
2. Right-click on the "Memory" folder in the Project Navigator
3. Select "Add Files to Memory..."
4. Navigate to the `Memory` folder
5. Select all the new folders (Models, Services, Views)
6. Make sure "Copy items if needed" is **UNCHECKED**
7. Make sure "Create groups" is **SELECTED**
8. Make sure "Memory" target is **CHECKED**
9. Click "Add"

OR simply:
1. Close Xcode completely
2. Reopen the project
3. Xcode should automatically detect the new files

## Testing

Use verification code: **123456**

This is hardcoded for testing purposes. In production, replace with your backend API.
