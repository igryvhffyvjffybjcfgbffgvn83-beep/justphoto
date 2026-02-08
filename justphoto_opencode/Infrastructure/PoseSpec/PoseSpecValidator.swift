import Foundation

enum PoseSpecValidationError: Error, LocalizedError {
    case notJSONObject
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
        case .notJSONObject:
            return "PoseSpec root is not a JSON object"
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
    static func validateRequiredFields(data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let obj = json as? [String: Any] else {
            throw PoseSpecValidationError.notJSONObject
        }

        var missing: [String] = []

        func requireString(_ key: String) {
            guard let v = obj[key] else {
                missing.append(key)
                return
            }
            guard v is String else {
                missing.append(key)
                return
            }
        }

        func requireArray(_ key: String) {
            guard let v = obj[key] else {
                missing.append(key)
                return
            }
            guard v is [Any] else {
                missing.append(key)
                return
            }
        }

        func requireObject(_ key: String) {
            guard let v = obj[key] else {
                missing.append(key)
                return
            }
            guard v is [String: Any] else {
                missing.append(key)
                return
            }
        }

        requireString("schemaVersion")
        requireString("prdVersion")
        requireString("generatedAt")
        requireArray("changeLog")
        requireObject("binding")
        requireObject("rois")
        requireObject("sceneCatalog")

        if !missing.isEmpty {
            throw PoseSpecValidationError.missingRequiredKeys(missing)
        }
    }

    static func validatePrdVersion(data: Data, expected: String) throws {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let obj = json as? [String: Any] else {
            throw PoseSpecValidationError.notJSONObject
        }

        guard let v = obj["prdVersion"] else {
            throw PoseSpecValidationError.missingRequiredKeys(["prdVersion"])
        }
        guard let actual = v as? String else {
            throw PoseSpecValidationError.wrongType(key: "prdVersion", expected: "String")
        }
        guard actual == expected else {
            throw PoseSpecValidationError.prdVersionMismatch(expected: expected, actual: actual)
        }
    }

    static func validateBindingAliasesMinimalSet(data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let obj = json as? [String: Any] else {
            throw PoseSpecValidationError.notJSONObject
        }

        guard let binding = obj["binding"] as? [String: Any] else {
            throw PoseSpecValidationError.missingRequiredKeys(["binding"])
        }
        guard let aliases = binding["aliases"] as? [String: Any] else {
            throw PoseSpecValidationError.missingRequiredKeys(["binding.aliases"])
        }

        let requiredAliases: [String] = [
            "lShoulder", "rShoulder", "lHip", "rHip", "lAnkle", "rAnkle",
            "faceBBox", "noseTip", "chinCenter",
            "lEye", "rEye", "eyeMid", "hipMid", "ankleMid",
        ]

        let missing = requiredAliases.filter { aliases[$0] == nil }
        if !missing.isEmpty {
            throw PoseSpecValidationError.bindingMissingAliases(missing)
        }

        guard let sets = binding["sets"] as? [String: Any] else {
            throw PoseSpecValidationError.missingRequiredKeys(["binding.sets"])
        }
        guard let bodyPoints = sets["bodyPoints"] as? [String: Any] else {
            throw PoseSpecValidationError.bindingMissingBodyPointsSet
        }

        let expectedFrom = "metric.landmarks"
        let expectedInclude = "body.*"

        guard let from = bodyPoints["from"] as? String,
              let include = bodyPoints["include"] as? String,
              let rule = bodyPoints["rule"] as? String
        else {
            throw PoseSpecValidationError.bindingBodyPointsSetMismatch
        }

        // PRD 4.4.2: bodyPoints must be defined deterministically.
        guard from == expectedFrom, include == expectedInclude, rule.contains("defaults.confidence.minLandmarkConfidence") else {
            throw PoseSpecValidationError.bindingBodyPointsSetMismatch
        }
    }

