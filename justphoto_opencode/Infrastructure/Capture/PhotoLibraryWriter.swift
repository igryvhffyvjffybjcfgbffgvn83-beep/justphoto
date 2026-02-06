import Foundation
import Photos

enum PhotoLibraryWriterError: Error {
    case notAuthorized(status: PHAuthorizationStatus)
    case missingLocalIdentifier
}

// Minimal PhotoKit writer for M4.11.
// Later milestones add verification retry, album archiving, and richer error reasons.
final class PhotoLibraryWriter: Sendable {
    nonisolated static let shared = PhotoLibraryWriter()
    private nonisolated init() {}

    func ensureAddAuthorization() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let newStatus: PHAuthorizationStatus = await withCheckedContinuation { c in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { s in
                    c.resume(returning: s)
                }
            }
            guard newStatus == .authorized else {
                throw PhotoLibraryWriterError.notAuthorized(status: newStatus)
            }
        default:
            throw PhotoLibraryWriterError.notAuthorized(status: status)
        }
    }

    func savePhoto(fileURL: URL) async throws -> String {
        try await ensureAddAuthorization()

        return try await withCheckedThrowingContinuation { c in
            var localId: String?
            PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, fileURL: fileURL, options: nil)
                localId = req.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { ok, err in
                if let err {
                    c.resume(throwing: err)
                    return
                }
                guard ok else {
                    c.resume(throwing: NSError(domain: "PhotoLibraryWriter", code: 1))
                    return
                }
                guard let localId else {
                    c.resume(throwing: PhotoLibraryWriterError.missingLocalIdentifier)
                    return
                }
                c.resume(returning: localId)
            }
        }
    }

    // Immediate post-write verification fetch (M4.12).
    nonisolated func fetchAssetCount(localIdentifier: String) -> Int {
        let r = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return r.count
    }
}
