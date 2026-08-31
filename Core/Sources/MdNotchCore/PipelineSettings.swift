import Foundation

/// User-facing settings the pipeline honors.
public struct PipelineSettings: Sendable, Equatable {
    public enum Destination: Sendable, Equatable {
        /// Write the `.md` next to its source file (default).
        case alongsideSource
        /// Write every `.md` into one fixed folder.
        case fixedFolder(URL)
    }

    public var destination: Destination

    public init(destination: Destination = .alongsideSource) {
        self.destination = destination
    }
}
