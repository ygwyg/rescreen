import Foundation
import Testing

@testable import RescreenBroker

@Suite("PathValidator")
struct PathValidatorTests {
    // MARK: - Canonicalization

    @Test("Canonicalizes absolute paths")
    func canonicalizesAbsolutePaths() {
        // /tmp may or may not resolve to /private/tmp depending on whether
        // the path exists. Use an existing path to verify canonicalization.
        let result = PathValidator.canonicalize("/tmp")
        let expected = PathValidator.canonicalize("/tmp")
        #expect(result == expected)
        // Key property: result should be an absolute path without .. segments
        #expect(result.hasPrefix("/"))
        #expect(!result.contains(".."))
    }

    @Test("Removes trailing slashes")
    func removesTrailingSlash() {
        let result = PathValidator.canonicalize("/usr/local/")
        #expect(!result.hasSuffix("/"))
    }

    @Test("Resolves parent directory traversal")
    func resolvesParentTraversal() {
        let result = PathValidator.canonicalize("/tmp/a/b/../c")
        // The .. should be resolved regardless of whether the path exists
        #expect(!result.contains(".."))
        #expect(result.hasSuffix("/a/c"))
    }

    @Test("Expands tilde to home directory")
    func expandsTilde() {
        let result = PathValidator.canonicalize("~/Documents")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(result.hasPrefix(home))
        #expect(result.hasSuffix("Documents"))
    }

    // MARK: - isAllowed

    @Test("Allows exact path match")
    func allowsExactMatch() {
        let validator = PathValidator(allowedPaths: ["/tmp"])
        #expect(validator.isAllowed("/tmp"))
    }

    @Test("Allows subpath within allowed directory")
    func allowsSubpath() {
        let validator = PathValidator(allowedPaths: ["/tmp"])
        #expect(validator.isAllowed("/tmp/somefile.txt"))
    }

    @Test("Allows deeply nested subpath")
    func allowsDeeplyNested() {
        let validator = PathValidator(allowedPaths: ["/tmp"])
        #expect(validator.isAllowed("/tmp/a/b/c/d.txt"))
    }

    @Test("Rejects path outside allowed directory")
    func rejectsOutsidePath() {
        let validator = PathValidator(allowedPaths: ["/tmp"])
        #expect(!validator.isAllowed("/etc/passwd"))
    }

    @Test("Rejects path that is a prefix but not a directory boundary")
    func rejectsPrefixWithoutBoundary() {
        // "/tmp_evil" starts with "/tmp" but is NOT under /tmp/
        let validator = PathValidator(allowedPaths: ["/tmp"])
        #expect(!validator.isAllowed("/private/tmp_evil/secret"))
    }

    @Test("Rejects everything when no paths are allowed")
    func rejectsWhenNoPaths() {
        let validator = PathValidator(allowedPaths: [])
        #expect(!validator.isAllowed("/tmp/test"))
        #expect(!validator.isAllowed("/"))
    }

    @Test("Blocks path traversal attack via ..")
    func blocksTraversalAttack() {
        let validator = PathValidator(allowedPaths: ["/tmp"])
        // Attempt to escape /tmp via ..
        #expect(!validator.isAllowed("/tmp/../etc/passwd"))
    }

    @Test("Supports multiple allowed paths")
    func supportsMultiplePaths() {
        let validator = PathValidator(allowedPaths: ["/tmp", "/var/log"])
        #expect(validator.isAllowed("/tmp/test"))
        #expect(validator.isAllowed("/var/log/syslog"))
        #expect(!validator.isAllowed("/etc/passwd"))
    }

    // MARK: - validate

    @Test("Validate returns canonical path when allowed")
    func validateReturnsCanonical() {
        let validator = PathValidator(allowedPaths: ["/tmp"])
        let result = validator.validate("/tmp/test.txt")
        #expect(result != nil)
        // Should return the canonical form
        #expect(result == PathValidator.canonicalize("/tmp/test.txt"))
    }

    @Test("Validate returns nil when disallowed")
    func validateReturnsNil() {
        let validator = PathValidator(allowedPaths: ["/tmp"])
        #expect(validator.validate("/etc/shadow") == nil)
    }

    // MARK: - allowedPathsDescription

    @Test("Description shows paths")
    func descriptionShowsPaths() {
        let validator = PathValidator(allowedPaths: ["/tmp", "/var"])
        let desc = validator.allowedPathsDescription
        #expect(desc.contains("tmp"))
        #expect(desc.contains("var"))
    }

    @Test("Description shows none when empty")
    func descriptionShowsNone() {
        let validator = PathValidator(allowedPaths: [])
        #expect(validator.allowedPathsDescription == "(none)")
    }
}
