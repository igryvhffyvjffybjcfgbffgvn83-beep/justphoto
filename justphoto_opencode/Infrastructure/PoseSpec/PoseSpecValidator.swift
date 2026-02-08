import Foundation

enum PoseSpecValidationError: Error, LocalizedError {
    case notJSONObject
    case missingRequiredKeys([String])
    case wrongType(key: String, expected: String)
    case prdVersionMismatch(expected: String, actual: String)

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
}
