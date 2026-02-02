import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        if let popover = vc.popoverPresentationController {
            popover.sourceView = vc.view
            popover.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        _ = uiViewController
    }
}
#else
struct ShareSheet: View {
    let activityItems: [Any]

    var body: some View {
        _ = activityItems
        return Text("Sharing is unavailable on this platform")
    }
}
#endif
