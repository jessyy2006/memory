//
//  CreateAccountView.swift
//  Memory
//
//  Created by Jessica Young on 11/19/25.
//

import SwiftUI
import AuthenticationServices

enum ContactMethod {
    case email
    case phone
}

struct CreateAccountView: View {
    @Environment(AuthenticationService.self) private var authService
    @State private var contactMethod: ContactMethod = .email
    @State private var emailOrPhone = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    @State private var emailError: String?
    @State private var phoneError: String?
    @State private var passwordError: String?
    @State private var confirmPasswordError: String?

    @State private var isCreatingAccount = false
    @State private var showVerificationView = false
    @State private var createdUser: User?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Create Account")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Sign up to get started")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 40)

                    // Contact Method Picker
                    Picker("Contact Method", selection: $contactMethod) {
                        Text("Email").tag(ContactMethod.email)
                        Text("Phone").tag(ContactMethod.phone)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: contactMethod) { _, _ in
                        clearErrors()
                        emailOrPhone = ""
                    }

                    // Email or Phone Field
                    if contactMethod == .email {
                        AuthTextField(
                            title: "Email Address",
                            placeholder: "your.email@example.com",
                            text: $emailOrPhone,
                            keyboardType: .emailAddress,
                            errorMessage: emailError
                        )
                        .onChange(of: emailOrPhone) { _, _ in
                            emailError = nil
                        }
                    } else {
                        AuthTextField(
                            title: "Phone Number",
                            placeholder: "+1 (555) 123-4567",
                            text: $emailOrPhone,
                            keyboardType: .phonePad,
                            errorMessage: phoneError
                        )
                        .onChange(of: emailOrPhone) { _, _ in
                            phoneError = nil
                        }
                    }

                    // Password Fields
                    AuthTextField(
                        title: "Password",
                        placeholder: "At least 8 characters",
                        text: $password,
                        isSecure: true,
                        errorMessage: passwordError
                    )
                    .onChange(of: password) { _, _ in
                        passwordError = nil
                    }

                    AuthTextField(
                        title: "Confirm Password",
                        placeholder: "Re-enter your password",
                        text: $confirmPassword,
                        isSecure: true,
                        errorMessage: confirmPasswordError
                    )
                    .onChange(of: confirmPassword) { _, _ in
                        confirmPasswordError = nil
                    }

                    // Password Requirements
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password must contain:")
                            .font(.caption)
                            .foregroundColor(.gray)

                        HStack(spacing: 4) {
                            Image(systemName: password.count >= 8 ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(password.count >= 8 ? .green : .gray)
                                .font(.caption)
                            Text("At least 8 characters")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: password.rangeOfCharacter(from: .letters) != nil ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(password.rangeOfCharacter(from: .letters) != nil ? .green : .gray)
                                .font(.caption)
                            Text("Letters")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: password.rangeOfCharacter(from: .decimalDigits) != nil ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(password.rangeOfCharacter(from: .decimalDigits) != nil ? .green : .gray)
                                .font(.caption)
                            Text("Numbers")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Create Account Button
                    AuthButton(
                        title: "Create Account",
                        style: .primary,
                        isLoading: isCreatingAccount,
                        action: createAccount
                    )
                    .padding(.top, 8)

                    // Divider
                    DividerWithText(text: "OR")
                        .padding(.vertical, 8)

                    // Social Sign In Buttons
                    SignInWithAppleButton(.signUp) { request in
                        request.requestedScopes = [.email, .fullName]
                        request.nonce = authService.generateNonce()
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(10)

                    AuthButton(
                        title: "Sign in with Google",
                        style: .google,
                        action: handleGoogleSignIn
                    )

                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .navigationDestination(isPresented: $showVerificationView) {
                if let user = createdUser {
                    @Bindable var bindableAuthService = authService
                    VerificationCodeView(
                        authService: bindableAuthService,
                        user: user,
                        contactMethod: contactMethod == .email ? user.email ?? "" : user.phoneNumber ?? "",
                        isEmail: contactMethod == .email
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func createAccount() {
        clearErrors()

        // Validate passwords match
        guard password == confirmPassword else {
            confirmPasswordError = "Passwords do not match"
            return
        }

        Task {
            isCreatingAccount = true
            defer { isCreatingAccount = false }

            do {
                let user = try await authService.createAccount(
                    email: contactMethod == .email ? emailOrPhone : nil,
                    phoneNumber: contactMethod == .phone ? emailOrPhone : nil,
                    password: password
                )

                // Verification email is automatically sent by Supabase
                // No need to manually send it here

                createdUser = user
                showVerificationView = true

            } catch let error as AuthError {
                handleAuthError(error)
            } catch {
                passwordError = "An unexpected error occurred"
            }
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        Task {
            isCreatingAccount = true
            defer { isCreatingAccount = false }

            do {
                switch result {
                case .success(let authorization):
                    print("🍎 Apple authorization received")
                    let user = try await authService.signInWithApple(authorization: authorization)
                    print("✅ Successfully signed in with Apple: \(user.email ?? "No email")")
                    // Authentication complete - authService.isAuthenticated should be true

                case .failure(let error):
                    print("❌ Apple Sign In failed: \(error.localizedDescription)")
                    passwordError = "Apple Sign In failed: \(error.localizedDescription)"
                }
            } catch let error as AuthError {
                print("❌ Auth error: \(error.localizedDescription)")
                passwordError = error.localizedDescription
            } catch {
                print("❌ Error: \(error.localizedDescription)")
                passwordError = "Apple Sign In error: \(error.localizedDescription)"
            }
        }
    }

    private func handleGoogleSignIn() {
        // Google Sign In requires additional setup
        passwordError = "Google Sign In requires GoogleSignIn SDK. Please check SUPABASE_SETUP.md for instructions."
        print("⚠️ Google Sign In tapped - Requires GoogleSignIn SDK setup")
    }

    private func handleAuthError(_ error: AuthError) {
        switch error {
        case .invalidEmail:
            emailError = error.localizedDescription
        case .invalidPhoneNumber:
            phoneError = error.localizedDescription
        case .weakPassword:
            passwordError = error.localizedDescription
        default:
            passwordError = error.localizedDescription
        }
    }

    private func clearErrors() {
        emailError = nil
        phoneError = nil
        passwordError = nil
        confirmPasswordError = nil
    }
}

#Preview {
    CreateAccountView()
        .environment(AuthenticationService())
}
