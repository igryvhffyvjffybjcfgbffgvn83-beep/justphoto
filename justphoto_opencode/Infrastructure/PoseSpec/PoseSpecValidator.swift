import Foundation

enum PoseSpecValidationError: Error, LocalizedError {
    case missingRequiredKeys([String])
    case wrongType(key: String, expected: String)
    case prdVersionMismatch(expected: String, actual: String)
    case bindingMissingAliases([String])
    case bindingMissingBodyPointsSet
    case bindingBodyPointsSetMismatch
    case roisMissing([String])
    case roisBadDefinition(String)

    var errorDescription: String? {
        switch self {
        case .missingRequiredKeys(let keys):
            return "PoseSpec missing required keys: \(keys.joined(separator: ", "))"
        case .wrongType(let key, let expected):
            return "PoseSpec key has wrong type: \(key) (expected \(expected))"
        case .prdVersionMismatch(let expected, let actual):
            return "PoseSpec prdVersion mismatch: expected=\(expected) actual=\(actual)"
        case .bindingMissingAliases(let keys):
            return "PoseSpec binding.aliases missing: \(keys.joined(separator: ", "))"
        case .bindingMissingBodyPointsSet:
            return "PoseSpec binding.sets.bodyPoints missing"
        case .bindingBodyPointsSetMismatch:
            return "PoseSpec binding.sets.bodyPoints definition mismatch"
        case .roisMissing(let keys):
            return "PoseSpec rois missing: \(keys.joined(separator: ", "))"
        case .roisBadDefinition(let msg):
            return "PoseSpec rois invalid: \(msg)"
        }
    }
}

// M6.3: Minimal required-fields validator for PoseSpec.json.
enum PoseSpecValidator {
    static func validateRequiredFields(_ spec: PoseSpec) throws {
        var missing: [String] = []

        if spec.schemaVersion.isEmpty { missing.append("schemaVersion") }
        if spec.prdVersion.isEmpty { missing.append("prdVersion") }
        if spec.generatedAt.isEmpty { missing.append("generatedAt") }
        if spec.changeLog.isEmpty { missing.append("changeLog") }
        if spec.binding == nil { missing.append("binding") }

        if !missing.isEmpty {
            throw PoseSpecValidationError.missingRequiredKeys(missing)
        }
    }

    static func validatePrdVersion(_ spec: PoseSpec) throws {
        let expected = PoseSpec.supportedVersion
        let actual = spec.prdVersion
        guard actual == expected else {
            throw PoseSpecValidationError.prdVersionMismatch(expected: expected, actual: actual)
        }
    }

    static func validateBindingAliasesMinimalSet(_ spec: PoseSpec) throws {
        guard let binding = spec.binding else {
            throw PoseSpecValidationError.missingRequiredKeys(["binding"])
        }

        let aliases = binding.aliases

        let requiredAliases: [String] = [
            "lShoulder", "rShoulder", "lHip", "rHip", "lAnkle", "rAnkle",
            "faceBBox", "noseTip", "chinCenter",
            "lEye", "rEye", "eyeMid", "hipMid", "ankleMid",
        ]

        let missing = requiredAliases.filter { aliases[$0] == nil }
        if !missing.isEmpty {
            throw PoseSpecValidationError.bindingMissingAliases(missing)
        }

        let bodyPoints = binding.sets.bodyPoints

        let expectedFrom = "metric.landmarks"
        let expectedInclude = "body.*"

        let from = bodyPoints.from
        let include = bodyPoints.include
        let rule = bodyPoints.rule

        // PRD 4.4.2: bodyPoints must be defined deterministically.
        guard from == expectedFrom, include == expectedInclude, rule.contains("defaults.confidence.minLandmarkConfidence") else {
            throw PoseSpecValidationError.bindingBodyPointsSetMismatch
        }
    }

    static func validateRoisDictionary(_ spec: PoseSpec) throws {
        let required: [String] = ["faceROI", "eyeROI", "bgROI"]
        var missing: [String] = []
        if spec.rois.faceROI == nil { missing.append("faceROI") }
        if spec.rois.eyeROI == nil { missing.append("eyeROI") }
        if spec.rois.bgROI == nil { missing.append("bgROI") }
        if !missing.isEmpty {
            throw PoseSpecValidationError.roisMissing(missing)
        }

        guard let face = spec.rois.faceROI else {
            throw PoseSpecValidationError.roisMissing(required)
        }
        guard !face.from.isEmpty else {
            throw PoseSpecValidationError.roisBadDefinition("rois.faceROI.from empty")
        }
        guard face.paddingPctOfBBox.x >= 0.0, face.paddingPctOfBBox.x <= 1.0,
              face.paddingPctOfBBox.y >= 0.0, face.paddingPctOfBBox.y <= 1.0
        else {
            throw PoseSpecValidationError.roisBadDefinition("rois.faceROI.paddingPctOfBBox out of range [0,1]")
        }
        _ = face.clampToFrame

        guard let eye = spec.rois.eyeROI else {
            throw PoseSpecValidationError.roisMissing(["eyeROI"])
        }
        guard eye.from.count >= 2 else {
            throw PoseSpecValidationError.roisBadDefinition("rois.eyeROI.from must be an array of >=2 strings")
        }
        guard eye.from.allSatisfy({ !$0.isEmpty }) else {
            throw PoseSpecValidationError.roisBadDefinition("rois.eyeROI.from contains empty string")
        }
        guard !eye.center.isEmpty else {
            throw PoseSpecValidationError.roisBadDefinition("rois.eyeROI.center empty")
        }
        guard !eye.sizeRule.w.isEmpty, !eye.sizeRule.h.isEmpty else {
            throw PoseSpecValidationError.roisBadDefinition("rois.eyeROI.sizeRule empty")
        }
        _ = eye.clampToFrame
        guard !eye.requiresConfidence.isEmpty else {
            throw PoseSpecValidationError.roisBadDefinition("rois.eyeROI.requiresConfidence empty")
        }

        guard let bg = spec.rois.bgROI else {
            throw PoseSpecValidationError.roisMissing(["bgROI"])
        }
        guard !bg.type.isEmpty else {
            throw PoseSpecValidationError.roisBadDefinition("rois.bgROI.type empty")
        }
        guard !bg.minus.isEmpty else {
            throw PoseSpecValidationError.roisBadDefinition("rois.bgROI.minus empty")
        }
    }
}
