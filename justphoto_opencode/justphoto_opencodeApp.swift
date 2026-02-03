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
    @Environment(\.scenePhase) private var scenePhase

    init() {
        print("GRDBReady")

        do {
            let result = try DatabaseManager.shared.start()
            print("DBOpened: \(result.path) existed_before=\(result.existedBefore) exists_after=\(result.existsAfter)")

            if result.newMigrations.isEmpty {
                print("DBMigrationsUpToDate")
            } else {
                for id in result.newMigrations {
                    print("DBMigrated:\(id)")
                }
            }

            let session = try SessionRepository.shared.ensureFreshSession(scene: "cafe")
            print("SessionReady: \(session.sessionId) changed=\(session.changed)")
            if let counts = try SessionRepository.shared.currentWorksetCounts() {
                print("WorksetCounts: session_items=\(counts.sessionItems) ref_items=\(counts.refItems)")
            }
        } catch {
            print("DBOpenFAILED: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        do {
                            _ = try SessionRepository.shared.ensureFreshSession(scene: "cafe")
                            try SessionRepository.shared.touchCurrentSession()
                        } catch {
                            print("SessionEnsureFAILED: \(error)")
                        }
                    case .inactive, .background:
                        DatabaseManager.shared.flush(reason: "scenePhase_\(String(describing: phase))")
                    @unknown default:
                        break
                    }
                }
        }
    }
}
