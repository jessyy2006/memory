//
//  AuthButton.swift
//  Memory
//
//  Created by Jessica Young on 11/19/25.
//

import SwiftUI

enum AuthButtonStyle {
    case primary
    case secondary
    case apple
    case google

    var backgroundColor: Color {
        switch self {
        case .primary:
            return .blue
        case .secondary:
            return Color(.systemGray6)
        case .apple:
            return .black
        case .google:
            return .white
        }
    }

    var foregroundColor: Color {
        switch self {
        case .primary, .apple:
            return .white
        case .secondary:
            return .primary
        case .google:
            return .black
        }
    }

    var borderColor: Color? {
        switch self {
        case .google:
            return Color(.systemGray4)
        default:
            return nil
        }
    }
}

struct AuthButton: View {
    let title: String
    let style: AuthButtonStyle
    let icon: String?
    let isLoading: Bool
    let action: () -> Void

    init(
        title: String,
        style: AuthButtonStyle = .primary,
        icon: String? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.icon = icon
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                }

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(
                            tint: style.foregroundColor
                        ))
                } else {
                    Text(title)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundColor(style.foregroundColor)
            .background(style.backgroundColor)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(style.borderColor ?? Color.clear, lineWidth: 1)
            )
        }
        .disabled(isLoading)
    }
}

struct DividerWithText: View {
    let text: String

    var body: some View {
        HStack {
            VStack { Divider() }
            Text(text)
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.horizontal, 8)
            VStack { Divider() }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        AuthButton(
            title: "Create Account",
            style: .primary,
            action: {}
        )

        AuthButton(
            title: "Cancel",
            style: .secondary,
            action: {}
        )

        AuthButton(
            title: "Sign in with Apple",
            style: .apple,
            icon: "apple.logo",
            action: {}
        )

        AuthButton(
            title: "Sign in with Google",
            style: .google,
            action: {}
        )

        AuthButton(
            title: "Loading...",
            style: .primary,
            isLoading: true,
            action: {}
        )

        DividerWithText(text: "OR")
    }
    .padding()
}
