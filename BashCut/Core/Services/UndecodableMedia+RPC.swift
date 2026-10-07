import BashCutAutomation
import BashCutEngine
import BashCutProject

extension UndecodableMediaError: RPCFailureProviding {
    /// Media this Mac cannot decode (VP9 without the system decoder, for example): typed so an agent converts the
    /// file instead of reading a black frame as the picture.
    public var rpcFailure: RPCFailure {
        RPCFailure(-32602, localizedDescription, category: .unsupportedMedia, data: [
            "media": .array(media.map {
                .object([
                    "media": .string($0.mediaID), "path": .string($0.path), "codec": .string($0.codec),
                    "start": .integer($0.start), "end": .integer($0.end),
                ])
            }),
        ])
    }
}
