//
//  VerificationCodeView.swift
//  Memory
//
//  Created by Jessica Young on 11/19/25.
//

import SwiftUI

struct VerificationCodeView: View {
    @Bindable var authService: AuthenticationService
    let user: User
    let contactMethod: String
    let isEmail: Bool
    let onVerificationSuccess: () -> Void

    @State private var verificationCode = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?
    @State private var isResending = false
    @State private var canResend = true
    @State private var remainingSeconds = 0
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private let codeLength = 6

    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: isEmail ? "envelope.fill" : "message.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Verify Your \(isEmail ? "Email" : "Phone Number")")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("We've sent a 6-digit code to")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                Text(contactMethod)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .padding(.top, 40)

            // Verification Code Input
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    ForEach(0..<codeLength, id: \.self) { index in
                        VerificationDigitBox(
                            digit: index < verificationCode.count
                                ? String(verificationCode[verificationCode.index(verificationCode.startIndex, offsetBy: index)])
                                : "",
                            isFocused: index == verificationCode.count
                        )
                    }
                }

                // Hidden TextField for input
                TextField("", text: $verificationCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .focused($isTextFieldFocused)
                    .onChange(of: verificationCode) { _, newValue in
                        // Limit to 6 digits
                        if newValue.count > codeLength {
                            verificationCode = String(newValue.prefix(codeLength))
                        }
                        // Auto-verify when 6 digits entered
                        if verificationCode.count == codeLength {
                            verifyCode()
                        }
                        errorMessage = nil
                    }

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 8)
                }
            }

            // Verify Button
            AuthButton(
                title: "Verify",
                style: .primary,
                isLoading: isVerifying,
                action: verifyCode
            )
            .disabled(verificationCode.count != codeLength)
            .opacity(verificationCode.count == codeLength ? 1.0 : 0.6)

            // Resend Code
            VStack(spacing: 8) {
                Text("Didn't receive the code?")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                if canResend {
                    Button(action: resendCode) {
                        if isResending {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Resend Code")
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                    }
                    .disabled(isResending)
                } else {
                    Text("Resend in \(remainingSeconds)s")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .navigationBarBackButtonHidden(false)
        .onAppear {
            // Focus the hidden text field to show keyboard
            isTextFieldFocused = true
        }
        .onTapGesture {
            // Tap anywhere to refocus if keyboard was dismissed
            isTextFieldFocused = true
        }
    }

    // MARK: - Actions

    private func verifyCode() {
        guard verificationCode.count == codeLength else { return }

        print("🔐 Starting verification with code: \(verificationCode)")

        Task { @MainActor in
            isVerifying = true
            defer {
                isVerifying = false
                print("🔐 isVerifying set to false")
            }

            do {
                print("🔐 Calling authService.verifyCode...")
                let success = try await authService.verifyCode(
                    verificationCode,
                    for: user,
                    isEmail: isEmail
                )

                print("🔐 Verification result: \(success)")

                if success {
                    // Successfully verified - navigate to profile completion
                    print("✅ Verification successful! Triggering navigation callback...")
                    onVerificationSuccess()
                    print("✅ Navigation callback triggered")
                } else {
                    print("❌ Verification returned false")
                }
            } catch let error as AuthError {
                print("❌ AuthError during verification: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                // Clear the code so user can try again
                verificationCode = ""
            } catch {
                print("❌ Unknown error during verification: \(error.localizedDescription)")
                errorMessage = "Verification failed. Please try again."
                verificationCode = ""
            }
        }
    }

    private func resendCode() {
        print("🔄 Resend code button tapped")
        print("🔄 Contact: \(contactMethod), isEmail: \(isEmail)")

        Task { @MainActor in
            isResending = true
            canResend = false
            defer {
                isResending = false
                print("🔄 Resend operation completed")
            }

            do {
                print("🔄 Calling authService.sendVerificationCode...")
                try await authService.sendVerificationCode(
                    to: contactMethod,
                    isEmail: isEmail
                )

                print("✅ Verification code resent successfully")
                // Start countdown
                remainingSeconds = 60
                startResendTimer()

            } catch {
                print("❌ Failed to resend: \(error.localizedDescription)")
                errorMessage = "Failed to resend code. Please try again."
                canResend = true
            }
        }
    }

    private func startResendTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            } else {
                canResend = true
                timer.invalidate()
            }
        }
    }
}

struct VerificationDigitBox: View {
    let digit: String
    let isFocused: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))
                .frame(width: 45, height: 55)

            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Color.blue : Color.clear, lineWidth: 2)
                .frame(width: 45, height: 55)

            Text(digit)
                .font(.title)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    @Previewable @State var authService = AuthenticationService()
    NavigationStack {
        VerificationCodeView(
            authService: authService,
            user: User(email: "test@example.com"),
            contactMethod: "test@example.com",
            isEmail: true,
            onVerificationSuccess: {
                print("Verification successful in preview")
            }
        )
    }
}
