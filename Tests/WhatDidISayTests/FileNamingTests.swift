import Foundation
import Testing
@testable import WhatDidISay

@Suite struct FileNamingTests {
    @Test func takenNamesGetTheNextFreeSuffix() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileNamingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func next() -> String { FileNaming.uniqueURL(base: "call", ext: "m4a", in: folder).lastPathComponent }

        #expect(next() == "call.m4a")
        FileManager.default.createFile(atPath: folder.appendingPathComponent("call.m4a").path, contents: nil)
        #expect(next() == "call (2).m4a")
        FileManager.default.createFile(atPath: folder.appendingPathComponent("call (2).m4a").path, contents: nil)
        #expect(next() == "call (3).m4a")
    }
}
