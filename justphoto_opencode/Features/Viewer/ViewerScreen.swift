import Foundation
import SwiftUI

struct ViewerScreen: View {
    @EnvironmentObject private var promptCenter: PromptCenter
    @Environment(\.dismiss) private var dismiss

    @State private var failedItems: [SessionRepository.SessionItemSummary] = []
    @State private var thumbFailedItems: [SessionRepository.SessionItemSummary] = []
    @State private var isRetrying = false
    @State private var showingAbandonConfirm = false
    @State private var abandonTargetItemId: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if failedItems.isEmpty {
                    if thumbFailedItems.isEmpty {
                        Text("没有需要处理的项目")
                        .font(.headline)
                        .padding(.top, 12)

                        Text("你可以返回继续拍摄。")
                            .foregroundStyle(.secondary)

                        Button("关闭") { dismiss() }
                            .buttonStyle(.bordered)
                            .padding(.top, 8)
                    } else {
                        thumbFailedSection
                    }
                } else {
                    writeFailedSection

                    if !thumbFailedItems.isEmpty {
                        Divider().padding(.vertical, 8)
                        thumbFailedSection
                    }
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Viewer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新") { refresh() }
                        .disabled(isRetrying)
                }
            }
            .task { refresh() }
        }
        .confirmationDialog(
            "放弃此张？",
            isPresented: $showingAbandonConfirm,
            titleVisibility: .visible
        ) {
            Button("放弃此张", role: .destructive) {
                let id = abandonTargetItemId
                abandonTargetItemId = ""
                abandonOne(itemId: id)
            }
            Button("取消", role: .cancel) {
                abandonTargetItemId = ""
            }
        } message: {
            Text("这张照片未保存到系统相册，放弃后将从本次列表移除。")
        }
        .promptHost()
    }

    @ViewBuilder
    private func failedRow(_ item: SessionRepository.SessionItemSummary) -> some View {
        let pendingRel = item.pendingFileRelPath ?? ""
        let pendingExists = (!pendingRel.isEmpty && PendingFileStore.shared.fileExists(relativePath: pendingRel))

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("照片 \(item.shotSeq)")
                    .font(.subheadline.weight(.semibold))
                Text(WriteFailReason.writeFailedMessage(reasonText: nil))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(pendingExists ? "pending: OK" : "pending: missing")
                    .font(.caption2)
                    .foregroundStyle(pendingExists ? Color.secondary : Color.red)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button("重试") {
                    retryOne(itemId: item.itemId)
                }
                .buttonStyle(.bordered)
                .disabled(isRetrying)

                Button("放弃") {
                    abandonTargetItemId = item.itemId
                    showingAbandonConfirm = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(isRetrying)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func refresh() {
        do {
            failedItems = try SessionRepository.shared.writeFailedItemsForCurrentSession()
            thumbFailedItems = try SessionRepository.shared.thumbFailedItemsForCurrentSession()
        } catch {
            failedItems = []
            thumbFailedItems = []
            promptCenter.show(makeViewerToast(key: "viewer_refresh_failed", message: "刷新失败"))
            print("ViewerRefreshFAILED: \(error)")
        }
    }

    private var writeFailedSection: some View {
        VStack(spacing: 12) {
            Text("有 \(failedItems.count) 张照片未保存")
                .font(.headline)
                .padding(.top, 12)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(failedItems, id: \.itemId) { item in
                        failedRow(item)
                    }
                }
                .padding(.top, 6)
            }

            Button(isRetrying ? "正在重试..." : "重试全部") {
                retryAll()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRetrying)
        }
    }

    private var thumbFailedSection: some View {
        VStack(spacing: 12) {
            let permanent = permanentThumbFailedItems

            Text("有 \(thumbFailedItems.count) 张缩略图异常")
                .font(.headline)
                .padding(.top, 12)

            if !permanent.isEmpty {
                HStack {
                    Text("缩略生成失败，不影响原图")
                        .font(.footnote.weight(.semibold))
                    Spacer(minLength: 0)
                    Button("重建缩略") {
                        rebuildThumbBatch(permanent)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRetrying)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.systemYellow).opacity(0.22))
                )
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(thumbFailedItems, id: \.itemId) { item in
                        thumbFailedRow(item)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private var permanentThumbFailedItems: [SessionRepository.SessionItemSummary] {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        return thumbFailedItems.filter { item in
            let age = nowMs - Int64(item.createdAtMs)
            if age < 30_000 { return false }
            let rel = item.thumbCacheRelPath ?? ""
            if rel.isEmpty { return true }
            return !ThumbCacheStore.shared.fileExists(relativePath: rel)
        }
    }

    @ViewBuilder
    private func thumbFailedRow(_ item: SessionRepository.SessionItemSummary) -> some View {
        let rel = item.thumbCacheRelPath ?? ""
        let exists = (!rel.isEmpty && ThumbCacheStore.shared.fileExists(relativePath: rel))

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("照片 \(item.shotSeq)")
                    .font(.subheadline.weight(.semibold))
                Text("缩略生成失败")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(exists ? "thumb: OK" : "thumb: missing")
                    .font(.caption2)
                    .foregroundStyle(exists ? Color.secondary : Color.red)
            }

            Spacer(minLength: 0)

            Button("重建") {
                rebuildThumbOne(itemId: item.itemId)
            }
            .buttonStyle(.bordered)
            .disabled(isRetrying)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func rebuildThumbOne(itemId: String) {
        isRetrying = true
        Task {
            await ThumbnailPipeline.shared.rebuildThumbnail(itemId: itemId)
            await MainActor.run {
                isRetrying = false
                refresh()
                promptCenter.show(makeViewerToast(key: "viewer_thumb_rebuild", message: "已请求重建"))
            }
        }
    }

    private func rebuildThumbBatch(_ items: [SessionRepository.SessionItemSummary]) {
        isRetrying = true
        let ids = items.map { $0.itemId }
        Task {
            for id in ids {
                await ThumbnailPipeline.shared.rebuildThumbnail(itemId: id)
            }
            await MainActor.run {
                isRetrying = false
                refresh()
                promptCenter.show(makeViewerToast(key: "viewer_thumb_rebuild_all", message: "已请求重建"))
            }
        }
    }

    private func retryOne(itemId: String) {
        isRetrying = true
        Task {
            let ok = await CaptureCoordinator.shared.retryWriteFailedItem(itemId: itemId)
            await MainActor.run {
                isRetrying = false
                refresh()
                promptCenter.show(makeViewerToast(
                    key: ok ? "viewer_retry_ok" : "viewer_retry_failed",
                    message: ok ? "已重试保存" : "重试失败"
                ))
            }
        }
    }

    private func retryAll() {
        isRetrying = true
        let ids = failedItems.map { $0.itemId }
        Task {
            var okCount = 0
            for id in ids {
                if await CaptureCoordinator.shared.retryWriteFailedItem(itemId: id) {
                    okCount += 1
                }
            }
            await MainActor.run {
                isRetrying = false
                refresh()
                promptCenter.show(makeViewerToast(
                    key: "viewer_retry_all_done",
                    message: "已重试：\(okCount)/\(ids.count)"
                ))
            }
        }
    }

    private func abandonOne(itemId: String) {
        isRetrying = true
        Task {
            let ok = await CaptureCoordinator.shared.abandonItem(itemId: itemId)
            await MainActor.run {
                isRetrying = false
                refresh()
                promptCenter.show(makeViewerToast(
                    key: ok ? "viewer_abandon_ok" : "viewer_abandon_failed",
                    message: ok ? "已放弃此张" : "放弃失败"
                ))

                if failedItems.isEmpty {
                    dismiss()
                }
            }
        }
    }

    private func makeViewerToast(key: String, message: String) -> Prompt {
        Prompt(
            key: key,
            level: .L1,
            surface: .viewerBannerTop,
            priority: 10,
            blocksShutter: false,
            isClosable: false,
            autoDismissSeconds: 2.0,
            gate: .none,
            title: nil,
            message: message,
            primaryActionId: nil,
            primaryTitle: nil,
            secondaryActionId: nil,
            secondaryTitle: nil,
            tertiaryActionId: nil,
            tertiaryTitle: nil,
            throttle: .init(
                perKeyMinIntervalSec: 2,
                globalWindowSec: 0,
                globalMaxCountInWindow: 0,
                suppressAfterDismissSec: 0
            ),
            payload: [:],
            emittedAt: Date()
        )
    }
}

#Preview {
    NavigationStack { ViewerScreen() }
        .environmentObject(PromptCenter())
}
