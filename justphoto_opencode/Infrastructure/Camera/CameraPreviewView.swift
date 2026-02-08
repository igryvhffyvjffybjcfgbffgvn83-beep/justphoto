import AVFoundation
import SwiftUI

#if canImport(UIKit)
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
#else
struct CameraPreviewView: View {
    let session: AVCaptureSession
    var body: some View { Color.black }
}
#endif
