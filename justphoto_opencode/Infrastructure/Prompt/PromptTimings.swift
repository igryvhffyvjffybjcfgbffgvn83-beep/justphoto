import Foundation

enum PromptTimings {
    // PRD Appendix A.3.1
    static let l1ToastSeconds: Double = 4.0
    static let l2BannerSeconds: Double = 6.0
    static let voiceOverL1ToastSeconds: Double = 6.0
    static let voiceOverL2BannerSeconds: Double = 8.0

    static func toastAutoDismissSeconds(base: Double?, voiceOverEnabled: Bool) -> Double {
        let normal = base ?? l1ToastSeconds
        guard voiceOverEnabled else { return normal }
        return max(normal, voiceOverL1ToastSeconds)
    }

    static func bannerAutoDismissSeconds(base: Double?, voiceOverEnabled: Bool) -> Double {
        let normal = base ?? l2BannerSeconds
        guard voiceOverEnabled else { return normal }
        return max(normal, voiceOverL2BannerSeconds)
    }
}
