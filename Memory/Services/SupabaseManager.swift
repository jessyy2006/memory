//
//  SupabaseManager.swift
//  Memory
//
//  Updated: return the correct types (no `.session` on a Session)
//

import Foundation
import Supabase
import Auth
import UIKit

struct UserProfile: Codable {
    let id: UUID?
    let userId: UUID?
    let username: String
    let fullName: String?
    let bio: String?
    let avatarUrl: String?
    let authProvider: String
    let createdAt: Date?
    let lastLoginAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case username
        case fullName = "full_name"
        case bio
        case avatarUrl = "avatar_url"
        case authProvider = "auth_provider"
        case createdAt = "created_at"
        case lastLoginAt = "last_login_at"
        case updatedAt = "updated_at"
    }
}

struct UserProfileUpdate: Encodable {
    let username: String?
    let fullName: String?
    let bio: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case username
        case fullName = "full_name"
        case bio
        case avatarUrl = "avatar_url"
    }
}

struct LastLoginUpdate: Encodable {
    let lastLoginAt: String

    enum CodingKeys: String, CodingKey {
        case lastLoginAt = "last_login_at"
    }
}

class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        self.client = SupabaseClient(
            supabaseURL: SupabaseConfig.supabaseURL,
            supabaseKey: SupabaseConfig.supabaseAnonKey
        )
    }

    // MARK: - Authentication

    /// Sign up with email and password.
    /// Returns AuthResponse (SDK v2.37.0 returns AuthResponse).
    func signUpWithEmail(email: String, password: String) async throws -> AuthResponse {
        let authResponse = try await client.auth.signUp(
            email: email,
            password: password,
            redirectTo: nil
        )
        print("✅ Signup requested. Email verification sent to: \(email)")
        print("📧 Check your inbox for the verification code")
        return authResponse
    }

    /// Sign up with phone and password.
    func signUpWithPhone(phone: String, password: String) async throws -> AuthResponse {
        let authResponse = try await client.auth.signUp(phone: phone, password: password)
        print("✅ Signup requested. SMS verification (if required) sent to: \(phone)")
        return authResponse
    }

    /// Sign in with email/password — return the Session (the SDK you're using returns a Session directly).
    func signInWithEmail(email: String, password: String) async throws -> Session {
        let response = try await client.auth.signIn(email: email, password: password)
        // response is a Session (not an AuthResponse) in the SDK that produced your error,
        // so return it directly instead of `response.session`.
        return response
    }

    /// Sign in with phone/password — return the Session.
    func signInWithPhone(phone: String, password: String) async throws -> Session {
        let response = try await client.auth.signIn(phone: phone, password: password)
        return response
    }

    /// Verify OTP for email — returns AuthResponse.
    func verifyEmailOTP(email: String, token: String) async throws -> AuthResponse {
        let authResponse = try await client.auth.verifyOTP(email: email, token: token, type: .email)
        return authResponse
    }

    /// Verify OTP for phone — returns AuthResponse.
    func verifyPhoneOTP(phone: String, token: String) async throws -> AuthResponse {
        let authResponse = try await client.auth.verifyOTP(phone: phone, token: token, type: .sms)
        return authResponse
    }

    /// Sign in with OAuth provider using id token (Apple).
    func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        let response = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        return response
    }

    /// Sign in with Google id token.
    func signInWithGoogle(idToken: String) async throws -> Session {
        let response = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .google, idToken: idToken)
        )
        return response
    }

    /// Sign out current user (clears local session).
    func signOut() async throws {
        try await client.auth.signOut()
    }

    /// Get current session — newer SDKs often expose `currentSession`.
    func getCurrentSession() async throws -> Session? {
        do {
            return try await client.auth.session
        } catch {
            return nil
        }
    }

    /// Get current user (throws if there's no active session).
    func getCurrentUser() async throws -> Auth.User {
        let session = try await client.auth.session
        return session.user
    }

    // MARK: - Database Operations

    func updateUserProfile(
        userId: UUID,
        username: String? = nil,
        fullName: String? = nil,
        bio: String? = nil,
        avatarUrl: String? = nil
    ) async throws {
        // First, check if profile exists
        let existingProfile = try? await getUserProfile(userId: userId)

        if existingProfile == nil {
            // Profile doesn't exist - create it with UPSERT
            print("⚠️ Profile doesn't exist, creating it...")

            struct ProfileInsert: Encodable {
                let userId: String
                let username: String
                let fullName: String?
                let bio: String?
                let avatarUrl: String?

                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                    case username
                    case fullName = "full_name"
                    case bio
                    case avatarUrl = "avatar_url"
                }
            }

            let insert = ProfileInsert(
                userId: userId.uuidString,
                username: username ?? "user_\(String(userId.uuidString.prefix(8)))",
                fullName: fullName,
                bio: bio,
                avatarUrl: avatarUrl
            )

            try await client
                .from(SupabaseConfig.Tables.profiles)
                .insert(insert)
                .execute()

            print("✅ Profile created")
        } else {
            // Profile exists - update it
            let update = UserProfileUpdate(
                username: username,
                fullName: fullName,
                bio: bio,
                avatarUrl: avatarUrl
            )

            try await client
                .from(SupabaseConfig.Tables.profiles)
                .update(update)
                .eq("user_id", value: userId.uuidString)
                .execute()

            print("✅ Profile updated")
        }
    }

    func getUserProfile(userId: UUID) async throws -> UserProfile? {
        let response = try await client
            .from(SupabaseConfig.Tables.profiles)
            .select()
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UserProfile.self, from: response.data)
    }

    func updateLastLogin(userId: UUID) async throws {
        let update = LastLoginUpdate(
            lastLoginAt: ISO8601DateFormatter().string(from: Date())
        )

        try await client
            .from(SupabaseConfig.Tables.profiles)
            .update(update)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    func deleteUserProfile(userId: UUID) async throws {
        try await client
            .from(SupabaseConfig.Tables.profiles)
            .delete()
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    // MARK: - Storage Operations

    /// Upload avatar image to Supabase Storage
    /// Returns the public URL of the uploaded image
    func uploadAvatar(userId: UUID, imageData: Data) async throws -> String {
        print("📦 Processing image (\(imageData.count) bytes)...")

        guard let originalImage = UIImage(data: imageData) else {
            throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
        }

        // Resize image to max 1024px (Instagram profile size)
        let maxDimension: CGFloat = 1024
        let resizedImage: UIImage

        if originalImage.size.width > maxDimension || originalImage.size.height > maxDimension {
            print("📐 Resizing from \(originalImage.size)...")
            let scale = min(maxDimension / originalImage.size.width, maxDimension / originalImage.size.height)
            let newSize = CGSize(width: originalImage.size.width * scale, height: originalImage.size.height * scale)

            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            originalImage.draw(in: CGRect(origin: .zero, size: newSize))
            resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? originalImage
            UIGraphicsEndImageContext()

            print("✅ Resized to \(resizedImage.size)")
        } else {
            resizedImage = originalImage
        }

        // Compress with quality based on file size
        var compressionQuality: CGFloat = 0.8
        var finalImageData = resizedImage.jpegData(compressionQuality: compressionQuality) ?? imageData

        // If still too large, compress more
        while finalImageData.count > 500_000 && compressionQuality > 0.3 {
            compressionQuality -= 0.1
            if let compressed = resizedImage.jpegData(compressionQuality: compressionQuality) {
                finalImageData = compressed
                print("📦 Compressing... \(finalImageData.count) bytes (quality: \(Int(compressionQuality * 100))%)")
            }
        }

        print("✅ Final size: \(finalImageData.count) bytes")

        let fileName = "\(userId.uuidString).jpg"
        let filePath = fileName

        print("📤 Uploading to: avatars/\(filePath)")

        // Upload to storage (removed timeout - let it complete naturally)
        try await self.client.storage
            .from("avatars")
            .upload(
                filePath,
                data: finalImageData,
                options: .init(
                    cacheControl: "3600",
                    contentType: "image/jpeg",
                    upsert: true
                )
            )

        // Get public URL
        let publicURL = try client.storage
            .from("avatars")
            .getPublicURL(path: filePath)

        print("✅ Upload complete: \(publicURL.absoluteString)")
        return publicURL.absoluteString
    }

    /// Delete avatar from Supabase Storage
    func deleteAvatar(userId: UUID) async throws {
        let fileName = "\(userId.uuidString).jpg"

        try await client.storage
            .from("avatars")
            .remove(paths: [fileName])
    }

    // MARK: - Verification

    func resendVerificationEmail(email: String) async throws {
        try await client.auth.resend(email: email, type: .signup)
        print("✅ Verification email resent to: \(email)")
    }

    func resendVerificationSMS(phone: String) async throws {
        try await client.auth.resend(phone: phone, type: .sms)
        print("✅ Verification SMS resent to: \(phone)")
    }

    // MARK: - Memory Operations

    /// Fetch all memories for a user
    func fetchMemories(userId: UUID) async throws -> [MemoryRecord] {
        let response = try await client
            .from(SupabaseConfig.Tables.memories)
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("timestamp", ascending: true)
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([MemoryRecord].self, from: response.data)
    }

    /// Insert a new memory
    func insertMemory(memory: Memory) async throws {
        // Verify session before inserting
        print("🔍 [SupabaseManager] Checking session before insert...")
        guard let session = try? await getCurrentSession() else {
            print("❌ [SupabaseManager] No active session found!")
            throw NSError(domain: "SupabaseManager", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No active session. Please log in again."])
        }

        print("✅ [SupabaseManager] Session active for user: \(session.user.id)")
        print("📝 [SupabaseManager] Inserting memory for user: \(memory.userId)")

        if session.user.id != memory.userId {
            print("⚠️ [SupabaseManager] WARNING: Session user ID (\(session.user.id)) does not match memory user ID (\(memory.userId))")
        }

        let insert = MemoryInsert(memory: memory)

        try await client
            .from(SupabaseConfig.Tables.memories)
            .insert(insert)
            .execute()

        print("✅ Memory created: \(memory.type.title)")
    }

    /// Delete a memory
    func deleteMemory(memoryId: UUID) async throws {
        try await client
            .from(SupabaseConfig.Tables.memories)
            .delete()
            .eq("id", value: memoryId.uuidString)
            .execute()

        print("✅ Memory deleted")
    }

    // MARK: - Memory Storage Operations

    /// Upload memory media to Supabase Storage
    /// Returns the public URL of the uploaded file
    func uploadMemoryMedia(
        userId: UUID,
        data: Data,
        type: MemoryType,
        isThumbnail: Bool = false
    ) async throws -> String {
        // Verify session before uploading
        print("🔍 [Storage] Checking session before upload...")
        guard let session = try? await getCurrentSession() else {
            print("❌ [Storage] No active session for upload!")
            throw NSError(domain: "SupabaseManager", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No active session. Please log in again."])
        }
        print("✅ [Storage] Session active for user: \(session.user.id)")
        print("📝 [Storage] Uploading for user: \(userId)")

        let fileExtension: String
        let contentType: String

        switch type {
        case .photo:
            fileExtension = "jpg"
            contentType = "image/jpeg"
        case .video:
            fileExtension = "mp4"
            contentType = "video/mp4"
        case .audio:
            fileExtension = "m4a"
            contentType = "audio/mp4"
        case .note:
            throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Notes don't require media upload"])
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let suffix = isThumbnail ? "_thumb" : ""
        let fileName = "\(userId.uuidString)_\(timestamp)\(suffix).\(fileExtension)"
        let filePath = fileName

        print("📤 Uploading \(type.title) to: memories/\(filePath) (\(data.count) bytes)")
        print("📝 File will be named: \(fileName)")

        // Upload to storage
        do {
            try await client.storage
                .from("memories")
                .upload(
                    filePath,
                    data: data,
                    options: .init(
                        cacheControl: "3600",
                        contentType: contentType,
                        upsert: false
                    )
                )

            print("✅ Upload successful!")
        } catch {
            print("❌ Storage upload failed: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            throw error
        }

        // Get public URL
        let publicURL = try client.storage
            .from("memories")
            .getPublicURL(path: filePath)

        print("✅ Upload complete: \(publicURL.absoluteString)")
        return publicURL.absoluteString
    }

    /// Delete memory media from Supabase Storage
    func deleteMemoryMedia(url: String) async throws {
        // Extract the file path from the URL
        guard let urlObj = URL(string: url),
              let path = urlObj.pathComponents.last else {
            return
        }

        try await client.storage
            .from("memories")
            .remove(paths: [path])

        print("✅ Media file deleted: \(path)")
    }
}
