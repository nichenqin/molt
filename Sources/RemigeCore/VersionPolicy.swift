import Foundation

/// How far a target version moves from the installed version.
public enum UpdateMagnitude: String, Codable, Hashable, Sendable, CaseIterable {
    /// The source does not expose comparable versions (for example `mas`).
    case unknown
    case patch
    case minor
    case major
}

/// Where `latestVersion` came from. Sparkle feeds can hide a newer release
/// that requires a newer macOS, so "latest" is not always absolute.
public enum LatestBasis: String, Codable, Hashable, Sendable {
    case source
    case osCompatible
}

/// Why `targetVersion` differs from `latestVersion`.
public enum TargetOrigin: String, Codable, Hashable, Sendable {
    case latest
    /// Newest version on the installed major line, chosen by the `hold` policy.
    case heldMajor
    /// Explicit version from `versionTargets`.
    case pinned
}

/// An argv-safe template for managers that accept `package@version`.
public struct VersionedInstall: Codable, Hashable, Sendable {
    public var executable: String
    public var argumentsPrefix: [String]
    public var package: String
    public var versionSeparator: String

    public init(
        executable: String,
        argumentsPrefix: [String],
        package: String,
        versionSeparator: String = "@"
    ) {
        self.executable = executable
        self.argumentsPrefix = argumentsPrefix
        self.package = package
        self.versionSeparator = versionSeparator
    }

    public func plan(for version: String) -> UpgradePlan {
        .command(
            executable,
            argumentsPrefix + ["\(package)\(versionSeparator)\(version)"]
        )
    }
}

extension OutdatedItem {
    /// Resolves the target version once, before the item is cached or shown.
    ///
    /// `hold` can only cap the target when the source can build a versioned
    /// install command. Homebrew, appcasts and release-page apps have no
    /// version history in their scan output, so they fall back to `prompt`:
    /// the major update stays visible but leaves the batch.
    public mutating func applyUpdatePolicy(
        config: RemigeConfig,
        candidates: [String] = [],
        latestBasis: LatestBasis = .source
    ) {
        self.latestBasis = latestBasis

        guard let current = Version(currentVersion), let latest = Version(latestVersion) else {
            targetVersion = latestVersion
            updateMagnitude = .unknown
            targetOrigin = .latest
            majorVersionAvailable = false
            isBatchEligible = !pinned
            return
        }

        let latestMagnitude = latest.updateMagnitude(from: current)
        majorVersionAvailable = latestMagnitude == .major

        if let raw = config.versionTargets[id],
            let target = Version(raw),
            versionedInstall != nil,
            target > current,
            target <= latest
        {
            assignTarget(target, current: current, origin: .pinned)
            isBatchEligible = !pinned
            return
        }

        switch config.updatePolicy.major {
        case .allow:
            assignTarget(latest, current: current, origin: .latest)
            isBatchEligible = !pinned
        case .prompt:
            assignTarget(latest, current: current, origin: .latest)
            isBatchEligible = !pinned && latestMagnitude != .major
        case .hold:
            if latestMagnitude == .major, versionedInstall != nil,
                let held = candidates.compactMap(Version.init)
                    .filter({ $0 > current && $0 <= latest && $0.isSameMajorLine(as: current) })
                    .max()
            {
                assignTarget(held, current: current, origin: .heldMajor)
                isBatchEligible = !pinned
            } else {
                assignTarget(latest, current: current, origin: .latest)
                isBatchEligible = !pinned && latestMagnitude != .major
            }
        }
    }

    /// Applies an explicit target. Returns false when the source cannot install
    /// a chosen version or the version is outside `(current, latest]`.
    @discardableResult
    public mutating func selectTarget(_ rawVersion: String) -> Bool {
        guard versionedInstall != nil,
            let current = Version(currentVersion),
            let latest = Version(latestVersion),
            let target = Version(rawVersion),
            target > current,
            target <= latest
        else { return false }

        majorVersionAvailable = latest.updateMagnitude(from: current) == .major
        assignTarget(target, current: current, origin: .pinned)
        isBatchEligible = !pinned
        return true
    }

    /// The item participates in "Update All" and in `remige upgrade --all`.
    public var isBatchable: Bool {
        isBatchEligible && upgrade.canRunAutomatically
    }

    private mutating func assignTarget(
        _ target: Version,
        current: Version,
        origin: TargetOrigin
    ) {
        targetVersion = target.raw
        updateMagnitude = target.updateMagnitude(from: current)
        targetOrigin = origin
        if let versionedInstall {
            upgrade = versionedInstall.plan(for: target.raw)
        }
    }
}
