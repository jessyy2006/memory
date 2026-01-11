# Troubleshooting Authentication Issues

## Issue 1: Verification Emails Not Sending

### Why emails might not send:

1. **Supabase Email Configuration** (Most Common)
   - By default, Supabase has rate limits on email sending in development
   - You need to configure a custom SMTP provider for production

### Solutions:

#### Option A: Check Development Rate Limits
1. Go to your Supabase Dashboard
2. Click **Settings → API**
3. Scroll down to **Rate Limits**
4. Check if you've hit the email rate limit (usually 3-4 emails per hour in development)
5. **Wait an hour and try again**

#### Option B: Check Spam Folder
- Supabase emails often go to spam
- Check your spam/junk folder for emails from `noreply@mail.app.supabase.io`

#### Option C: Configure Custom SMTP (Recommended for Production)
1. Go to **Authentication → Email Templates**
2. Click **Settings** (gear icon)
3. Enable **Use custom SMTP server**
4. Configure with your email provider:
   - **SendGrid** (Free tier available)
   - **AWS SES**
   - **Mailgun**
   - **Postmark**

#### Option D: Use Test Email Feature
1. In Supabase Dashboard, go to **Authentication → Users**
2. Click **Add user** → **Create new user**
3. Check **Auto Confirm User** to bypass email verification for testing

### Check Supabase Logs:
1. Go to **Logs → Auth Logs**
2. Look for any errors related to email sending
3. Common errors:
   - `Rate limit exceeded` - Wait and try again
   - `SMTP configuration error` - Set up custom SMTP
   - `Invalid email template` - Check email template configuration

---

## Issue 2: Sign in with Apple Not Working

### Common Issues:

#### 1. Capability Not Added
**Solution:**
1. Open Xcode
2. Select your project
3. Select **Memory** target
4. Go to **Signing & Capabilities**
5. Click **+ Capability**
6. Add **Sign in with Apple**

#### 2. Supabase Apple Provider Not Configured
**Solution:**
1. Go to **Authentication → Providers** in Supabase
2. Enable **Apple**
3. Add your Apple Developer credentials:
   - **Services ID**: com.yourapp.client
   - **Team ID**: Find in Apple Developer Account
   - **Key ID**: Create in Apple Developer → Keys
   - **Private Key**: Download from Apple Developer

#### 3. Apple Developer Account Setup
**Solution:**
1. Go to [Apple Developer](https://developer.apple.com)
2. Go to **Certificates, Identifiers & Profiles**
3. Create an **App ID** with Sign in with Apple enabled
4. Create a **Services ID**
5. Configure **Sign in with Apple** for your Services ID
6. Add return URL: `https://YOUR_PROJECT.supabase.co/auth/v1/callback`

### Debug Steps:
1. Run the app
2. Tap **Sign in with Apple**
3. Check Xcode console for error messages
4. Look for:
   - `🍎 Apple authorization received` - Authorization succeeded
   - `❌ Apple Sign In failed` - Check error message

---

## Issue 3: Sign in with Google Not Working

Google Sign In requires additional SDK setup:

### Steps to Enable Google Sign In:

#### 1. Add GoogleSignIn SDK
1. In Xcode, go to **File → Add Package Dependencies**
2. Enter: `https://github.com/google/GoogleSignIn-iOS`
3. Select version **7.0.0** or later
4. Click **Add Package**

#### 2. Configure Google Cloud Console
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project or select existing
3. Enable **Google Sign-In API**
4. Create OAuth 2.0 credentials:
   - **Application type**: iOS
   - **Bundle ID**: com.jessicay.Memory (or your bundle ID)
5. Download the configuration file

#### 3. Update Supabase
1. Go to **Authentication → Providers** in Supabase
2. Enable **Google**
3. Add your **Client ID** and **Client Secret**

#### 4. Update Code
Replace the `handleGoogleSignIn` function in CreateAccountView.swift:

```swift
import GoogleSignIn

private func handleGoogleSignIn() {
    guard let presentingViewController = UIApplication.shared.windows.first?.rootViewController else {
        return
    }

    GIDSignIn.sharedInstance.signIn(
        withPresenting: presentingViewController
    ) { result, error in
        Task {
            if let error = error {
                self.passwordError = "Google Sign In failed: \(error.localizedDescription)"
                return
            }

            guard let idToken = result?.user.idToken?.tokenString else {
                self.passwordError = "Failed to get Google ID token"
                return
            }

            do {
                let user = try await self.authService.signInWithGoogle(idToken: idToken)
                print("✅ Successfully signed in with Google")
            } catch {
                self.passwordError = "Google Sign In error: \(error.localizedDescription)"
            }
        }
    }
}
```

---

## Debugging Tips

### Enable Detailed Logging
The app now prints detailed logs. Check Xcode Console for:
- 📝 Account creation steps
- ✅ Success messages
- ❌ Error messages
- 📧 Email sending status
- 🍎 Apple Sign In status

### Common Log Messages:

| Message | Meaning |
|---------|---------|
| `📧 Signing up with email` | Account creation started |
| `✅ Signup successful. Email verification sent` | Email sent by Supabase |
| `❌ Supabase error: Rate limit exceeded` | Too many emails sent (wait 1 hour) |
| `✅ Email sent successfully` | Verification code resent |
| `❌ Failed to send verification code` | Check Supabase configuration |

### Test Without Verification (Development Only)

For testing, you can temporarily skip email verification:

1. In Supabase Dashboard → **Authentication → Settings**
2. Scroll to **Email Auth**
3. Toggle **Enable email confirmations** to OFF
4. Users will be able to sign in immediately without verification

**⚠️ WARNING**: Remember to turn this back ON for production!

---

## Still Having Issues?

1. **Check Supabase Status**: [status.supabase.com](https://status.supabase.com)
2. **View Auth Logs**: Supabase Dashboard → **Logs → Auth Logs**
3. **Check API Rate Limits**: Settings → API → Rate Limits
4. **Verify API Keys**: Make sure `SupabaseConfig.swift` has correct URL and anon key
5. **Check Network**: Ensure simulator/device has internet connection

---

## Quick Test Checklist

- [ ] Supabase project created
- [ ] API keys added to `SupabaseConfig.swift`
- [ ] Database table created (profiles)
- [ ] Email provider configured (or waiting between attempts)
- [ ] Sign in with Apple capability added
- [ ] Internet connection working
- [ ] Checking spam folder for emails
- [ ] Reading Xcode console for error messages
