import Foundation
import Photos

enum AlbumArchiverError: Error {
    case notAuthorized(status: PHAuthorizationStatus)
    case missingAlbumIdentifier
    case albumNotFound
    case assetNotFound
}

// M4.24: Album archiving (best-effort).
// Ensures the "Just Photo" album exists and adds assets to it.
actor AlbumArchiver {
    static let shared = AlbumArchiver()

    private let albumTitle = "Just Photo"
    private var cachedAlbumLocalId: String? = nil

    #if DEBUG
    private var debugForceFailOnce: Bool = false
    private var debugForceFailTimes: Int = 0
    #endif

    private init() {}

    func archive(assetLocalIdentifier: String) async throws -> String {
        #if DEBUG
        if debugForceFailOnce {
            debugForceFailOnce = false
            throw NSError(domain: "AlbumArchiver", code: 999)
        }
        if debugForceFailTimes > 0 {
            debugForceFailTimes -= 1
            throw NSError(domain: "AlbumArchiver", code: 998)
        }
        #endif

        try await ensureReadWriteAuthorization()
        let albumId = try await ensureAlbum()
        try await addAsset(assetLocalIdentifier: assetLocalIdentifier, toAlbumLocalIdentifier: albumId)
        return albumId
    }

    #if DEBUG
    func setDebugForceFailOnce() {
        debugForceFailOnce = true
        print("AlbumArchiverDebugForceFailOnce: armed")
    }

    func setDebugForceFail(times: Int) {
        debugForceFailTimes = max(0, times)
        print("AlbumArchiverDebugForceFailTimesSet: \(debugForceFailTimes)")
    }
    #endif

    private func ensureReadWriteAuthorization() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let newStatus: PHAuthorizationStatus = await withCheckedContinuation { c in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
                    c.resume(returning: s)
                }
            }
            guard newStatus == .authorized || newStatus == .limited else {
                throw AlbumArchiverError.notAuthorized(status: newStatus)
            }
        default:
            throw AlbumArchiverError.notAuthorized(status: status)
        }
    }

    private func ensureAlbum() async throws -> String {
        if let id = cachedAlbumLocalId, fetchAlbum(localIdentifier: id) != nil {
            return id
        }

        if let existing = fetchAlbumByTitle(albumTitle) {
            cachedAlbumLocalId = existing.localIdentifier
            return existing.localIdentifier
        }

        let createdId = try await createAlbum(title: albumTitle)
        cachedAlbumLocalId = createdId
        return createdId
    }

    private nonisolated func fetchAlbum(localIdentifier: String) -> PHAssetCollection? {
        let r = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [localIdentifier], options: nil)
        return r.firstObject
    }

    private nonisolated func fetchAsset(localIdentifier: String) -> PHAsset? {
        let r = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return r.firstObject
    }

    private nonisolated func fetchAlbumByTitle(_ title: String) -> PHAssetCollection? {
        let r = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var out: PHAssetCollection? = nil
        r.enumerateObjects { c, _, stop in
            if c.localizedTitle == title {
                out = c
                stop.pointee = true
            }
        }
        return out
    }

    private func createAlbum(title: String) async throws -> String {
        try await withCheckedThrowingContinuation { c in
            var newId: String?
            PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                newId = req.placeholderForCreatedAssetCollection.localIdentifier
            } completionHandler: { ok, err in
                if let err {
                    c.resume(throwing: err)
                    return
                }
                guard ok else {
                    c.resume(throwing: NSError(domain: "AlbumArchiver", code: 1))
                    return
                }
                guard let newId else {
                    c.resume(throwing: AlbumArchiverError.missingAlbumIdentifier)
                    return
                }
                c.resume(returning: newId)
            }
        }
    }

    private func addAsset(assetLocalIdentifier: String, toAlbumLocalIdentifier albumLocalIdentifier: String) async throws {
        // Preflight fetch to deterministically detect phantom/missing assets.
        guard let asset = fetchAsset(localIdentifier: assetLocalIdentifier) else {
            throw AlbumArchiverError.assetNotFound
        }

        guard let album = fetchAlbum(localIdentifier: albumLocalIdentifier) else {
            throw AlbumArchiverError.albumNotFound
        }

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                guard let req = PHAssetCollectionChangeRequest(for: album) else {
                    return
                }
                req.addAssets([asset] as NSArray)
            } completionHandler: { ok, err in
                if let err {
                    c.resume(throwing: err)
                    return
                }
                guard ok else {
                    // Disambiguate common failure causes.
                    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                    if status != .authorized && status != .limited {
                        c.resume(throwing: AlbumArchiverError.notAuthorized(status: status))
                        return
                    }
                    c.resume(throwing: NSError(domain: "AlbumArchiver", code: 2))
                    return
                }
                c.resume(returning: ())
            }
        }
    }
}
