#!/usr/bin/env python3
"""A/B bench: the same short editing brief run by the Claude Code agent and the Codex agent, launched as BashCut does.

  scripts/bench-agents.py fixture                 build the fixed bench project once (.local/bench/ab/fixture)
  scripts/bench-agents.py run claude|codex [--cap MIN] [--brief FILE] [--keep-config]
  scripts/bench-agents.py table RUN_DIR...        re-parse runs; prints the side-by-side table, writes ab-table.json

A manual bench, never run by tests: it starts real agent CLIs and spends tokens. Needs the bench dev app
(`.local/scripts/dev-copy.sh bench` → build/bench, bench.sock) and the licensed test clips in Fixtures/media/real
(`.local/scripts/real-footage/fetch.sh`); projects, runs and the bench token stay under .local, never committed.

How a run starts the agent the way the app does: the bench dev app (build/bench, bench.sock; see dev-copy.sh) opens a
copy of the fixture, `bashcut agent open <agent> --new` makes the app launch its own terminal agent (fresh token for
that author, CommandCatalog.instructions + project context + knowledge as the prompt, MCP config, kit, env
allowlist). The script reads that process's exact argv, env and cwd (sysctl KERN_PROCARGS2), stops it, and runs the
same command line headless with the brief: claude gains `-p … --output-format stream-json --verbose`, codex runs
`exec --json --skip-git-repo-check` with the same `-c` options. The tab and its token stay open in the app.

Stops at: the agent ending its turn, a checkpoint awaiting the user, a question to the user (AskUserQuestion,
agent ask), or the time cap. Then `review run --summary` on the copy. Everything lands in .local/bench/ab/<stamp>-<agent>.
"""
import collections, ctypes, json, os, re, shutil, signal, subprocess, sys, threading, time
from datetime import datetime, timezone

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SUPPORT = os.path.expanduser("~/Library/Application Support/BashCut")
APP = os.path.join(REPO, "build/bench/BashCut.app")
CLI = os.path.join(APP, "Contents/MacOS/bashcut")
SOCKET = os.path.join(SUPPORT, "bench.sock")
BENCH = os.path.join(REPO, ".local/bench/ab")
FIXTURE = os.path.join(BENCH, "fixture")
REAL = os.path.join(REPO, "Fixtures/media/real")   # licensed test clips from .local/scripts/real-footage/fetch.sh
KEEP_CONFIG = "--keep-config" in sys.argv
FIXTURE_CLIPS = ["vi-talking-head.mp4", "nhatrang-market-run.mp4", "gopro-ridges-music.mp4"]
DEFAULT_BRIEF = ("Dựng một video dọc 20–25 giây từ footage trong project: mở bằng câu nói hay nhất trong "
                 "vi-talking-head, chèn B-roll cảnh chợ và cảnh núi, có phụ đề. Tự quyết các lựa chọn, không cần "
                 "hỏi lại. Không xuất video; xong thì chạy review run và dừng.")


# ---------------------------------------------------------------- app plumbing

def bench_token():
    return open(os.path.join(REPO, ".local/bench/token-bench.txt")).read().strip()


def cli(*args, token=None, check=False, timeout=300):
    env = dict(os.environ, BASHCUT_SOCKET=SOCKET, BASHCUT_SESSION_TOKEN=token or bench_token())
    p = subprocess.run([CLI, *args], env=env, capture_output=True, text=True, timeout=timeout)
    if check and p.returncode not in (0,):
        raise SystemExit(f"bashcut {' '.join(args)} failed: {p.stdout}{p.stderr}")
    try:
        return json.loads(p.stdout)
    except ValueError:
        return {"raw": p.stdout.strip(), "stderr": p.stderr.strip(), "exit": p.returncode}


