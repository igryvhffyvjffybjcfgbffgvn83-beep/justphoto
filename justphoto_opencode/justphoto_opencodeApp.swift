//
//  justphoto_opencodeApp.swift
//  justphoto_opencode
//
//  Created by 番茄 on 1/2/2026.
//

import SwiftUI
import GRDB

@main
struct justphoto_opencodeApp: App {
    init() {
        print("GRDBReady")

        do {
            let result = try DatabaseManager.shared.start()
            print("DBOpened: \(result.path) existed_before=\(result.existedBefore) exists_after=\(result.existsAfter)")

            if result.migratedV1 {
                print("DBMigrated:v1")
            } else {
                print("DBMigrationsUpToDate")
            }
        } catch {
            print("DBOpenFAILED: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
