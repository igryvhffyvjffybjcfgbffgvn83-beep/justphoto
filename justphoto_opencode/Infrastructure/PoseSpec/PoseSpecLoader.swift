import Foundation

enum PoseSpecLoaderError: Error, LocalizedError {
    case missingResource
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "PoseSpec.json not found in app bundle"
        case .invalidJSON:
            return "PoseSpec.json is not valid / decodable"
        }
    }
}

struct PoseSpecHeader: Decodable, Sendable {
    let name: String?
    let schemaVersion: String?
    let generatedAt: String?
    let prdVersion: String
}

// M6.2: Loads PoseSpec.json from app bundle.
final class PoseSpecLoader {
    static let shared = PoseSpecLoader()
    private init() {}

    func loadHeader(bundle: Bundle = .main) throws -> PoseSpecHeader {
        let data = try loadData(bundle: bundle, applyDebugPatch: false)
        do {
            return try JSONDecoder().decode(PoseSpecHeader.self, from: data)
        } catch {
            throw PoseSpecLoaderError.invalidJSON
        }
    }

    func loadData(bundle: Bundle = .main, applyDebugPatch: Bool = true) throws -> Data {
        guard let url = bundle.url(forResource: "PoseSpec", withExtension: "json") else {
            throw PoseSpecLoaderError.missingResource
        }
        let raw = try Data(contentsOf: url)

#if DEBUG
        guard applyDebugPatch else {
            return raw
        }

        if PoseSpecDebugSettings.consumeUseMissingAliasOnce() {
            if var obj = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
               var binding = obj["binding"] as? [String: Any],
               var aliases = binding["aliases"] as? [String: Any]
            {
                aliases.removeValue(forKey: "lShoulder")
                binding["aliases"] = aliases
                obj["binding"] = binding
                if let broken = try? JSONSerialization.data(withJSONObject: obj) {
                    print("PoseSpecDebug: using missing alias once")
                    return broken
                }
            }
        }

        if PoseSpecDebugSettings.consumeUseWrongPrdVersionOnce() {
            if var obj = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] {
                obj["prdVersion"] = "v0.0.0"
                if let broken = try? JSONSerialization.data(withJSONObject: obj) {
                    print("PoseSpecDebug: using wrong prdVersion once")
                    return broken
                }
            }
        }

        if PoseSpecDebugSettings.consumeUseBrokenPoseSpecOnce() {
            // Deliberately break required fields for M6.3 validation verify.
            if var obj = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] {
                obj.removeValue(forKey: "binding")
                if let broken = try? JSONSerialization.data(withJSONObject: obj) {
                    print("PoseSpecDebug: using broken PoseSpec once")
                    return broken
                }
            }
        }
#endif

        return raw
    }
}