def ensure_app():
    """Starts the bench app on bench.sock. Every app copy writes the one external-agent token file, so the bench
    app's token goes to token-bench.txt and the running dev app's file is put back."""
    if app_running() and "error" not in cli("app", "version"):
        return
    token_file = os.path.join(SUPPORT, "automation-token")
    saved = open(token_file).read() if os.path.exists(token_file) else None
    # A clean environment, as from the Finder: `open` passes the caller's variables on, and the app's allowlist
    # (CLAUDE_*, CODEX_*) would hand a calling Claude session's host variables to the bench agents.
    clean = {k: os.environ[k] for k in ("HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG") if k in os.environ}
    clean["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
    subprocess.run(["open", "-n", "--env", f"BASHCUT_SOCKET={SOCKET}", APP], check=True, env=clean)
    for _ in range(90):
        time.sleep(1)
        now = open(token_file).read() if os.path.exists(token_file) else None
        if now and now != saved:
            fd = os.open(os.path.join(REPO, ".local/bench/token-bench.txt"), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            os.write(fd, now.encode()); os.close(fd)
            if saved:
                fd = os.open(token_file, os.O_WRONLY | os.O_TRUNC); os.write(fd, saved.encode()); os.close(fd)
            if "error" not in cli("app", "version"):
                return
    raise SystemExit("bench app did not answer on bench.sock (is external agent access on in its Settings?)")


def app_running():
    return subprocess.run(["pgrep", "-f", os.path.join(APP, "Contents/MacOS/BashCutApp")], capture_output=True).returncode == 0


def procargs(pid):
    """argv and env of a process of this user (KERN_PROCARGS2)."""
    libc = ctypes.CDLL("libc.dylib", use_errno=True)
    mib = (ctypes.c_int * 3)(1, 49, pid)
    size = ctypes.c_size_t(0)
    libc.sysctl(mib, 3, None, ctypes.byref(size), None, 0)
    buf = ctypes.create_string_buffer(size.value)
    if libc.sysctl(mib, 3, buf, ctypes.byref(size), None, 0) != 0:
        raise OSError(ctypes.get_errno(), "sysctl KERN_PROCARGS2")
    raw = buf.raw[:size.value]
    argc = int.from_bytes(raw[:4], "little")
    rest = raw[4:]
    exe, _, rest = rest.partition(b"\0")
    rest = rest.lstrip(b"\0")
    parts = rest.split(b"\0")
    argv = [x.decode() for x in parts[:argc]]
    env = {}
    for x in parts[argc:]:
        if not x:
            break
        k, _, v = x.decode(errors="replace").partition("=")
        env[k] = v
    return exe.decode(), argv, env


def proc_cwd(pid):
    out = subprocess.run(["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"], capture_output=True, text=True).stdout
    return next((l[1:] for l in out.splitlines() if l.startswith("n")), None)


def descendants(root):
    rows = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,comm="], capture_output=True, text=True).stdout.splitlines()
    kids = collections.defaultdict(list)
    comm = {}
    for r in rows:
        pid, ppid, c = r.split(None, 2)
        kids[int(ppid)].append(int(pid))
        comm[int(pid)] = c
    out, todo = [], [root]
    while todo:
        p = todo.pop()
        for k in kids[p]:
            out.append((k, comm[k]))
            todo.append(k)
    return out


def app_pid():
    out = subprocess.run(["pgrep", "-f", os.path.join(APP, "Contents/MacOS/BashCutApp")], capture_output=True, text=True)
    pids = [int(x) for x in out.stdout.split()]
    if not pids:
        raise SystemExit("bench app is not running")
    return pids[0]


def capture_launch(agent):
    """Has the app launch its terminal agent, returns its {exe, argv, env, cwd} and stops the interactive process."""
    root = app_pid()
    before = {p for p, _ in descendants(root)}
    r = cli("agent", "open", agent, "--new")
    if "error" in r:
        raise SystemExit(f"agent open {agent}: {r}")
    name = "claude" if agent == "claude" else "codex"
    for _ in range(40):
        time.sleep(0.5)
        new = [p for p, c in descendants(root) if p not in before and os.path.basename(c) == name]
        if new:
            pid = min(new)
            exe, argv, env = procargs(pid)
            cwd = proc_cwd(pid)
            os.kill(pid, signal.SIGTERM)
            return {"pid": pid, "exe": exe, "argv": argv, "env": env, "cwd": cwd}
    raise SystemExit(f"no {name} process appeared under the bench app")


# ---------------------------------------------------------------- fixture

def make_fixture():
    ensure_app()
    if os.path.exists(FIXTURE):
        raise SystemExit(f"{FIXTURE} exists; remove it to rebuild")
    # The clips live in the project's own footage folder (a folder without a project becomes the project), so a
    # copy of the fixture is self-contained.
    footage = os.path.join(FIXTURE, "footage")
    os.makedirs(footage)
    for c in FIXTURE_CLIPS:
        shutil.copy2(os.path.join(REAL, c), footage)
    r = cli("project", "create", "--name", "fixture", "--dir", BENCH, "--footage", footage, "--canvas", "portrait",
            "--language", "vi", "--import", "--discard-current", check=True)
    print(json.dumps(r, ensure_ascii=False)[:600])
    for job in (r.get("jobs") or {}).values():
        if isinstance(job, str):
            for _ in range(30):
                st = cli("jobs", "wait", job, timeout=200)
                if (st.get("job") or {}).get("finishedAt"):
                    break
            print("job", job, json.dumps(st.get("job", st), ensure_ascii=False)[:300])
    print(cli("project", "save"))
    print("fixture:", FIXTURE)


# ---------------------------------------------------------------- run

def asks_user(line):
    """A tool call that puts a question to the user: AskUserQuestion, agent ask (MCP or CLI)."""
    try:
        d = json.loads(line)
    except ValueError:
        return False
    names = []
    if d.get("type") == "assistant":
        for c in d["message"].get("content", []):
            if c.get("type") == "tool_use":
                names.append(c["name"])
                if c["name"] == "Bash":
                    names += ["cli:" + k for k in cli_commands(c["input"].get("command", ""))]
    elif d.get("type") in ("item.started", "item.completed"):
        it = d.get("item", {})
        if it.get("type") == "mcp_tool_call":
            names.append(it.get("tool", ""))
        if it.get("type") == "command_execution":
            names += ["cli:" + k for k in cli_commands(it.get("command", ""))]
    return any(n == "AskUserQuestion" or n.endswith("bashcut_agent_ask") or n == "cli:agent ask" for n in names)


def stop_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(10)
    except Exception:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except Exception:
            pass


def run(agent, cap_min, brief):
    ensure_app()
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    out = os.path.join(BENCH, f"{stamp}-{agent}")
    os.makedirs(out)
    project = os.path.join(out, "project")
    shutil.copytree(FIXTURE, project)
    for name in os.listdir(project):          # the copy keeps the fixture's name; renaming is not needed to open it
        pass
    r = cli("project", "open", project, "--discard-current")
    if "error" in r:
        raise SystemExit(f"project open: {r}")
    launch = capture_launch(agent)
    token = launch["env"].get("BASHCUT_SESSION_TOKEN", "")
    saved = dict(launch, env={k: ("<token>" if k == "BASHCUT_SESSION_TOKEN" else v) for k, v in launch["env"].items()})
    json.dump(saved, open(os.path.join(out, "launch.json"), "w"), indent=1, ensure_ascii=False)
    open(os.path.join(out, "brief.txt"), "w").write(brief)

    argv = launch["argv"]
    if agent == "claude":
        cmd = [launch["exe"]] + argv[1:] + ["-p", brief, "--output-format", "stream-json", "--verbose"]
    else:
        # In the app's TUI Codex asks before each MCP call (the user picks approve or approve for the session);
        # exec's policy is never, which fails them. Approve bashcut's tools, as a user approving for the session.
        cmd = [launch["exe"]] + argv[1:] + ["-c", 'mcp_servers.bashcut.default_tools_approval_mode="approve"',
                                            "exec", "--json", "--skip-git-repo-check", brief]
    env = dict(launch["env"])
    env["CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS"] = "0"   # print mode waits for background sub-agents, as a tab would
    overrides = ["codex: bashcut MCP tools pre-approved (the TUI asks per call)"] if agent == "codex" else []
    # Claude keys its login by config folder; the folder chosen in BashCut Settings may hold an expired login. Use
    # the default folder (its plugins and kit are the same) unless --keep-config.
    if agent == "claude" and "CLAUDE_CONFIG_DIR" in env and not KEEP_CONFIG:
        overrides.append(f"dropped CLAUDE_CONFIG_DIR={env.pop('CLAUDE_CONFIG_DIR')}")
    started = time.time()
    stream = open(os.path.join(out, "stream.jsonl"), "w")
    times = open(os.path.join(out, "stream.times"), "w")
    proc = subprocess.Popen(cmd, cwd=launch["cwd"], env=env, stdout=subprocess.PIPE, stdin=subprocess.DEVNULL,
                            stderr=open(os.path.join(out, "stderr.log"), "w"), text=True, start_new_session=True)
    flags = {"ask": False}

    def reader():
        for line in proc.stdout:
            stream.write(line)
            times.write(f"{time.time() - started:.2f}\n")
            stream.flush(); times.flush()
            if asks_user(line):
                flags["ask"] = True

    th = threading.Thread(target=reader, daemon=True)
    th.start()
    stop, last_poll = None, 0.0
    while stop is None:
        time.sleep(1)
        now = time.time()
        if proc.poll() is not None:
            stop = "turn_ended"
        elif flags["ask"]:
            stop = "question_to_user"
        elif now - started > cap_min * 60:
            stop = "time_cap"
        elif now - last_poll > 10:
            last_poll = now
            st = cli("checkpoint", "status", token=token, timeout=30)
            if isinstance(st, dict) and st.get("status") == "awaiting_user":
                stop = "checkpoint_awaiting_user"
                json.dump(st, open(os.path.join(out, "checkpoint.json"), "w"), indent=1, ensure_ascii=False)
    if proc.poll() is None:
        time.sleep(3)   # let the last events flush
        stop_group(proc)
    th.join(10)
    stream.close(); times.close()
    wall = time.time() - started
    review = cli("review", "run", "--summary", token=token, timeout=200)
    json.dump(review, open(os.path.join(out, "review.json"), "w"), indent=1, ensure_ascii=False)
    meta = {"agent": agent, "stamp": stamp, "stop": stop, "wall_s": round(wall, 1), "cap_min": cap_min,
            "exit": proc.returncode, "cwd": launch["cwd"], "overrides": overrides, "commit": subprocess.run(
                ["git", "-C", REPO, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()}
    json.dump(meta, open(os.path.join(out, "meta.json"), "w"), indent=1)
    print(json.dumps(summarize(out), indent=1, ensure_ascii=False)[:3000])
    return out


# ---------------------------------------------------------------- parsing

def bashcut_name(tool):
    """mcp__bashcut__bashcut_context_get / mcp__plugin_bc_bashcut__bashcut_context_get / bashcut_context_get → context get."""
    t = tool.split("__")[-1]
    if not t.startswith("bashcut_"):
        return None
    group, _, cmd = t[len("bashcut_"):].partition("_")
    return f"{group} {cmd}".strip()


def cli_commands(command):
    """`bashcut X Y` invocations inside a shell command."""
    out = []
    for m in re.finditer(r"(?:^|[\s;&|(`'\"/])bashcut\s+([a-z][\w-]*)(?:\s+([a-z][\w-]*))?", command):
        out.append(f"{m.group(1)} {m.group(2) or ''}".strip())
    return out


def human_question(text):
    t = (text or "").strip()
    return bool(t) and (t.endswith("?") or re.search(r"(bạn (có )?muốn|should I|do you want|which (one|option))", t, re.I))


def parse_claude(out):
    lines = open(os.path.join(out, "stream.jsonl")).read().splitlines()
    tpath = os.path.join(out, "stream.times")
    ts = [float(x) for x in open(tpath).read().split()] if os.path.exists(tpath) else [0.0] * len(lines)
    seen, main, subs, results, agents = set(), [], collections.defaultdict(list), [], {}
    tools, bc, wakes, last_text, ask = collections.Counter(), collections.Counter(), 0, "", False
    result_chars = collections.Counter()
    tool_label = {}
    for i, line in enumerate(lines):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        t = d.get("type")
        if t == "result":
            results.append(d)
            continue
        if t == "user":
            c = d.get("message", {}).get("content")
            if isinstance(c, str) or (isinstance(c, list) and not any(x.get("type") == "tool_result" for x in c)):
                if d.get("parent_tool_use_id") is None and results:
                    wakes += 1    # a new main turn not caused by a tool result: background task notification
            for x in c if isinstance(c, list) else []:
                if x.get("type") == "tool_result":
                    body = x.get("content")
                    size = len(body) if isinstance(body, str) else sum(len(y.get("text", "")) for y in body or [] if y.get("type") == "text")
                    result_chars[tool_label.get(x["tool_use_id"], "?")] += size
            continue
        if t != "assistant":
            continue
        m, owner = d["message"], d.get("parent_tool_use_id")
        for c in m["content"]:
            if c["type"] == "tool_use":
                name = c["name"]
                if name in ("Agent", "Task"):
                    agents[c["id"]] = c["input"].get("subagent_type", "?")
                if name == "AskUserQuestion":
                    ask = True
                label = name
                b = bashcut_name(name) if name.startswith("mcp__") else None
                if b:
                    bc["mcp:" + b] += 1
                    label = "mcp " + b
                    if b == "agent ask":
                        ask = True
                if name == "Bash":
                    cmds = cli_commands(c["input"].get("command", ""))
                    for k in cmds:
                        bc["cli:" + k] += 1
                        ask = ask or k == "agent ask"
                    label = "Bash " + (cmds[0] if cmds else c["input"].get("command", "").split()[0] if c["input"].get("command") else "")
                tools[name if not name.startswith("mcp__") else "mcp:" + (b or name)] += 1
                tool_label[c["id"]] = label
            if c["type"] == "text" and owner is None:
                last_text = c["text"]
        if m["id"] in seen:
            continue
        seen.add(m["id"])
        u = m["usage"]
        ctx = u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
        (main if owner is None else subs[owner]).append((ts[i] if i < len(ts) else 0, ctx, u.get("output_tokens", 0)))
    total, per_model, cost = 0, {}, None
    if results:
        last = results[-1]
        for k, v in last.get("modelUsage", {}).items():
            per_model[k] = v["inputTokens"] + v["cacheReadInputTokens"] + v["cacheCreationInputTokens"] + v["outputTokens"]
        total, cost = sum(per_model.values()), last.get("total_cost_usd")
    else:   # killed before a result record: sum per-message usage
        total = sum(c + o for _, c, o in main) + sum(c + o for v in subs.values() for _, c, o in v)
    sub_tokens = collections.Counter()
    for k, v in subs.items():
        sub_tokens[agents.get(k, "?")] += sum(c + o for _, c, o in v)
    return {
        "total_tokens": total, "per_model": per_model, "cost_usd": cost,
        "main_requests": len(main), "main_tokens": sum(c + o for _, c, o in main),
        "sub_agent_tokens": dict(sub_tokens),
        "context_first": main[0][1] if main else 0, "context_last": main[-1][1] if main else 0,
        "context_max": max((c for _, c, _ in main), default=0),
        "context_over_time": [[round(t), c] for t, c, _ in main],
        "tools": dict(tools.most_common()), "bashcut": dict(bc.most_common()),
        "result_chars_by_call": dict(result_chars.most_common(15)),
        "idle_wakeups": max(len(results) - 1, wakes), "result_legs": len(results),
        "asked_user": ask, "last_message": last_text[-600:],
    }


def codex_rollout(thread_id):
    root = os.path.expanduser("~/.codex/sessions")
    for dirpath, _, files in os.walk(root):
        for f in files:
            if thread_id and thread_id in f:
                return os.path.join(dirpath, f)
    return None


def parse_codex(out):
    lines = open(os.path.join(out, "stream.jsonl")).read().splitlines()
    tools, bc, thread, usage, last_text, ask = collections.Counter(), collections.Counter(), None, {}, "", False
    result_chars, turns = collections.Counter(), 0
    for line in lines:
        try:
            d = json.loads(line)
        except ValueError:
            continue
        t = d.get("type")
        if t == "thread.started":
            thread = d.get("thread_id")
        if t == "turn.started":
            turns += 1
        if t == "turn.completed":
            usage = d.get("usage", {})
        if t != "item.completed":
            continue
        it = d.get("item", {})
        k = it.get("type")
        if k == "mcp_tool_call":
            b = bashcut_name(it.get("tool", "")) or it.get("tool")
            tools["mcp:" + b] += 1
            bc["mcp:" + b] += 1
            ask = ask or b == "agent ask"
            res = it.get("result") or {}
            result_chars["mcp " + b] += len(json.dumps(res, ensure_ascii=False)) if res else 0
        elif k == "command_execution":
            cmd = it.get("command", "")
            cmds = cli_commands(cmd)
            tools["shell"] += 1
            for c in cmds:
                bc["cli:" + c] += 1
                ask = ask or c == "agent ask"
            result_chars["shell " + (cmds[0] if cmds else cmd.split()[-1][:30] if cmd.split() else "")] += len(it.get("aggregated_output", ""))
        elif k == "agent_message":
            last_text = it.get("text", "")
        elif k:
            tools[k] += 1
    ctx, total, first_ts = [], None, None
    rp = codex_rollout(thread)
    if rp:
        for line in open(rp):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            ts = d.get("timestamp")
            when = datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp() if ts else None
            first_ts = first_ts or when
            p = d.get("payload", {})
            if d.get("type") == "event_msg" and p.get("type") == "token_count" and p.get("info"):
                last = p["info"].get("last_token_usage", {})
                ctx.append((round(when - first_ts) if when else 0, last.get("input_tokens", 0), last.get("output_tokens", 0)))
                total = p["info"].get("total_token_usage", {})
    tot = (total or {}).get("total_tokens") or (usage.get("input_tokens", 0) + usage.get("output_tokens", 0))
    return {
        "total_tokens": tot, "usage": total or usage, "cost_usd": None, "rollout": rp,
        "main_requests": len(ctx), "main_tokens": tot, "sub_agent_tokens": {},
        "context_first": ctx[0][1] if ctx else 0, "context_last": ctx[-1][1] if ctx else 0,
        "context_max": max((c for _, c, _ in ctx), default=0),
        "context_over_time": [[t, c] for t, c, _ in ctx],
        "tools": dict(tools.most_common()), "bashcut": dict(bc.most_common()),
        "result_chars_by_call": dict(result_chars.most_common(15)),
        "idle_wakeups": max(turns - 1, 0), "result_legs": turns,
        "asked_user": ask, "last_message": last_text[-600:],
    }


def summarize(out):
    meta = json.load(open(os.path.join(out, "meta.json")))
    s = parse_claude(out) if meta["agent"] == "claude" else parse_codex(out)
    bc = s["bashcut"]
    s["tool_calls"] = sum(s["tools"].values())
    s["context_get"] = bc.get("mcp:context get", 0) + bc.get("cli:context get", 0)
    try:
        rv = json.load(open(os.path.join(out, "review.json")))
    except (OSError, ValueError):
        rv = {}
    issues = rv.get("issues") or []
    s["review"] = {"status": (rv.get("summary") or {}).get("status"), "count": len(issues),
                   "by_severity": dict(collections.Counter(i.get("severity") for i in issues)),
                   "issues": [f"{i.get('severity')}: {i.get('kind')} — {i.get('title')}" for i in issues][:20],
                   "error": rv.get("error")}
    cp = os.path.join(out, "checkpoint.json")
    s["human_answer_needed"] = bool(s["asked_user"] or meta["stop"] in ("checkpoint_awaiting_user", "question_to_user")
                                    or os.path.exists(cp) or human_question(s["last_message"]))
    s.update(meta)
    s["run_dir"] = os.path.relpath(out, REPO)
    return s


ROWS = [("wall time (s)", "wall_s"), ("stop reason", "stop"), ("total tokens", "total_tokens"),
        ("cost (USD)", "cost_usd"), ("model requests (main)", "main_requests"), ("context first", "context_first"),
        ("context last", "context_last"), ("context max", "context_max"), ("tool calls", "tool_calls"),
        ("context get", "context_get"), ("idle wake-ups", "idle_wakeups"), ("asked user", "asked_user"),
        ("human answer needed", "human_answer_needed")]


def table(dirs):
    runs = [summarize(d) for d in dirs]
    w = 24
    print(f"{'':<{w}}" + "".join(f"{r['agent'] + ' ' + r['stamp']:>26}" for r in runs))
    for title, key in ROWS:
        print(f"{title:<{w}}" + "".join(f"{str(r.get(key)):>26}" for r in runs))
    print(f"{'review status / issues':<{w}}" + "".join(
        f"{str(r['review']['status']) + ' ' + json.dumps(r['review']['by_severity']):>26}" for r in runs))
    names = sorted({k for r in runs for k in r["bashcut"]}, key=lambda k: -sum(r["bashcut"].get(k, 0) for r in runs))
    print("\nbashcut commands (mcp: tool, cli: bashcut in a shell)")
    for k in names[:30]:
        print(f"  {k:<{w + 6}}" + "".join(f"{r['bashcut'].get(k, 0):>20}" for r in runs))
    print("\ntools")
    for k in sorted({k for r in runs for k in r["tools"]}, key=lambda k: -sum(r["tools"].get(k, 0) for r in runs))[:25]:
        print(f"  {k:<{w + 6}}" + "".join(f"{r['tools'].get(k, 0):>20}" for r in runs))
    path = os.path.join(BENCH, "ab-table.json")
    json.dump({"generated": datetime.now(timezone.utc).isoformat(), "runs": runs}, open(path, "w"), indent=1,
              ensure_ascii=False)
    print("\nsaved", os.path.relpath(path, REPO))


def main():
    a = sys.argv[1:]
    if not a:
        raise SystemExit(__doc__)
    if a[0] == "fixture":
        make_fixture()
    elif a[0] == "run":
        cap = float(a[a.index("--cap") + 1]) if "--cap" in a else 25
        brief = open(a[a.index("--brief") + 1]).read().strip() if "--brief" in a else DEFAULT_BRIEF
        out = run(a[1], cap, brief)
        print("run:", os.path.relpath(out, REPO))
    elif a[0] in ("report", "table"):
        table([os.path.abspath(x) for x in a[1:]])
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
