//
//  ProfileCompletionView.swift
//  Memory
//
//  Created by Jessica Young on 11/19/25.
//

import SwiftUI
import PhotosUI
import Auth

struct ProfileCompletionView: View {
    @Bindable var authService: AuthenticationService
    let user: User

    @State private var fullName = ""
    @State private var username = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: Image?
    @State private var profileImageData: Data?
    @State private var isCompleting = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 8) {
                Text("Complete Your Profile")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Tell us a bit about yourself")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.top, 40)

            // Profile Picture Picker
            VStack(spacing: 16) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    ZStack {
                        if let profileImage = profileImage {
                            profileImage
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color(.systemGray5))
                                .frame(width: 120, height: 120)
                                .overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 30))
                                            .foregroundColor(.gray)
                                        Text("Add Photo")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                )
                        }
                    }
                }
                .onChange(of: selectedPhoto) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            profileImage = Image(uiImage: uiImage)
                            profileImageData = data
                        }
                    }
                }

                Text("Optional")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            // Full Name Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Full Name")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                TextField("Enter your full name", text: $fullName)
                    .textContentType(.name)
                    .autocapitalization(.words)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }

            // Username Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                TextField("Choose a username", text: $username)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Spacer()

            // Complete Button
            AuthButton(
                title: "Complete Profile",
                style: .primary,
                isLoading: isCompleting,
                action: completeProfile
            )
            .disabled(fullName.isEmpty || username.isEmpty)
            .opacity(fullName.isEmpty || username.isEmpty ? 0.6 : 1.0)
        }
        .padding(.horizontal, 24)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $showSuccess) {
            ProfileSuccessView(user: user, profileImage: profileImage)
        }
    }

    // MARK: - Actions

    private func completeProfile() {
        guard !fullName.isEmpty else {
            errorMessage = "Please enter your full name"
            return
        }

        guard !username.isEmpty else {
            errorMessage = "Please enter a username"
            return
        }

        Task {
            isCompleting = true
            defer { isCompleting = false }

            do {
                print("🚀 Starting profile completion...")

                // Get the current user ID from auth
                print("🔍 Getting current user...")
                let authUser = try await SupabaseManager.shared.getCurrentUser()
                let userId = authUser.id
                print("✅ User ID: \(userId)")

                // Upload profile photo if selected
                var avatarUrl: String? = nil
                if let imageData = profileImageData {
                    print("📷 Uploading profile photo (\(imageData.count) bytes)...")
                    do {
                        avatarUrl = try await SupabaseManager.shared.uploadAvatar(
                            userId: userId,
                            imageData: imageData
                        )
                        print("✅ Photo uploaded: \(avatarUrl ?? "unknown")")
                    } catch {
                        print("⚠️ Photo upload failed: \(error.localizedDescription)")
                        print("⚠️ Continuing without photo...")
                        // Don't fail the whole process if photo upload fails
                    }
                }

                // Update profile in database
                print("💾 Updating profile in database...")
                print("   Username: \(username)")
                print("   Full name: \(fullName)")
                print("   Avatar URL: \(avatarUrl ?? "none")")

                do {
                    try await SupabaseManager.shared.updateUserProfile(
                        userId: userId,
                        username: username,
                        fullName: fullName,
                        bio: nil,
                        avatarUrl: avatarUrl
                    )
                    print("✅ Profile updated in database")
                } catch {
                    print("❌ Database update failed: \(error)")
                    print("❌ Error details: \(error.localizedDescription)")
                    throw error
                }

                // Update local user object
                user.fullName = fullName
                user.username = username
                user.profileImageURL = avatarUrl

                print("✅ Profile completed successfully!")
                print("   Name: \(fullName)")
                print("   Username: \(username)")
                print("   Photo: \(avatarUrl != nil ? "Uploaded" : "None")")

                // Small delay to ensure everything is saved
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                // Navigate to success page
                await MainActor.run {
                    showSuccess = true
                }

            } catch {
                print("❌ Error completing profile: \(error)")
                print("❌ Error type: \(type(of: error))")
                print("❌ Error details: \(error.localizedDescription)")

                await MainActor.run {
                    errorMessage = "Failed to complete profile: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var authService = AuthenticationService()
    ProfileCompletionView(
        authService: authService,
        user: User(email: "test@example.com")
    )
}
