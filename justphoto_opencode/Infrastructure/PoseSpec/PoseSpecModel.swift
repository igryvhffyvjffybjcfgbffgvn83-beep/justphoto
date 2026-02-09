import Foundation

// M6.2: Strongly-typed PoseSpec model.

// A Codable JSON value for sections we don't need to type yet.
enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:
            try c.encodeNil()
        case .bool(let b):
            try c.encode(b)
        case .number(let n):
            try c.encode(n)
        case .string(let s):
            try c.encode(s)
        case .array(let a):
            try c.encode(a)
        case .object(let o):
            try c.encode(o)
        }
    }
}

struct PoseSpec: Codable, Sendable {
    // M6.4: Single source of truth for PRD version match.
    static let supportedVersion = "v1.1.4"

    let name: String
    let schemaVersion: String
    let generatedAt: String
    let coordinateSystem: CoordinateSystem
    let qaAssets: QAAssets
    let defaults: Defaults
    let sceneDefaults: [String: SceneDefaults]
    let mutexGroups: [String]
    let metrics: Metrics
    let cues: [JSONValue]

    let prdVersion: String
    let sceneCatalog: SceneCatalog
    let directorScriptCard: JSONValue
    let praisePolicy: JSONValue
    let changeLog: [ChangeLogEntry]

    let binding: PoseSpecBinding?
    let rois: ROIs
    let withRefPolicy: JSONValue
    let v1Proxies: JSONValue
}

struct CoordinateSystem: Codable, Sendable {
    let space: String
    let x: String
    let y: String
    let range: [Double]
    let note: String
}

struct QAAssets: Codable, Sendable {
    let namingConvention: String
    let requirement: String
}

struct Defaults: Codable, Sendable {
    let confidence: ConfidenceDefaults
    let antiJitter: AntiJitterDefaults
    let hysteresis: HysteresisDefaults
    let selection: JSONValue
}

struct ConfidenceDefaults: Codable, Sendable {
    let minConfidence: Double
    let multiPersonDegradeTo: [String]
    let fallbackCueId: String
    let minLandmarkConfidence: Double
}

struct AntiJitterDefaults: Codable, Sendable {
    let persistFrames: Int
    let minHoldMs: Int
    let cooldownMs: Int
}

struct HysteresisDefaults: Codable, Sendable {
    let enabled: Bool
    let note: String
}

struct SceneDefaults: Codable, Sendable {
    let confidence: SceneConfidenceDefaults
    let antiJitter: AntiJitterDefaults
}

struct SceneConfidenceDefaults: Codable, Sendable {
    let minConfidence: Double
    let fallbackCueId: String
}

struct Metrics: Codable, Sendable {
    let helpers: [String: String]
    let notes: [String]
}

struct SceneCatalog: Codable, Sendable {
    let uiScenes: [String]
    let internalSharedScene: String
    let evaluationRule: String
    let analyticsSceneParam: String
}

struct ChangeLogEntry: Codable, Sendable {
    let version: String?
    let date: String
    let notes: [String]?
    let changes: [String]?
    let referenceCases: [String]?
    let scope: String?
    let items: [String]?
}

struct PoseSpecBinding: Codable, Sendable {
    let aliases: [String: String]
    let sets: PoseSpecBindingSets
    let notes: [String]
}

struct PoseSpecBindingSets: Codable, Sendable {
    let bodyPoints: BodyPointsSet
}

struct BodyPointsSet: Codable, Sendable {
    let from: String
    let include: String
    let rule: String
}

struct ROIs: Codable, Sendable {
    let faceROI: FaceROI?
    let eyeROI: EyeROI?
    let bgROI: BgROI?
}

struct FaceROI: Codable, Sendable {
    let from: String
    let paddingPctOfBBox: XY
    let clampToFrame: Bool
    let notes: String?
}

struct EyeROI: Codable, Sendable {
    let from: [String]
    let shape: String
    let center: String
    let sizeRule: SizeRule
    let clampToFrame: Bool
    let requiresConfidence: String
    let notes: String?
}

struct BgROI: Codable, Sendable {
    let type: String
    let minus: String
    let implementation: String?
    let notes: String?
}

struct SizeRule: Codable, Sendable {
    let w: String
    let h: String
}

struct XY: Codable, Sendable {
    let x: Double
    let y: Double
}
