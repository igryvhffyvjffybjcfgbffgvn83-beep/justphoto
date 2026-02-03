import Foundation

enum DatabasePaths {
    static func databaseDirectoryURL(appSubdirName: String = "JustPhoto") throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let dir = base
            .appendingPathComponent(appSubdirName, isDirectory: true)
            .appendingPathComponent("Database", isDirectory: true)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func databaseFileURL(
        appSubdirName: String = "JustPhoto",
        filename: String = "justphoto.sqlite"
    ) throws -> URL {
        let dir = try databaseDirectoryURL(appSubdirName: appSubdirName)
        return dir.appendingPathComponent(filename, isDirectory: false)
    }
}
