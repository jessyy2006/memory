//
//  AuthenticationService.swift
//  Memory
//
//  Created by Jessica Young on 11/19/25.
//

import Foundation
import SwiftUI
import AuthenticationServices
import Supabase
import Auth
import CryptoKit

enum AuthError: LocalizedError {
    case invalidEmail
    case invalidPhoneNumber
    case weakPassword
    case verificationFailed
    case userAlreadyExists
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Please enter a valid email address"
        case .invalidPhoneNumber:
            return "Please enter a valid phone number"
        case .weakPassword:
            return "Password must be at least 8 characters with letters and numbers"
        case .verificationFailed:
            return "Verification code is incorrect"
        case .userAlreadyExists:
            return "An account with this email or phone number already exists"
        case .unknown(let message):
            return message
        }
    }
}

@Observable
class AuthenticationService {
    var currentUser: User?
    var isAuthenticated = false

    private let supabase = SupabaseManager.shared
    private var currentNonce: String?

    var currentUserId: UUID? {
        currentUser?.id
    }

    init() {
        // Check for existing session on init
        Task {
            await restoreSession()
        }
    }

    // MARK: - Session Management

    @MainActor
    private func restoreSession() async {
        do {
            print("🔄 Checking for existing session...")

            if let session = try await supabase.getCurrentSession() {
                print("✅ Found existing session for user: \(session.user.id)")

                // Check if session is expired
                if Date().timeIntervalSince1970 > session.expiresAt {
                    print("⚠️ Session is expired")
                    isAuthenticated = false
                    currentUser = nil
                    return
                }

                // Session is valid - restore authentication state
                print("✅ Session is valid, restoring authentication...")

                let user = User(
                    id: session.user.id,
                    email: session.user.email,
                    isEmailVerified: true,
                    authProvider: .emailPassword
                )

                currentUser = user
                isAuthenticated = true
                print("✅ Authentication restored successfully")
            } else {
                print("ℹ️ No existing session found")
                isAuthenticated = false
            }
        } catch {
            print("❌ Error restoring session: \(error.localizedDescription)")
            isAuthenticated = false
            currentUser = nil
        }
    }

    // MARK: - Email/Phone Validation

    func validateEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    func validatePhoneNumber(_ phone: String) -> Bool {
        // Remove common formatting characters
        let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        // Check for valid length (10-15 digits, optionally starting with +)
        return cleaned.count >= 10 && cleaned.count <= 15
    }

    func validatePassword(_ password: String) -> Bool {
        // At least 8 characters, contains letters and numbers
        let minLength = password.count >= 8
        let hasLetters = password.rangeOfCharacter(from: .letters) != nil
        let hasNumbers = password.rangeOfCharacter(from: .decimalDigits) != nil
        return minLength && hasLetters && hasNumbers
    }

    // MARK: - Account Creation

    func createAccount(
        email: String?,
        phoneNumber: String?,
        password: String,
        provider: AuthProvider = .emailPassword
    ) async throws -> User {
        // Validate inputs
        if let email = email, !email.isEmpty {
            guard validateEmail(email) else {
                throw AuthError.invalidEmail
            }
        }

        if let phone = phoneNumber, !phone.isEmpty {
            guard validatePhoneNumber(phone) else {
                throw AuthError.invalidPhoneNumber
            }
        }

        guard validatePassword(password) else {
            throw AuthError.weakPassword
        }

        do {
            // Create account in Supabase
            print("📝 Creating account...")
            let authResponse: AuthResponse
            if let email = email, !email.isEmpty {
                print("📧 Signing up with email: \(email)")
                authResponse = try await supabase.signUpWithEmail(email: email, password: password)
            } else if let phone = phoneNumber, !phone.isEmpty {
                print("📱 Signing up with phone: \(phone)")
                authResponse = try await supabase.signUpWithPhone(phone: phone, password: password)
            } else {
                throw AuthError.unknown("No email or phone provided")
            }

            let userId = authResponse.user.id
            print("✅ Account created with user ID: \(userId)")
            print("✅ User profile automatically created by database trigger")

            // Create local user object with Supabase user ID
            let user = User(
                id: userId,
                email: email,
                phoneNumber: phoneNumber,
                isEmailVerified: false,
                isPhoneVerified: false,
                authProvider: provider
            )

            self.currentUser = user
            self.isAuthenticated = false // Require verification first

            print("✅ Account creation complete. Check your email/phone for verification code.")
            return user

        } catch let error as AuthError {
            print("❌ Auth error: \(error.localizedDescription)")
            throw error
        } catch {
            // Map Supabase errors to our custom errors
            print("❌ Supabase error: \(error.localizedDescription)")
            throw AuthError.unknown(error.localizedDescription)
        }
    }

