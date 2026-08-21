import Foundation

public enum RemuxInputKind: Sendable, Equatable {
    case transportStream
    case fragmentedMP4Playlist
}

public enum RemuxCommand {
    public static func arguments(
        input: URL,
        output: URL,
        kind: RemuxInputKind
    ) -> [String] {
        var arguments = [
            "-y",
            "-hide_banner",
            "-loglevel", "error"
        ]
        if kind == .fragmentedMP4Playlist {
            arguments += ["-protocol_whitelist", "file,crypto,data"]
        }
        arguments += [
            "-i", input.path,
            "-map", "0",
            "-c", "copy",
            "-movflags", "+faststart",
            output.path
        ]
        return arguments
    }
}
