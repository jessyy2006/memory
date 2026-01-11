//
//  SupabaseConfig.swift
//  Memory
//
//  Created by Jessica Young on 11/19/25.
//

import Foundation

struct SupabaseConfig {
    // MARK: - Configuration
    // Replace these with your actual Supabase project credentials
    // Find these at: https://app.supabase.com/project/YOUR_PROJECT_ID/settings/api

    static let supabaseURL = URL(string: "https://zmdcomjuboudxukyvyes.supabase.co")!
    static let supabaseAnonKey = "sb_publishable_p9mcEGI76AcLsNCSLdkKqQ_5_-w3VsY"

    // MARK: - Database Tables
    struct Tables {
        static let users = "users"
        static let profiles = "profiles"
        static let memories = "memories"
    }
}

/*
 SETUP INSTRUCTIONS:

 1. Go to https://supabase.com and create a new project
 2. Copy your Project URL and anon/public key from Settings > API
 3. Replace the placeholder values above

 4. Run this SQL in your Supabase SQL Editor to create the users table:

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
   UNIQUE(phone_number)
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

 CREATE POLICY "Users can delete their own profile"
   ON profiles FOR DELETE
   USING (auth.uid() = user_id);

 -- Create a trigger to automatically create profiles when users sign up
 CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger AS $$
 BEGIN
   INSERT INTO public.profiles (user_id, email, auth_provider, is_email_verified, is_phone_verified)
   VALUES (
     NEW.id,
     NEW.email,
     'emailPassword',
     false,
     false
   );
   RETURN NEW;
 END;
 $$ LANGUAGE plpgsql SECURITY DEFINER;

 DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
 CREATE TRIGGER on_auth_user_created
   AFTER INSERT ON auth.users
   FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

 5. Create the memories table for storing user memories:

 CREATE TABLE memories (
   id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
   user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
   type TEXT NOT NULL CHECK (type IN ('photo', 'video', 'note', 'audio')),
   content TEXT NOT NULL,
   thumbnail_url TEXT,
   duration DOUBLE PRECISION,
   timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
   created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
   updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
 );

 -- Create index for faster queries
 CREATE INDEX idx_memories_user_id_timestamp ON memories(user_id, timestamp);

 -- Enable Row Level Security
 ALTER TABLE memories ENABLE ROW LEVEL SECURITY;

 -- Create policies for memories
 CREATE POLICY "Users can view their own memories"
   ON memories FOR SELECT
   USING (auth.uid() = user_id);

 CREATE POLICY "Users can insert their own memories"
   ON memories FOR INSERT
   WITH CHECK (auth.uid() = user_id);

 CREATE POLICY "Users can update their own memories"
   ON memories FOR UPDATE
   USING (auth.uid() = user_id);

 CREATE POLICY "Users can delete their own memories"
   ON memories FOR DELETE
   USING (auth.uid() = user_id);

 6. Create storage buckets for memories:
    - Go to Storage in Supabase Dashboard
    - Create a bucket called "memories" with public access
*/
