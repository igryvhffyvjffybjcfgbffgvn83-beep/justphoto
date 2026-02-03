import Foundation

enum PromptLevel: String, Codable, Sendable {
    case L1
    case L2
    case L3
}

enum PromptSurface: String, Codable, Sendable {
    case cameraToastBottom
    case cameraBannerTop
    case cameraModalCenter
    case viewerBannerTop
    case viewerBlockingBarTop
    case sheetBannerTop
    case sheetModalCenter
}

enum WriteFailReason: String, Codable, Sendable {
    case no_permission
    case no_space
    case photo_lib_unavailable
    case system_pressure
}

enum RefRejectReason: String, Codable, Sendable {
    case multi_person
    case face_too_small
    case eyes_not_visible
    case upper_body_incomplete
}

enum FrequencyGate: String, Codable, Sendable {
    case none
    case sessionOnce
    case installOnce
    case stateOnly
}

enum DismissReason: String, Codable, Sendable {
    case auto
    case close
    case action
    case preempt
}

struct ThrottleRule: Codable, Sendable, Equatable {
    var perKeyMinIntervalSec: Double
    var globalWindowSec: Double
    var globalMaxCountInWindow: Int
    var suppressAfterDismissSec: Double
}

enum PromptPayloadValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    private enum CodingKeys: String, CodingKey {
        case type
        case string
        case int
        case double
        case bool
    }

    private enum PayloadType: String, Codable {
        case string
        case int
        case double
        case bool
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(PayloadType.self, forKey: .type)
        switch type {
        case .string:
            self = .string(try c.decode(String.self, forKey: .string))
        case .int:
            self = .int(try c.decode(Int.self, forKey: .int))
        case .double:
            self = .double(try c.decode(Double.self, forKey: .double))
        case .bool:
            self = .bool(try c.decode(Bool.self, forKey: .bool))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .string(v):
            try c.encode(PayloadType.string, forKey: .type)
            try c.encode(v, forKey: .string)
        case let .int(v):
            try c.encode(PayloadType.int, forKey: .type)
            try c.encode(v, forKey: .int)
        case let .double(v):
            try c.encode(PayloadType.double, forKey: .type)
            try c.encode(v, forKey: .double)
        case let .bool(v):
            try c.encode(PayloadType.bool, forKey: .type)
            try c.encode(v, forKey: .bool)
        }
    }
}

struct PromptAction: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var title: String
}

struct Prompt: Codable, Sendable, Equatable, Identifiable {
    // NOTE: Field list is intentionally aligned with PRD Appendix A.2.2.
    var key: String
    var level: PromptLevel
    var surface: PromptSurface
    var priority: Int
    var blocksShutter: Bool
    var isClosable: Bool
    var autoDismissSeconds: Double?
    var gate: FrequencyGate
    var title: String?
    var message: String
    var primaryActionId: String?
    var primaryTitle: String?
    var secondaryActionId: String?
    var secondaryTitle: String?
    var tertiaryActionId: String?
    var tertiaryTitle: String?
    var throttle: ThrottleRule
    var payload: [String: PromptPayloadValue]
    var emittedAt: Date

    var id: String { "\(key)|\(Int(emittedAt.timeIntervalSince1970 * 1000))" }

    var actions: [PromptAction] {
        var out: [PromptAction] = []
        if let id = primaryActionId, let title = primaryTitle {
            out.append(.init(id: id, title: title))
        }
        if let id = secondaryActionId, let title = secondaryTitle {
            out.append(.init(id: id, title: title))
        }
        if let id = tertiaryActionId, let title = tertiaryTitle {
            out.append(.init(id: id, title: title))
        }
        return out
    }
}
