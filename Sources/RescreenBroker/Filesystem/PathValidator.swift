import Foundation

/// Validates and canonicalizes filesystem paths, preventing path traversal attacks.
final class PathValidator {
    private let allowedPaths: [String]

    init(allowedPaths: [String] = []) {
        self.allowedPaths = allowedPaths.map { Self.canonicalize($0) }
    }

    /// Canonicalize a path: expand tilde, resolve symlinks, standardize.
    static func canonicalize(_ path: String) -> String {
        let expanded = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardized
        // Resolve symlinks to prevent symlink-based traversal
        let resolved = url.resolvingSymlinksInPath()
        return resolved.path
    }

    /// Check if a path is within one of the allowed paths.
    func isAllowed(_ path: String) -> Bool {
        if allowedPaths.isEmpty { return false }

        let canonical = Self.canonicalize(path)

        for allowed in allowedPaths {
            if canonical == allowed || canonical.hasPrefix(allowed + "/") {
                return true
            }
        }
        return false
    }

    /// Validate a path and return the canonical version, or nil if disallowed.
    func validate(_ path: String) -> String? {
        let canonical = Self.canonicalize(path)
        guard isAllowed(canonical) else { return nil }
        return canonical
    }

    /// Return a description of allowed paths for error messages.
    var allowedPathsDescription: String {
        if allowedPaths.isEmpty { return "(none)" }
        return allowedPaths.joined(separator: ", ")
    }
}
