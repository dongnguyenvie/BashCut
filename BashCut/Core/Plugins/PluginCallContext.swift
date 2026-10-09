import BashCutPlugin
import BashCutProject
import Foundation

/// What the job around a plugin capability call wants from it (P2-G4), carried as a task-local so every capability
/// call inside the job sees it without each command passing it on:
/// - `usage` collects the providers called and what they reported using and charging,
/// - `requestID` goes to the provider as `requestId`, so a provider can refuse to charge twice for one request,
/// - `dryRun` freezes the request `CapabilityService.run` would send and throws `PluginDryRun` instead of sending it.
public struct PluginCallContext: Sendable {
    public var usage: PluginUsageRecorder?
    public var requestID: String?
    public var dryRun = false

    public init(usage: PluginUsageRecorder? = nil, requestID: String? = nil, dryRun: Bool = false) {
        self.usage = usage
        self.requestID = requestID
        self.dryRun = dryRun
    }

    @TaskLocal public static var current = PluginCallContext()
}

/// Thrown by `CapabilityService.run` in a dry run: the request as it would be sent and the provider's estimate.
public struct PluginDryRun: Error, Sendable {
    public let request: JSONValue
}

/// Usage reported by the plugin providers one job called. Core never prices anything: units and cost appear only
/// when a provider reports them in its result's `usage` (`{units: {name: number}, costUSD, charged}`), and a cost
/// counts only when the provider does not say `charged: false`.
public final class PluginUsageRecorder: @unchecked Sendable, Equatable {
    private let lock = NSLock()
    private var providers: [String] = []
    private var units: [String: Double] = [:]
    private var cost: Double?

    public init() {}

    public static func == (lhs: PluginUsageRecorder, rhs: PluginUsageRecorder) -> Bool { lhs === rhs }

    /// One provider call: `provider` is `plugin/provider`; `usage` is the result's `usage` field, if any.
    public func record(provider: String, usage: JSONValue?) {
        let fields = usage?.object ?? [:]
        lock.withLock {
            if !providers.contains(provider) { providers.append(provider) }
            for (name, value) in fields["units"]?.object ?? [:] {
                if let amount = Self.amount(value) { units[name, default: 0] += amount }
            }
            if fields["charged"]?.bool != false, let charge = fields["costUSD"].flatMap(Self.amount) {
                cost = (cost ?? 0) + charge
            }
        }
    }

    /// `{provider, units, costUSD, costSource}`: `provider` joins the providers called (nil when none was),
    /// `costSource` is `provider` when a provider reported a charge and nil otherwise.
    public var json: [String: JSONValue] {
        lock.withLock {
            [
                "provider": providers.isEmpty ? .null : .string(providers.joined(separator: ", ")),
                "units": units.isEmpty ? .null : .object(units.mapValues(JSONValue.number)),
                "costUSD": cost.map(JSONValue.number) ?? .null,
                "costSource": cost == nil ? .null : .string("provider"),
            ]
        }
    }

    /// A reported amount: a finite number from 0 up.
    static func amount(_ value: JSONValue) -> Double? {
        guard let number = value.double, number.isFinite, number >= 0 else { return nil }
        return number
    }
}