    static func validateRoisDictionary(data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let obj = json as? [String: Any] else {
            throw PoseSpecValidationError.notJSONObject
        }

        guard let rois = obj["rois"] as? [String: Any] else {
            throw PoseSpecValidationError.missingRequiredKeys(["rois"])
        }

        let required: [String] = ["faceROI", "eyeROI", "bgROI"]
        let missing = required.filter { rois[$0] == nil }
        if !missing.isEmpty {
            throw PoseSpecValidationError.roisMissing(missing)
        }

        func requireObject(_ key: String) throws -> [String: Any] {
            guard let v = rois[key] else { throw PoseSpecValidationError.roisMissing([key]) }
            guard let d = v as? [String: Any] else {
                throw PoseSpecValidationError.wrongType(key: "rois.\(key)", expected: "Object")
            }
            return d
        }

        func requireString(_ dict: [String: Any], _ key: String, fullKey: String) throws -> String {
            guard let v = dict[key] else { throw PoseSpecValidationError.roisBadDefinition("missing \(fullKey)") }
            guard let s = v as? String else { throw PoseSpecValidationError.wrongType(key: fullKey, expected: "String") }
            return s
        }

        func requireBool(_ dict: [String: Any], _ key: String, fullKey: String) throws -> Bool {
            guard let v = dict[key] else { throw PoseSpecValidationError.roisBadDefinition("missing \(fullKey)") }
            guard let b = v as? Bool else { throw PoseSpecValidationError.wrongType(key: fullKey, expected: "Bool") }
            return b
        }

        func requireNumber01(_ dict: [String: Any], _ key: String, fullKey: String) throws -> Double {
            guard let v = dict[key] else { throw PoseSpecValidationError.roisBadDefinition("missing \(fullKey)") }
            guard let n = v as? NSNumber else { throw PoseSpecValidationError.wrongType(key: fullKey, expected: "Number") }
            let d = n.doubleValue
            guard d >= 0.0, d <= 1.0 else {
                throw PoseSpecValidationError.roisBadDefinition("\(fullKey) out of range [0,1]")
            }
            return d
        }

        // faceROI
        let face = try requireObject("faceROI")
        _ = try requireString(face, "from", fullKey: "rois.faceROI.from")
        if let pad = face["paddingPctOfBBox"] {
            guard let padObj = pad as? [String: Any] else {
                throw PoseSpecValidationError.wrongType(key: "rois.faceROI.paddingPctOfBBox", expected: "Object")
            }
            _ = try requireNumber01(padObj, "x", fullKey: "rois.faceROI.paddingPctOfBBox.x")
            _ = try requireNumber01(padObj, "y", fullKey: "rois.faceROI.paddingPctOfBBox.y")
        } else {
            throw PoseSpecValidationError.roisBadDefinition("missing rois.faceROI.paddingPctOfBBox")
        }
        _ = try requireBool(face, "clampToFrame", fullKey: "rois.faceROI.clampToFrame")

        // eyeROI
        let eye = try requireObject("eyeROI")
        guard let fromArr = eye["from"] as? [Any] else {
            throw PoseSpecValidationError.wrongType(key: "rois.eyeROI.from", expected: "Array")
        }
        guard fromArr.allSatisfy({ $0 is String }), fromArr.count >= 2 else {
            throw PoseSpecValidationError.roisBadDefinition("rois.eyeROI.from must be an array of >=2 strings")
        }
        _ = try requireString(eye, "center", fullKey: "rois.eyeROI.center")
        guard let sizeRule = eye["sizeRule"] as? [String: Any] else {
            throw PoseSpecValidationError.wrongType(key: "rois.eyeROI.sizeRule", expected: "Object")
        }
        _ = try requireString(sizeRule, "w", fullKey: "rois.eyeROI.sizeRule.w")
        _ = try requireString(sizeRule, "h", fullKey: "rois.eyeROI.sizeRule.h")
        _ = try requireBool(eye, "clampToFrame", fullKey: "rois.eyeROI.clampToFrame")
        _ = try requireString(eye, "requiresConfidence", fullKey: "rois.eyeROI.requiresConfidence")

        // bgROI
        let bg = try requireObject("bgROI")
        _ = try requireString(bg, "type", fullKey: "rois.bgROI.type")
        _ = try requireString(bg, "minus", fullKey: "rois.bgROI.minus")
    }
}
