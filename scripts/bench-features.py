#!/usr/bin/env python3
"""Run every feature group end to end against a running BashCut and report what fails, what is slow and what breaks
an invariant (undo restores the timeline, save and reopen keep it, review stays clean, exports have the right length).

    scripts/bench-features.py [--only media,timeline,...] [--stress 500] [--keep] [--app PATH_TO_BashCut.app]

It works in a scratch project under build/bench-features/run-<time>/ with generated media (ffmpeg), saves the
open project first and reopens it at the end. Library items, lessons, preferences and skills it creates are project
scope (one library item visits user scope and is removed). It never runs plugin actions, agents or network
providers. The report is printed and written next to the project as report.json and report.md.

Python standard library only; talks to the automation socket like scripts/bench-automation.py.
"""
import argparse, json, os, shutil, socket, statistics, subprocess, sys, time, traceback, uuid
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SUPPORT = os.path.expanduser("~/Library/Application Support/BashCut")
SOCK = os.environ.get("BASHCUT_SOCKET", os.path.join(SUPPORT, "automation.sock"))
FPS = 30
# A step slower than this is reported as slow (ui.frame and exports have their own budgets).
SLOW_MS = 250


# MARK: Socket


class RPCError(Exception):
    def __init__(self, method, error):
        self.method, self.code, self.message = method, error.get("code"), error.get("message", "")
        super().__init__(f"{method}: {self.code} {self.message}")


def token():
    return os.environ.get("BASHCUT_SESSION_TOKEN") or open(os.path.join(SUPPORT, "automation-token")).read().strip()


def rpc(method, params=None, timeout=120):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
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
        raise RPCError(method, response["error"])
    return response["result"]


def rev():
    return rpc("context.get")["rev"]


def edit(method, **params):
    """An edit command with the current revision."""
    return rpc(method, {**params, "baseRev": rev()})


def apply(ops, label="bench", dry=False):
    return rpc("timeline.apply", {"ops": ops, "baseRev": rev(), "label": label, "dryRun": dry})


def timeline():
    """The timeline without its revision, for before/after comparisons."""
    value = rpc("timeline.get")
    value.pop("rev", None)
    return value


def items():
    return {item["id"]: {**item, "track": track["id"]} for track in rpc("timeline.get")["tracks"]
            for item in track["items"]}


def wait_idle(timeout=120):
    deadline = time.time() + timeout
    while rpc("context.get")["busy"]:
        if time.time() > deadline:
            raise AssertionError("BashCut stayed busy")
        time.sleep(0.2)


def wait_job(job, timeout=300):
    deadline = time.time() + timeout
    while True:
        status = rpc("jobs.status", {"job": job})
        state = status.get("state") if isinstance(status, dict) else None
        if state in ("done", "finished", "completed", "failed", "cancelled", "succeeded"):
            return status
        if time.time() > deadline:
            raise AssertionError(f"job {job} still {state} after {timeout}s")
        time.sleep(0.3)


def diff(a, b, path=""):
    """The first difference between two JSON values, as a readable path."""
    if type(a) is not type(b):
        return f"{path}: {json.dumps(a)[:80]} → {json.dumps(b)[:80]}"
    if isinstance(a, dict):
        for key in sorted(set(a) | set(b)):
            if key not in a or key not in b:
                return f"{path}.{key}: {'added' if key in b else 'removed'}"
            found = diff(a[key], b[key], f"{path}.{key}")
            if found:
                return found
        return None
    if isinstance(a, list):
        if len(a) != len(b):
            return f"{path}: {len(a)} → {len(b)} entries"
        for index, (x, y) in enumerate(zip(a, b)):
            found = diff(x, y, f"{path}[{index}]")
            if found:
                return found
        return None
    return None if a == b else f"{path}: {json.dumps(a)[:80]} → {json.dumps(b)[:80]}"


# MARK: Report


class Bench:
    def __init__(self):
        self.results = []
        self.group = ""

    def step(self, name, fn, budget=None):
        """Runs one check. An exception is a failure; an AssertionError message says what was wrong. Edit checks
        (an edit plus undo, redo and timeline reads) get a larger default budget than single commands."""
        if budget is None:
            budget = UNDO_REDO_MS if self.group in ("timeline", "clip", "library") else SLOW_MS
        start = time.perf_counter()
        status, note, value = "pass", "", None
        try:
            value = fn()
            if isinstance(value, str) and value.startswith(("SKIP", "NOTE")):
                status, note = value[:4].lower(), value[5:].strip()
        except AssertionError as error:
            status, note = "fail", str(error) or "assertion failed"
        except RPCError as error:
            status, note = "fail", str(error)
        except Exception as error:  # noqa: BLE001 - every unexpected error is a finding
            status, note = "error", f"{type(error).__name__}: {error} @ {traceback.extract_tb(error.__traceback__)[-1].lineno}"
        ms = (time.perf_counter() - start) * 1000
        if status == "pass" and ms > budget:
            status, note = "slow", f"{ms:.0f} ms > {budget} ms budget" + (f"; {note}" if note else "")
        self.results.append({"group": self.group, "name": name, "status": status, "ms": round(ms, 2), "note": note})
        mark = {"pass": "✓", "skip": "-", "note": "?", "slow": "⏱", "fail": "✗", "error": "‼"}[status]
        print(f"  {mark} {name:58s} {ms:9.1f} ms  {note}", flush=True)
        return value if status in ("pass", "slow") else None

    def section(self, name):
        self.group = name
        print(f"\n== {name}", flush=True)

    def write(self, folder: Path, meta):
        counts = {key: sum(1 for r in self.results if r["status"] == key)
                  for key in ("pass", "slow", "note", "skip", "fail", "error")}
        (folder / "report.json").write_text(json.dumps({"meta": meta, "counts": counts, "results": self.results},
                                                       indent=2, ensure_ascii=False))
        lines = [f"# BashCut feature bench {meta['started']}", "",
                 " · ".join(f"{key} {value}" for key, value in counts.items()), ""]
        problems = [r for r in self.results if r["status"] in ("fail", "error", "slow", "note")]
        if problems:
            lines += ["| Group | Step | Status | ms | Note |", "|---|---|---|---|---|"]
            lines += [f"| {r['group']} | {r['name']} | {r['status']} | {r['ms']:.0f} | {r['note'].replace('|', '/')} |"
                      for r in problems]
        (folder / "report.md").write_text("\n".join(lines) + "\n")
        return counts


