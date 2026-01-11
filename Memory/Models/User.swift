//
//  User.swift
//  Memory
//
//  Created by Jessica Young on 11/19/25.
//

import Foundation
import SwiftData

@Model
final class User {
    var id: UUID
    var email: String?
    var phoneNumber: String?
    var fullName: String?
    var username: String?
    var profileImageURL: String?
    var isEmailVerified: Bool
    var isPhoneVerified: Bool
    var createdAt: Date
    var lastLoginAt: Date?
    var authProvider: AuthProvider

    init(
        id: UUID = UUID(),
        email: String? = nil,
        phoneNumber: String? = nil,
        fullName: String? = nil,
        username: String? = nil,
        profileImageURL: String? = nil,
        isEmailVerified: Bool = false,
        isPhoneVerified: Bool = false,
        createdAt: Date = Date(),
        lastLoginAt: Date? = nil,
        authProvider: AuthProvider = .emailPassword
    ) {
        self.id = id
        self.email = email
        self.phoneNumber = phoneNumber
        self.fullName = fullName
        self.username = username
        self.profileImageURL = profileImageURL
        self.isEmailVerified = isEmailVerified
        self.isPhoneVerified = isPhoneVerified
        self.createdAt = createdAt
        self.lastLoginAt = lastLoginAt
        self.authProvider = authProvider
    }
}

enum AuthProvider: String, Codable {
    case emailPassword
    case phonePassword
    case apple
    case google
}
