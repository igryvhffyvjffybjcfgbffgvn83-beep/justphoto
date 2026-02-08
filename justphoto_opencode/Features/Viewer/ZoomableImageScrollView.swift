import SwiftUI

#if canImport(UIKit)
import UIKit

// M5.5: UIScrollView-based zoom/pan bridge.
struct ZoomableImageScrollView: UIViewRepresentable {
    let image: UIImage?
    let imageId: String

    @Binding var zoomScale: CGFloat
    @Binding var isPinching: Bool

    var minimumZoomScale: CGFloat = 1.0
    var maximumZoomScale: CGFloat = 4.0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = minimumZoomScale
        scrollView.maximumZoomScale = maximumZoomScale
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .black

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.image = image
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)

        // Make the imageView match the scrollView's frame at zoomScale=1.
        // The content size grows automatically when zoomed.
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        context.coordinator.imageView = imageView
        context.coordinator.lastImageId = imageId
        context.coordinator.zoomScaleBinding = $zoomScale
        context.coordinator.isPinchingBinding = $isPinching

        if let pinch = scrollView.pinchGestureRecognizer {
            pinch.addTarget(context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        }

        zoomScale = 1.0
        isPinching = false
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        context.coordinator.zoomScaleBinding = $zoomScale
        context.coordinator.isPinchingBinding = $isPinching

        if context.coordinator.lastImageId != imageId {
            context.coordinator.lastImageId = imageId
            scrollView.setZoomScale(1.0, animated: false)
            scrollView.setContentOffset(.zero, animated: false)
            zoomScale = 1.0
            isPinching = false
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        fileprivate weak var imageView: UIImageView?
        fileprivate var lastImageId: String = ""
        fileprivate var zoomScaleBinding: Binding<CGFloat>?
        fileprivate var isPinchingBinding: Binding<Bool>?

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began, .changed:
                isPinchingBinding?.wrappedValue = true
            default:
                isPinchingBinding?.wrappedValue = false
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            _ = scrollView
            return imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            zoomScaleBinding?.wrappedValue = scrollView.zoomScale
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            _ = view
            _ = scale
            zoomScaleBinding?.wrappedValue = scrollView.zoomScale
        }
    }
}

#else
struct ZoomableImageScrollView: View {
    let imageId: String
    @Binding var zoomScale: CGFloat
    @Binding var isPinching: Bool

    var body: some View {
        _ = imageId
        _ = zoomScale
        _ = isPinching
        return Image(systemName: "photo")
    }
}
#endif
