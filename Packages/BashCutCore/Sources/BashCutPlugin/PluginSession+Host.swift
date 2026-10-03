import BashCutProject
import Foundation

/// Host calls (plugin API 4): a `call` line from a request that has a `PluginHostChannel` runs on the app side,
/// and its result goes back as a `callResult` line.
extension PluginSession {
    /// Hands an `event` line to the request's host channel, in order.
    func receiveEvent(_ fields: [String: JSONValue]) {
        guard let id = fields["id"]?.string, let entry = pending[id], let host = entry.host,
            let event = fields["event"]
        else { return }
        pending[id]?.lastActivity = Date()
        host.event(event)
    }

    /// Runs a host call for a request that has a host channel, or answers that it cannot.
    func receiveCall(_ fields: [String: JSONValue]) {
        guard let callID = fields["callId"]?.string, !callID.isEmpty, callID.count <= 200 else { return }
        guard let id = fields["id"]?.string, let host = pending[id]?.host, let method = fields["method"]?.string else {
            answerCall(callID, .failure(PluginCallFailure(code: -32601, message: "This request cannot call BashCut")))
            return
        }
        let params = fields["params"] ?? .object([:])
        guard let size = try? JSONEncoder().encode(params).count, size <= 1024 * 1024 else {
            answerCall(callID, .failure(PluginCallFailure(code: -32602, message: "Call parameters are too large")))
            return
        }
        pending[id]?.activeCalls += 1
        pending[id]?.lastActivity = Date()
        Task { [weak self] in
            let result = await host.call(method, params)
            await self?.finishCall(request: id, callID: callID, result)
        }
    }

    private func finishCall(request id: String, callID: String, _ result: Result<JSONValue, PluginCallFailure>) {
        if pending[id] != nil {
            pending[id]?.activeCalls -= 1
            pending[id]?.lastActivity = Date()
        }
        answerCall(callID, result)
    }

    private func answerCall(_ callID: String, _ result: Result<JSONValue, PluginCallFailure>) {
        var message: [String: JSONValue] = ["type": .string("callResult"), "callId": .string(callID)]
        switch result {
        case .success(let value): message["result"] = value
        case .failure(let failure):
            message["error"] = .object(["code": .integer(failure.code), "message": .string(failure.message)])
        }
        guard let data = try? JSONEncoder().encode(JSONValue.object(message)), data.count <= 1024 * 1024 else {
            answerCall(callID, .failure(PluginCallFailure(code: -32603, message: "The result is larger than 1 MiB")))
            return
        }
        try? write(data)
    }
}
