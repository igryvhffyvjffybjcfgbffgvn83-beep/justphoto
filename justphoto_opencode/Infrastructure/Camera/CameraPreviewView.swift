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

        if rois.eyeROIs.isEmpty {
            eyeLayer.path = nil
        } else {
            let eyePath = UIBezierPath()
            for eye in rois.eyeROIs {
                eyePath.append(UIBezierPath(rect: convertPortraitNormalizedToLayerRect(eye)))
            }
            eyeLayer.path = eyePath.cgPath
        }
    }

    private func convertPortraitNormalizedToLayerRect(_ r: CGRect) -> CGRect {
        // PoseSpec canonical space is portrait-normalized and Y-Down, matching AVCaptureMetadataOutput.
        return videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: r)
    }
}
#else
struct CameraPreviewView: View {
    let session: AVCaptureSession
    let debugROIs: ROISet?
    var body: some View { Color.black }
}
#endif
