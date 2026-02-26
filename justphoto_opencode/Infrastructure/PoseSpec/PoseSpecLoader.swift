import Foundation

enum PoseSpecLoaderError: Error, LocalizedError {
    case missingResource
    case invalidJSON
    case invalidConfidenceRange

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "PoseSpec.json not found in app bundle"
        case .invalidJSON:
            return "PoseSpec.json is not valid / decodable"
        case .invalidConfidenceRange:
            return "PoseSpec confidence values must be finite and in [0,1]"
        }
    }
}

struct PoseSpecHeader: Sendable {
    let name: String
    let schemaVersion: String
    let generatedAt: String
    let prdVersion: String
}

// M6.2: Loads PoseSpec.json from app bundle.
final class PoseSpecLoader {
    static let shared = PoseSpecLoader()
    private init() {}

    func loadPoseSpec(bundle: Bundle = .main, applyDebugPatch: Bool = true) throws -> PoseSpec {
        let data = try loadData(bundle: bundle, applyDebugPatch: applyDebugPatch)
        do {
            let spec = try JSONDecoder().decode(PoseSpec.self, from: data)
            try validateConfidence(spec: spec)
            JPDebugPrint("PoseSpecLoadedFromBundle | Version: \(spec.prdVersion) | Latest Log: \(spec.changeLog.last?.notes?.last ?? spec.changeLog.last?.changes?.last ?? spec.changeLog.last?.items?.last ?? spec.changeLog.last?.scope ?? spec.changeLog.last?.version ?? "n/a")")
            return spec
        } catch {
            if let error = error as? PoseSpecLoaderError {
                throw error
            }
            throw PoseSpecLoaderError.invalidJSON
        }
    }

    func loadHeader(bundle: Bundle = .main) throws -> PoseSpecHeader {
        let spec = try loadPoseSpec(bundle: bundle, applyDebugPatch: false)
        return PoseSpecHeader(
            name: spec.name,
            schemaVersion: spec.schemaVersion,
            generatedAt: spec.generatedAt,
            prdVersion: spec.prdVersion
        )
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

        if let patched = debugPatchedPoseSpecData(raw: raw) {
            return patched
        }
#endif

        return raw
    }

    private func validateConfidence(spec: PoseSpec) throws {
        let minConfidence = spec.defaults.confidence.minConfidence
        let minLandmarkConfidence = spec.defaults.confidence.minLandmarkConfidence
        guard minConfidence.isFinite,
              minLandmarkConfidence.isFinite,
              minConfidence >= 0.0,
              minConfidence <= 1.0,
              minLandmarkConfidence >= 0.0,
              minLandmarkConfidence <= 1.0 else {
            throw PoseSpecLoaderError.invalidConfidenceRange
        }
    }

#if DEBUG
    private func debugPatchedPoseSpecData(raw: Data) -> Data? {
        let anyPatch =
            PoseSpecDebugSettings.debugIsMissingEyeROIArmed() ||
            PoseSpecDebugSettings.debugIsMissingAliasArmed() ||
            PoseSpecDebugSettings.debugIsWrongPrdArmed() ||
            PoseSpecDebugSettings.debugIsBrokenPoseSpecArmed()

        guard anyPatch else { return nil }

        guard var root = (try? JSONDecoder().decode([String: JSONValue].self, from: raw)) else {
            return nil
        }

        if PoseSpecDebugSettings.consumeUseMissingEyeROIOnce() {
            if case .object(var rois) = root["rois"] {
                rois.removeValue(forKey: "eyeROI")
                root["rois"] = .object(rois)
                print("PoseSpecDebug: using missing eyeROI once")
            }
        }

        if PoseSpecDebugSettings.consumeUseMissingAliasOnce() {
            if case .object(var binding) = root["binding"],
               case .object(var aliases) = binding["aliases"]
            {
                aliases.removeValue(forKey: "lShoulder")
                binding["aliases"] = .object(aliases)
                root["binding"] = .object(binding)
                print("PoseSpecDebug: using missing alias once")
            }
        }

        if PoseSpecDebugSettings.consumeUseWrongPrdVersionOnce() {
            root["prdVersion"] = .string("v0.0.0")
            print("PoseSpecDebug: using wrong prdVersion once")
        }

        if PoseSpecDebugSettings.consumeUseBrokenPoseSpecOnce() {
            // Deliberately break required fields for M6.3 validation verify.
            root.removeValue(forKey: "binding")
            print("PoseSpecDebug: using broken PoseSpec once")
        }

        let encoder = JSONEncoder()
        if #available(iOS 11.0, *) {
            encoder.outputFormatting = [.sortedKeys]
        }
        return try? encoder.encode(root)
    }
#endif
}
