//
//  Archive.swift
//  AltSign
//
//  Created by Magesh K on 28/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import NativeBridge

public enum Archive {

    public struct Entry: Sendable, Hashable {
        public let filename: String
        public let uncompressedSize: Int64
        public let compressedSize: Int64
        public let crc: UInt32
        public let externalAttributes: UInt32

        public var isDirectory: Bool {
            return filename.hasSuffix("/") || ((externalAttributes >> 16) & 0o040000 != 0)
        }

        public var posixPermissions: UInt32 {
            let perms = (externalAttributes >> 16) & 0o777
            if perms != 0 { return perms }
            return isDirectory ? 0o755 : 0o644
        }

        public init(
            filename: String,
            uncompressedSize: Int64,
            compressedSize: Int64,
            crc: UInt32,
            externalAttributes: UInt32
        ) {
            self.filename = filename
            self.uncompressedSize = uncompressedSize
            self.compressedSize = compressedSize
            self.crc = crc
            self.externalAttributes = externalAttributes
        }
    }

    public final class Reader {

        private let handle: native_bridge_unzFile

        private init(_ handle: native_bridge_unzFile) {
            self.handle = handle
        }

        deinit {
            native_bridge_unzClose(handle)
        }

        public static func open(at url: URL) throws -> Reader {
            verboseLog("[AltSign] Archive.Reader.open(at: \(url.path)) started")
            guard FileManager.default.fileExists(atPath: url.path) else {
                debugLog("[AltSign] Archive.Reader.open failed: file not found at \(url.path)")
                throw Archive.Error.fileNotFound(url)
            }
            var status: Int32 = 0
            guard let h = url.path.withCString({
                native_bridge_unzOpenWithStatus($0, &status)
            }) else {
                debugLog("[AltSign] Archive.Reader.open failed with minizip-ng status: \(status)")
                if status == -111 /* MZ_OPEN_ERROR */ {
                    throw Archive.Error.readFailed(url)
                }
                throw Archive.Error.corruptArchive(url)
            }
            verboseLog("[AltSign] Archive.Reader.open succeeded")
            return Reader(h)
        }

        public func goToFirstFile() throws {
            verboseLog("[AltSign] Archive.Reader.goToFirstFile called")
            guard native_bridge_unzGoToFirstFile(handle) == 0 else {
                debugLog("[AltSign] Archive.Reader.goToFirstFile failed")
                throw Archive.Error.readFailed(.init(fileURLWithPath: ""))
            }
        }

        public func goToNextFile() -> Bool {
            let hasNext = native_bridge_unzGoToNextFile(handle) == 0
            verboseLog("[AltSign] Archive.Reader.goToNextFile called. Has next file: \(hasNext)")
            return hasNext
        }

        public func currentFilename() throws -> String {
            var info = [UInt8](repeating: 0, count: 256)
            var name = [CChar](repeating: 0, count: 1024)

            let r = native_bridge_unzGetCurrentFileInfo(
                handle,
                &info,
                &name,
                1024
            )

            guard r == 0 else {
                debugLog("[AltSign] Archive.Reader.currentFilename failed to get info from native bridge")
                throw Archive.Error.readFailed(.init(fileURLWithPath: ""))
            }

            let filename = String(cString: name)
            verboseLog("[AltSign] Archive.Reader.currentFilename retrieved: \(filename)")
            return filename
        }

        public func currentFileExternalAttributes() -> UInt32 {
            return native_bridge_unzGetCurrentFileExternalAttributes(handle)
        }

        public func currentEntry() throws -> Entry {
            var info = native_bridge_zip_entry_info()
            guard native_bridge_unzGetCurrentEntryInfo(handle, &info) == 0 else {
                debugLog("[AltSign] Archive.Reader.currentEntry failed to read entry info")
                throw Archive.Error.readFailed(.init(fileURLWithPath: ""))
            }

            let filenameWithPtr = withUnsafeBytes(of: &info.filename) { rawBuffer in
                String(cString: rawBuffer.baseAddress!.assumingMemoryBound(to: CChar.self))
            }

            return Entry(
                filename: filenameWithPtr,
                uncompressedSize: info.uncompressed_size,
                compressedSize: info.compressed_size,
                crc: info.crc,
                externalAttributes: info.external_fa
            )
        }

        public func entries() throws -> [Entry] {
            var result: [Entry] = []
            try goToFirstFile()
            repeat {
                let entry = try currentEntry()
                result.append(entry)
            } while goToNextFile()
            return result
        }

        public func readCurrentFile() throws -> Data {
            verboseLog("[AltSign] Archive.Reader.readCurrentFile started")
            guard native_bridge_unzOpenCurrentFile(handle) == 0 else {
                debugLog("[AltSign] Archive.Reader.readCurrentFile failed: native_bridge_unzOpenCurrentFile returned error")
                throw Archive.Error.readFailed(.init(fileURLWithPath: ""))
            }

            defer {
                native_bridge_unzCloseCurrentFile(handle)
            }

            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 32_768)

