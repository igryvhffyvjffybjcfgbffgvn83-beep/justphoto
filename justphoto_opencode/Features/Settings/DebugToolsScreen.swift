#if DEBUG

import Foundation
import SwiftUI
import GRDB
import AVFoundation
import Photos
import UIKit

struct DebugToolsScreen: View {
    @EnvironmentObject private var promptCenter: PromptCenter

    @State private var statusText: String = ""
    @State private var statusIsError: Bool = false
    @State private var isRunning: Bool = false
    @State private var isRefTargetRunning: Bool = false

    @State private var showAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""

    @State private var m49LastPendingRelPath: String = ""
    @State private var m4CleanupTestItemId: String = ""

    @State private var showingViewerDebug: Bool = false
    private static let cueStabilityLayer = CueStabilityLayer()

    var body: some View {
#if true
        List {
            Section("Debug Tools") {
                Group {
                Button("DebugToolsPing") {
                    print("DebugToolsPing")
                }

                Button("PromptModelSmokeTest") {
                    let p = Prompt(
                        key: "debug_test",
                        level: .L3,
                        surface: .sheetModalCenter,
                        priority: 1,
                        blocksShutter: false,
                        isClosable: false,
                        autoDismissSeconds: nil,
                        gate: .none,
                        title: "Test Title",
                        message: "Test message",
                        primaryActionId: "dismiss",
                        primaryTitle: "OK",
                        secondaryActionId: nil,
                        secondaryTitle: nil,
                        tertiaryActionId: nil,
                        tertiaryTitle: nil,
                        throttle: .init(
                            perKeyMinIntervalSec: 0,
                            globalWindowSec: 0,
                            globalMaxCountInWindow: 0,
                            suppressAfterDismissSec: 0
                        ),
                        payload: [
                            "count": .int(1),
                            "scene": .string("cafe")
                        ],
                        emittedAt: Date()
                    )

                    do {
                        let data = try JSONEncoder().encode(p)
                        let json = String(data: data, encoding: .utf8) ?? "<utf8 failed>"
                        print("PromptModelSmokeTest: \(json)")
                        statusText = "PromptModelSmokeTest: OK\n\n\(json)"
                        statusIsError = false
                        alertTitle = "Prompt model"
                        alertMessage = "Encoded OK"
                        showAlert = true
                    } catch {
                        print("PromptModelSmokeTestFAILED: \(error)")
                        statusText = "PromptModelSmokeTest: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "Prompt model failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("ShowTestL3") {
                    promptCenter.show(makeTestL3Prompt(key: "test_l3", title: "Test Modal"))
                }

                Button("ShowTestL3A") {
                    promptCenter.show(makeTestL3Prompt(key: "A", title: "Test A"))
                }

                Button("ShowTestL3B") {
                    promptCenter.show(makeTestL3Prompt(key: "B", title: "Test B"))
                }

                Button("ShowTestToast") {
                    promptCenter.show(makeTestL1ToastPrompt(key: "toast_test"))
                }

                Button("ShowTestBannerWithButton") {
                    promptCenter.show(makeTestL2BannerWithButton(key: "banner_test"))
                }

                Button("ShowTestBannerAutoDismiss") {
                    promptCenter.show(makeTestL2BannerAutoDismiss(key: "banner_auto"))
                }

                Button("PrintDiagnosticsPath") {
                    do {
                        let logger = DiagnosticsLogger()
                        let dir = try logger.diagnosticsDirectoryURL()
                        let file = try logger.currentLogFileURL()

                        print("DiagnosticsDirectory: \(dir.path)")
                        print("DiagnosticsPath: \(file.path)")

                        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
                        if !names.isEmpty {
                            print("DiagnosticsFiles: \(names.sorted())")
                        }

                        statusText = "DiagnosticsDirectory:\n\(dir.path)\n\nDiagnosticsPath:\n\(file.path)"
                        statusIsError = false
                        alertTitle = "Diagnostics path"
                        alertMessage = file.path
                        showAlert = true
                    } catch {
                        statusText = "PrintDiagnosticsPath: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "Diagnostics path failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("PrintDBPath") {
                    do {
                        let fileURL = try DatabasePaths.databaseFileURL()
                        print("DBPath: \(fileURL.path)")

                        statusText = "DBPath:\n\(fileURL.path)"
                        statusIsError = false
                        alertTitle = "DB path"
                        alertMessage = fileURL.path
                        showAlert = true
                    } catch {
                        statusText = "PrintDBPath: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "DB path failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("PrintCameraAuth") {
                    let av = AVCaptureDevice.authorizationStatus(for: .video)
                    let mapped = CameraAuthMapper.map(av)
                    print("PrintCameraAuth:\(mapped.rawValue) av=\(String(describing: av))")

                    statusText = "CameraAuth:\n\(mapped.rawValue)\n\nAVAuthorizationStatus:\n\(String(describing: av))"
                    statusIsError = false
                    alertTitle = "CameraAuth"
                    alertMessage = mapped.rawValue
                    showAlert = true
                }

                Button("SimulateWarmupDelay=0s") {
                    WarmupDebugSettings.setSimulatedReadyDelaySec(0)
                    let v = WarmupDebugSettings.simulatedReadyDelaySec()
                    print("SimulateWarmupDelaySet:\(v)s")

                    statusText = "SimulateWarmupDelay: \(v)s"
                    statusIsError = false
                    alertTitle = "Warmup delay"
                    alertMessage = "\(v)s"
                    showAlert = true
                }

                Button("SimulateWarmupDelay=4s") {
                    WarmupDebugSettings.setSimulatedReadyDelaySec(4)
                    let v = WarmupDebugSettings.simulatedReadyDelaySec()
                    print("SimulateWarmupDelaySet:\(v)s")

                    statusText = "SimulateWarmupDelay: \(v)s"
                    statusIsError = false
                    alertTitle = "Warmup delay"
                    alertMessage = "\(v)s"
                    showAlert = true
                }

                Button("SimulateWarmupDelay=9s (fail)") {
                    WarmupDebugSettings.setSimulatedReadyDelaySec(9)
                    let v = WarmupDebugSettings.simulatedReadyDelaySec()
                    print("SimulateWarmupDelaySet:\(v)s")

                    statusText = "SimulateWarmupDelay: \(v)s"
                    statusIsError = false
                    alertTitle = "Warmup delay"
                    alertMessage = "\(v)s"
                    showAlert = true
                }

                Button("PrintWarmupDelay") {
                    let v = WarmupDebugSettings.simulatedReadyDelaySec()
                    print("WarmupDelay:\(v)s")

                    statusText = "WarmupDelay: \(v)s"
                    statusIsError = false
                    alertTitle = "Warmup delay"
                    alertMessage = "\(v)s"
                    showAlert = true
                }

                Button("SimulateCameraInitFailureReason=permission_denied") {
                    CameraInitFailureDebugSettings.setSimulatedFailureReason(.permission_denied)
                    let v = CameraInitFailureDebugSettings.simulatedFailureReason()?.rawValue ?? "<nil>"
                    print("SimulateCameraInitFailureReasonSet:\(v)")

                    statusText = "CameraInitFailureReason: \(v)"
                    statusIsError = false
                    alertTitle = "Camera init reason"
                    alertMessage = v
                    showAlert = true
                }

                Button("SimulateCameraInitFailureReason=camera_in_use") {
                    CameraInitFailureDebugSettings.setSimulatedFailureReason(.camera_in_use)
                    let v = CameraInitFailureDebugSettings.simulatedFailureReason()?.rawValue ?? "<nil>"
                    print("SimulateCameraInitFailureReasonSet:\(v)")

                    statusText = "CameraInitFailureReason: \(v)"
                    statusIsError = false
                    alertTitle = "Camera init reason"
                    alertMessage = v
                    showAlert = true
                }

                Button("SimulateCameraInitFailureReason=hardware_unavailable") {
                    CameraInitFailureDebugSettings.setSimulatedFailureReason(.hardware_unavailable)
                    let v = CameraInitFailureDebugSettings.simulatedFailureReason()?.rawValue ?? "<nil>"
                    print("SimulateCameraInitFailureReasonSet:\(v)")

                    statusText = "CameraInitFailureReason: \(v)"
                    statusIsError = false
                    alertTitle = "Camera init reason"
                    alertMessage = v
                    showAlert = true
                }

                Button("SimulateCameraInitFailureReason=unknown") {
                    CameraInitFailureDebugSettings.setSimulatedFailureReason(.unknown)
                    let v = CameraInitFailureDebugSettings.simulatedFailureReason()?.rawValue ?? "<nil>"
                    print("SimulateCameraInitFailureReasonSet:\(v)")

                    statusText = "CameraInitFailureReason: \(v)"
                    statusIsError = false
                    alertTitle = "Camera init reason"
                    alertMessage = v
                    showAlert = true
                }

                Button("ClearCameraInitFailureReason") {
                    CameraInitFailureDebugSettings.setSimulatedFailureReason(nil)
                    let v = CameraInitFailureDebugSettings.simulatedFailureReason()?.rawValue ?? "<nil>"
                    print("SimulateCameraInitFailureReasonCleared")

                    statusText = "CameraInitFailureReason: \(v)"
                    statusIsError = false
                    alertTitle = "Camera init reason"
                    alertMessage = v
                    showAlert = true
                }

                Button("PrintCameraInitFailureReason") {
                    let v = CameraInitFailureDebugSettings.simulatedFailureReason()?.rawValue ?? "<nil>"
                    print("CameraInitFailureReason:\(v)")

                    statusText = "CameraInitFailureReason: \(v)"
                    statusIsError = false
                    alertTitle = "Camera init reason"
                    alertMessage = v
                    showAlert = true
                }

                Button("DBCheckTables") {
                    do {
                        guard let queue = DatabaseManager.shared.dbQueue else {
                            throw NSError(domain: "Database", code: 1, userInfo: [NSLocalizedDescriptionKey: "DB not ready"])
                        }

                        let (sessionsExists, sessionItemsExists, refItemsExists, localStatsExists) = try queue.read { db in
                            (
                                try db.tableExists("sessions"),
                                try db.tableExists("session_items"),
                                try db.tableExists("ref_items"),
                                try db.tableExists("local_stats")
                            )
                        }

                        let sessionsText = sessionsExists ? "true" : "false"
                        let sessionItemsText = sessionItemsExists ? "true" : "false"
                        let refItemsText = refItemsExists ? "true" : "false"
                        let localStatsText = localStatsExists ? "true" : "false"
                        print("DBCheckTables: sessions=\(sessionsText) session_items=\(sessionItemsText) ref_items=\(refItemsText) local_stats=\(localStatsText)")

                        statusText = "DBCheckTables\n\nsessions=\(sessionsText)\nsession_items=\(sessionItemsText)\nref_items=\(refItemsText)\nlocal_stats=\(localStatsText)"
                        statusIsError = !(sessionsExists && sessionItemsExists && refItemsExists && localStatsExists)
                        alertTitle = "DBCheckTables"
                        alertMessage = "sessions=\(sessionsText)\nsession_items=\(sessionItemsText)\nref_items=\(refItemsText)\nlocal_stats=\(localStatsText)"
                        showAlert = true
                    } catch {
                        statusText = "DBCheckTables: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "DBCheckTables failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("PrintDBStartMetrics") {
                    if let metrics = DatabaseManager.shared.lastStartMetrics {
                        let formatter = ISO8601DateFormatter()
                        let startedAt = formatter.string(from: metrics.startedAt)
                        let migrations = metrics.newMigrations.isEmpty ? "none" : metrics.newMigrations.joined(separator: ", ")
                        let mainText = metrics.wasMainThread ? "true" : "false"
                        print(
                            "DBStartMetrics: started_at=\(startedAt) duration_ms=\(metrics.durationMs) main_thread=\(mainText) existed_before=\(metrics.existedBefore) exists_after=\(metrics.existsAfter) new_migrations=\(migrations) path=\(metrics.path)"
                        )

                        statusText = """
                        DBStartMetrics

                        started_at=\(startedAt)
                        duration_ms=\(metrics.durationMs)
                        main_thread=\(mainText)
                        existed_before=\(metrics.existedBefore)
                        exists_after=\(metrics.existsAfter)
                        new_migrations=\(migrations)
                        path=\(metrics.path)
                        """
                        statusIsError = false
                        alertTitle = "DBStartMetrics"
                        alertMessage = "duration_ms=\(metrics.durationMs)\nmain_thread=\(mainText)\nnew_migrations=\(migrations)"
                        showAlert = true
                    } else {
                        statusText = "DBStartMetrics: missing (DB not started)"
                        statusIsError = true
                        alertTitle = "DBStartMetrics"
                        alertMessage = "No start metrics yet."
                        showAlert = true
                    }
                }

                Button("CreateNewSession") {
                    do {
                        let id = try SessionRepository.shared.createNewSession(scene: "cafe")
                        print("SessionCreated:\(id)")

                        statusText = "CreateNewSession: OK\n\nSessionCreated:\n\(id)"
                        statusIsError = false
                        alertTitle = "Session created"
                        alertMessage = id
                        showAlert = true
                    } catch {
                        statusText = "CreateNewSession: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "Session create failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("PrintSessionId") {
                    do {
                        let id = try SessionRepository.shared.currentSessionId() ?? "<nil>"
                        print("CurrentSessionId:\(id)")

                        statusText = "CurrentSessionId:\n\(id)"
                        statusIsError = false
                        alertTitle = "Current session"
                        alertMessage = id
                        showAlert = true
                    } catch {
                        statusText = "PrintSessionId: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "PrintSessionId failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("SetSessionOldLastActive") {
                    do {
                        // Create a fresh session, seed some rows, then force lastActiveAt to >12h ago.
                        let id = try SessionRepository.shared.createNewSession(scene: "cafe")
                        try SessionRepository.shared.seedWorksetForCurrentSession()

                        let oldLastActiveMs = Int64((Date().timeIntervalSince1970 - (13 * 60 * 60)) * 1000)
                        try SessionRepository.shared.setCurrentSessionLastActiveMs(oldLastActiveMs)

                        let counts = try SessionRepository.shared.currentWorksetCounts()
                        print("SetSessionOldLastActive: session_id=\(id) last_active_ms=\(oldLastActiveMs)")
                        if let counts {
                            print("WorksetSeeded: session_items=\(counts.sessionItems) ref_items=\(counts.refItems)")
                        }

                        statusText = "SetSessionOldLastActive: OK\n\nSessionId:\n\(id)\n\nlast_active_ms:\n\(oldLastActiveMs)"
                        statusIsError = false
                        alertTitle = "Session lastActive forced old"
                        alertMessage = id
                        showAlert = true
                    } catch {
                        statusText = "SetSessionOldLastActive: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "SetSessionOldLastActive failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("PrintWorksetCounts") {
                    do {
                        let counts = try SessionRepository.shared.currentWorksetCounts()
                        let sessionItems = counts?.sessionItems ?? -1
                        let refItems = counts?.refItems ?? -1
                        print("WorksetCounts: session_items=\(sessionItems) ref_items=\(refItems)")

                        statusText = "WorksetCounts\n\nsession_items=\(sessionItems)\nref_items=\(refItems)"
                        statusIsError = false
                        alertTitle = "Workset counts"
                        alertMessage = "session_items=\(sessionItems) ref_items=\(refItems)"
                        showAlert = true
                    } catch {
                        statusText = "PrintWorksetCounts: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "PrintWorksetCounts failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("PrintCounts") {
                    do {
                        let counts = try SessionRepository.shared.currentWorksetCounter()
                        let workset = counts?.worksetCount ?? -1
                        let inflight = counts?.inFlightCount ?? -1
                        print("Counts: workset_count=\(workset) in_flight_count=\(inflight)")

                        statusText = "Counts\n\nworkset_count=\(workset)\nin_flight_count=\(inflight)"
                        statusIsError = false
                        alertTitle = "Counts"
                        alertMessage = "workset_count=\(workset) in_flight_count=\(inflight)"
                        showAlert = true
                    } catch {
                        statusText = "PrintCounts: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "PrintCounts failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                }
            }

            Section("M4 Tools") {
                Button("M4.7 ForceShutterTap (bypass UI)") {
                    CaptureCoordinator.shared.shutterTapped()
                    statusText = "M4.7 ForceShutterTap: sent"
                    statusIsError = false
                    alertTitle = "M4.7 shutter"
                    alertMessage = "sent"
                    showAlert = true
                }

                Button("M4.8 PrintLatestSessionItem") {
                    do {
                        if let s = try SessionRepository.shared.latestSessionItemForCurrentSession() {
                            print("M4.8LatestItem: item_id=\(s.itemId) shot_seq=\(s.shotSeq) state=\(s.state.rawValue) liked=\(s.liked) asset_id=\(s.assetId ?? "<nil>") pending=\(s.pendingFileRelPath ?? "<nil>")")
                            statusText = "M4.8LatestItem\n\nitem_id=\(s.itemId)\nshot_seq=\(s.shotSeq)\nstate=\(s.state.rawValue)\nliked=\(s.liked)\nasset_id=\(s.assetId ?? "<nil>")\npending=\(s.pendingFileRelPath ?? "<nil>")"
                            statusIsError = false
                            alertTitle = "M4.8 latest"
                            alertMessage = "shot_seq=\(s.shotSeq)"
                            showAlert = true
                        } else {
                            print("M4.8LatestItem: <nil>")
                            statusText = "M4.8LatestItem\n\n<nil>"
                            statusIsError = false
                            alertTitle = "M4.8 latest"
                            alertMessage = "<nil>"
                            showAlert = true
                        }
                    } catch {
                        statusText = "M4.8LatestItem: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "M4.8 latest failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("M4.15 MarkLatestWriteFailed") {
                    do {
                        guard let latest = try SessionRepository.shared.latestSessionItemForCurrentSession() else {
                            statusText = "M4.15 MarkLatestWriteFailed: no latest item"
                            statusIsError = true
                            alertTitle = "M4.15"
                            alertMessage = "no latest item"
                            showAlert = true
                            return
                        }

                        try SessionRepository.shared.markWriteFailed(itemId: latest.itemId)
                        print("M4.15MarkedWriteFailed: item_id=\(latest.itemId) shot_seq=\(latest.shotSeq)")

                        statusText = "M4.15 MarkLatestWriteFailed: OK\n\nitem_id=\(latest.itemId)\nshot_seq=\(latest.shotSeq)"
                        statusIsError = false
                        alertTitle = "M4.15 marked"
                        alertMessage = "DBFlushed should appear"
                        showAlert = true
                    } catch {
                        statusText = "M4.15 MarkLatestWriteFailed: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "M4.15 failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("M4.9 WriteDummyPending") {
                    do {
                        let itemId = UUID().uuidString
                        let rel = PendingFileStore.shared.makeRelativePath(itemId: itemId, fileExtension: "bin")
                        let payload = "dummy-\(itemId)".data(using: .utf8) ?? Data([0x64, 0x75, 0x6D, 0x6D, 0x79])
                        let url = try PendingFileStore.shared.writeAtomic(data: payload, toRelativePath: rel)
                        let exists = FileManager.default.fileExists(atPath: url.path)

                        m49LastPendingRelPath = rel
                        print("PendingFileWritten: rel_path=\(rel) url=\(url.path) bytes=\(payload.count) exists=\(exists)")

                        statusText = "M4.9 WriteDummyPending: OK\n\nrel_path=\(rel)\nurl=\(url.path)\nbytes=\(payload.count)\nexists=\(exists)"
                        statusIsError = false
                        alertTitle = "M4.9 pending written"
                        alertMessage = "exists=\(exists)"
                        showAlert = true
                    } catch {
                        statusText = "M4.9 WriteDummyPending: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "M4.9 pending failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("M4.9 DeleteLastDummyPending") {
                    do {
                        guard !m49LastPendingRelPath.isEmpty else {
                            statusText = "M4.9 DeleteLastDummyPending: no rel_path"
                            statusIsError = true
                            alertTitle = "M4.9 delete"
                            alertMessage = "no rel_path"
                            showAlert = true
                            return
                        }

                        let deleted = try PendingFileStore.shared.delete(relativePath: m49LastPendingRelPath)
                        print("PendingFileDeleted: rel_path=\(m49LastPendingRelPath) deleted=\(deleted)")

                        statusText = "M4.9 DeleteLastDummyPending: OK\n\nrel_path=\(m49LastPendingRelPath)\ndeleted=\(deleted)"
                        statusIsError = false
                        alertTitle = "M4.9 pending deleted"
                        alertMessage = "deleted=\(deleted)"
                        showAlert = true
                    } catch {
                        statusText = "M4.9 DeleteLastDummyPending: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "M4.9 delete failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("M4.A CleanupTest: PrepareLatestItemFiles") {
                    do {
                        guard let latest = try SessionRepository.shared.latestSessionItemForCurrentSession() else {
                            statusText = "CleanupTest: no latest item"
                            statusIsError = true
                            alertTitle = "CleanupTest"
                            alertMessage = "no latest item"
                            showAlert = true
                            return
                        }

                        let itemId = latest.itemId
                        let pendingRel = PendingFileStore.shared.makeRelativePath(itemId: itemId, fileExtension: "bin")
                        let thumbRel = ThumbCacheStore.shared.makeRelativePath(itemId: itemId, fileExtension: "bin")

                        let pendingData = "pending-\(itemId)".data(using: .utf8) ?? Data([0x70])
                        let thumbData = "thumb-\(itemId)".data(using: .utf8) ?? Data([0x74])

                        let pendingURL = try PendingFileStore.shared.writeAtomic(data: pendingData, toRelativePath: pendingRel)
                        let thumbURL = try ThumbCacheStore.shared.writeAtomic(data: thumbData, toRelativePath: thumbRel)

                        try SessionRepository.shared.updatePendingFileRelPath(itemId: itemId, relPath: pendingRel)
                        try SessionRepository.shared.updateThumbCacheRelPath(itemId: itemId, relPath: thumbRel)

                        let pendingExists = PendingFileStore.shared.fileExists(relativePath: pendingRel)
                        let thumbExists = ThumbCacheStore.shared.fileExists(relativePath: thumbRel)

                        m4CleanupTestItemId = itemId

                        print("CleanupTestPrepared: item_id=\(itemId) pending=\(pendingURL.path) exists=\(pendingExists) thumb=\(thumbURL.path) exists=\(thumbExists)")

                        statusText = "CleanupTestPrepared\n\nitem_id=\(itemId)\n\npending_rel=\(pendingRel)\npending_exists=\(pendingExists)\n\nthumb_rel=\(thumbRel)\nthumb_exists=\(thumbExists)"
                        statusIsError = false
                        alertTitle = "CleanupTest prepared"
                        alertMessage = "pending/thumb files written"
                        showAlert = true
                    } catch {
                        statusText = "CleanupTestPrepare FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "CleanupTest prepare failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("M4.A CleanupTest: CleanupPreparedItem") {
                    do {
                        guard !m4CleanupTestItemId.isEmpty else {
                            statusText = "CleanupTest: no prepared item_id"
                            statusIsError = true
                            alertTitle = "CleanupTest"
                            alertMessage = "no item_id"
                            showAlert = true
                            return
                        }

                        let r = try SessionRepository.shared.cleanupItem(itemId: m4CleanupTestItemId)
                        let pendingExists = (r.pendingFileRelPath.map { PendingFileStore.shared.fileExists(relativePath: $0) }) ?? false
                        let thumbExists = (r.thumbCacheRelPath.map { ThumbCacheStore.shared.fileExists(relativePath: $0) }) ?? false

                        print("CleanupTestResult: item_id=\(r.itemId) deleted=\(r.deletedRowCount) pending_rel=\(r.pendingFileRelPath ?? "<nil>") pending_deleted=\(r.pendingDeleted) pending_exists_after=\(pendingExists) thumb_rel=\(r.thumbCacheRelPath ?? "<nil>") thumb_deleted=\(r.thumbDeleted) thumb_exists_after=\(thumbExists)")

                        statusText = "CleanupTestResult\n\nitem_id=\(r.itemId)\ndeleted_row=\(r.deletedRowCount)\n\npending_rel=\(r.pendingFileRelPath ?? "<nil>")\npending_deleted=\(r.pendingDeleted)\npending_exists_after=\(pendingExists)\n\nthumb_rel=\(r.thumbCacheRelPath ?? "<nil>")\nthumb_deleted=\(r.thumbDeleted)\nthumb_exists_after=\(thumbExists)"
                        statusIsError = false
                        alertTitle = "CleanupTest cleaned"
                        alertMessage = "pending/thumb should be gone"
                        showAlert = true
                    } catch {
                        statusText = "CleanupTestCleanup FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "CleanupTest cleanup failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("M4.10 SimulateNoPhotoData (next shutter)") {
                    CaptureCoordinator.shared.setSimulateNoPhotoDataOnce()
                    print("M4.10SimulateNoPhotoDataOnce: armed")
                    statusText = "M4.10 SimulateNoPhotoData: armed for next shutter"
                    statusIsError = false
                    alertTitle = "M4.10 armed"
                    alertMessage = "next shutter will timeout"
                    showAlert = true
                }

                Button("M4.13 ForceFirstFetchNilThenSuccess (next verification)") {
                    CaptureCoordinator.shared.setForceFirstVerificationFetchNilOnce()
                    print("M4.13ForceFirstVerificationFetchNilOnce: armed")
                    statusText = "M4.13 ForceFirstFetchNilThenSuccess: armed for next verification"
                    statusIsError = false
                    alertTitle = "M4.13 armed"
                    alertMessage = "next write_success will retry after 500ms"
                    showAlert = true
                }

                Button("M4.19 TriggerCaptureFailed x3") {
                    Task { @MainActor in
                        for i in 1...3 {
                            NotificationCenter.default.post(name: CaptureEvents.captureFailed, object: nil)
                            print("M4.19PostCaptureFailed: #\(i)")
                            try? await Task.sleep(nanoseconds: 200_000_000)
                        }

                        let c = await CaptureFailureTracker.shared.currentCount()
                        print("M4.19Triggered: count_in_window=\(c)")
                        statusText = "M4.19 Triggered\n\ncount_in_window=\(c)"
                        statusIsError = false
                        alertTitle = "M4.19 triggered"
                        alertMessage = "count_in_window=\(c)"
                        showAlert = true
                    }
                }

                Button("M4.20 ThumbPipelineTest (latest item)") {
                    Task {
                        let latest = await MainActor.run { try? SessionRepository.shared.latestSessionItemForCurrentSession() }
                        guard let itemId = latest?.itemId else {
                            await MainActor.run {
                                statusText = "M4.20 ThumbPipelineTest: no latest item"
                                statusIsError = true
                                alertTitle = "M4.20"
                                alertMessage = "no latest item"
                                showAlert = true
                            }
                            return
                        }

                        await ThumbnailPipeline.shared.requestThumbnail(itemId: itemId)
                        await MainActor.run {
                            statusText = "M4.20 ThumbPipelineTest: requested\n\nitem_id=\(itemId)"
                            statusIsError = false
                            alertTitle = "M4.20"
                            alertMessage = "requested"
                            showAlert = true
                        }
                    }
                }

                Button("M4.21 DelayThumbnail=6s") {
                    Task {
                        await ThumbnailPipeline.shared.setDebugDelay(seconds: 6.0)
                        await MainActor.run {
                            statusText = "M4.21 DelayThumbnail: set to 6s"
                            statusIsError = false
                            alertTitle = "M4.21"
                            alertMessage = "delay=6s"
                            showAlert = true
                        }
                    }
                }

                Button("M4.21 DelayThumbnail=default") {
                    Task {
                        await ThumbnailPipeline.shared.setDebugDelay(seconds: nil)
                        await MainActor.run {
                            statusText = "M4.21 DelayThumbnail: reset to default"
                            statusIsError = false
                            alertTitle = "M4.21"
                            alertMessage = "delay=default"
                            showAlert = true
                        }
                    }
                }

                Button("M4.22 DelayThumbnail=6s (self-heal demo)") {
                    Task {
                        await ThumbnailPipeline.shared.setDebugDelay(seconds: 6.0)
                        await MainActor.run {
                            statusText = "M4.22 self-heal demo\n\nDelayThumbnail=6s"
                            statusIsError = false
                            alertTitle = "M4.22"
                            alertMessage = "delay=6s"
                            showAlert = true
                        }
                    }
                }

                Button("M4.23 DelayThumbnail=35s") {
                    Task {
                        await ThumbnailPipeline.shared.setDebugDelay(seconds: 35.0)
                        await MainActor.run {
                            statusText = "M4.23 DelayThumbnail: set to 35s"
                            statusIsError = false
                            alertTitle = "M4.23"
                            alertMessage = "delay=35s"
                            showAlert = true
                        }
                    }
                }

                Button("M4.23 OpenViewer") {
                    showingViewerDebug = true
                }

                Button("M4.25 ForceAlbumAddFailOnce") {
                    Task {
                        await AlbumArchiver.shared.setDebugForceFailOnce()
                        await MainActor.run {
                            statusText = "M4.25 ForceAlbumAddFailOnce: armed"
                            statusIsError = false
                            alertTitle = "M4.25"
                            alertMessage = "next album add will fail"
                            showAlert = true
                        }
                    }
                }

                Button("M4.27 ForceAlbumAddFailTimes=3") {
                    Task {
                        await AlbumArchiver.shared.setDebugForceFail(times: 3)
                        await MainActor.run {
                            statusText = "M4.27 ForceAlbumAddFailTimes: set to 3"
                            statusIsError = false
                            alertTitle = "M4.27"
                            alertMessage = "next 3 album adds will fail"
                            showAlert = true
                        }
                    }
                }

                Button("M4.25 PrintGateFlag (album_add_failed_banner)") {
                    do {
                        let key = PromptGateFlagKeys.sessionOnce(promptKey: "album_add_failed_banner")
                        let v = try SessionRepository.shared.sessionFlagBool(key)
                        print("M4.25GateFlag: \(key)=\(v)")
                        statusText = "M4.25GateFlag\n\n\(key)=\(v)"
                        statusIsError = false
                        alertTitle = "M4.25 gate"
                        alertMessage = v ? "true (will suppress banner)" : "false"
                        showAlert = true
                    } catch {
                        statusText = "M4.25GateFlag FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "M4.25 gate failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("M4.25 ClearGateFlag (album_add_failed_banner)") {
                    do {
                        let key = PromptGateFlagKeys.sessionOnce(promptKey: "album_add_failed_banner")
                        try SessionRepository.shared.setSessionFlagBool(key, value: false)
                        print("M4.25GateFlagCleared: \(key)=false")
                        statusText = "M4.25GateFlagCleared\n\n\(key)=false"
                        statusIsError = false
                        alertTitle = "M4.25 gate cleared"
                        alertMessage = "banner can show once again in this session"
                        showAlert = true
                    } catch {
                        statusText = "M4.25GateClear FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "M4.25 gate clear failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("ListSessionItemStates") {
                    let values = SessionItemState.allCases.map { $0.rawValue }
                    print("SessionItemStates: \(values)")
                    statusText = "SessionItemStates\n\n" + values.joined(separator: "\n")
                    statusIsError = false
                    alertTitle = "SessionItemStates"
                    alertMessage = "count=\(values.count)"
                    showAlert = true
                }

                Button("M4.14 PrintWriteFailReasons") {
                    let rows = WriteFailReason.allCases.map { r in
                        return "\(r.rawValue) -> \(r.reasonTextZh)"
                    }

                    let samples = [
                        "nil => \(WriteFailReason.writeFailedMessage(reason: nil))",
                    ] + WriteFailReason.allCases.map {
                        "\($0.rawValue) => \(WriteFailReason.writeFailedMessage(reason: $0))"
                    }

                    let msg = (rows + [""] + samples).joined(separator: "\n")
                    print("WriteFailReasons\n\n\(msg)")

                    statusText = "M4.14 WriteFailReasons\n\n" + msg
                    statusIsError = false
                    alertTitle = "M4.14 write_failed reasons"
                    alertMessage = WriteFailReason.allCases.map { $0.reasonTextZh }.joined(separator: "\n")
                    showAlert = true
                }

                Button("M4.3 NewSession + SeedWorksetThumbReady x14") {
                    do {
                        let id = try SessionRepository.shared.createNewSession(scene: "cafe")
                        let inserted = try SessionRepository.shared.insertWorksetItemsForCurrentSession(count: 14, state: .finalized)
                        let counts = try SessionRepository.shared.currentWorksetCounter()
                        let workset = counts?.worksetCount ?? -1
                        let inflight = counts?.inFlightCount ?? -1

                        print("M4.3Seed14: session_id=\(id) inserted=\(inserted) workset_count=\(workset) in_flight_count=\(inflight)")

                        statusText = "M4.3Seed14: OK\n\nSessionId:\n\(id)\n\ninserted=\(inserted)\nworkset_count=\(workset)\nin_flight_count=\(inflight)"
                        statusIsError = false
                        alertTitle = "M4.3 seeded 14"
                        alertMessage = "workset_count=\(workset)"
                        showAlert = true
                    } catch {
                        statusText = "M4.3Seed14: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "M4.3Seed14 failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("M4.3 InsertWorksetThumbReady x1") {
                    do {
                        let inserted = try SessionRepository.shared.insertWorksetItemsForCurrentSession(count: 1, state: .finalized)
                        let counts = try SessionRepository.shared.currentWorksetCounter()
                        let workset = counts?.worksetCount ?? -1

                        print("M4.3Insert1: inserted=\(inserted) workset_count=\(workset)")

                        statusText = "M4.3Insert1: OK\n\ninserted=\(inserted)\nworkset_count=\(workset)"
                        statusIsError = false
                        alertTitle = "M4.3 inserted 1"
                        alertMessage = "workset_count=\(workset)"
                        showAlert = true
                    } catch {
                        statusText = "M4.3Insert1: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "M4.3Insert1 failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("M4.3 PrintGateFlag (workset_15_count_banner)") {
                    do {
                        let k = PromptGateFlagKeys.sessionOnce(promptKey: "workset_15_count_banner")
                        let v = try SessionRepository.shared.sessionFlagBool(k)
                        print("M4.3GateFlag: \(k)=\(v)")

                        statusText = "M4.3GateFlag\n\n\(k)=\(v)"
                        statusIsError = false
                        alertTitle = "M4.3 gate flag"
                        alertMessage = "\(v)"
                        showAlert = true
                    } catch {
                        statusText = "M4.3GateFlag: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "M4.3GateFlag failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("M4.3 ClearGateFlag (workset_15_count_banner)") {
                    do {
                        let k = PromptGateFlagKeys.sessionOnce(promptKey: "workset_15_count_banner")
                        try SessionRepository.shared.setSessionFlagBool(k, value: false)
                        let v = try SessionRepository.shared.sessionFlagBool(k)
                        print("M4.3GateFlagCleared: \(k)=\(v)")

                        statusText = "M4.3GateFlagCleared\n\n\(k)=\(v)"
                        statusIsError = false
                        alertTitle = "M4.3 gate flag cleared"
                        alertMessage = "\(v)"
                        showAlert = true
                    } catch {
                        statusText = "M4.3GateFlagCleared: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "M4.3GateFlagCleared failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("M4.4 NewSession + SeedWorksetThumbReady x19") {
                    do {
                        let id = try SessionRepository.shared.createNewSession(scene: "cafe")
                        let inserted = try SessionRepository.shared.insertWorksetItemsForCurrentSession(count: 19, state: .finalized)
                        let counts = try SessionRepository.shared.currentWorksetCounter()
                        let workset = counts?.worksetCount ?? -1
                        let inflight = counts?.inFlightCount ?? -1

                        print("M4.4Seed19: session_id=\(id) inserted=\(inserted) workset_count=\(workset) in_flight_count=\(inflight)")

                        statusText = "M4.4Seed19: OK\n\nSessionId:\n\(id)\n\ninserted=\(inserted)\nworkset_count=\(workset)\nin_flight_count=\(inflight)"
                        statusIsError = false
                        alertTitle = "M4.4 seeded 19"
                        alertMessage = "workset_count=\(workset)"
                        showAlert = true
                    } catch {
                        statusText = "M4.4Seed19: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "M4.4Seed19 failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("M4.4 InsertWorksetThumbReady x1") {
                    do {
                        let inserted = try SessionRepository.shared.insertWorksetItemsForCurrentSession(count: 1, state: .finalized)
                        let counts = try SessionRepository.shared.currentWorksetCounter()
                        let workset = counts?.worksetCount ?? -1

                        print("M4.4Insert1: inserted=\(inserted) workset_count=\(workset)")

                        statusText = "M4.4Insert1: OK\n\ninserted=\(inserted)\nworkset_count=\(workset)"
                        statusIsError = false
                        alertTitle = "M4.4 inserted 1"
                        alertMessage = "workset_count=\(workset)"
                        showAlert = true
                    } catch {
                        statusText = "M4.4Insert1: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "M4.4Insert1 failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("M4.4 LikeLatest x3") {
                    do {
                        let updated = try SessionRepository.shared.setLikedForLatestItemsForCurrentSession(count: 3, liked: true)
                        let counts = try SessionRepository.shared.currentWorksetCounter()
                        let workset = counts?.worksetCount ?? -1
                        print("M4.4LikeLatest3: updated=\(updated) workset_count=\(workset)")

                        statusText = "M4.4LikeLatest3: OK\n\nupdated=\(updated)\nworkset_count=\(workset)"
                        statusIsError = false
                        alertTitle = "M4.4 liked latest"
                        alertMessage = "updated=\(updated)"
                        showAlert = true
                    } catch {
                        statusText = "M4.4LikeLatest3: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "M4.4LikeLatest3 failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

            }

            Section("PoseSpec / Diagnostics") {
                Button("M5.9 ForceFavoriteSyncFailOnce") {
                    Task {
                        await FavoriteSyncer.shared.setDebugForceFailOnce()
                        await MainActor.run {
                            statusText = "M5.9 ForceFavoriteSyncFailOnce: armed"
                            statusIsError = false
                            alertTitle = "M5.9 favorite sync"
                            alertMessage = "armed"
                            showAlert = true
                        }
                    }
                }

                Button("PrintPoseSpecPrdVersion") {
                    do {
                        let header = try PoseSpecLoader.shared.loadHeader()
                        print("PoseSpecPrdVersion:\(header.prdVersion)")

                        statusText = "PoseSpec\n\nprdVersion=\(header.prdVersion)"
                        statusIsError = false
                        alertTitle = "PoseSpec"
                        alertMessage = "prdVersion=\(header.prdVersion)"
                        showAlert = true
                    } catch {
                        print("PoseSpecPrdVersionFAILED: \(error)")

                        statusText = "PoseSpec: FAILED\n\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "PoseSpec failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("M6.3 ArmBrokenPoseSpecOnce") {
                    PoseSpecDebugSettings.armUseBrokenPoseSpecOnce()
                    print("PoseSpecDebug: armed broken PoseSpec once")
                    statusText = "M6.3 ArmBrokenPoseSpecOnce: armed\n\nRelaunch app to trigger validation"
                    statusIsError = false
                    alertTitle = "PoseSpec debug"
                    alertMessage = "armed (broken once)"
                    showAlert = true
                }

                Button("M6.4 ArmWrongPrdVersionOnce") {
                    PoseSpecDebugSettings.armUseWrongPrdVersionOnce()
                    print("PoseSpecDebug: armed wrong prdVersion once")
                    statusText = "M6.4 ArmWrongPrdVersionOnce: armed\n\nRelaunch app to trigger validation"
                    statusIsError = false
                    alertTitle = "PoseSpec debug"
                    alertMessage = "armed (wrong prdVersion once)"
                    showAlert = true
                }

                Button("M6.5 ArmMissingAliasOnce") {
                    PoseSpecDebugSettings.armUseMissingAliasOnce()
                    print("PoseSpecDebug: armed missing alias once")
                    statusText = "M6.5 ArmMissingAliasOnce: armed\n\nRelaunch app to trigger validation"
                    statusIsError = false
                    alertTitle = "PoseSpec debug"
                    alertMessage = "armed (missing alias once)"
                    showAlert = true
                }

                Button("M6.6 ArmMissingEyeROIOnce") {
                    PoseSpecDebugSettings.armUseMissingEyeROIOnce()
                    print("PoseSpecDebug: armed missing eyeROI once")
                    statusText = "M6.6 ArmMissingEyeROIOnce: armed\n\nRelaunch app to trigger validation"
                    statusIsError = false
                    alertTitle = "PoseSpec debug"
                    alertMessage = "armed (missing eyeROI once)"
                    showAlert = true
                }

                Button("M6.7 PrintCanonicalNormalization") {
                    #if canImport(UIKit)
                    let io = PoseSpecOrientation.currentInterfaceOrientation()
                    #else
                    let io: Any? = nil
                    #endif

                    let back = PoseSpecOrientation.cgImageOrientation(interface: io as Any, isFrontCamera: false)
                    let front = PoseSpecOrientation.cgImageOrientation(interface: io as Any, isFrontCamera: true)
                    let p = CGPoint(x: 0.2, y: 0.3)

                    let backOut = PoseSpecCoordinateNormalizer.normalize(p, sourceOrientation: back)
                    let frontOut = PoseSpecCoordinateNormalizer.normalize(p, sourceOrientation: front)

                    print("PoseSpecNormalize: normalizedSpace=canonical_yDown")
                    print("PoseSpecNormalize: interface=\(String(describing: io))")
                    print("PoseSpecNormalize: sample_in_vision_yUp=\(p) back_orient=\(back.rawValue) out=\(backOut)")
                    print("PoseSpecNormalize: sample_in_vision_yUp=\(p) front_orient=\(front.rawValue) out=\(frontOut)")

                    statusText = "M6.7 canonical (portrait + y-down)\n\ninterface=\(String(describing: io))\nback=\(back.rawValue) out=\(backOut)\nfront=\(front.rawValue) out=\(frontOut)"
                    statusIsError = false
                    alertTitle = "M6.7"
                    alertMessage = "normalizedSpace=canonical_yDown"
                    showAlert = true
                }

                Button("M6.12 VisionDelay=400ms (T0 timeout)") {
                    Task {
                        await VisionPipeline.shared.setDebugDelay(ms: 400)
                        await MainActor.run {
                            statusText = "M6.12 VisionDelay: set to 400ms"
                            statusIsError = false
                            alertTitle = "M6.12"
                            alertMessage = "delay=400ms"
                            showAlert = true
                        }
                    }
                }

                Button("M6.12 VisionDelay=default") {
                    Task {
                        await VisionPipeline.shared.setDebugDelay(ms: nil)
                        await MainActor.run {
                            statusText = "M6.12 VisionDelay: reset to default"
                            statusIsError = false
                            alertTitle = "M6.12"
                            alertMessage = "delay=default"
                            showAlert = true
                        }
                    }
                }

                Button("M6.13 CueSelectorSingle") {
                    if let result = CueSelectorDebug.validateSingleCandidate() {
                        print("CueSelectorSingle: cueId=\(result.candidate.cueId) reason=\(result.reason)")
                        statusText = "M6.13 CueSelectorSingle: OK\n\ncueId=\(result.candidate.cueId)\nreason=\(result.reason)"
                        statusIsError = false
                        alertTitle = "M6.13"
                        alertMessage = "cueId=\(result.candidate.cueId)"
                        showAlert = true
                    } else {
                        print("CueSelectorSingle: FAILED")
                        statusText = "M6.13 CueSelectorSingle: FAILED"
                        statusIsError = true
                        alertTitle = "M6.13"
                        alertMessage = "No result"
                        showAlert = true
                    }
                }

                Button("M6.13 CueSelectorNone") {
                    let result = CueSelectorDebug.validateEmpty()
                    let ok = (result == nil)
                    print("CueSelectorNone: \(ok ? "OK" : "FAILED")")
                    statusText = ok ? "M6.13 CueSelectorNone: OK\n\n(result=nil)" : "M6.13 CueSelectorNone: FAILED"
                    statusIsError = !ok
                    alertTitle = "M6.13"
                    alertMessage = ok ? "result=nil" : "expected nil"
                    showAlert = true
                }

                Button("M6.13 CueSelectorPriorityWins") {
                    if let result = CueSelectorDebug.validatePriorityWins() {
                        print("CueSelectorPriorityWins: cueId=\(result.candidate.cueId) reason=\(result.reason)")
                        statusText = "M6.13 CueSelectorPriorityWins: OK\n\ncueId=\(result.candidate.cueId)\nreason=\(result.reason)"
                        statusIsError = false
                        alertTitle = "M6.13"
                        alertMessage = "cueId=\(result.candidate.cueId)"
                        showAlert = true
                    } else {
                        print("CueSelectorPriorityWins: FAILED")
                        statusText = "M6.13 CueSelectorPriorityWins: FAILED"
                        statusIsError = true
                        alertTitle = "M6.13"
                        alertMessage = "No result"
                        showAlert = true
                    }
                }

                Button("M6.13 CueSelectorSeverityWins") {
                    if let result = CueSelectorDebug.validateSeverityBoostWins() {
                        print("CueSelectorSeverityWins: cueId=\(result.candidate.cueId) reason=\(result.reason)")
                        statusText = "M6.13 CueSelectorSeverityWins: OK\n\ncueId=\(result.candidate.cueId)\nreason=\(result.reason)"
                        statusIsError = false
                        alertTitle = "M6.13"
                        alertMessage = "cueId=\(result.candidate.cueId)"
                        showAlert = true
                    } else {
                        print("CueSelectorSeverityWins: FAILED")
                        statusText = "M6.13 CueSelectorSeverityWins: FAILED"
                        statusIsError = true
                        alertTitle = "M6.13"
                        alertMessage = "No result"
                        showAlert = true
                    }
                }

                Button("M6.13 CueSelectorTimeline") {
                    let lines = CueSelectorDebug.simulateTimeline()
                    print("CueSelectorTimeline:\n" + lines.joined(separator: "\n"))
                    statusText = "M6.13 CueSelectorTimeline\n\n" + lines.joined(separator: "\n")
                    statusIsError = false
                    alertTitle = "M6.13"
                    alertMessage = "timeline printed"
                    showAlert = true
                }

                Button("M6.14 AntiJitterTimeline") {
                    let lines = AntiJitterGateDebug.simulateHoldVsFrames()
                    print("AntiJitterTimeline:\n" + lines.joined(separator: "\n"))
                    statusText = "M6.14 AntiJitterTimeline\n\n" + lines.joined(separator: "\n")
                    statusIsError = false
                    alertTitle = "M6.14"
                    alertMessage = "timeline printed"
                    showAlert = true
                }

                Button("CreateWriteFailedItem") {
                    do {
                        let itemId = try SessionRepository.shared.insertWriteFailedItemAndFlush()
                        let count = try SessionRepository.shared.countWriteFailedItems()
                        print("WriteFailedItemCreated:\(itemId)")
                        print("WriteFailedItemCount:\(count)")

                        statusText = "CreateWriteFailedItem: OK\n\nitem_id=\(itemId)\ncount=\(count)"
                        statusIsError = false
                        alertTitle = "write_failed inserted"
                        alertMessage = "item_id=\(itemId)\ncount=\(count)"
                        showAlert = true
                    } catch {
                        statusText = "CreateWriteFailedItem: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "CreateWriteFailedItem failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }
                // This action is frequently used as an emergency unblock during dev.
                // Force-enable it even if a parent view accidentally disables interaction.
                .disabled(false)
                .tint(.blue)

                Button("CountWriteFailedItems") {
                    do {
                        let count = try SessionRepository.shared.countWriteFailedItems()
                        print("WriteFailedItemCount:\(count)")

                        statusText = "WriteFailedItemCount:\n\(count)"
                        statusIsError = false
                        alertTitle = "write_failed count"
                        alertMessage = String(count)
                        showAlert = true
                    } catch {
                        statusText = "CountWriteFailedItems: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "CountWriteFailedItems failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("ClearWriteFailedItems") {
                    do {
                        let deleted = try SessionRepository.shared.deleteWriteFailedItemsForCurrentSession()
                        let count = try SessionRepository.shared.countWriteFailedItems()
                        print("WriteFailedItemsDeleted:\(deleted)")
                        print("WriteFailedItemCount:\(count)")

                        statusText = "ClearWriteFailedItems: OK\n\ndeleted=\(deleted)\nremaining=\(count)"
                        statusIsError = false
                        alertTitle = "write_failed cleared"
                        alertMessage = "deleted=\(deleted) remaining=\(count)"
                        showAlert = true
                    } catch {
                        statusText = "ClearWriteFailedItems: FAILED\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "ClearWriteFailedItems failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("SpamDiagnostics") {
                    guard !isRunning else { return }
                    isRunning = true
                    statusText = "SpamDiagnostics: running..."
                    statusIsError = false

                    Task {
                        let result = await spamDiagnostics()
                        await MainActor.run {
                            isRunning = false
                            statusText = result.statusText
                            statusIsError = !result.ok
                            alertTitle = result.ok ? "SpamDiagnostics done" : "SpamDiagnostics failed"
                            alertMessage = result.alertMessage
                            showAlert = true
                        }
                    }
                }
                .disabled(isRunning)

                Button("CreateFakeOldLogs") {
                    guard !isRunning else { return }
                    isRunning = true
                    statusText = "CreateFakeOldLogs: running..."
                    statusIsError = false

                    Task {
                        let result = createFakeOldLogs()
                        await MainActor.run {
                            isRunning = false
                            statusText = result.statusText
                            statusIsError = !result.ok
                            alertTitle = result.ok ? "Fake logs created" : "CreateFakeOldLogs failed"
                            alertMessage = result.alertMessage
                            showAlert = true
                        }
                    }
                }
                .disabled(isRunning)

                Button("RunRotationNow") {
                    guard !isRunning else { return }
                    isRunning = true
                    statusText = "RunRotationNow: running..."
                    statusIsError = false

                    Task {
                        let result = runRotationNow()
                        await MainActor.run {
                            isRunning = false
                            statusText = result.statusText
                            statusIsError = !result.ok
                            alertTitle = result.ok ? "Rotation complete" : "RunRotationNow failed"
                            alertMessage = result.alertMessage
                            showAlert = true
                        }
                    }
                }
                .disabled(isRunning)

                Button {
                    guard !isRunning else { return }
                    isRunning = true
                    statusText = "WriteTestDiagnostic: running..."
                    statusIsError = false
                    print("WriteTestDiagnosticTapped")

                    Task {
                        let result = await writeTestDiagnostic()
                        await MainActor.run {
                            isRunning = false
                            statusText = result.statusText
                            statusIsError = !result.ok
                            alertTitle = result.ok ? "Diagnostic generated" : "Diagnostic failed"
                            alertMessage = result.alertMessage
                            showAlert = true
                        }
                    }
                } label: {
                    HStack {
                        Text("WriteTestDiagnostic")
                        Spacer()
                        if isRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)

                a13RequiredEventsSection

                m429PhantomAssetHealerSection

                if !statusText.isEmpty {
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(statusIsError ? .red : .secondary)
                        .textSelection(.enabled)
                }

                Text("Debug-only tools live here")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Debug Tools")
        .promptHost()
        .sheet(isPresented: $showingViewerDebug) {
            ViewerScreen()
                .environment(\.promptHostInstalled, false)
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
#else
        List {
            Section("PoseSpec") {
                Button("PrintPoseSpecPrdVersion") {
                    do {
                        let spec = try PoseSpecLoader.shared.loadPoseSpec()
                        print("PoseSpecPrdVersion:\(spec.prdVersion)")

                        statusText = "PoseSpec\n\nprdVersion=\(spec.prdVersion)\nexpected=\(PoseSpec.supportedVersion)"
                        statusIsError = false
                        alertTitle = "PoseSpec"
                        alertMessage = "prdVersion=\(spec.prdVersion)"
                        showAlert = true
                    } catch {
                        print("PoseSpecPrdVersionFAILED: \(error)")
                        statusText = "PoseSpec: FAILED\n\n\(error.localizedDescription)"
                        statusIsError = true
                        alertTitle = "PoseSpec failed"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }

                Button("M6.3 ArmBrokenPoseSpecOnce") {
                    PoseSpecDebugSettings.armUseBrokenPoseSpecOnce()
                    print("PoseSpecDebug: armed broken PoseSpec once")
                    statusText = "M6.3 ArmBrokenPoseSpecOnce: armed\n\nRelaunch app to trigger validation"
                    statusIsError = false
                    alertTitle = "PoseSpec debug"
                    alertMessage = "armed (broken once)"
                    showAlert = true
                }

                Button("M6.4 ArmWrongPrdVersionOnce") {
                    PoseSpecDebugSettings.armUseWrongPrdVersionOnce()
                    print("PoseSpecDebug: armed wrong prdVersion once")
                    statusText = "M6.4 ArmWrongPrdVersionOnce: armed\n\nRelaunch app to trigger validation"
                    statusIsError = false
                    alertTitle = "PoseSpec debug"
                    alertMessage = "armed (wrong prdVersion once)"
                    showAlert = true
                }

                Button("M6.5 ArmMissingAliasOnce") {
                    PoseSpecDebugSettings.armUseMissingAliasOnce()
                    print("PoseSpecDebug: armed missing alias once")
                    statusText = "M6.5 ArmMissingAliasOnce: armed\n\nRelaunch app to trigger validation"
                    statusIsError = false
                    alertTitle = "PoseSpec debug"
                    alertMessage = "armed (missing alias once)"
                    showAlert = true
                }

                Button("M6.6 ArmMissingEyeROIOnce") {
                    PoseSpecDebugSettings.armUseMissingEyeROIOnce()
                    print("PoseSpecDebug: armed missing eyeROI once")
                    statusText = "M6.6 ArmMissingEyeROIOnce: armed\n\nRelaunch app to trigger validation"
                    statusIsError = false
                    alertTitle = "PoseSpec debug"
                    alertMessage = "armed (missing eyeROI once)"
                    showAlert = true
                }

                Button("M6.7 PrintCanonicalNormalization") {
                    #if canImport(UIKit)
                    let io = PoseSpecOrientation.currentInterfaceOrientation()
                    #else
                    let io: Any? = nil
                    #endif

                    let back = PoseSpecOrientation.cgImageOrientation(interface: io as Any, isFrontCamera: false)
                    let front = PoseSpecOrientation.cgImageOrientation(interface: io as Any, isFrontCamera: true)
                    let p = CGPoint(x: 0.2, y: 0.3)

                    let backOut = PoseSpecCoordinateNormalizer.normalize(p, sourceOrientation: back)
                    let frontOut = PoseSpecCoordinateNormalizer.normalize(p, sourceOrientation: front)

                    print("PoseSpecNormalize: normalizedSpace=canonical_yDown")
                    print("PoseSpecNormalize: interface=\(String(describing: io))")
                    print("PoseSpecNormalize: sample_in_vision_yUp=\(p) back_orient=\(back.rawValue) out=\(backOut)")
                    print("PoseSpecNormalize: sample_in_vision_yUp=\(p) front_orient=\(front.rawValue) out=\(frontOut)")

                    statusText = "M6.7 canonical (portrait + y-down)\n\ninterface=\(String(describing: io))\nback=\(back.rawValue) out=\(backOut)\nfront=\(front.rawValue) out=\(frontOut)"
                    statusIsError = false
                    alertTitle = "M6.7"
                    alertMessage = "normalizedSpace=canonical_yDown"
                    showAlert = true
                }

                Button {
                    guard !isRefTargetRunning else { return }
                    isRefTargetRunning = true
                    statusText = "M6.16 RefTargetExtractor: running..."
                    statusIsError = false
                    print("M6.16 RefTargetExtractor: start")

                    Task {
                        let result = await runRefTargetExtractorDebug()
                        await MainActor.run {
                            isRefTargetRunning = false
                            statusText = result.statusText
                            statusIsError = !result.ok
                            alertTitle = result.ok ? "M6.16 RefTargetExtractor" : "M6.16 RefTargetExtractor failed"
                            alertMessage = result.alertMessage
                            showAlert = true
                        }
                    }
                } label: {
                    HStack {
                        Text("M6.16 RunRefTargetExtractor")
                        Spacer()
                        if isRefTargetRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRefTargetRunning)
            }

            Section("Diagnostics") {
                Button("CancelSemanticsProbe") {
                    WarmupTracker.debugStartCancelProbe()
                    CaptureCoordinator.shared.debugCancelDeadlineProbe()
                    Task { await AlbumAddRetryScheduler.shared.debugCancelProbe() }
                    print("CancelSemanticsProbe: started")
                    statusText = "CancelSemanticsProbe: started\n\nCheck console for WarmupCancelProbe/CaptureCancelProbe/AlbumAutoRetryCancelProbe logs."
                    statusIsError = false
                    alertTitle = "CancelSemanticsProbe"
                    alertMessage = "Started cancellation probes."
                    showAlert = true
                }

                Button("InjectMetricCase: FRAME_MOVE_LEFT_HARD") {
                    guard let result = CueEvaluatorDebug.injectMetricCase("FRAME_MOVE_LEFT_HARD") else {
                        print("InjectMetricCase: FAILED")
                        statusText = "InjectMetricCase: FAILED"
                        statusIsError = true
                        alertTitle = "InjectMetricCase"
                        alertMessage = "No result"
                        showAlert = true
                        return
                    }
                    let stable = DebugToolsScreen.cueStabilityLayer.apply(result)
                    print("CueEvalDebug: cueId=\(result.cueId)")
                    print("CueEvalDebug: level=\(result.level.rawValue)")
                    print("CueEvalDebug: matchedThresholdId=\(result.matchedThresholdId ?? "nil")")
                    print("CueEvalDebug: usedRefMode=\(result.usedRefMode.rawValue)")
                    print("CueStability: stableFrameCount=\(stable.stableFrameCount)")
                    print("CueStability: stabilityState=\(stable.stabilityState.rawValue)")
                    statusText = """
                    InjectMetricCase: FRAME_MOVE_LEFT_HARD
                    cueId=\(result.cueId)
                    level=\(result.level.rawValue)
                    matchedThresholdId=\(result.matchedThresholdId ?? "nil")
                    usedRefMode=\(result.usedRefMode.rawValue)
                    stableFrameCount=\(stable.stableFrameCount)
                    stabilityState=\(stable.stabilityState.rawValue)
                    """
                    statusIsError = false
                    alertTitle = "InjectMetricCase"
                    alertMessage = "Printed CueEvaluator debug output."
                    showAlert = true
                }

                Button {
                    guard !isRunning else { return }
                    isRunning = true
                    statusText = "WriteTestDiagnostic: running..."
                    statusIsError = false
                    print("WriteTestDiagnosticTapped")

                    Task {
                        let result = await writeTestDiagnostic()
                        await MainActor.run {
                            isRunning = false
                            statusText = result.statusText
                            statusIsError = !result.ok
                            alertTitle = result.ok ? "Diagnostic generated" : "Diagnostic failed"
                            alertMessage = result.alertMessage
                            showAlert = true
                        }
                    }
                } label: {
                    HStack {
                        Text("WriteTestDiagnostic")
                        Spacer()
                        if isRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)
            }

            if !statusText.isEmpty {
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(statusIsError ? .red : .secondary)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Debug Tools")
        .promptHost()
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
#endif
    }

    @ViewBuilder
    private var a13RequiredEventsSection: some View {
        Section("A.13 Required Events") {
            Button("WriteA13 withref_match_state") {
                guard !isRunning else { return }
                isRunning = true
                statusText = "WriteA13 withref_match_state: running..."
                statusIsError = false

                Task {
                    let result = await writeA13_withrefMatchState()
                    await MainActor.run {
                        isRunning = false
                        statusText = result.statusText
                        statusIsError = !result.ok
                        alertTitle = result.ok ? "A.13 event written" : "A.13 event failed"
                        alertMessage = result.alertMessage
                        showAlert = true
                    }
                }
            }
            .disabled(isRunning)

            Button("WriteA13 withref_fallback") {
                guard !isRunning else { return }
                isRunning = true
                statusText = "WriteA13 withref_fallback: running..."
                statusIsError = false

                Task {
                    let result = await writeA13_withrefFallback()
                    await MainActor.run {
                        isRunning = false
                        statusText = result.statusText
                        statusIsError = !result.ok
                        alertTitle = result.ok ? "A.13 event written" : "A.13 event failed"
                        alertMessage = result.alertMessage
                        showAlert = true
                    }
                }
            }
            .disabled(isRunning)

            Button("WriteA13 photo_write_verification") {
                guard !isRunning else { return }
                isRunning = true
                statusText = "WriteA13 photo_write_verification: running..."
                statusIsError = false

                Task {
                    let result = await writeA13_photoWriteVerification()
                    await MainActor.run {
                        isRunning = false
                        statusText = result.statusText
                        statusIsError = !result.ok
                        alertTitle = result.ok ? "A.13 event written" : "A.13 event failed"
                        alertMessage = result.alertMessage
                        showAlert = true
                    }
                }
            }
            .disabled(isRunning)

            Button("WriteA13 phantom_asset_detected") {
                guard !isRunning else { return }
                isRunning = true
                statusText = "WriteA13 phantom_asset_detected: running..."
                statusIsError = false

                Task {
                    let result = await writeA13_phantomAssetDetected()
                    await MainActor.run {
                        isRunning = false
                        statusText = result.statusText
                        statusIsError = !result.ok
                        alertTitle = result.ok ? "A.13 event written" : "A.13 event failed"
                        alertMessage = result.alertMessage
                        showAlert = true
                    }
                }
            }
            .disabled(isRunning)

            Button("WriteA13 odr_auto_retry") {
                guard !isRunning else { return }
                isRunning = true
                statusText = "WriteA13 odr_auto_retry: running..."
                statusIsError = false

                Task {
                    let result = await writeA13_odrAutoRetry()
                    await MainActor.run {
                        isRunning = false
                        statusText = result.statusText
                        statusIsError = !result.ok
                        alertTitle = result.ok ? "A.13 event written" : "A.13 event failed"
                        alertMessage = result.alertMessage
                        showAlert = true
                    }
                }
            }
            .disabled(isRunning)
        }
    }

    @ViewBuilder
    private var m429PhantomAssetHealerSection: some View {
        Section("M4.29 Phantom Asset Healer") {
            Button("Inject + Heal Phantom Asset") {
                guard !isRunning else { return }
                isRunning = true
                statusText = "M4.29 Inject+Heal: running..."
                statusIsError = false

                Task {
                    let result = await m429_injectAndHealPhantomAsset()
                    await MainActor.run {
                        isRunning = false
                        statusText = result.statusText
                        statusIsError = !result.ok
                        alertTitle = result.ok ? "M4.29 ok" : "M4.29 failed"
                        alertMessage = result.alertMessage
                        showAlert = true
                    }
                }
            }
            .disabled(isRunning)
        }
    }

    private func writeTestDiagnostic() async -> (ok: Bool, statusText: String, alertMessage: String) {
        let logger = DiagnosticsLogger()
        let event = DiagnosticsEvent.makeTestEvent()
        do {
            let line = try logger.encodeJSONLine(event)
            print(line)

            guard let appendResult = await DiagnosticsEventWriter.shared.appendJSONLine(line) else {
                return (
                    ok: false,
                    statusText: "WriteTestDiagnostic: FAILED (append failed)",
                    alertMessage: "Append failed. Check console for DiagnosticsAppendFAILED."
                )
            }
            print("DiagnosticAppended")

            let data = Data(line.utf8)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let requiredKeys = ["ts_ms", "session_id", "event", "scene", "payload"]
                let ok = requiredKeys.allSatisfy { obj[$0] != nil }
                print(ok ? "DiagnosticEventFieldsOK" : "DiagnosticEventFieldsMISSING")

                if ok {
                    return (
                        ok: true,
                        statusText: "WriteTestDiagnostic: OK\n\nfile: \(appendResult.fileURL.path)\nbytes: \(appendResult.bytesBefore) -> \(appendResult.bytesAfter)\n\n\(line)",
                        alertMessage: "Success. A JSON line was appended (see file path in status)."
                    )
                } else {
                    return (
                        ok: false,
                        statusText: "WriteTestDiagnostic: FAILED (missing required fields)\n\nfile: \(appendResult.fileURL.path)\nbytes: \(appendResult.bytesBefore) -> \(appendResult.bytesAfter)\n\n\(line)",
                        alertMessage: "JSON generated, but required keys are missing."
                    )
                }
            } else {
                print("DiagnosticEventParseFAILED")
                return (
                    ok: false,
                    statusText: "WriteTestDiagnostic: FAILED (JSON parse failed)",
                    alertMessage: "Could not parse the encoded JSON line. Check console output."
                )
            }
        } catch {
            print("DiagnosticEventEncodeFAILED: \(error)")
            return (
                ok: false,
                statusText: "WriteTestDiagnostic: FAILED (encode error)",
                alertMessage: "Encode/parse failed: \(error.localizedDescription)"
            )
        }
    }

    private func runRefTargetExtractorDebug() async -> (ok: Bool, statusText: String, alertMessage: String) {
        guard let cgImage = loadRefTargetDebugImage() else {
            return (
                ok: false,
                statusText: "M6.16 RefTargetExtractor: FAILED\nmissing debug image",
                alertMessage: "RefTargetDebug.png not found in bundle."
            )
        }

        let input = RefTargetInput(cgImage: cgImage, orientation: .up)
        guard let output = await RefTargetExtractor.extract(input: input) else {
            return (
                ok: false,
                statusText: "M6.16 RefTargetExtractor: FAILED\nextract returned nil",
                alertMessage: "Extractor returned nil. Check console for Vision errors."
            )
        }

        let summary = formatMetricOutputs(output.metrics)
        print("M6.16 RefTargetExtractor: metrics_count=\(output.metrics.count)")
        print(summary)

        return (
            ok: true,
            statusText: "M6.16 RefTargetExtractor: OK\n\n" + summary,
            alertMessage: "Printed target metrics to console."
        )
    }

    private func loadRefTargetDebugImage() -> CGImage? {
        if let url = Bundle.main.url(forResource: "RefTargetDebug", withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path)?.cgImage {
            return image
        }
        if let image = UIImage(named: "RefTargetDebug")?.cgImage {
            return image
        }
        return nil
    }

    private func formatMetricOutputs(_ metrics: [MetricKey: MetricOutput]) -> String {
        let keys = MetricKey.allCases
        let lines: [String] = keys.compactMap { key in
            guard let output = metrics[key] else { return nil }
            if let value = output.value {
                let formatted = String(format: "%.5f", value)
                return "\(key.rawValue)=\(formatted)"
            }
            let reason = output.reason?.rawValue ?? "unknown"
            return "\(key.rawValue)=unavailable(\(reason))"
        }
        return lines.joined(separator: "\n")
    }

    private func m429_injectAndHealPhantomAsset() async -> (ok: Bool, statusText: String, alertMessage: String) {
        do {
            // Ensure Photo Library read access so the healer can evaluate phantom-ness.
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if status == .notDetermined {
                _ = await withCheckedContinuation { (c: CheckedContinuation<PHAuthorizationStatus, Never>) in
                    PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
                        c.resume(returning: s)
                    }
                }
            }

            let item: SessionRepository.SessionItemSummary = try await MainActor.run {
                if (try SessionRepository.shared.currentSessionId()) == nil {
                    _ = try SessionRepository.shared.createNewSession(scene: "cafe")
                }

                let s = try SessionRepository.shared.insertOptimisticCapturedPreviewItemAndFlush()
                let fakeAssetId = "debug_phantom_asset_" + UUID().uuidString
                try SessionRepository.shared.markWriteSuccess(itemId: s.itemId, assetId: fakeAssetId)
                try SessionRepository.shared.updateAlbumState(itemId: s.itemId, state: .failed)
                return try SessionRepository.shared.sessionItemSummary(itemId: s.itemId) ?? s
            }

            let assetId = item.assetId ?? ""
            guard !assetId.isEmpty else {
                return (false, "M4.29 Inject+Heal: FAILED\nmissing asset_id", "Missing asset_id")
            }

            let report = await PhantomAssetHealer.shared.healIfNeeded(
                itemId: item.itemId,
                assetId: assetId,
                source: "debug_tools"
            )

            let stillExists: Bool = await MainActor.run {
                (try? SessionRepository.shared.sessionItemSummary(itemId: item.itemId)) != nil
            }

            if let report {
                let txt = "M4.29 Inject+Heal: OK\nitem_id=\(report.itemId)\nauth=\(report.authSnapshot)\naction=\(report.healAction.rawValue)\npruned=\(report.wasPruned ? "true" : "false")\nstill_exists=\(stillExists ? "true" : "false")\nasset_id_hash=\(report.assetIdHash)"
                return (true, txt, "Phantom asset healed (or attempted).")
            }

            let txt = "M4.29 Inject+Heal: SKIPPED\nNo phantom detected (or not authorized/limited).\nitem_id=\(item.itemId)\nstill_exists=\(stillExists ? "true" : "false")"
            return (true, txt, "No heal performed.")
        } catch {
            return (false, "M4.29 Inject+Heal: FAILED\n\(error.localizedDescription)", error.localizedDescription)
        }
    }

    private func spamDiagnostics() async -> (ok: Bool, statusText: String, alertMessage: String) {
        do {
            let logger = DiagnosticsLogger()
            let file = try logger.currentLogFileURL()
            let dir = try logger.diagnosticsDirectoryURL()

            let rotation = DiagnosticsRotationManager(maxTotalBytes: 50 * 1024 * 1024)

            // Roughly ~1KB per line. Write enough to cross 50MB quickly, then rotate.
            // This is debug-only and used solely to validate size rotation.
            let payloadString = String(repeating: "x", count: 900)
            let targetLines = 80_000

            for i in 0..<targetLines {
                let event = DiagnosticsEvent(
                    ts_ms: Int64(Date().timeIntervalSince1970 * 1000),
                    session_id: "dev_session",
                    event: "spam",
                    scene: "cafe",
                    payload: [
                        "i": String(i),
                        "data": payloadString
                    ]
                )

                let line = try logger.encodeJSONLine(event)
                guard await DiagnosticsEventWriter.shared.appendJSONLine(line) != nil else {
                    return (
                        ok: false,
                        statusText: "SpamDiagnostics: FAILED (append failed)",
                        alertMessage: "Append failed. Check console for DiagnosticsAppendFAILED."
                    )
                }

                if i % 2000 == 0 {
                    try rotation.rotateIfNeeded()
                }
            }

            try rotation.rotateIfNeeded()
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []

            return (
                ok: true,
                statusText: "SpamDiagnostics: OK\n\nDiagnosticsDirectory:\n\(dir.path)\n\nCurrentFile:\n\(file.path)",
                alertMessage: "Done. Check console for RotationBySizeTriggered and file list: \(names.sorted())"
            )
        } catch {
            return (
                ok: false,
                statusText: "SpamDiagnostics: FAILED\n\(error.localizedDescription)",
                alertMessage: error.localizedDescription
            )
        }
    }

    private func createFakeOldLogs() -> (ok: Bool, statusText: String, alertMessage: String) {
        do {
            let logger = DiagnosticsLogger()
            let dir = try logger.diagnosticsDirectoryURL()

            let oldDate = Date().addingTimeInterval(-40 * 24 * 60 * 60)
            let recentDate = Date().addingTimeInterval(-2 * 24 * 60 * 60)

            let old1 = dir.appendingPathComponent("fake-old-1.jsonl")
            let old2 = dir.appendingPathComponent("fake-old-2.jsonl")
            let recent = dir.appendingPathComponent("fake-recent.jsonl")

            try Data("{}\n".utf8).write(to: old1, options: Data.WritingOptions.atomic)
            try Data("{}\n".utf8).write(to: old2, options: Data.WritingOptions.atomic)
            try Data("{}\n".utf8).write(to: recent, options: Data.WritingOptions.atomic)

            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: old1.path)
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: old2.path)
            try FileManager.default.setAttributes([.modificationDate: recentDate], ofItemAtPath: recent.path)

            print("CreateFakeOldLogsCreated: \([old1.lastPathComponent, old2.lastPathComponent, recent.lastPathComponent])")

            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            return (
                ok: true,
                statusText: "CreateFakeOldLogs: OK\n\nDiagnosticsDirectory:\n\(dir.path)\n\nFiles:\n\(names.sorted().joined(separator: "\n"))",
                alertMessage: "Created 2 old logs (~40d) and 1 recent (~2d)."
            )
        } catch {
            return (
                ok: false,
                statusText: "CreateFakeOldLogs: FAILED\n\(error.localizedDescription)",
                alertMessage: error.localizedDescription
            )
        }
    }

    private func runRotationNow() -> (ok: Bool, statusText: String, alertMessage: String) {
        do {
            let logger = DiagnosticsLogger()
            let dir = try logger.diagnosticsDirectoryURL()
            let rotation = DiagnosticsRotationManager(maxTotalBytes: 50 * 1024 * 1024)

            try rotation.deleteOldLogs(now: Date(), maxAgeDays: 30)

            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            return (
                ok: true,
                statusText: "RunRotationNow: OK\n\nRemaining files:\n\(names.sorted().joined(separator: "\n"))",
                alertMessage: "Check console for RotationByAgeDeletedFiles."
            )
        } catch {
            return (
                ok: false,
                statusText: "RunRotationNow: FAILED\n\(error.localizedDescription)",
                alertMessage: error.localizedDescription
            )
        }
    }

    private func writeA13_withrefMatchState() async -> (ok: Bool, statusText: String, alertMessage: String) {
        if let result = await DiagnosticsEventWriter.shared.logWithRefMatchState(
            sessionId: "dev_session",
            scene: "cafe",
            match: false,
            requiredDimensions: ["centerXOffset", "centerYOffset"],
            blockedBy: ["centerXOffset"],
            mirrorApplied: true
        ) {
            print(result.jsonLine)
            print("A13EventWritten: withref_match_state")
            return (
                ok: true,
                statusText: "WriteA13 withref_match_state: OK\n\nfile: \(result.fileURL.path)\n\n\(result.jsonLine)",
                alertMessage: "Appended withref_match_state to diagnostics log."
            )
        }
        print("A13EventWriteFAILED: withref_match_state")
        return (
            ok: false,
            statusText: "WriteA13 withref_match_state: FAILED",
            alertMessage: "Append failed. Check console for DiagnosticsAppendFAILED."
        )
    }

    private func writeA13_withrefFallback() async -> (ok: Bool, statusText: String, alertMessage: String) {
        if let result = await DiagnosticsEventWriter.shared.logWithRefFallback(
            sessionId: "dev_session",
            scene: "cafe",
            reason: "missing_eyeROI",
            missing: ["eyeROI"]
        ) {
            print(result.jsonLine)
            print("A13EventWritten: withref_fallback")
            return (
                ok: true,
                statusText: "WriteA13 withref_fallback: OK\n\nfile: \(result.fileURL.path)\n\n\(result.jsonLine)",
                alertMessage: "Appended withref_fallback to diagnostics log."
            )
        }
        print("A13EventWriteFAILED: withref_fallback")
        return (
            ok: false,
            statusText: "WriteA13 withref_fallback: FAILED",
            alertMessage: "Append failed. Check console for DiagnosticsAppendFAILED."
        )
    }

    private func writeA13_photoWriteVerification() async -> (ok: Bool, statusText: String, alertMessage: String) {
        if let result = await DiagnosticsEventWriter.shared.logPhotoWriteVerification(
            sessionId: "dev_session",
            scene: "cafe",
            assetId: "debug_asset_id",
            firstFetchMs: 12,
            retryUsed: true,
            retryDelayMs: 500,
            verifiedWithin2s: true
        ) {
            print(result.jsonLine)
            print("A13EventWritten: photo_write_verification")
            return (
                ok: true,
                statusText: "WriteA13 photo_write_verification: OK\n\nfile: \(result.fileURL.path)\n\n\(result.jsonLine)",
                alertMessage: "Appended photo_write_verification to diagnostics log."
            )
        }
        print("A13EventWriteFAILED: photo_write_verification")
        return (
            ok: false,
            statusText: "WriteA13 photo_write_verification: FAILED",
            alertMessage: "Append failed. Check console for DiagnosticsAppendFAILED."
        )
    }

    private func writeA13_phantomAssetDetected() async -> (ok: Bool, statusText: String, alertMessage: String) {
        if let result = await DiagnosticsEventWriter.shared.logPhantomAssetDetected(
            sessionId: "dev_session",
            scene: "cafe",
            assetIdHash: "debug_hash",
            authSnapshot: "limited",
            healAction: "pruned"
        ) {
            print(result.jsonLine)
            print("A13EventWritten: phantom_asset_detected")
            return (
                ok: true,
                statusText: "WriteA13 phantom_asset_detected: OK\n\nfile: \(result.fileURL.path)\n\n\(result.jsonLine)",
                alertMessage: "Appended phantom_asset_detected to diagnostics log."
            )
        }
        print("A13EventWriteFAILED: phantom_asset_detected")
        return (
            ok: false,
            statusText: "WriteA13 phantom_asset_detected: FAILED",
            alertMessage: "Append failed. Check console for DiagnosticsAppendFAILED."
        )
    }

    private func writeA13_odrAutoRetry() async -> (ok: Bool, statusText: String, alertMessage: String) {
        if let result = await DiagnosticsEventWriter.shared.logODRAutoRetry(
            sessionId: "dev_session",
            scene: "cafe",
            stateBefore: "failed_retry",
            debounceMs: 500,
            result: "success"
        ) {
            print(result.jsonLine)
            print("A13EventWritten: odr_auto_retry")
            return (
                ok: true,
                statusText: "WriteA13 odr_auto_retry: OK\n\nfile: \(result.fileURL.path)\n\n\(result.jsonLine)",
                alertMessage: "Appended odr_auto_retry to diagnostics log."
            )
        }
        print("A13EventWriteFAILED: odr_auto_retry")
        return (
            ok: false,
            statusText: "WriteA13 odr_auto_retry: FAILED",
            alertMessage: "Append failed. Check console for DiagnosticsAppendFAILED."
        )
    }

    private func makeTestL3Prompt(key: String, title: String) -> Prompt {
        Prompt(
            key: key,
            level: .L3,
            surface: .sheetModalCenter,
            priority: 80,
            blocksShutter: false,
            isClosable: false,
            autoDismissSeconds: nil,
            gate: .none,
            title: title,
            message: "This is a test modal (\(key)).",
            primaryActionId: "primary",
            primaryTitle: "OK",
            secondaryActionId: "secondary",
            secondaryTitle: "Cancel",
            tertiaryActionId: nil,
            tertiaryTitle: nil,
            throttle: .init(
                perKeyMinIntervalSec: 0,
                globalWindowSec: 0,
                globalMaxCountInWindow: 0,
                suppressAfterDismissSec: 0
            ),
            payload: [:],
            emittedAt: Date()
        )
    }

    private func makeTestL1ToastPrompt(key: String) -> Prompt {
        Prompt(
            key: key,
            level: .L1,
            surface: .cameraToastBottom,
            priority: 10,
            blocksShutter: false,
            isClosable: false,
            autoDismissSeconds: 4.0,
            gate: .none,
            title: nil,
            message: "Toast: \(key)",
            primaryActionId: nil,
            primaryTitle: nil,
            secondaryActionId: nil,
            secondaryTitle: nil,
            tertiaryActionId: nil,
            tertiaryTitle: nil,
            throttle: .init(
                perKeyMinIntervalSec: 0,
                globalWindowSec: 0,
                globalMaxCountInWindow: 0,
                suppressAfterDismissSec: 0
            ),
            payload: [:],
            emittedAt: Date()
        )
    }

    private func makeTestL2BannerWithButton(key: String) -> Prompt {
        Prompt(
            key: key,
            level: .L2,
            surface: .sheetBannerTop,
            priority: 40,
            blocksShutter: false,
            isClosable: true,
            autoDismissSeconds: nil,
            gate: .none,
            title: "Banner test",
            message: "This banner stays until you tap the button or close.",
            primaryActionId: "primary",
            primaryTitle: "OK",
            secondaryActionId: nil,
            secondaryTitle: nil,
            tertiaryActionId: nil,
            tertiaryTitle: nil,
            throttle: .init(
                perKeyMinIntervalSec: 0,
                globalWindowSec: 0,
                globalMaxCountInWindow: 0,
                suppressAfterDismissSec: 0
            ),
            payload: [:],
            emittedAt: Date()
        )
    }

    private func makeTestL2BannerAutoDismiss(key: String) -> Prompt {
        Prompt(
            key: key,
            level: .L2,
            surface: .sheetBannerTop,
            priority: 40,
            blocksShutter: false,
            isClosable: true,
            autoDismissSeconds: nil,
            gate: .none,
            title: "Banner auto-dismiss",
            message: "This banner auto-dismisses when it has no primary button.",
            primaryActionId: nil,
            primaryTitle: nil,
            secondaryActionId: nil,
            secondaryTitle: nil,
            tertiaryActionId: nil,
            tertiaryTitle: nil,
            throttle: .init(
                perKeyMinIntervalSec: 0,
                globalWindowSec: 0,
                globalMaxCountInWindow: 0,
                suppressAfterDismissSec: 0
            ),
            payload: [:],
            emittedAt: Date()
        )
    }
}

private struct PromptDebugModal: View {
    @EnvironmentObject private var promptCenter: PromptCenter
    let prompt: Prompt

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(prompt.title ?? "")
                .font(.headline)

            Text(prompt.message)
                .font(.body)

            if prompt.key == "A" {
                Button("Preempt to Test B") {
                    promptCenter.show(
                        Prompt(
                            key: "B",
                            level: .L3,
                            surface: .sheetModalCenter,
                            priority: 80,
                            blocksShutter: false,
                            isClosable: false,
                            autoDismissSeconds: nil,
                            gate: .none,
                            title: "Test B",
                            message: "This is a test modal (B).",
                            primaryActionId: "primary",
                            primaryTitle: "OK",
                            secondaryActionId: "secondary",
                            secondaryTitle: "Cancel",
                            tertiaryActionId: nil,
                            tertiaryTitle: nil,
                            throttle: .init(
                                perKeyMinIntervalSec: 0,
                                globalWindowSec: 0,
                                globalMaxCountInWindow: 0,
                                suppressAfterDismissSec: 0
                            ),
                            payload: [:],
                            emittedAt: Date()
                        )
                    )
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)

            ForEach(prompt.actions) { action in
                Button(action.title) {
                    promptCenter.actionTapped(prompt: prompt, actionId: action.id)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
}

#Preview {
    NavigationStack { DebugToolsScreen() }
}

#endif
