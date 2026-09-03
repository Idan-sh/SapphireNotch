//
//  ModelSecurity.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

#if !SAPPHIRE_FULL_BUILD
import Foundation
import CryptoKit

enum ModelSecurity {
    /// Placeholder key — real Face ID model decryption requires the private package.
    static var encryptionKey: SymmetricKey {
        SymmetricKey(size: .bits256)
    }
}
#endif
