//
//  NSCharacterSet+ASCII.swift
//  AltSign
//

import Foundation

extension CharacterSet {

    // Equivalent to +asciiAlphanumericCharacterSet
    // Apple's servers only accept ASCII alphanumerics.

    public static var asciiAlphanumericCharacterSet: CharacterSet {
        CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        )
    }
}

extension Data {
    func hexEncodedString() -> String {
        return self.map { String(format: "%02hhx", $0) }.joined()
    }
}