def expect(condition, message):
    if not condition:
        raise AssertionError(message)


# An undo/redo check is an edit, two undos, a redo and four timeline reads.
UNDO_REDO_MS = 800


def undo_redo(label, ops):
    """Applies ops, then checks undo restores the timeline exactly and redo brings the edit back."""
    before = timeline()
    result = apply(ops, label)
    after = timeline()
    expect(diff(before, after), f"{label}: the edit changed nothing")
    rpc("timeline.undo", {"baseRev": rev()})
    found = diff(before, timeline())
    expect(not found, f"undo did not restore: {found}")
    rpc("timeline.redo", {"baseRev": rev()})
    found = diff(after, timeline())
    expect(not found, f"redo differs: {found}")
    rpc("timeline.undo", {"baseRev": rev()})
    return result


def responsive(fn, limit=500):
    """Runs fn while another connection polls context.get: the longest wait says whether the app's main actor
    stayed free. Returns fn's result; fails when a poll waited more than `limit` ms."""
    import threading
    done, stalls, error, value = threading.Event(), [], [], []
    def work():
        try:
            value.append(fn())
        except Exception as caught:  # noqa: BLE001 - re-raised below
            error.append(caught)
        finally:
            done.set()
    thread = threading.Thread(target=work)
    thread.start()
    began = time.perf_counter()
    while not done.is_set():
        start = time.perf_counter()
        rpc("context.get")
        waited = (time.perf_counter() - start) * 1000
        if waited > 100:
            stalls.append(f"{(start - began):.1f}s:{waited:.0f}ms")
        time.sleep(0.05)
    thread.join()
    if error:
        raise error[0]
    worst = max([float(x.split(":")[1][:-2]) for x in stalls] or [0])
    expect(worst <= limit, f"context.get waited {worst:.0f} ms while it ran (UI blocked); stalls {' '.join(stalls)}")
    return value[0] if value else None


def review_ids():
    return {entry["id"] for entry in rpc("review.run")}


# MARK: Media


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *map(str, args)], check=True)


def make_media(folder: Path):
    folder.mkdir(parents=True, exist_ok=True)
    h264 = ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "ultrafast"]
    aac = ["-c:a", "aac", "-b:a", "96k"]
    ffmpeg("-f", "lavfi", "-i", f"testsrc2=size=540x960:rate={FPS}", "-f", "lavfi",
           "-i", "sine=frequency=330:sample_rate=48000:beep_factor=4", "-t", "12", *h264, *aac, "-shortest",
           folder / "talk.mp4")
    ffmpeg("-f", "lavfi", "-i", f"smptehdbars=size=1280x720:rate={FPS}", "-f", "lavfi",
           "-i", "sine=frequency=550:sample_rate=48000", "-t", "8", *h264, *aac, "-shortest", folder / "wide.mp4")
    ffmpeg("-f", "lavfi", "-i", f"mandelbrot=size=540x960:rate={FPS}", "-t", "8", *h264, folder / "silent.mp4")
    ffmpeg("-f", "lavfi", "-i",
           "aevalsrc='0.25*sin(2*PI*110*t)+0.6*sin(2*PI*1000*t)*exp(-60*mod(t\\,0.5))':s=48000:d=30",
           *aac, folder / "music.m4a")
    ffmpeg("-f", "lavfi", "-i", "sine=frequency=1320:sample_rate=48000", "-t", "0.6", *aac, folder / "ding.m4a")
    ffmpeg("-f", "lavfi", "-i", "color=c=orange:size=400x400", "-frames:v", "1", folder / "sticker.png")
    (folder / "captions.srt").write_text(
        "1\n00:00:00,500 --> 00:00:02,000\nXin chào các bạn\n\n"
        "2\n00:00:02,500 --> 00:00:04,500\nĐây là bài kiểm tra BashCut\n\n"
        "3\n00:00:05,000 --> 00:00:07,000\nWord by word captions\n", encoding="utf-8")
    lines = ['TITLE "Bench warm"', "LUT_3D_SIZE 5"]
    for b in range(5):
        for g in range(5):
            for r in range(5):
                lines.append(f"{min(1, r / 4 * 1.08):.6f} {g / 4:.6f} {b / 4 * 0.9:.6f}")
    (folder / "warm.cube").write_text("\n".join(lines) + "\n")
    legacy = folder.parent / "legacy" / "timeline"
    legacy.mkdir(parents=True, exist_ok=True)
    (legacy / "edl.json").write_text(json.dumps({
        "fps": FPS, "total_frames": 120,
        "clips": [{"path": str(folder / "talk.mp4"), "src_in_frame": 30, "so_frame": 60, "rec_frame": 0,
                   "sec": "Hook", "sub": "Xin chào|1.0|Legacy"},
                  {"path": str(folder / "wide.mp4"), "src_in_frame": 0, "so_frame": 60, "rec_frame": 60,
                   "sec": "Body"}],
        "vo": [], "fx": {}}))


def probe_seconds(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                         capture_output=True, text=True).stdout.strip()
    return float(out) if out else 0.0


# MARK: Scenarios


