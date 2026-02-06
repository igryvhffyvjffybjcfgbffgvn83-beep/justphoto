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
            image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    private var image: Image {
#if canImport(UIKit)
        guard let rel = item.thumbCacheRelPath,
              let url = try? ThumbCacheStore.shared.fullURL(forRelativePath: rel),
              let img = UIImage(contentsOfFile: url.path)
        else {
            return Image(systemName: "photo")
        }
        return Image(uiImage: img)
#else
        return Image(systemName: "photo")
#endif
    }
}
