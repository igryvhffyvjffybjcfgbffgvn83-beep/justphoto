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
        let data = try loadData(bundle: bundle)
        do {
            return try JSONDecoder().decode(PoseSpecHeader.self, from: data)
        } catch {
            throw PoseSpecLoaderError.invalidJSON
        }
    }

    func loadData(bundle: Bundle = .main) throws -> Data {
        guard let url = bundle.url(forResource: "PoseSpec", withExtension: "json") else {
            throw PoseSpecLoaderError.missingResource
        }
        return try Data(contentsOf: url)
    }
}
