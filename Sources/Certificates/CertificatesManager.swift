//
//  CertificatesManager.swift
//  AltSign
//
//  Created by Magesh K on 07/07/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import CodeSignKit

public enum CertificatesManager {

    public typealias CSRSubject = CodeSignKit.CSRSubject

    public enum Error: Swift.Error {
        case operationFailed(String)
    }

    private static func extractDERFromPEMOrDER(_ data: Data, boundaryKeyword: String) -> Data? {
        if let str = String(data: data, encoding: .utf8), str.contains("-----BEGIN ") {
            let lines = str.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)

            guard let beginIndex = lines.firstIndex(where: { $0.contains("-----BEGIN ") && $0.contains("\(boundaryKeyword)-----") }),
                  let endIndex = lines[beginIndex...].firstIndex(where: { $0.contains("-----END ") && $0.contains("\(boundaryKeyword)-----") }) else {
                return nil
            }

            let base64Body = lines[(beginIndex + 1)..<endIndex]
                .filter { !$0.hasPrefix("Bag Attributes") }
                .filter { !$0.hasPrefix("    ") }
                .filter { !$0.hasPrefix("localKeyID:") }
                .filter { !$0.hasPrefix("friendlyName:") }
                .filter { !$0.hasPrefix("Key Attributes:") }
                .joined()

            return Data(base64Encoded: base64Body, options: .ignoreUnknownCharacters)
        }
        return data
    }

    public static func generateCSR(
        subject: CSRSubject
    ) throws -> (csr: Data, privateKey: Data) {
        verboseLog("""
        [AltSign] CertificatesManager.generateCSR started:
          • Country: \(subject.country)
          • State: \(subject.state)
          • Locality: \(subject.locality)
          • Organization: \(subject.organization)
          • Common Name: \(subject.commonName)
        """)

        do {
            let result = try CSRBuilder.generate(subject: subject)
            let csrData = Data(result.csrPEM.utf8)
            let keyData = Data(result.privateKeyPEM.utf8)
            verboseLog("[AltSign] CertificatesManager.generateCSR succeeded. Generated CSR size: \(csrData.count) bytes, privateKey size: \(keyData.count) bytes")
            return (csrData, keyData)
        } catch {
            throw Error.operationFailed("CSR generation failed: \(error.localizedDescription)")
        }
    }

    public static func extractPKCS12(
        _ data: Data,
        password: String?
    ) throws -> (cert: Data, key: Data) {
        verboseLog("[AltSign] CertificatesManager.extractPKCS12 started. Data size: \(data.count) bytes, hasPassword: \(password != nil)")

        let parser: PKCS12Parser
        do {
            parser = try PKCS12Parser(p12Data: data, password: password ?? "")
        } catch {
            verboseLog("[AltSign] CertificatesManager.extractPKCS12 failed: \(error)")
            throw ALTCertificateError.decryptionFailed(cause: error.localizedDescription)
        }

        guard let leafCert = parser.leafCertificate else {
            throw ALTCertificateError.extractionFailed(cause: "No X.509 certificate found in PKCS#12 archive")
        }

        let certPEM = "-----BEGIN CERTIFICATE-----\n" +
            leafCert.rawDER.base64EncodedString(options: .lineLength64Characters) +
            "\n-----END CERTIFICATE-----\n"
        let certData = Data(certPEM.utf8)

        let keyData: Data
        if let keyDER = parser.privateKeyDER {
            let keyPEM = "-----BEGIN RSA PRIVATE KEY-----\n" +
                keyDER.base64EncodedString(options: .lineLength64Characters) +
                "\n-----END RSA PRIVATE KEY-----\n"
            keyData = Data(keyPEM.utf8)
        } else {
            keyData = Data()
        }

        verboseLog("[AltSign] CertificatesManager.extractPKCS12 succeeded. Extracted cert size: \(certData.count) bytes, key size: \(keyData.count) bytes")
        return (certData, keyData)
    }

    public static func parseCertificate(
        _ data: Data
    ) -> (name: String, serial: String, creationDate: Date?, expiryDate: Date?)? {
        verboseLog("[AltSign] CertificatesManager.parseCertificate started. Cert size: \(data.count) bytes")

        guard let derData = extractDERFromPEMOrDER(data, boundaryKeyword: "CERTIFICATE"),
              let cert = X509Certificate(der: derData) else {
            verboseLog("[AltSign] CertificatesManager.parseCertificate failed: unable to decode X.509 certificate")
            return nil
        }

        let name = cert.commonName ?? cert.subjectSummary
        let serial = cert.serialNumberHex
        let creationDate = cert.notBefore
        let expiryDate = cert.notAfter

        verboseLog("[AltSign] CertificatesManager.parseCertificate succeeded. Name: \(name), Serial: \(serial)")
        return (name, serial, creationDate, expiryDate)
    }

    public static func createPKCS12(
        cert: Data,
        key: Data?,
        password: String?
    ) throws -> Data {
        verboseLog("[AltSign] CertificatesManager.createPKCS12 started. Cert size: \(cert.count) bytes, hasKey: \(key != nil)")

        guard let certDER = extractDERFromPEMOrDER(cert, boundaryKeyword: "CERTIFICATE") else {
            throw Error.operationFailed("failed to parse certificate during PKCS12 generation")
        }

        var keyDER: Data? = nil
        if let keyData = key {
            keyDER = extractDERFromPEMOrDER(keyData, boundaryKeyword: "PRIVATE KEY") ??
                     extractDERFromPEMOrDER(keyData, boundaryKeyword: "RSA PRIVATE KEY") ?? keyData
        }

        do {
            let result = try PKCS12Builder.build(
                certificateDER: certDER,
                privateKeyDER: keyDER,
                password: password
            )
            verboseLog("[AltSign] CertificatesManager.createPKCS12 succeeded. Output size: \(result.count) bytes")
            return result
        } catch {
            throw Error.operationFailed("failed to create PKCS12 container: \(error.localizedDescription)")
        }
    }

    public static func extractUnencryptedPKCS12(_ data: Data) throws -> (cert: Data, key: Data) {
        return try extractPKCS12(data, password: nil)
    }

    public static func createUnencryptedPKCS12(cert: Data, key: Data?) throws -> Data {
        return try createPKCS12(cert: cert, key: key, password: nil)
    }
}
