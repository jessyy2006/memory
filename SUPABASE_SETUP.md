# Supabase Integration Setup Guide

## Overview

Your Memory app is now integrated with Supabase for:
- **User Authentication** (Email, Phone, Apple, Google)
- **User Profile Storage** (Database)
- **Email/SMS Verification** (OTP)
- **Session Management**

---

## Step 1: Install Supabase Swift SDK

1. Open your project in Xcode
2. Go to **File → Add Package Dependencies**
3. Enter this URL: `https://github.com/supabase/supabase-swift`
4. Select **Up to Next Major Version** and click **Add Package**
5. Make sure **Supabase** is checked for your Memory target
6. Click **Add Package**

---

## Step 2: Create Supabase Project

1. Go to [https://supabase.com](https://supabase.com)
2. Click **Start your project**
3. Sign in or create an account
4. Click **New project**
5. Fill in:
   - **Name**: Memory App
   - **Database Password**: (create a strong password)
   - **Region**: Choose closest to your users
6. Click **Create new project**

---

## Step 3: Get Your API Keys

1. Once your project is created, go to **Settings** (gear icon)
2. Click **API** in the sidebar
3. Copy these values:
   - **Project URL** (e.g., `https://xxxxx.supabase.co`)
   - **anon/public** key (the long string under "Project API keys")

---

## Step 4: Configure Your App

1. Open `Memory/Services/SupabaseConfig.swift`
2. Replace the placeholder values:

```swift
static let supabaseURL = URL(string: "YOUR_SUPABASE_URL")!
static let supabaseAnonKey = "YOUR_SUPABASE_ANON_KEY"
```

Example:
```swift
static let supabaseURL = URL(string: "https://abcdefgh.supabase.co")!
static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

---

## Step 5: Create Database Table

1. In your Supabase dashboard, click **SQL Editor** (left sidebar)
2. Click **New query**
3. Copy and paste this SQL:

```sql
-- Create profiles table
CREATE TABLE profiles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  phone_number TEXT,
  is_email_verified BOOLEAN DEFAULT false,
  is_phone_verified BOOLEAN DEFAULT false,
  auth_provider TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  last_login_at TIMESTAMP WITH TIME ZONE,
  UNIQUE(email),
  UNIQUE(phone_number),
  UNIQUE(user_id)
);

-- Enable Row Level Security
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can view their own profile"
  ON profiles FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own profile"
  ON profiles FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own profile"
  ON profiles FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Create index for faster queries
CREATE INDEX idx_profiles_user_id ON profiles(user_id);
CREATE INDEX idx_profiles_email ON profiles(email);
```

4. Click **Run** (or press Cmd+Enter)

---

## Step 6: Enable Authentication Providers

### Email Authentication (Already Enabled)
- Email auth is enabled by default in Supabase

### Phone Authentication (Optional)
1. Go to **Authentication → Providers**
2. Enable **Phone**
3. Choose a provider (Twilio, MessageBird, etc.)
4. Add your API credentials

### Sign in with Apple
1. Go to **Authentication → Providers**
2. Enable **Apple**
3. Follow the instructions to configure Apple Sign In
4. Add your **Services ID** and **Team ID**

### Sign in with Google
1. Go to **Authentication → Providers**
2. Enable **Google**
3. Add your **Client ID** and **Client Secret** from Google Cloud Console

---

## Step 7: Configure Email Templates (Optional)

1. Go to **Authentication → Email Templates**
2. Customize your:
   - Confirmation email
   - Magic link email
   - Password recovery email

---

## Step 8: Test Your Integration

### Test Email Sign Up:
1. Run your app in the simulator
2. Choose **Email** signup
3. Enter: test@example.com
4. Password: TestPass123
5. Check your Supabase dashboard **Authentication → Users** to see the new user

### Test Phone Sign Up:
1. Choose **Phone** signup
2. Enter your real phone number (for testing)
3. You should receive an SMS with OTP code
4. Enter the code to verify

---

## Step 9: Enable Apple Sign In (iOS)

1. In Xcode, select your project
2. Select your **Memory** target
3. Go to **Signing & Capabilities**
4. Click **+ Capability**
5. Add **Sign in with Apple**

---

## What Happens Now?

When a user creates an account:
1. ✅ Account is created in Supabase Auth
2. ✅ Verification email/SMS is sent automatically
3. ✅ User profile is saved to `profiles` table
4. ✅ User must verify OTP to complete signup
5. ✅ Session is managed automatically

---

## Database Schema

Your `profiles` table stores:
- `id` - Unique profile ID
- `user_id` - Links to Supabase auth.users
- `email` - User's email (optional)
- `phone_number` - User's phone (optional)
- `is_email_verified` - Email verification status
- `is_phone_verified` - Phone verification status
- `auth_provider` - How they signed up (email, phone, apple, google)
- `created_at` - Account creation timestamp
- `last_login_at` - Last login timestamp

---

## Security Notes

- ✅ Row Level Security (RLS) is enabled
- ✅ Users can only access their own data
- ✅ API keys are safe to use in mobile apps (anon key only)
- ⚠️ Never commit your Supabase keys to public repositories
- ⚠️ Consider using environment variables for production

---

## Troubleshooting

### "Missing import of defining module 'Supabase'"
- Clean Build Folder (Shift+Cmd+K)
- Delete Derived Data
- Rebuild project

### "Invalid API key"
- Double-check your anon key in SupabaseConfig.swift
- Make sure you copied the full key

### OTP not received
- Check your email spam folder
- For SMS: verify your phone provider is configured correctly
- Check Supabase logs in **Logs → Edge Functions**

---

## Next Steps

Your authentication is now fully integrated! Consider adding:
- User profiles with avatars
- Remember me functionality
- Social login with Facebook, GitHub
- Password reset flow
- Account deletion

---

## Support

- Supabase Docs: https://supabase.com/docs
- Supabase Swift SDK: https://github.com/supabase/supabase-swift
- Community: https://github.com/supabase/supabase/discussions
