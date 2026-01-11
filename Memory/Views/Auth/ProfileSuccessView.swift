//
//  ProfileSuccessView.swift
//  Memory
//
//  Created by Jessica Young on 11/19/25.
//

import SwiftUI
import Combine

struct ProfileSuccessView: View {
    let user: User
    let profileImage: Image?
    @Environment(AuthenticationService.self) private var authService

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Success Icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
            }

            // Success Message
            VStack(spacing: 8) {
                Text("Profile Complete!")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Welcome to Memory")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            // Profile Information Card
            VStack(spacing: 20) {
                // Profile Picture
                if let profileImage = profileImage {
                    profileImage
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                        )
                }

                // User Details
                VStack(spacing: 12) {
                    if let fullName = user.fullName {
                        ProfileInfoRow(icon: "person.fill", label: "Name", value: fullName)
                    }

                    if let username = user.username {
                        ProfileInfoRow(icon: "at", label: "Username", value: "@\(username)")
                    }

                    if let email = user.email {
                        ProfileInfoRow(icon: "envelope.fill", label: "Email", value: email)
                    } else if let phone = user.phoneNumber {
                        ProfileInfoRow(icon: "phone.fill", label: "Phone", value: phone)
                    }

                    ProfileInfoRow(
                        icon: "checkmark.shield.fill",
                        label: "Verified",
                        value: user.isEmailVerified || user.isPhoneVerified ? "Yes" : "No"
                    )
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(15)
            }
            .padding(.horizontal, 24)

            Spacer()

            // Continue Button
            AuthButton(
                title: "Continue to App",
                style: .primary,
                action: {
                    // Mark as fully authenticated
                    authService.isAuthenticated = true
                }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .navigationBarBackButtonHidden(true)
    }
}

struct ProfileInfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Spacer()
        }
    }
}

#Preview {
    @Previewable @State var authService = AuthenticationService()
    ProfileSuccessView(
        user: User(
            email: "jessica@example.com",
            fullName: "Jessica Young",
            username: "jessicay",
            isEmailVerified: true
        ),
        profileImage: nil
    )
    .environment(authService)
}