            while true {
                let read = native_bridge_unzReadCurrentFile(
                    handle,
                    &buffer,
                    UInt32(buffer.count)
                )

                if read < 0 {
                    debugLog("[AltSign] Archive.Reader.readCurrentFile failed: native_bridge_unzReadCurrentFile returned error code \(read)")
                    throw Archive.Error.readFailed(.init(fileURLWithPath: ""))
                }

                if read == 0 { break }

                result.append(buffer, count: Int(read))
            }

            verboseLog("[AltSign] Archive.Reader.readCurrentFile completed. Read size: \(result.count) bytes")
            return result
        }

        public func extractCurrentFile(to destinationURL: URL) throws {
            verboseLog("[AltSign] Archive.Reader.extractCurrentFile(to: \(destinationURL.path)) started")
            let result = destinationURL.path.withCString {
                native_bridge_unzExtractCurrentFileToFile(handle, $0)
            }
            guard result == 0 else {
                debugLog("[AltSign] Archive.Reader.extractCurrentFile failed: native_bridge_unzExtractCurrentFileToFile returned error")
                throw Archive.Error.readFailed(destinationURL)
            }
            verboseLog("[AltSign] Archive.Reader.extractCurrentFile completed successfully")
        }
    }

    public final class Writer {

        private let handle: native_bridge_zipFile

        private init(_ handle: native_bridge_zipFile) {
            self.handle = handle
        }

        deinit {
            verboseLog("[AltSign] Archive.Writer.deinit closing zip handle")
            native_bridge_zipClose(handle)
        }

        public static func create(at url: URL) throws -> Writer {
            verboseLog("[AltSign] Archive.Writer.create(at: \(url.path)) started")
            var status: Int32 = 0
            guard let h = url.path.withCString({
                native_bridge_zipOpenWithStatus($0, &status)
            }) else {
                debugLog("[AltSign] Archive.Writer.create failed with minizip-ng status: \(status)")
                throw Archive.Error.writeFailed(url)
            }
            verboseLog("[AltSign] Archive.Writer.create succeeded")
            return Writer(h)
        }

        public func setCompressLevel(_ level: Int16) {
            native_bridge_zipSetCompressLevel(handle, level)
        }

        public func addFile(at fileURL: URL, pathInZip: String) throws {
            verboseLog("[AltSign] Archive.Writer.addFile started for file: \(fileURL.path) -> \(pathInZip)")
            let ok = fileURL.path.withCString { sourcePath in
                pathInZip.withCString { zipPath in
                    native_bridge_zipAddFile(handle, sourcePath, zipPath) == 0
                }
            }
            guard ok else {
                debugLog("[AltSign] Archive.Writer.addFile failed for \(fileURL.path)")
                throw Archive.Error.writeFailed(fileURL)
            }
            verboseLog("[AltSign] Archive.Writer.addFile completed successfully")
        }

        public func writeFile(path: String, data: Data?, permissions: UInt32) throws {
            verboseLog("[AltSign] Archive.Writer.writeFile started for internal path: '\(path)', data size: \(data?.count ?? 0) bytes, permissions: \(String(format: "%0o", permissions))")

            let openOK = path.withCString {
                native_bridge_zipOpenNewFileInZipWithPermissions(handle, $0, permissions)
            } == 0

            guard openOK else {
                debugLog("[AltSign] Archive.Writer.writeFile failed: native_bridge_zipOpenNewFileInZipWithPermissions returned error")
                throw Archive.Error.writeFailed(.init(fileURLWithPath: path))
            }

            defer {
                native_bridge_zipCloseFileInZip(handle)
            }

            guard let data else {
                verboseLog("[AltSign] Archive.Writer.writeFile completed: no data to write")
                return
            }

            let ok = data.withUnsafeBytes {
                native_bridge_zipWriteInFileInZip(
                    handle,
                    $0.baseAddress,
                    UInt32(data.count)
                )
            } == 0

            guard ok else {
                debugLog("[AltSign] Archive.Writer.writeFile failed: native_bridge_zipWriteInFileInZip returned error")
                throw Archive.Error.writeFailed(.init(fileURLWithPath: path))
            }

            verboseLog("[AltSign] Archive.Writer.writeFile completed successfully")
        }
    }

    public enum Error: Swift.Error, LocalizedError {
        case fileNotFound(URL)
        case corruptArchive(URL)
        case readFailed(URL)
        case writeFailed(URL)
        case missingAppBundle(URL)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return "File not found: \(url.lastPathComponent)"
            case .corruptArchive(let url):
                return "Archive appears to be corrupt: \(url.lastPathComponent)"
            case .readFailed(let url):
                return "Failed to read archive: \(url.lastPathComponent)"
            case .writeFailed(let url):
                return "Failed to write archive: \(url.lastPathComponent)"
            case .missingAppBundle(let url):
                return "No .app bundle found inside \(url.lastPathComponent)"
            }
        }
    }
}