class Run:
    def __init__(self, bench: Bench, folder: Path, options):
        self.b, self.folder, self.options = bench, folder, options
        self.media_dir = folder / "media"
        self.media = {}

    # Project

    def project(self):
        b = self.b
        b.section("project")
        b.step("project.create (scratch)", lambda: rpc("project.create", {
            "name": "Bench", "directory": str(self.folder), "canvas": "portrait", "resolution": "1080",
            "fps": "30", "language": "vi", "saveCurrent": True}), budget=2000)
        b.step("project.get has a path", lambda: expect(rpc("context.get").get("project"), "no project path"))
        b.step("schema.get", lambda: expect(rpc("schema.get"), "empty schema"))
        b.step("project.recents lists the scratch project", lambda: expect(
            any(str(self.folder) in json.dumps(entry) for entry in rpc("project.recents")),
            "scratch project not in recents"))

    def import_media(self):
        b = self.b
        b.section("media")
        for name, kind in [("talk.mp4", "video"), ("wide.mp4", "video"), ("silent.mp4", "video"),
                           ("music.m4a", "audio"), ("ding.m4a", "audio"), ("sticker.png", "image")]:
            def run(name=name, kind=kind):
                result = edit("media.import", path=str(self.media_dir / name), kind=kind)
                wait_idle()
                self.media[name] = result["media"]
            b.step(f"media.import {name}", run, budget=3000)
        def listed():
            listed = rpc("media.list")
            entries = listed if isinstance(listed, list) else listed.get("media", [])
            expect(len(entries) >= 6, f"media.list has {len(entries)} entries")
            for entry in entries:
                if entry.get("kind") in ("video", "audio"):
                    expect((entry.get("frames") or entry.get("durationFrames") or entry.get("duration") or 0) > 0,
                           f"{entry.get('name')}: no duration")
        b.step("media.list has every import with a duration", listed)
        def reimport():
            again = edit("media.import", path=str(self.media_dir / "talk.mp4"), kind="video")["media"]
            if again != self.media["talk.mp4"]:
                return "NOTE importing the same file again adds a second media entry"
        b.step("media.import twice", reimport)
        b.step("media.import a missing file is rejected", lambda: self.rejects(
            lambda: edit("media.import", path=str(self.media_dir / "nope.mp4"))))
        b.step("media.place talk on Main", lambda: edit("media.place", media=self.media["talk.mp4"], atFrame=0))
        b.step("media.place wide on Main", lambda: edit("media.place", media=self.media["wide.mp4"]))
        b.step("media.place music", lambda: edit("media.place", media=self.media["music.m4a"], atFrame=0))
        b.step("media.place image (sticker)", lambda: edit("media.place", media=self.media["sticker.png"], atFrame=30))
        def placed():
            found = items()
            expect(len(found) >= 4, f"only {len(found)} items after placing 4 media")
            talk = [i for i in found.values() if i.get("media") == self.media["talk.mp4"]]
            expect(len(talk) >= 1, "talk.mp4 not on the timeline")
            expect(any(i.get("linkedAudio") for i in talk), "talk.mp4 video has no linked audio")
        b.step("placed items are on the timeline, video linked to sound", placed)
        b.step("media.proxy talk", lambda: rpc("media.proxy", {"media": self.media["talk.mp4"]}), budget=1000)

    def known(self, fn, text, issue):
        """A step that hits a known, tracked gap is skipped instead of failed."""
        try:
            return fn()
        except RPCError as error:
            if text in error.message:
                return f"SKIP known gap ({issue})"
            raise

    def rejects(self, fn, code=None):
        try:
            fn()
        except RPCError as error:
            if code is not None:
                expect(error.code == code, f"rejected with {error.code}, expected {code}: {error.message}")
            return
        raise AssertionError("was accepted")

    # Timeline

    def main_items(self):
        tracks = rpc("timeline.get")["tracks"]
        main = next(t for t in tracks if t.get("role") == "main")
        return main, sorted(main["items"], key=lambda i: i["at"])

    def timeline_ops(self):
        b = self.b
        b.section("timeline")
        main, clips = self.main_items()
        first = clips[0]["id"]
        b.step("stale baseRev is rejected with -32002", lambda: self.rejects(
            lambda: rpc("timeline.apply", {"ops": [{"op": "setProperties", "item": first, "patch": {"opacity": 0.5}}],
                                           "baseRev": rev() - 1}), code=-32002))
        b.step("unknown op is rejected", lambda: self.rejects(lambda: apply([{"op": "explode", "item": first}])))
        b.step("unknown item is rejected", lambda: self.rejects(
            lambda: apply([{"op": "setProperties", "item": "missing", "patch": {"opacity": 0.5}}])))
        def dry():
            before = timeline()
            apply([{"op": "setProperties", "item": first, "patch": {"opacity": 0.5}}], dry=True)
            expect(not diff(before, timeline()), "dry run changed the timeline")
        b.step("dryRun changes nothing", dry)
        b.step("setProperties undo/redo", lambda: undo_redo("props", [
            {"op": "setProperties", "item": first, "patch": {"opacity": 0.7, "transform": {"zoom": 1.2}}}]))
        b.step("split undo/redo", lambda: undo_redo("split", [
            {"op": "split", "item": first, "atFrame": clips[0]["at"] + 60, "newID": "bench-split"}]))
        b.step("trim end ripple undo/redo", lambda: undo_redo("trim", [
            {"op": "trim", "item": first, "edge": "end", "toFrame": clips[0]["at"] + clips[0]["dur"] - 30,
             "ripple": True}]))
        # Slip and roll need spare source: trim the first clip's end first (ripple) in the same edit.
        trimmed = clips[0]["at"] + clips[0]["dur"] - 30
        b.step("slip undo/redo", lambda: undo_redo("slip", [
            {"op": "trim", "item": first, "edge": "end", "toFrame": trimmed, "ripple": True},
            {"op": "slip", "item": first, "sourceIn": 15}]))
        if len(clips) > 1:
            second = clips[1]["id"]
            b.step("roll undo/redo", lambda: undo_redo("roll", [
                {"op": "trim", "item": first, "edge": "end", "toFrame": trimmed, "ripple": True},
                {"op": "roll", "item": first, "edge": "end", "toFrame": trimmed + 10}]))
            b.step("reorder undo/redo", lambda: undo_redo("reorder", [
                {"op": "reorder", "item": second, "before": first}]))
            b.step("transition dissolve undo/redo", lambda: undo_redo("transition", [
                {"op": "upsertTransition", "id": "bench-t", "kind": "dissolve", "from": first, "to": second,
                 "duration": 10}]))
            b.step("ripple delete undo/redo", lambda: undo_redo("delete", [
                {"op": "delete", "item": second, "ripple": True}]))
        b.step("section + beat grid undo/redo", lambda: undo_redo("markers", [
            {"op": "upsertSection", "id": "bench-hook", "label": "Hook", "atFrame": 0},
            {"op": "setBeatGrid", "media": self.media["music.m4a"], "bpm": 120,
             "frames": list(range(0, 300, 15))}]))
        b.step("track add/delete undo/redo", lambda: undo_redo("track", [
            {"op": "addTrack", "track": {"id": "bench-track", "kind": "video", "role": "overlay", "name": "B",
                                         "items": []}, "atIndex": 1}]))
        def project_props():
            apply([{"op": "setProjectProperties", "patch": {"name": "Bench renamed"}}])
            expect(rpc("project.get")["name"] == "Bench renamed", "name not changed")
            rpc("timeline.undo", {"baseRev": rev()})
            expect(rpc("project.get")["name"] == "Bench", "undo did not restore the name")
        b.step("project properties undo", project_props)
        def move_and_gap():
            _, clips_now = self.main_items()
            last = clips_now[-1]
            edit("timeline.move", item=last["id"], track=main["id"], atFrame=last["at"] + last["dur"] + 60)
            expect("gap" in json.dumps(rpc("review.run")).lower(), "review did not report the gap")
            edit("timeline.close-gap", atFrame=last["at"] + last["dur"] + 10, track=main["id"])
            moved = items()[last["id"]]
            expect(moved["at"] == last["at"], f"close-gap left the clip at {moved['at']}, expected {last['at']}")
        b.step("timeline.move then close-gap", move_and_gap)
        def noop():
            _, now = self.main_items()
            item = now[0]
            op = [{"op": "setProperties", "item": item["id"], "patch": {"opacity": item.get("opacity", 1)}}]
            # The first apply may store a default the item did not have yet; the second must change nothing.
            first = apply(op)
            middle = rev()
            second = apply(op)
            if first.get("changed"):
                rpc("timeline.undo", {"baseRev": rev()})
            expect(second.get("changed") is False and second.get("rev") == middle,
                   f"an edit that changes nothing returned {second} at revision {middle}")
        b.step("an edit that changes nothing", noop)
        b.step("timeline.get text", lambda: expect("MAIN" in rpc("timeline.get", {"format": "text"}), "no MAIN line"))

    def clips(self):
        b = self.b
        b.section("clip")
        _, clips = self.main_items()
        target = clips[0]["id"]
        rpc("ui.select", {"item": target})
        b.step("clip.speed 2x keep duration", lambda: self.edit_undo("clip.speed", item=target, speed=2.0,
                                                                     keepDuration=True))
        b.step("clip.speed 0.5x", lambda: self.edit_undo("clip.speed", item=target, speed=0.5))
        for preset in ["montage", "hero", "bullet", "jump-cut", "flash-in", "flash-out"]:
            b.step(f"clip.speed-curve {preset}", lambda preset=preset: self.edit_undo(
                "clip.speed-curve", item=target, preset=preset))
        for preset in ["zoom-in", "zoom-out", "pan-left", "pan-right", "pan-up", "pan-down", "fade-in-out", "pop-in",
                       "slide-up", "zoom-punch"]:
            b.step(f"clip.motion {preset}", lambda preset=preset: self.edit_undo("clip.motion", item=target,
                                                                                preset=preset))
        for prop, value in [("opacity", 0.5), ("zoom", 1.4), ("pan", 50), ("tilt", -30), ("rotation", 10),
                            ("volume", -6)]:
            b.step(f"clip.keyframe {prop}", lambda prop=prop, value=value: self.edit_undo(
                "clip.keyframe", item=target, property=prop, value=value, atFrame=clips[0]["at"] + 10))
        b.step("clip.speed 0 is rejected", lambda: self.rejects(lambda: edit("clip.speed", item=target, speed=0)))
        b.step("clip.speed 1000 is rejected", lambda: self.rejects(lambda: edit("clip.speed", item=target,
                                                                                 speed=1000)))
        def reverse():
            result = rpc("clip.reverse", {"item": target})
            job = result.get("job") if isinstance(result, dict) else None
            if job:
                status = wait_job(job)
                expect(status.get("state") not in ("failed", "cancelled"), f"reverse job {status}")
            wait_idle()
            expect(items()[target].get("reversed") or "revers" in json.dumps(items()[target]).lower(),
                   "clip is not marked reversed")
        b.step("clip.reverse (UI stays responsive)", lambda: responsive(reverse), budget=15000)

    def edit_undo(self, method, **params):
        before = timeline()
        edit(method, **params)
        expect(diff(before, timeline()), f"{method} changed nothing")
        rpc("timeline.undo", {"baseRev": rev()})
        found = diff(before, timeline())
        expect(not found, f"undo did not restore: {found}")

    # Layers, colour, style

    def layers(self):
        b = self.b
        b.section("layers + colour")
        added = {}
        for kind in ["video", "adjustment", "text", "audio"]:
            def add(kind=kind):
                added[kind] = edit("layers.add", kind=kind, name=f"Bench {kind}")["track"]
            b.step(f"layers.add {kind}", add)
        if "video" in added:
            for flag in ["hidden", "locked"]:
                b.step(f"layers.set {flag}", lambda flag=flag: edit("layers.set", track=added["video"], **{flag: True}))
            b.step("locked layer refuses an insert", lambda: self.rejects(lambda: apply([
                {"op": "insert", "track": added["video"], "item": {"id": "bench-locked", "media": self.media["wide.mp4"],
                                                                     "at": 0, "dur": 30, "in": 0}}])))
            b.step("layers.set unlock", lambda: edit("layers.set", track=added["video"], locked=False))
        if "audio" in added:
            b.step("layers.set muted", lambda: edit("layers.set", track=added["audio"], muted=True))
        b.step("luts.import", lambda: edit("luts.import", path=str(self.media_dir / "warm.cube"), name="Bench warm"))
        lut = (rpc("project.get").get("luts") or [{}])[-1].get("id")
        b.step("luts.import a broken .cube is rejected", lambda: self.rejects(lambda: self.broken_lut()))
        b.step("adjustment.add exposure/contrast", lambda: edit("adjustment.add", exposure=0.2, contrast=1.1,
                                                                 atFrame=0, duration=90))
        b.step("adjustment.add with LUT", lambda: edit("adjustment.add", lut=lut, lutStrength=0.6, atFrame=90,
                                                       duration=60))
        _, clips = self.main_items()
        b.step("looks.save from item", lambda: edit("looks.save", id="bench-look", title="Bench look",
                                                    item=clips[0]["id"], exposure=0.1, saturation=1.2))
        b.step("style.save", lambda: edit("style.save", id="bench-kit", title="Bench kit", look="bench-look",
                                           captionPreset="bold-outline"))
        b.step("style.apply", lambda: edit("style.apply", kit="bench-kit"), budget=500)
        b.step("style.delete", lambda: edit("style.delete", id="bench-kit"))
        b.step("looks.delete", lambda: edit("looks.delete", id="bench-look"))
        b.step("project.format landscape fit then back", lambda: (
            edit("project.format", canvas="landscape", clips="fit"),
            expect(rpc("project.get")["format"].get("width", 0) > rpc("project.get")["format"].get("height", 0),
                   "landscape canvas is not wider than tall"),
            edit("project.format", canvas="portrait", clips="fill")))

    def broken_lut(self):
        path = self.media_dir / "broken.cube"
        path.write_text("LUT_3D_SIZE 4\n0 0 0\n1 1\n")
        edit("luts.import", path=str(path), name="Broken")

    # Captions

    def captions(self):
        b = self.b
        b.section("captions")
        srt = (self.media_dir / "captions.srt").read_text()
        b.step("captions.import", lambda: edit("captions.import", text=srt))
        def exported():
            text = rpc("captions.export")
            text = text if isinstance(text, str) else json.dumps(text, ensure_ascii=False)
            expect("Xin chào các bạn" in text, "the Vietnamese caption is missing from the export")
            expect("00:00:00,500" in text, "the first cue time is not 00:00:00,500")
        b.step("captions.export round-trips text and timing", exported)
        b.step("captions.import --replace keeps 3 cues", lambda: (
            edit("captions.import", text=srt, replace=True),
            expect(rpc("captions.export").count("-->") == 3, "replace did not leave exactly 3 cues")))
        for style in ["highlight", "karaoke", "reveal", "none"]:
            b.step(f"captions.words {style} --all", lambda style=style: edit("captions.words", style=style, all=True))
        b.step("captions.import garbage is rejected", lambda: self.rejects(
            lambda: edit("captions.import", text="not a subtitle file")))

    # Library

    def library(self):
        b = self.b
        b.section("library")
        for panel in ["audio", "text", "stickers", "effects", "transitions", "filters", "voice"]:
            b.step(f"library.list panel {panel}", lambda panel=panel: rpc("library.list", {"panel": panel}))
        b.step("library.stats", lambda: rpc("library.stats"))
        _, clips = self.main_items()
        target = clips[0]["id"]
        rpc("ui.select", {"item": target})
        created = []
        other = clips[1]["id"] if len(clips) > 1 else target
        # Something to save: a grade and a transition on the first cut, and a text item.
        apply([{"op": "setProperties", "item": target, "patch": {"color": {"exposure": 0.3, "saturation": 1.3},
                                                                 "transform": {"zoom": 1.25}}}])
        if len(clips) > 1 and clips[0]["at"] + clips[0]["dur"] == clips[1]["at"]:
            apply([{"op": "upsertTransition", "id": "bench-lib-t", "kind": "dissolve", "from": target,
                    "to": clips[1]["id"], "duration": 8}])
        text_item = next((i["id"] for i in items().values() if i.get("text")), None)
        for kind in ["effect-preset", "look", "transition-preset", "text-preset"]:
            def save(kind=kind):
                params = {"kind": kind, "name": f"Bench {kind}", "scope": "project", "tags": "bench"}
                params["item"] = text_item if kind == "text-preset" else target
                result = rpc("library.save-selection", params)
                created.append((kind, result.get("id") or result.get("item", {}).get("id")))
            b.step(f"library.save-selection {kind}", save)
        def add_audio():
            result = rpc("library.add", {"kind": "audio", "name": "Bench ding", "file": str(self.media_dir / "ding.m4a"),
                                         "scope": "project", "tags": "bench"})
            created.append(("audio", result.get("id") or result.get("item", {}).get("id")))
        b.step("library.add audio file", add_audio)
        def add_sticker():
            result = rpc("library.add", {"kind": "sticker", "name": "Bench sticker",
                                         "file": str(self.media_dir / "sticker.png"), "scope": "project"})
            created.append(("sticker", result.get("id") or result.get("item", {}).get("id")))
        b.step("library.add sticker file", add_sticker)
        def listed():
            found = rpc("library.list", {"query": "Bench", "scope": "project"})
            expect(len(found) == len(created), f"query found {len(found)} of {len(created)}")
            tagged = rpc("library.list", {"tag": "bench", "scope": "project"})
            expect(len(tagged) == len(created) - 1, f"tag filter found {len(tagged)}, expected {len(created) - 1}")
        b.step("library.list --query / --tag", listed)
        if any(kind == "transition-preset" for kind, _ in created):
            apply([{"op": "deleteTransition", "id": "bench-lib-t"}])
        for kind, identifier in list(created):
            if not identifier:
                continue
            if kind in ("effect-preset", "look", "transition-preset"):
                b.step(f"library.apply {kind}", lambda identifier=identifier, kind=kind: self.edit_undo(
                    "library.apply", id=identifier, item=target if kind == "transition-preset" else other))
            if kind in ("text-preset", "audio", "sticker"):
                b.step(f"library.place {kind}", lambda identifier=identifier: self.known(
                    lambda: self.edit_undo("library.place", id=identifier, atFrame=30, duration=45, text="Bench"),
                    "not supported yet", "#78/#64"))
        if created and created[0][1]:
            first = created[0][1]
            b.step("library.update rename", lambda: rpc("library.update", {"id": first, "name": "Bench renamed",
                                                                            "scope": "project"}))
            b.step("library.move to user and back", lambda: (
                rpc("library.move", {"id": first, "scope": "project", "to": "user"}),
                rpc("library.move", {"id": first, "scope": "user", "to": "project"})))
        pack = self.folder / "bench-pack"
        b.step("library.export-pack", lambda: rpc("library.export-pack", {"output": str(pack), "scope": "project",
                                                                           "name": "Bench pack"}))
        for kind, identifier in created:
            if identifier:
                b.step(f"library.remove {kind}", lambda identifier=identifier: rpc(
                    "library.remove", {"id": identifier, "scope": "project"}))
        exported = next(iter(sorted(self.folder.glob("bench-pack*"))), None)
        if exported:
            b.step("library.import-pack restores the items", lambda: (
                rpc("library.import-pack", {"path": str(exported), "scope": "project"}),
                expect(len(rpc("library.list", {"query": "Bench", "scope": "project"})) == len(created),
                       "the imported pack has a different number of items")))
            for kind, identifier in created:
                if identifier:
                    try:
                        rpc("library.remove", {"id": identifier, "scope": "project"})
                    except RPCError:
                        pass
        else:
            b.step("library.export-pack wrote a file", lambda: expect(False, f"nothing at {pack}*"))

    # Knowledge and skills

    def knowledge(self):
        b = self.b
        b.section("knowledge + skills")
        lesson = {}
        def add():
            result = rpc("knowledge.add-lesson", {"title": "Bench lesson", "symptom": "s", "cause": "c", "fix": "f",
                                                   "tags": "bench", "scope": "project"})
            lesson["id"] = result.get("id") or result.get("lesson", {}).get("id")
            expect(lesson["id"], f"no id in {result}")
        b.step("knowledge.add-lesson project", add)
        if lesson.get("id"):
            b.step("knowledge.update-lesson", lambda: rpc("knowledge.update-lesson", {"id": lesson["id"],
                                                                                     "fix": "f2"}))
            b.step("knowledge.lessons --query", lambda: expect(
                "Bench lesson" in json.dumps(rpc("knowledge.lessons", {"query": "Bench", "scope": "project"})),
                "lesson not found by query"))
            b.step("knowledge.remove-lesson", lambda: rpc("knowledge.remove-lesson", {"id": lesson["id"]}))
        b.step("knowledge.set-pref project", lambda: rpc("knowledge.set-pref", {"key": "bench.pref", "value": "1",
                                                                                 "scope": "project"}))
        b.step("knowledge.set-fact", lambda: rpc("knowledge.set-fact", {"key": "bench.fact", "value": "x"}))
        b.step("context.get carries the fact", lambda: expect(
            "bench.fact" in json.dumps(rpc("context.get")), "fact missing from context knowledge"))
        def history_and_revert():
            history = rpc("knowledge.history", {"scope": "project", "limit": 10})
            entries = history if isinstance(history, list) else history.get("changes", history.get("history", []))
            expect(entries, "empty history")
            fact = next((e for e in entries if "bench.fact" in json.dumps(e)), None)
            expect(fact, "no history entry for bench.fact")
            rpc("knowledge.revert", {"id": fact["id"]})
            expect("bench.fact" not in json.dumps(rpc("knowledge.facts")), "revert left the fact")
        b.step("knowledge.history + revert", history_and_revert)
        b.step("knowledge.set-pref remove", lambda: rpc("knowledge.set-pref", {"key": "bench.pref", "remove": True,
                                                                                "scope": "project"}))
        b.step("knowledge.memo project", lambda: rpc("knowledge.memo", {"text": "Bench memo\n", "scope": "project"}))
        b.step("knowledge.memo clear", lambda: rpc("knowledge.memo", {"clear": True, "scope": "project"}))
        skill = "---\nname: bench-skill\ndescription: Bench skill.\n---\n\nBody.\n"
        b.step("skills.save project", lambda: rpc("skills.save", {"name": "bench-skill", "text": skill,
                                                                   "scope": "project"}))
        b.step("skills.get", lambda: expect("Body." in json.dumps(rpc("skills.get", {"name": "bench-skill",
                                                                                     "scope": "project"})), "no body"))
        b.step("skills.disable/enable", lambda: (rpc("skills.disable", {"name": "bench-skill", "scope": "project"}),
                                                 rpc("skills.enable", {"name": "bench-skill", "scope": "project"})))
        b.step("skills.remove", lambda: rpc("skills.remove", {"name": "bench-skill", "scope": "project"}))
        b.step("skills.list kit", lambda: expect(rpc("skills.list", {"scope": "kit"}), "no kit skills"))
        b.step("skills.save rejects a path name", lambda: self.rejects(
            lambda: rpc("skills.save", {"name": "../escape", "text": skill, "scope": "project"})))

    # UI

    def ui(self):
        b = self.b
        b.section("ui")
        b.step("close dialogs left open", lambda: self.close_all())
        for panel in ["media", "audio", "text", "stickers", "effects", "transitions", "filters", "voice"]:
            b.step(f"ui.panel {panel}", lambda panel=panel: rpc("ui.panel", {"panel": panel}))
        views = [{"zoom": 50}, {"snap": False}, {"snap": True}, {"safeArea": True}, {"viewerZoom": "50"},
                 {"viewerZoom": "fit"}, {"compare": True}, {"compare": False}, {"inspector": "color"},
                 {"inspector": "speed"}, {"libraryQuery": "bench"}, {"libraryScope": "project"},
                 {"libraryQuery": ""}, {"libraryScope": "all"}, {"reveal": 120}]
        for view in views:
            b.step(f"ui.view {json.dumps(view)}", lambda view=view: rpc("ui.view", view))
        b.step("ui.seek 45 then context playhead", lambda: (
            rpc("ui.seek", {"frame": 45}), expect(rpc("context.get")["playhead"] == 45, "playhead is not 45")))
        b.step("ui.frame", lambda: expect(rpc("ui.frame", {"frame": 45}), "no frame"), budget=1000)
        b.step("ui.select a track", lambda: rpc("ui.select", {"track": "v1"}))
        b.step("ui.actions", lambda: expect(rpc("ui.actions"), "no actions"))
        for dialog in ["export", "review", "history", "sections", "shortcuts", "commands", "settings", "plugins",
                       "doctor", "knowledge", "new-project", "add-plugin"]:
            b.step(f"ui.open {dialog} + close", lambda dialog=dialog: self.open_and_close(dialog), budget=1500)
        b.step("ui.dialog is empty at the end", lambda: expect(not self.open_dialog(), f"left open: {self.open_dialog()}"))
        b.step("ui.notify", lambda: rpc("ui.notify", {"message": "Bench notification"}))
        b.step("ui.source", lambda: rpc("ui.source", {"media": self.media["talk.mp4"], "in": 10, "out": 60}))

    def open_dialog(self):
        state = rpc("ui.dialog")
        if isinstance(state, dict):
            return state.get("dialog") or state.get("open") or state.get("sheets") or None
        return state or None

    def close_all(self):
        closes = 0
        while self.open_dialog() and closes < 4:
            for option in ["cancel", "close", "done"]:
                try:
                    rpc("ui.respond", {"option": option})
                    break
                except RPCError:
                    continue
            closes += 1
            time.sleep(0.25)
        return closes

    def open_and_close(self, dialog):
        rpc("ui.open", {"dialog": dialog})
        time.sleep(0.25)
        expect(self.open_dialog(), f"{dialog} did not report as open")
        closes = 0
        while self.open_dialog() and closes < 3:
            for option in ["cancel", "close", "done"]:
                try:
                    rpc("ui.respond", {"option": option})
                    break
                except RPCError:
                    continue
            closes += 1
            time.sleep(0.25)
        left = self.open_dialog()
        expect(not left, f"{dialog} still open after {closes} closes: {json.dumps(left)[:120]}")

    # Persistence

    def persistence(self):
        b = self.b
        b.section("persistence")
        before = {}
        def save():
            before["timeline"] = timeline()
            rpc("project.save")
            expect(not rpc("context.get")["dirty"], "still dirty after save")
        b.step("project.save", save, budget=1000)
        path = rpc("context.get")["project"]
        def reopen():
            rpc("project.close", {})
            rpc("project.open", {"path": path})
            wait_idle()
            found = diff(before["timeline"], timeline())
            expect(not found, f"reopened timeline differs: {found}")
            expect(rpc("timeline.get")["rev"] >= 0, "no revision")
        b.step("close + reopen keeps the timeline", reopen, budget=3000)
        b.step("undo after reopen still works", lambda: rpc("timeline.undo", {"baseRev": rev()}))
        b.step("redo after reopen", lambda: rpc("timeline.redo", {"baseRev": rev()}))
        b.step("review after reopen has no errors", lambda: expect(
            not [e for e in rpc("review.run") if e.get("severity") == "error"], "review errors"))

    # Export

    def export(self):
        b = self.b
        b.section("export")
        out = self.folder / "exports"
        out.mkdir(exist_ok=True)
        length = {}
        def run():
            tracks = rpc("timeline.get")["tracks"]
            length["frames"] = max(i["at"] + i["dur"] for t in tracks for i in t["items"])
            rpc("export.start", {"preset": "quick-draft", "name": "bench", "directory": str(out),
                                 "includeSRT": True})
            deadline = time.time() + 600
            while True:
                status = rpc("export.status")
                text = json.dumps(status)
                if any(word in text for word in ('"done"', '"finished"', '"completed"', '"failed"', '"idle"')) \
                        and not rpc("context.get")["busy"]:
                    break
                if time.time() > deadline:
                    raise AssertionError(f"export still running: {text[:200]}")
                time.sleep(0.5)
            expect('"failed"' not in json.dumps(status), f"export failed: {json.dumps(status)[:300]}")
        b.step("export.start quick-draft (UI stays responsive)", lambda: responsive(run), budget=60000)
        def check_file():
            movies = sorted(out.glob("bench*.mp4")) + sorted(out.glob("bench*.mov"))
            expect(movies, f"no movie in {out}: {[p.name for p in out.iterdir()]}")
            seconds = probe_seconds(movies[0])
            wanted = length["frames"] / FPS
            expect(abs(seconds - wanted) < 0.2, f"export is {seconds:.2f}s, timeline is {wanted:.2f}s")
            if any(t.get("role") == "captions" and t["items"] for t in rpc("timeline.get")["tracks"]):
                expect(sorted(out.glob("bench*.srt")), "no .srt next to the export")
        b.step("export length matches the timeline (and the SRT)", check_file)
        b.step("export.otio", lambda: (rpc("export.otio", {"name": "bench", "directory": str(out)}),
                                       expect(sorted(out.glob("bench*.otio")), "no .otio file")))
        def otio_valid():
            path = sorted(out.glob("bench*.otio"))[0]
            data = json.loads(path.read_text())
            expect(data.get("OTIO_SCHEMA", "").startswith("Timeline"), f"OTIO root is {data.get('OTIO_SCHEMA')}")
        b.step("otio is a valid Timeline document", otio_valid)

    # EDL import (opens a new project, so it runs last before stress)

    def edl(self):
        b = self.b
        b.section("edl")
        def run():
            rpc("project.save")
            rpc("edl.import", {"path": str(self.folder / "legacy" / "timeline" / "edl.json"), "saveCurrent": True})
            wait_idle()
            found = items()
            main = [i for i in found.values() if i.get("media") and i["track"] == "v1"] or \
                [i for i in found.values() if i.get("media")]
            expect(len(main) >= 2, f"EDL import has {len(found)} items")
            tracks = rpc("timeline.get")["tracks"]
            end = max(i["at"] + i["dur"] for t in tracks if t.get("role") == "main" for i in t["items"])
            expect(end == 120, f"imported main layer ends at {end}, expected 120")
        b.step("edl.import legacy edl.json", run, budget=5000)

    # Read-only service commands

    def services(self):
        b = self.b
        b.section("services")
        for method in ["app.version", "doctor.run", "storage.get", "agent.status", "agent.terminals",
                       "plugins.list", "plugins.hooks", "plugins.actions", "chat.status", "jobs.status",
                       "knowledge.get", "knowledge.proposals", "library.stats", "export.status"]:
            b.step(method, lambda method=method: responsive(lambda: rpc(method)),
                   budget=3000 if method == "doctor.run" else SLOW_MS)
        b.step("unknown method is -32601", lambda: self.rejects(lambda: rpc("nope.nothing"), code=-32601))
        b.step("missing required param is -32602", lambda: self.rejects(lambda: rpc("timeline.move", {}),
                                                                         code=-32602))

    # Stress

    def stress(self, count):
        b = self.b
        b.section(f"stress ({count} clips)")
        rpc("project.create", {"name": "Bench stress", "directory": str(self.folder), "canvas": "portrait",
                               "resolution": "1080", "fps": "30", "saveCurrent": True})
        talk = edit("media.import", path=str(self.media_dir / "talk.mp4"), kind="video")["media"]
        wait_idle()
        ops = [{"op": "insert", "track": "v1", "item": {"id": f"s{n}", "media": talk, "at": n * 15, "dur": 15,
                                                         "in": (n * 7) % 300}} for n in range(count)]
        # One apply takes at most 1000 operations.
        b.step(f"insert {count} clips", lambda: [apply(ops[n:n + 1000], "stress") for n in range(0, count, 1000)],
               budget=2000)
        times = {}
        def sample(name, fn, runs=10):
            values = []
            for _ in range(runs):
                start = time.perf_counter()
                fn()
                values.append((time.perf_counter() - start) * 1000)
            times[name] = statistics.median(values)
            return times[name]
        def p50(name, fn, budget):
            value = sample(name, fn)
            expect(value <= budget, f"p50 {value:.1f} ms > {budget} ms")
        b.step("timeline.get p50", lambda: p50("timeline.get", lambda: rpc("timeline.get"), 50), budget=5000)
        b.step("review.run p50", lambda: p50("review.run", lambda: rpc("review.run"), 50), budget=5000)
        b.step("one setProperties p50", lambda: p50("setProperties", lambda: apply(
            [{"op": "setProperties", "item": "s10", "patch": {"opacity": 0.9}}]), 50), budget=5000)
        b.step("ripple delete + undo", lambda: (apply([{"op": "delete", "item": "s1", "ripple": True}]),
                                                rpc("timeline.undo", {"baseRev": rev()})))
        b.step("100 single edits in a row", lambda: [apply([{"op": "setProperties", "item": f"s{n}",
                                                             "patch": {"opacity": 0.8}}]) for n in range(100)],
               budget=5000)
        b.step("100 undos", lambda: [rpc("timeline.undo", {"baseRev": rev()}) for _ in range(100)], budget=5000)
        b.step("ui.view zoom out to whole timeline", lambda: rpc("ui.view", {"zoom": 1}), budget=500)
        b.step("ui.frame mid timeline", lambda: rpc("ui.frame", {"frame": count * 7}), budget=1500)
        b.step("project.save", lambda: rpc("project.save"), budget=1000)
        path = rpc("context.get")["project"]
        b.step("close + reopen", lambda: (rpc("project.close", {}), rpc("project.open", {"path": path}),
                                          wait_idle()), budget=5000)
        print("    " + "  ".join(f"{k} {v:.1f} ms" for k, v in times.items()))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", help="comma-separated groups: project,media,timeline,clip,layers,captions,library,"
                                       "knowledge,ui,persistence,export,edl,services,stress")
    parser.add_argument("--stress", type=int, default=500, help="clips in the stress project (0 skips it)")
    parser.add_argument("--keep", action="store_true", help="keep the scratch folder")
    options = parser.parse_args()
    for tool in ("ffmpeg", "ffprobe"):
        if not shutil.which(tool):
            sys.exit(f"{tool} is required")
    try:
        context = rpc("context.get")
    except (FileNotFoundError, ConnectionRefusedError):
        sys.exit("BashCut is not running (no automation socket)")
    previous = context.get("project")
    if previous and context.get("dirty"):
        rpc("project.save")
    started = time.strftime("%Y%m%d-%H%M%S")
    folder = REPO / "build" / "bench-features" / f"run-{started}"
    folder.mkdir(parents=True)
    bench = Bench()
    run = Run(bench, folder, options)
    print(f"Scratch: {folder}")
    make_media(run.media_dir)
    groups = ["project", "media", "timeline", "clip", "layers", "captions", "library", "knowledge", "ui",
              "persistence", "export", "services", "edl"]
    wanted = set(options.only.split(",")) if options.only else set(groups) | {"stress"}
    try:
        run.project()
        if wanted & {"media", "timeline", "clip", "layers", "captions", "library", "ui", "persistence", "export"}:
            run.import_media()
        for group, fn in [("timeline", run.timeline_ops), ("clip", run.clips), ("layers", run.layers),
                          ("captions", run.captions), ("library", run.library), ("knowledge", run.knowledge),
                          ("ui", run.ui), ("persistence", run.persistence), ("export", run.export),
                          ("services", run.services), ("edl", run.edl)]:
            if group in wanted:
                fn()
        if "stress" in wanted and options.stress:
            run.stress(options.stress)
    finally:
        counts = bench.write(folder, {"started": started, "app": rpc("app.version")})
        print(f"\n{counts}\nReport: {folder / 'report.md'}")
        try:
            if previous:
                rpc("project.open", {"path": previous, "saveCurrent": True})
        except RPCError as error:
            print(f"Could not reopen {previous}: {error}")
        if not options.keep:
            for path in folder.iterdir():
                if path.name not in ("report.json", "report.md"):
                    shutil.rmtree(path) if path.is_dir() else path.unlink()


if __name__ == "__main__":
    main()
