//
//  AuthTextField.swift
//  Memory
//
//  Created by Jessica Young on 11/19/25.
//

import SwiftUI
import UIKit

struct AuthTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var errorMessage: String? = nil

    @State private var isPasswordVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            HStack {
                if isSecure && !isPasswordVisible {
                    SecureField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textContentType(isSecure ? .password : .none)
                        .autocapitalization(.none)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textContentType(textContentType)
                        .autocapitalization(autocapitalization)
                }

                if isSecure {
                    Button(action: { isPasswordVisible.toggle() }) {
                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(errorMessage != nil ? Color.red : Color.clear, lineWidth: 1)
            )

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private var textContentType: UITextContentType? {
        if title.lowercased().contains("email") {
            return .emailAddress
        } else if title.lowercased().contains("phone") {
            return .telephoneNumber
        }
        return .none
    }

    private var autocapitalization: UITextAutocapitalizationType {
        if keyboardType == .emailAddress {
            return .none
        }
        return .sentences
    }
}

#Preview {
    VStack(spacing: 20) {
        AuthTextField(
            title: "Email",
            placeholder: "Enter your email",
            text: .constant("")
        )

        AuthTextField(
            title: "Password",
            placeholder: "Enter your password",
            text: .constant(""),
            isSecure: true
        )

        AuthTextField(
            title: "Email",
            placeholder: "Enter your email",
            text: .constant("invalid"),
            errorMessage: "Please enter a valid email"
        )
    }
    .padding()
}
