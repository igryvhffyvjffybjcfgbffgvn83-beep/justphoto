import AVFoundation
import SwiftUI

#if canImport(UIKit)
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let debugROIs: ROISet?

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        v.updateDebugROIs(debugROIs)
        return v
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.videoPreviewLayer.session = session
        uiView.updateDebugROIs(debugROIs)
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    private let faceLayer = CAShapeLayer()
    private let eyeLayer = CAShapeLayer()
    private let bgLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupDebugLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDebugLayer()
    }

    private func setupDebugLayer() {
        func setup(_ l: CAShapeLayer, stroke: UIColor) {
            l.fillColor = UIColor.clear.cgColor
            l.lineWidth = 2
            l.strokeColor = stroke.cgColor
            l.lineJoin = .round
            l.lineDashPattern = [6, 4]
            layer.addSublayer(l)
        }

        setup(faceLayer, stroke: UIColor.systemGreen.withAlphaComponent(0.95))
        setup(eyeLayer, stroke: UIColor.systemBlue.withAlphaComponent(0.95))
        setup(bgLayer, stroke: UIColor.systemYellow.withAlphaComponent(0.90))
    }

    func updateDebugROIs(_ rois: ROISet?) {
        faceLayer.frame = bounds
        eyeLayer.frame = bounds
        bgLayer.frame = bounds

        guard let rois else {
            faceLayer.path = nil
            eyeLayer.path = nil
            bgLayer.path = nil
            return
        }

        let facePath = UIBezierPath(rect: convertPortraitNormalizedToLayerRect(rois.faceROI))
        faceLayer.path = facePath.cgPath

        let bgPath = UIBezierPath()
        for r in rois.bgRingRects {
            bgPath.append(UIBezierPath(rect: convertPortraitNormalizedToLayerRect(r)))
        }
        bgLayer.path = bgPath.cgPath

        if let eye = rois.eyeROI {
            eyeLayer.path = UIBezierPath(rect: convertPortraitNormalizedToLayerRect(eye)).cgPath
        } else {
            eyeLayer.path = nil
        }
    }

    private func convertPortraitNormalizedToLayerRect(_ r: CGRect) -> CGRect {
        // Our portrait-normalized space uses y-up; AVCaptureMetadataOutput uses y-down.
        let metadata = CGRect(x: r.minX, y: 1.0 - r.maxY, width: r.width, height: r.height)
        return videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: metadata)
    }
}
#else
struct CameraPreviewView: View {
    let session: AVCaptureSession
    let debugROIs: ROISet?
    var body: some View { Color.black }
}
#endif
