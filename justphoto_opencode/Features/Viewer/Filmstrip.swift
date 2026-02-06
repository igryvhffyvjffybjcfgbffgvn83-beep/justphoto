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
                        state: item.state,
                        thumbnailState: item.thumbnailState,
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
    let state: SessionItemState
    let thumbnailState: ThumbnailState?
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

            if state == .write_failed {
                Color.black.opacity(0.32)
            }

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

            VStack {
                HStack {
                    Spacer(minLength: 0)
                    badgeView
                        .padding(6)
                }
                Spacer(minLength: 0)
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

    @ViewBuilder
    private var badgeView: some View {
        switch badgeKind {
        case .none:
            EmptyView()
        case .saving:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(0.75)
                .padding(6)
                .background(Circle().fill(Color.black.opacity(0.36)))
        case .warning:
            Text("!")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.orange.opacity(0.92))
                )
        }
    }

    private enum BadgeKind {
        case none
        case saving
        case warning
    }

    private var badgeKind: BadgeKind {
        if state == .write_failed { return .warning }
        if state == .captured_preview || state == .writing { return .saving }
        if thumbnailState == .failed { return .warning }
        return .none
    }

    private var thumbImage: Image {
#if canImport(UIKit)
        guard let rel = thumbCacheRelPath,
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
