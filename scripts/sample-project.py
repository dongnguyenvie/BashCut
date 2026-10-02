#!/usr/bin/env python3
"""Build the BashCut sample project, a timeline that shows every kind of thing the editor draws, and check it.

    scripts/sample-project.py make     # generate media, build the project through the bashcut CLI, check it
    scripts/sample-project.py check    # only re-run the checks against the open sample project
    scripts/sample-project.py open     # open an existing sample project in BashCut

The project is built in the running app (it is launched from build/BashCut.app when needed) with the same
commands agents use, so `make` doubles as an end-to-end test of the automation surface. Media is generated with
ffmpeg; nothing here is committed. The default folder is build/sample-project/bashcut-sample.

What the timeline covers (see docs/guides/sample-project.md):
  Main      linked clips with sound (link icon, speech/underVO colors), a LUT and color grade, a reframed
            landscape clip, a dissolve, a freeze frame, a 2x clip with muted sound, a gap, a 4K HEVC clip that
            gets a proxy (skip with --light)
  Overlay   a picture-in-picture clip; a locked overlay layer and a hidden one
  Text      a title and SRT captions
  Audio     dialogue (linked), voiceover (one take overlaps speech: red warning), music with beat grid, ducking
            and fades, SFX on a muted layer
  Project   three sections, one agent-changed clip (sparkle) after reopening
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP = REPO / "build" / "BashCut.app"
CLI = APP / "Contents" / "MacOS" / "bashcut"
NAME = "BashCut Sample"
# The folder `project create` makes for NAME.
FOLDER = "bashcut-sample"
FPS = 30
# Marks a folder this script made, so `make` never deletes anything else.
MARKER = ".bashcut-sample"


# MARK: CLI


def bashcut(*args, check=True):
    """Runs the bashcut CLI and returns its JSON result (or text)."""
    result = subprocess.run([str(CLI), *map(str, args)], capture_output=True, text=True)
    if check and result.returncode != 0:
        sys.exit(f"bashcut {' '.join(map(str, args))} failed:\n{result.stderr or result.stdout}")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return result.stdout.strip()


def rev():
    return bashcut("context", "get")["rev"]


def apply(label, ops):
    """Applies operations as one undoable edit."""
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as file:
        json.dump(ops, file)
    try:
        return bashcut("timeline", "apply", file.name, "--base-rev", rev(), "--label", label)
    finally:
        os.unlink(file.name)


def ensure_app():
    if not CLI.exists():
        sys.exit("build/BashCut.app is missing: run scripts/run.sh first")
    if subprocess.run([str(CLI), "context", "get"], capture_output=True).returncode == 0:
        return
    subprocess.run(["open", str(APP)], check=True)
    for _ in range(60):
        if subprocess.run([str(CLI), "context", "get"], capture_output=True).returncode == 0:
            return
        time.sleep(0.5)
    sys.exit("BashCut did not start; open build/BashCut.app and try again")


def wait_idle(timeout=60):
    """Waits for imports and other busy work to finish."""
    deadline = time.time() + timeout
    while bashcut("context", "get")["busy"]:
        if time.time() > deadline:
            sys.exit("BashCut stayed busy")
        time.sleep(0.3)


# MARK: Media


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args], check=True)


def make_media(folder: Path, heavy: bool):
    """Short synthetic clips: portrait and landscape video with sound, silent video, picture-in-picture, 4K HEVC,
    music with a 120 BPM click, voiceover, two sound effects, captions and a LUT."""
    folder.mkdir(parents=True, exist_ok=True)
    h264 = ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "veryfast"]
    aac = ["-c:a", "aac", "-b:a", "96k"]
    ffmpeg("-f", "lavfi", "-i", f"testsrc2=size=540x960:rate={FPS}", "-f", "lavfi",
           "-i", "sine=frequency=330:sample_rate=48000:beep_factor=4", "-t", "10", *h264, *aac, "-shortest",
           folder / "a-roll-portrait.mp4")
    ffmpeg("-f", "lavfi", "-i", f"smptehdbars=size=1280x720:rate={FPS}", "-f", "lavfi",
           "-i", "sine=frequency=550:sample_rate=48000", "-t", "10", *h264, *aac, "-shortest",
           folder / "a-roll-landscape.mp4")
    ffmpeg("-f", "lavfi", "-i", f"mandelbrot=size=540x960:rate={FPS}", "-t", "8", *h264, folder / "b-roll-silent.mp4")
    ffmpeg("-f", "lavfi", "-i", f"rgbtestsrc=size=480x480:rate={FPS}", "-t", "6", *h264, folder / "pip.mp4")
    ffmpeg("-f", "lavfi", "-i", f"cellauto=size=540x960:rate={FPS}", "-t", "6", *h264, folder / "overlay-locked.mp4")
    if heavy:
        ffmpeg("-f", "lavfi", "-i", f"testsrc2=size=3840x2160:rate={FPS}", "-t", "3", "-c:v", "libx265",
               "-tag:v", "hvc1", "-pix_fmt", "yuv420p", "-preset", "ultrafast", folder / "b-roll-4k-hevc.mp4")
    # A click every half second (120 BPM) over a low pad, so beat detection and the beat grid line up.
    ffmpeg("-f", "lavfi", "-i",
           "aevalsrc='0.25*sin(2*PI*110*t)+0.6*sin(2*PI*1000*t)*exp(-60*mod(t\\,0.5))':s=48000:d=40",
           *aac, folder / "music-120bpm.m4a")
    ffmpeg("-f", "lavfi", "-i", "sine=frequency=220:sample_rate=48000:beep_factor=2", "-t", "5", *aac,
           folder / "voiceover.m4a")
    ffmpeg("-f", "lavfi", "-i", "anoisesrc=d=1:c=pink:a=0.4", "-af", "afade=t=out:st=0.2:d=0.8", *aac,
           folder / "sfx-whoosh.m4a")
    ffmpeg("-f", "lavfi", "-i", "sine=frequency=1320:sample_rate=48000", "-t", "0.6", "-af",
           "afade=t=out:st=0:d=0.6", *aac, folder / "sfx-ding.m4a")
    (folder / "captions.srt").write_text(
        "1\n00:00:02,000 --> 00:00:04,000\nXin chào! This is the BashCut sample\n\n"
        "2\n00:00:04,500 --> 00:00:07,000\nEvery layer kind is on this timeline\n\n"
        "3\n00:00:09,000 --> 00:00:12,000\nDrag, trim, split and zoom around\n\n"
        "4\n00:00:22,000 --> 00:00:25,000\nCaptions come from captions.srt\n", encoding="utf-8")
    write_lut(folder / "warm-look.cube")


def write_lut(path: Path, size=9):
    """A warm look: lifts red, trims blue."""
    lines = ['TITLE "Warm look"', f"LUT_3D_SIZE {size}"]
    for b in range(size):
        for g in range(size):
            for r in range(size):
                red, green, blue = (v / (size - 1) for v in (r, g, b))
                lines.append(f"{min(1, red * 1.08 + 0.02):.6f} {green:.6f} {blue * 0.88:.6f}")
    path.write_text("\n".join(lines) + "\n")


# MARK: Timeline


def build(project_dir: Path, heavy: bool):
    media_dir = project_dir / "media"
    ids = {}
    files = ["a-roll-portrait.mp4", "a-roll-landscape.mp4", "b-roll-silent.mp4", "pip.mp4", "overlay-locked.mp4",
             "music-120bpm.m4a", "voiceover.m4a", "sfx-whoosh.m4a", "sfx-ding.m4a"]
    if heavy:
        files.append("b-roll-4k-hevc.mp4")
    for file in files:
        kind = "audio" if file.endswith(".m4a") else "video"
        ids[file] = bashcut("media", "import", media_dir / file, "--kind", kind, "--base-rev", rev())["media"]
        wait_idle()
    bashcut("luts", "import", media_dir / "warm-look.cube", "--name", "Warm look", "--base-rev", rev())
    lut_id = bashcut("project", "get")["luts"][0]["id"]

    def clip(item_id, media, at, dur, source_in=0, **fields):
        return {"id": item_id, "media": ids[media], "at": at, "dur": dur, "in": source_in, **fields}

    def linked(video_id, audio_id, media, at, dur, source_in=0, video=None, audio=None):
        """A picture item on Main and its sound on Dialogue, inserted together."""
        return [
            {"op": "insert", "track": "v1",
             "item": clip(video_id, media, at, dur, source_in, linkedAudio=audio_id, **(video or {}))},
            {"op": "insert", "track": "a1",
             "item": clip(audio_id, media, at, dur, source_in, linkedVideo=video_id, **(audio or {}))},
        ]

    # Main: 0-240 portrait (speech, LUT), 240-420 landscape (reframed), 420-600 silent (underVO, freeze frame),
    # gap 600-660, 660-750 landscape at 2x with muted sound, 750-840 4K HEVC.
    main = (
        linked("m1-portrait", "d1-portrait", "a-roll-portrait.mp4", 0, 240,
               video={"tag": {"role": "speech"},
                      "color": {"lut": lut_id, "lutStrength": 0.8, "exposure": 0.15, "saturation": 1.1}},
               audio={"tag": {"role": "speech"}})
        + linked("m2-landscape", "d2-landscape", "a-roll-landscape.mp4", 240, 180, 30,
                 video={"reframePreset": "custom", "transform": {"zoom": 1.35, "pan": 40, "tilt": 0}})
        + [{"op": "insert", "track": "v1",
            "item": clip("m3-silent", "b-roll-silent.mp4", 420, 180, 0, tag={"role": "underVO"}, freezeFrame=45)}]
        + [{"op": "insert", "track": "v1", "item": clip("gap-filler", "b-roll-silent.mp4", 600, 60, 0)}]
        + linked("m4-fast", "d4-fast", "a-roll-landscape.mp4", 660, 90, 60,
                 video={"speed": 2, "muted": True}, audio={"speed": 2, "muted": True})
    )
    if heavy:
        main.append({"op": "insert", "track": "v1", "item": clip("m5-4k", "b-roll-4k-hevc.mp4", 750, 90)})
    apply("Sample: main layer", main)
    # Deleting the filler without ripple leaves a gap on Main; the dissolve sits on the first cut.
    apply("Sample: gap and transition", [
        {"op": "delete", "item": "gap-filler", "ripple": False},
        {"op": "upsertTransition", "id": "dissolve-1", "kind": "dissolve", "from": "m1-portrait",
         "to": "m2-landscape", "duration": 12},
    ])

    end = 840 if heavy else 750
    apply("Sample: overlay, text and audio", [
        {"op": "insert", "track": "v2", "item": clip(
            "o1-pip", "pip.mp4", 120, 120, 0, opacity=0.9,
            transform={"zoom": 0.4, "pan": 260, "tilt": -520}, reframePreset="custom")},
        {"op": "insert", "track": "t1", "item": {
            "id": "title", "at": 0, "dur": 55, "in": 0, "text": "BASHCUT SAMPLE", "style": "hook-title"}},
        {"op": "insert", "track": "a2", "item": clip("vo1-overlap", "voiceover.m4a", 60, 120)},
        {"op": "insert", "track": "a2", "item": clip("vo2", "voiceover.m4a", 450, 120, 10)},
        {"op": "insert", "track": "a3", "item": clip(
            "music", "music-120bpm.m4a", 0, end, 0, volumeDb=-6, fadeIn=30, fadeOut=60)},
        {"op": "insert", "track": "a4", "item": clip("sfx-whoosh", "sfx-whoosh.m4a", 228, 24)},
        {"op": "insert", "track": "a4", "item": clip("sfx-ding", "sfx-ding.m4a", 655, 15)},
        {"op": "setBeatGrid", "media": ids["music-120bpm.m4a"], "bpm": 120,
         "frames": list(range(0, end + 1, FPS // 2)), "generatedBy": {"tool": "sample-project"}},
        {"op": "upsertSection", "id": "hook", "label": "Hook", "atFrame": 0},
        {"op": "upsertSection", "id": "body", "label": "Body", "atFrame": 240},
        {"op": "upsertSection", "id": "outro", "label": "Outro", "atFrame": 660},
    ])
    bashcut("captions", "import", media_dir / "captions.srt", "--base-rev", rev())

    # Extra overlay layers: one locked (stripes, refuses edits), one hidden (faded, left out of preview).
    locked = bashcut("layers", "add", "--kind", "video", "--role", "overlay", "--name", "Locked overlay",
                     "--base-rev", rev())["track"]
    hidden = bashcut("layers", "add", "--kind", "video", "--role", "overlay", "--name", "Hidden overlay",
                     "--base-rev", rev())["track"]
    apply("Sample: extra overlays", [
        {"op": "insert", "track": locked, "item": clip("o2-locked", "overlay-locked.mp4", 300, 150)},
        {"op": "insert", "track": hidden, "item": clip("o3-hidden", "pip.mp4", 480, 90)},
    ])
    bashcut("layers", "set", locked, "--locked", "true", "--base-rev", rev())
    bashcut("layers", "set", hidden, "--hidden", "true", "--base-rev", rev())
    bashcut("layers", "set", "a4", "--muted", "true", "--base-rev", rev())
    bashcut("project", "save")


# MARK: Checks


def check(project_dir: Path, heavy: bool):
    """End-to-end checks: the saved project has every case, and the editor actions work on it."""
    failures = []

    def expect(condition, message):
        print(("  ok   " if condition else "  FAIL ") + message)
        if not condition:
            failures.append(message)

    project = bashcut("project", "get")
    tracks = project["tracks"]
    items = {item["id"]: (track, item) for track in tracks for item in track["items"]}
    roles = [track.get("role") for track in tracks]

    print("Project")
    expect(Path(bashcut("context", "get")["project"]).parent == project_dir, "the sample project is open")
    expect(all(role in roles for role in ["main", "overlay", "captions", "dialogue", "voiceover", "music", "sfx"]),
           "every layer role is present")
    expect(len(project.get("luts", [])) == 1, "one LUT in the catalog")
    expect(items["m1-portrait"][1].get("color", {}).get("lut") == project["luts"][0]["id"], "m1 uses the LUT")
    expect(items["m1-portrait"][1].get("linkedAudio") == "d1-portrait", "m1 is linked to its sound")
    expect(items["m3-silent"][1].get("freezeFrame") == 45, "m3 holds a freeze frame")
    expect(items["m4-fast"][1].get("speed") == 2 and items["m4-fast"][1].get("muted") is True, "m4 is 2x and muted")
    expect("gap-filler" not in items, "the filler is gone")
    main = next(track for track in tracks if track.get("role") == "main")
    ends = sorted((item["at"], item["at"] + item["dur"]) for item in main["items"])
    expect(any(b[0] > a[1] for a, b in zip(ends, ends[1:])), "Main has a gap")
    expect(len(project.get("transitions", [])) == 1, "one transition")
    expect(len(project.get("markers", [])) >= 3, "three sections")
    captions = [item for track in tracks if track.get("kind") == "text" for item in track["items"]]
    expect(len(captions) >= 5, f"title and captions on text layers ({len(captions)})")
    expect(any(track.get("locked") for track in tracks), "a locked layer")
    expect(any(track.get("hidden") for track in tracks), "a hidden layer")
    expect(any(track.get("muted") for track in tracks), "a muted layer")
    music = next(track for track in tracks if track.get("role") == "music")
    expect(music.get("duckUnderSpeechDb") is not None, "music ducks under speech")
    expect(project.get("beatGrid", {}).get("media") == music["items"][0]["media"], "music has a beat grid")
    if heavy:
        expect(any(media.get("width") == 3840 for media in project["media"]), "a 4K HEVC clip (proxy candidate)")

    print("Review")
    review = bashcut("review", "run")
    issues = review.get("issues", review) if isinstance(review, dict) else review
    expect(any("vo1-overlap" in json.dumps(issue) for issue in issues), "voiceover overlapping speech is flagged")

    print("Editor actions")
    bashcut("ui", "action", "timeline.zoom-fit")
    expect(bashcut("ui", "view")["zoom"] > 0, "zoom to fit")
    bashcut("ui", "select", "m2-landscape")
    expect(bashcut("context", "get")["selection"] == "m2-landscape", "select a clip")
    bashcut("ui", "seek", 0)
    bashcut("ui", "action", "shift+right")
    expect(bashcut("context", "get")["playhead"] == FPS, "shift+right steps one second")
    base = rev()
    result = subprocess.run([str(CLI), "timeline", "move", "o2-locked", "--track", "v2", "--at-frame", "600",
                             "--base-rev", str(base)], capture_output=True, text=True)
    expect(result.returncode != 0 and rev() == base, "a locked layer refuses edits")
    def item_count():
        return sum(len(track["items"]) for track in bashcut("project", "get")["tracks"])

    before = item_count()
    bashcut("ui", "seek", 300)
    bashcut("ui", "action", "timeline.split")
    expect(rev() == base + 1 and item_count() == before + 2, "split at the playhead (clip and its sound)")
    bashcut("timeline", "undo", "--base-rev", rev())
    expect(item_count() == before, "undo removes the split")
    bashcut("ui", "select")
    bashcut("ui", "seek", 0)
    bashcut("project", "save")  # the split was undone; saving clears the unsaved flag

    if failures:
        sys.exit(f"\n{len(failures)} check(s) failed")
    print("\nAll checks passed.")


# MARK: Main


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("command", nargs="?", default="make", choices=["make", "check", "open"])
    parser.add_argument("--dir", type=Path, default=REPO / "build" / "sample-project",
                        help="parent folder (default: build/sample-project)")
    parser.add_argument("--light", action="store_true", help="skip the 4K HEVC clip (faster, no proxy)")
    parser.add_argument("--discard-current", action="store_true",
                        help="discard unsaved changes in the project open in BashCut")
    args = parser.parse_args()
    parent = args.dir.resolve()
    project_dir = parent / FOLDER
    heavy = not args.light
    ensure_app()

    if args.command == "open":
        bashcut("project", "open", project_dir / "project.bashcut.json",
                *(["--discard-current"] if args.discard_current else []))
        return
    if args.command == "check":
        heavy = any(media.get("width") == 3840 for media in bashcut("project", "get")["media"])
        check(project_dir, heavy)
        return

    if shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg is required: brew install ffmpeg")
    context = bashcut("context", "get")
    open_sample = bool(context.get("project")) and Path(context["project"]).is_relative_to(parent)
    if context.get("dirty") and not args.discard_current and not open_sample:
        sys.exit("The open project has unsaved changes: save it, or pass --discard-current")
    if parent.exists():
        if not (parent / MARKER).exists():
            sys.exit(f"{parent} exists and was not made by this script; pass another --dir")
        if open_sample:
            bashcut("project", "create", "--name", "scratch", "--dir", tempfile.mkdtemp(), "--discard-current")
        shutil.rmtree(parent)
    parent.mkdir(parents=True)
    (parent / MARKER).write_text("Made by scripts/sample-project.py; safe to delete.\n")

    print(f"Creating {project_dir}")
    bashcut("project", "create", "--name", NAME, "--dir", parent, "--canvas", "portrait", "--fps", "30",
            "--style", "custom", "--discard-current")
    if Path(bashcut("context", "get")["project"]).parent != project_dir:
        sys.exit(f"project create did not make {project_dir}")
    print("Generating media")
    make_media(project_dir / "media", heavy)
    print("Building the timeline")
    build(project_dir, heavy)
    print("Checking")
    check(project_dir, heavy)
    # Reopen so the agent markers from building and checking clear, then make one agent edit to show the
    # sparkle and the agent-change notice.
    bashcut("project", "open", project_dir / "project.bashcut.json")
    apply("Sample: agent touch-up", [
        {"op": "setProperties", "item": "m2-landscape", "patch": {"color": {"contrast": 1.1}}}])
    bashcut("project", "save")
    bashcut("ui", "action", "timeline.zoom-fit")
    print(f"\nOpen in BashCut: {project_dir}")


if __name__ == "__main__":
    main()
