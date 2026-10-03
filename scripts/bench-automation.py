#!/usr/bin/env python3
"""Measure what an agent waits for: socket and MCP latency of common commands, and the time from an edit until
`ui frame` can show it. Run it against a running BashCut with a project open (a scratch or sample project:
--edits applies a small opacity change to the first main clip and undoes it).

    scripts/bench-automation.py [--mcp PATH_TO_bashcut-mcp] [--edits 5]

Python standard library only; reads the automation token file like the CLI.
"""
import argparse, json, os, socket, statistics, subprocess, time, uuid

SUPPORT = os.path.expanduser("~/Library/Application Support/BashCut")
SOCK = os.environ.get("BASHCUT_SOCKET", os.path.join(SUPPORT, "automation.sock"))


def token():
    return os.environ.get("BASHCUT_SESSION_TOKEN") or open(os.path.join(SUPPORT, "automation-token")).read().strip()


def rpc(method, params=None):
    start = time.perf_counter()
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(SOCK)
    s.sendall((json.dumps({"jsonrpc": "2.0", "id": str(uuid.uuid4()), "method": method,
                           "params": params or {}, "token": token()}) + "\n").encode())
    data = b""
    while not data.endswith(b"\n"):
        chunk = s.recv(1 << 20)
        if not chunk:
            break
        data += chunk
    s.close()
    response = json.loads(data)
    if "error" in response:
        raise SystemExit(f"{method}: {response['error']}")
    return (time.perf_counter() - start) * 1000, response["result"], len(data)


def report(label, samples, size=None):
    samples = sorted(samples)
    p95 = samples[max(0, int(len(samples) * 0.95) - 1)]
    extra = f"  {size / 1024:6.1f} KB" if size is not None else ""
    print(f"{label:40s} p50 {statistics.median(samples):7.2f} ms  p95 {p95:7.2f} ms{extra}")


def socket_bench():
    print("Socket (server + transport, no process start)")
    for method, params in [("context.get", None), ("timeline.get", {"format": "text"}), ("timeline.get", None),
                           ("project.get", None), ("review.run", None), ("ui.frame", None)]:
        runs = 10 if method == "ui.frame" else 40
        times, size = [], 0
        for _ in range(runs):
            elapsed, _, size = rpc(method, params)
            times.append(elapsed)
        report(f"  {method} {json.dumps(params) if params else ''}", times, size)


def mcp_bench(path):
    print(f"MCP ({path})")
    process = subprocess.Popen([path], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               text=True, bufsize=1)
    counter = 0

    def send(method, params=None, notify=False):
        nonlocal counter
        counter += 1
        message = {"jsonrpc": "2.0", "method": method, "params": params or {}}
        if not notify:
            message["id"] = counter
        start = time.perf_counter()
        process.stdin.write(json.dumps(message) + "\n")
        process.stdin.flush()
        if notify:
            return 0
        process.stdout.readline()
        return (time.perf_counter() - start) * 1000

    report("  start + initialize", [send("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                                         "clientInfo": {"name": "bench", "version": "1"}})])
    send("notifications/initialized", notify=True)
    report("  tools/list", [send("tools/list") for _ in range(10)])
    for tool, arguments in [("bashcut_context_get", {}), ("bashcut_timeline_get", {"format": "text"}),
                            ("bashcut_timeline_get", {}), ("bashcut_review_run", {})]:
        report(f"  {tool} {json.dumps(arguments) if arguments else ''}",
               [send("tools/call", {"name": tool, "arguments": arguments}) for _ in range(30)])
    process.terminate()


def edit_bench(count):
    print("Edit → frame (apply, then ui.frame waits for the rebuilt preview; each edit is undone)")
    _, timeline, _ = rpc("timeline.get")
    clip = next(item for track in timeline["tracks"] if track.get("role") == "main" for item in track["items"])
    applies, frames = [], []
    for _ in range(count):
        _, context, _ = rpc("context.get")
        start = time.perf_counter()
        elapsed, result, _ = rpc("timeline.apply", {"ops": [{"op": "setProperties", "item": clip["id"],
                                                                "patch": {"opacity": 0.9}}],
                                                       "baseRev": context["rev"], "label": "bench-automation"})
        rpc("ui.frame", {"frame": clip["at"]})
        frames.append((time.perf_counter() - start) * 1000)
        applies.append(elapsed)
        rpc("timeline.undo", {"baseRev": result["rev"] if isinstance(result, dict) and "rev" in result
                              else context["rev"] + 1})
        time.sleep(0.3)
    report("  timeline.apply (one setProperties)", applies)
    report("  apply → ui.frame ready", frames)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--mcp", default="/Applications/BashCut.app/Contents/MacOS/bashcut-mcp")
    parser.add_argument("--edits", type=int, default=0, help="also measure N edit → frame round trips")
    options = parser.parse_args()
    socket_bench()
    if os.path.exists(options.mcp):
        mcp_bench(options.mcp)
    if options.edits:
        edit_bench(options.edits)
