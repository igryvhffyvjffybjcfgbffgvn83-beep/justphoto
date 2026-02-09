import CryptoKit
import Foundation
import Photos

// M4.29: Limited phantom asset handling.
//
// A phantom asset is a localIdentifier we have stored, but PhotoKit can no longer
// fetch (commonly due to Limited Photos access changes or user deletion).
//
// Healing strategy (MVP): prune the local SessionItem so the app doesn't crash
// or get stuck retrying work that will never succeed.
actor PhantomAssetHealer {
    static let shared = PhantomAssetHealer()

    enum HealAction: String, Sendable {
        case pruned = "pruned"
        case skipped = "skipped"
    }

    struct HealReport: Sendable, Equatable {
        let itemId: String
        let assetIdHash: String
        let authSnapshot: String
        let healAction: HealAction
        let wasPruned: Bool
    }

    private init() {}

    func healIfNeeded(itemId: String, assetId: String, source: String) async -> HealReport? {
        let auth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let authSnapshot = Self.authSnapshotString(auth)

        // If we don't have read access, absence is expected; don't treat as phantom.
        guard auth == .authorized || auth == .limited else {
            return nil
        }

        let exists = fetchAssetExists(localIdentifier: assetId)
        guard !exists else {
            return nil
        }

        let hash = Self.assetIdHash(assetId)
        JPDebugPrint("PhantomAssetDetected: source=\(source) item_id=\(itemId) asset_id_hash=\(hash) auth=\(authSnapshot)")

        // MVP heal: prune local item.
        let deleted: Int = await MainActor.run {
            (try? SessionRepository.shared.deleteSessionItem(itemId: itemId)) ?? 0
        }

        let didPrune = deleted > 0
        let action: HealAction = didPrune ? .pruned : .skipped

        // M4.30: Emit required A.13 event.
        let sessionSnapshot: (sessionId: String, scene: String)? = await MainActor.run {
            do {
                guard let s = try SessionRepository.shared.loadCurrentSession() else { return nil }
                return (s.sessionId, s.scene)
            } catch {
                return nil
            }
        }
        if let sessionSnapshot {
            do {
                _ = try DiagnosticsLogger().logPhantomAssetDetected(
                    sessionId: sessionSnapshot.sessionId,
                    scene: sessionSnapshot.scene,
                    assetIdHash: hash,
                    authSnapshot: authSnapshot,
                    healAction: action.rawValue
                )
            } catch {
                JPDebugPrint("PhantomAssetDetectedLogFAILED: \(error)")
            }
        } else {
            JPDebugPrint("PhantomAssetDetectedLogSkipped: missing_session")
        }

        if didPrune {
            JPDebugPrint("PhantomAssetHealed: action=pruned item_id=\(itemId)")
        } else {
            JPDebugPrint("PhantomAssetHealSkipped: action=skipped item_id=\(itemId)")
        }

        return HealReport(
            itemId: itemId,
            assetIdHash: hash,
            authSnapshot: authSnapshot,
            healAction: action,
            wasPruned: didPrune
        )
    }

    private nonisolated func fetchAssetExists(localIdentifier: String) -> Bool {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).count > 0
    }

    private nonisolated static func authSnapshotString(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .limited:
            return "limited"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "not_determined"
        @unknown default:
            return "unknown"
        }
    }

    private nonisolated static func assetIdHash(_ assetId: String) -> String {
        let digest = SHA256.hash(data: Data(assetId.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
