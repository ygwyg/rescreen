import Foundation
import Yams

/// YAML profile document structure.
struct ProfileDocument: Codable {
    let name: String
    let description: String?
    let capabilities: [ProfileCapability]
}

struct ProfileCapability: Codable {
    let domain: String
    let target: ProfileTarget
    let constraints: [String: String]?
    let confirmation: String?       // defaults to "confirm"
    let scope: String?              // defaults to "session"
}

struct ProfileTarget: Codable {
    let app: String?
    let window: String?
    let paths: [String]?
    let urlFilter: [String]?
    let noDelete: Bool?
    let noBinary: Bool?
    let maxFileSize: String?

    enum CodingKeys: String, CodingKey {
        case app, window, paths
        case urlFilter = "url_filter"
        case noDelete = "no_delete"
        case noBinary = "no_binary"
        case maxFileSize = "max_file_size"
    }
}

/// Loads capability profiles from ~/.rescreen/profiles/*.yaml.
final class ProfileLoader {
    private let profileDir: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.profileDir = "\(home)/.rescreen/profiles"
    }

    /// Load a specific profile by name.
    func load(name: String) throws -> (profile: ProfileDocument, grants: [CapabilityGrant]) {
        let path = "\(profileDir)/\(name).yaml"
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let decoder = YAMLDecoder()
        let doc = try decoder.decode(ProfileDocument.self, from: content)
        let grants = toGrants(doc, profileName: name)
        return (doc, grants)
    }

    /// List available profile names.
    func availableProfiles() -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: profileDir) else {
            return []
        }
        return files
            .filter { $0.hasSuffix(".yaml") || $0.hasSuffix(".yml") }
            .map { String($0.dropLast($0.hasSuffix(".yaml") ? 5 : 4)) }
    }

    /// Ensure the profiles directory exists, creating it and an example profile if needed.
    func ensureProfileDir() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: profileDir) {
            try? fm.createDirectory(atPath: profileDir, withIntermediateDirectories: true)
            writeExampleProfile()
            Log.info("Created profiles directory: \(profileDir)")
        }
    }

    // MARK: - Internal

    private func toGrants(_ doc: ProfileDocument, profileName: String) -> [CapabilityGrant] {
        return doc.capabilities.enumerated().map { (index, cap) in
            let grantID = "cap_\(profileName)_\(index)"

            let target = CapabilityTarget(
                app: cap.target.app,
                window: cap.target.window ?? "*",
                paths: cap.target.paths?.map { expandTilde($0) },
                urlFilter: cap.target.urlFilter
            )

            // Build constraints dict from target-level constraints
            var constraints: [String: String]? = cap.constraints
            if let noDelete = cap.target.noDelete, noDelete {
                if constraints == nil { constraints = [:] }
                constraints?["no_delete"] = "true"
            }
            if let noBinary = cap.target.noBinary, noBinary {
                if constraints == nil { constraints = [:] }
                constraints?["no_binary"] = "true"
            }
            if let maxSize = cap.target.maxFileSize {
                if constraints == nil { constraints = [:] }
                constraints?["max_file_size"] = maxSize
            }

            let scope: GrantScope = {
                guard let s = cap.scope else { return .persistent }
                return GrantScope(rawValue: s) ?? .persistent
            }()

            let tier: ConfirmationTier = {
                guard let c = cap.confirmation else { return .confirm }
                return ConfirmationTier(rawValue: c) ?? .confirm
            }()

            return CapabilityGrant(
                id: grantID,
                domain: cap.domain,
                target: target,
                constraints: constraints,
                scope: scope,
                confirmation: tier
            )
        }
    }

    private func expandTilde(_ path: String) -> String {
        return NSString(string: path).expandingTildeInPath
    }

    private func writeExampleProfile() {
        let example = """
        # Rescreen Permission Profile
        # Place this file in ~/.rescreen/profiles/

        name: "Example Assistant"
        description: "Example profile — customize for your workflow"
        capabilities:
          - domain: perception.accessibility
            target: { app: "com.microsoft.VSCode" }
            confirmation: silent

          - domain: perception.screenshot
            target: { app: "com.microsoft.VSCode" }
            confirmation: silent

          - domain: action.input.*
            target: { app: "com.microsoft.VSCode" }
            confirmation: confirm

          - domain: fs.read
            target: { paths: ["~/Documents/**"] }
            confirmation: silent
        """

        let path = "\(profileDir)/example.yaml"
        try? example.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
