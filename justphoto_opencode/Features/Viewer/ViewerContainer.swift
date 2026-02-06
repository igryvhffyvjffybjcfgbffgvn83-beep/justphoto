import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// M5.4: Viewer shell (index + close + like placeholder).
struct ViewerContainer: View {
    @Environment(\.dismiss) private var dismiss

    let items: [SessionRepository.SessionItemSummary]
    let initialItemId: String?

    @State private var selectedItemId: String

    init(items: [SessionRepository.SessionItemSummary], initialItemId: String?) {
        self.items = items
        self.initialItemId = initialItemId
        _selectedItemId = State(initialValue: initialItemId ?? items.first?.itemId ?? "")
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if items.isEmpty {
                VStack(spacing: 12) {
                    Text("No items")
                        .foregroundStyle(.white)
                    Button("Close") { dismiss() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            } else {
                TabView(selection: $selectedItemId) {
                    ForEach(items, id: \.itemId) { item in
                        ViewerPage(item: item)
                            .tag(item.itemId)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                }
                .padding(.top, 6)
            }
        }
        .onAppear {
            if selectedItemId.isEmpty {
                selectedItemId = items.first?.itemId ?? ""
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }

            Spacer(minLength: 0)

            Text("\(currentIndexText)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )

            Spacer(minLength: 0)

            Button {
                // Like wiring lands in M5.8 (persistence).
            } label: {
                Image(systemName: currentItem?.liked == true ? "heart.fill" : "heart")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .disabled(true)
        }
        .padding(.horizontal, 12)
    }

    private var currentItem: SessionRepository.SessionItemSummary? {
        items.first { $0.itemId == selectedItemId }
    }

    private var currentIndexText: String {
        let idx = items.firstIndex { $0.itemId == selectedItemId } ?? 0
        return "\(idx + 1)/\(items.count)"
    }
}

private struct ViewerPage: View {
    let item: SessionRepository.SessionItemSummary

    var body: some View {
        ZStack {
            Color.black
            zoomable
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var zoomable: some View {
#if canImport(UIKit)
        ZoomableImageScrollView(image: uiImageForViewer, imageId: item.itemId)
#else
        Image(systemName: "photo")
#endif
    }

#if canImport(UIKit)
    private var uiImageForViewer: UIImage {
        guard let rel = item.thumbCacheRelPath,
              let url = try? ThumbCacheStore.shared.fullURL(forRelativePath: rel)
        else {
            return Self.makeNumericPlaceholderImage(text: "\(item.shotSeq)")
        }

        if let img = UIImage(contentsOfFile: url.path) {
            return img
        }
        return Self.makeNumericPlaceholderImage(text: "\(item.shotSeq)")
    }

    private static func makeNumericPlaceholderImage(text: String) -> UIImage {
        let size = CGSize(width: 1200, height: 1200)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let r = CGRect(origin: .zero, size: size)
            UIColor.black.setFill()
            ctx.fill(r)

            // High-contrast diagonal stripes.
            let stripeW: CGFloat = 60
            for i in -40..<60 {
                let x = CGFloat(i) * stripeW
                let path = UIBezierPath()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + stripeW, y: 0))
                path.addLine(to: CGPoint(x: x + size.width + stripeW, y: size.height))
                path.addLine(to: CGPoint(x: x + size.width, y: size.height))
                path.close()

                let isA = i % 2 == 0
                (isA ? UIColor.systemYellow : UIColor.systemCyan).withAlphaComponent(0.92).setFill()
                path.fill()
            }

            // Center number.
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 360, weight: .heavy),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph,
            ]

            let s = NSAttributedString(string: text, attributes: attrs)
            let box = CGRect(x: 0, y: (size.height - 420) / 2, width: size.width, height: 420)

            UIColor.white.withAlphaComponent(0.88).setFill()
            UIBezierPath(roundedRect: box.insetBy(dx: 180, dy: 40), cornerRadius: 90).fill()
            s.draw(in: box)
        }
    }
#endif
}
