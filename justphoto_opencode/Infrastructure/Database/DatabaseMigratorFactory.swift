import Foundation
import GRDB

enum DatabaseMigratorFactory {
    /// M1.10: migration framework placeholder.
    /// M1.12 will register schema migrations.
    static func makeMigrator() -> DatabaseMigrator {
        DatabaseMigrator()
    }
}
