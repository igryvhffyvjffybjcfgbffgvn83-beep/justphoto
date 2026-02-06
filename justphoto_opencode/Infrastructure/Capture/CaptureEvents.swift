import Foundation

import Foundation

enum CaptureEvents {
    nonisolated static let captureFailed = Notification.Name("justphoto.capture_failed")
    nonisolated static let writeFailed = Notification.Name("justphoto.write_failed")
    nonisolated static let albumAddFailed = Notification.Name("justphoto.album_add_failed")
    nonisolated static let sessionItemsChanged = Notification.Name("justphoto.session_items_changed")
}
