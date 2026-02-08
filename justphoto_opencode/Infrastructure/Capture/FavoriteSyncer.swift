import Foundation
import Photos

enum FavoriteSyncResult: Sendable, Equatable {
    case success
    case skipped_not_full_access
    case skipped_missing_asset
    case failed
}

// M5.9: Best-effort sync to system Favorites (full access only).
// Never requests permission; never blocks capture.
actor FavoriteSyncer {
    static let shared = FavoriteSyncer()

    #if DEBUG
    private var debugForceFailOnce: Bool = false
    #endif

    private init() {}

    func syncFavoriteIfPossible(assetLocalIdentifier: String?, isFavorite: Bool) async -> FavoriteSyncResult {
        let id = (assetLocalIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            return .skipped_missing_asset
        }

        // Full access only (NOT limited). Do not prompt here.
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized else {
            return .skipped_not_full_access
        }

        #if DEBUG
        if debugForceFailOnce {
            debugForceFailOnce = false
            return .failed
        }
        #endif

        guard let asset = Self.fetchAsset(localIdentifier: id) else {
            return .skipped_missing_asset
        }

        do {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges {
                    let req = PHAssetChangeRequest(for: asset)
                    req.isFavorite = isFavorite
                } completionHandler: { ok, err in
                    if let err {
                        c.resume(throwing: err)
                        return
                    }
                    guard ok else {
                        c.resume(throwing: NSError(domain: "FavoriteSyncer", code: 1))
                        return
                    }
                    c.resume(returning: ())
                }
            }
            return .success
        } catch {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if status != .authorized {
                return .skipped_not_full_access
            }
            return .failed
        }
    }

    #if DEBUG
    func setDebugForceFailOnce() {
        debugForceFailOnce = true
        print("FavoriteSyncerDebugForceFailOnce: armed")
    }
    #endif

    private nonisolated static func fetchAsset(localIdentifier: String) -> PHAsset? {
        let r = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return r.firstObject
    }
}
