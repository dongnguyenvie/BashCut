import BashCutAutomation
import BashCutPlugins
import BashCutProject

extension CapabilityUnavailable: RPCFailureProviding {
    /// No provider can serve (P2-G5): category `capability_missing` with the reason and every provider's state, so an
    /// agent can tell "install one" from "turn it on" from "fix its dependency".
    public var rpcFailure: RPCFailure {
        RPCFailure(-32000, report.message, category: .capabilityMissing, data: [
            "capability": .string(report.capability), "reason": report.reason.map { .string($0.rawValue) } ?? .null,
            "providers": .array(report.providers.map(\.json)),
        ])
    }
}