    // MARK: - 2FA Verification

    func sendVerificationCode(to contact: String, isEmail: Bool) async throws {
        do {
            print("📤 Sending verification code to \(contact)...")
            if isEmail {
                try await supabase.resendVerificationEmail(email: contact)
                print("✅ Email sent successfully")
            } else {
                try await supabase.resendVerificationSMS(phone: contact)
                print("✅ SMS sent successfully")
            }
        } catch {
            print("❌ Failed to send verification code: \(error.localizedDescription)")
            throw AuthError.unknown("Failed to send verification code: \(error.localizedDescription)")
        }
    }

    func verifyCode(_ code: String, for user: User, isEmail: Bool) async throws -> Bool {
        do {
            let authResponse: AuthResponse
            if isEmail, let email = user.email {
                authResponse = try await supabase.verifyEmailOTP(email: email, token: code)
            } else if !isEmail, let phone = user.phoneNumber {
                authResponse = try await supabase.verifyPhoneOTP(phone: phone, token: code)
            } else {
                throw AuthError.unknown("No email or phone number to verify")
            }

            // Update user with Supabase user ID
            let userId = authResponse.user.id
            user.id = userId

            // Update verification status
            if isEmail {
                user.isEmailVerified = true
            } else {
                user.isPhoneVerified = true
            }

            // Update last login in database
            try await supabase.updateLastLogin(userId: userId)

            self.currentUser = user
            // Don't set isAuthenticated yet - wait for profile completion
            user.lastLoginAt = Date()

            return true

        } catch {
            throw AuthError.verificationFailed
        }
    }

    // MARK: - Apple Sign In Helpers

    func generateNonce() -> String {
        let nonce = randomNonceString()
        self.currentNonce = nonce
        return sha256(nonce)
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()

        return hashString
    }

    // MARK: - Social Authentication

    func signInWithApple(authorization: ASAuthorization) async throws -> User {
        // Handle Apple Sign In
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            let email = appleIDCredential.email
            let identityToken = appleIDCredential.identityToken

            guard let tokenData = identityToken,
                  let tokenString = String(data: tokenData, encoding: .utf8) else {
                throw AuthError.unknown("Failed to get Apple identity token")
            }

            do {
                // Use the stored nonce (or generate one if missing)
                guard let nonce = currentNonce else {
                    throw AuthError.unknown("Invalid Apple Sign In state - missing nonce")
                }

                // Sign in with Supabase using Apple token
                let session: Auth.Session = try await supabase.signInWithApple(
                    idToken: tokenString,
                    nonce: nonce
                )

                // Update last login
                let userId = session.user.id
                try await supabase.updateLastLogin(userId: userId)

                let user = User(
                    id: userId,
                    email: email ?? session.user.email,
                    isEmailVerified: true,
                    authProvider: .apple
                )

                self.currentUser = user
                self.isAuthenticated = true
                user.lastLoginAt = Date()

                return user

            } catch {
                throw AuthError.unknown("Failed to authenticate with Apple: \(error.localizedDescription)")
            }
        }

        throw AuthError.unknown("Invalid Apple authorization")
    }

    func signInWithGoogle(idToken: String) async throws -> User {
        do {
            // Sign in with Supabase using Google token
            let session: Auth.Session = try await supabase.signInWithGoogle(idToken: idToken)

            // Update last login
            let userId = session.user.id
            try await supabase.updateLastLogin(userId: userId)

            let user = User(
                id: userId,
                email: session.user.email,
                isEmailVerified: true,
                authProvider: .google
            )

            self.currentUser = user
            self.isAuthenticated = true
            user.lastLoginAt = Date()

            return user

        } catch {
            throw AuthError.unknown("Failed to authenticate with Google: \(error.localizedDescription)")
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        do {
            try await supabase.signOut()
        } catch {
            print("Error signing out from Supabase: \(error.localizedDescription)")
        }

        currentUser = nil
        isAuthenticated = false
    }
}
