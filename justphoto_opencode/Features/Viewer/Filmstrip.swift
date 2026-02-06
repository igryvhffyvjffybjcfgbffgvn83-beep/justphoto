import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// M5.1: Filmstrip component (horizontal thumbnails).
// This is intentionally minimal; badges/order/liked wiring lands in later milestones.
struct Filmstrip: View {
    let items: [SessionRepository.SessionItemSummary]
    @Binding var selectedItemId: String?

    var itemSize: CGFloat = 56
    var itemSpacing: CGFloat = 10
    var cornerRadius: CGFloat = 14
    var onSelect: (SessionRepository.SessionItemSummary) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: itemSpacing) {
                ForEach(items, id: \.itemId) { item in
                    FilmstripThumb(
                        thumbCacheRelPath: item.thumbCacheRelPath,
                        shotSeq: item.shotSeq,
                        size: itemSize,
                        cornerRadius: cornerRadius,
                        isSelected: item.itemId == selectedItemId
                    )
                    .onTapGesture {
                        selectedItemId = item.itemId
                        onSelect(item)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Photo \(item.shotSeq)")
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

private struct FilmstripThumb: View {
    let thumbCacheRelPath: String?
    let shotSeq: Int
    let size: CGFloat
    let cornerRadius: CGFloat
    let isSelected: Bool

    var body: some View {
        ZStack {
            thumbImage
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipped()

            VStack {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    Text("\(shotSeq)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.28))
                        )
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(isSelected ? Color.primary.opacity(0.9) : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var thumbImage: Image {
#if canImport(UIKit)
        guard let rel = thumbCacheRelPath,
              let url = try? PendingFileStore.shared.fullURL(forRelativePath: rel),
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
