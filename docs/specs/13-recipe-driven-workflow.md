# 13 — Recipe-driven workflow, checklist and audits

Status: accepted (2026-10-09). Repos: `bash-cut`, `bashcut-agent-kit`, `bashcut-plugins`.

## 1. Why

A one-prompt run (an ad for a channel, `lesson/lesson-1.md`) shipped a draft with "two messages" and an ending that
did not answer the hook, while the agent reported it as passing. The causes were structural, not missing rules:

| Seen | Cause |
|---|---|
| Stage skills skipped, nothing noticed | Skill reads are self-reported (`run append stage`), never checked |
| `review run` said 0 issues with an empty profile | `ReviewSummary.passed` is `errors == 0`; `unsetLimits` is reported but does not affect it |
| "Two messages", ending ≠ hook | Only a fresh critic caught it, and the critic is optional ("when you can") |
| `bashcut.vlog:product-ad` missed | Plugin skills are not Claude Code skills; reaching one takes 3 hops (`edit-workflow` → `vlog:plan` → recipe table), each skippable |
| Recipe rules forgotten by stage 7–10 | They live only in the agent's context, read once at the start |
| Guessed channel name and subject | The kit says "never end a turn on a question"; `product-ad` says "ask, never guess" |
| No stop at all | Every gate `skip` by default, and nothing replaces a skipped gate |

## 2. Principles

1. **One engine, many recipes.** `bc:edit-workflow` runs every edit (stages, gates, checklist, audits). A recipe
   (any plugin skill: `bashcut.vlog:product-ad`, `:food`, `:tutorial`, a future `bashcut.mv:*`) never re-implements
   the process; it writes **data** into the plan that the engine and the critic read.
2. **Recipes are optional.** With no plugin the engine runs with the kit's defaults and generic checks, and says
   which recipe would add more.
3. **Load just in time.** The agent never loads all skills. It reads one recipe at intake and one stage skill per
   stage; `context get` tells it which. Rules that must outlive the context window live in project data.
4. **The tool records facts; the agent does not certify itself.** Skill reads, gate events and audit verdicts are
   written by BashCut (or a hook), not claimed by the agent. A "done" without evidence is not done.
5. **Flexible, not blocking by default.** Only two things block (§7). Everything else is reported.

## 3. Entry points

| The user | Path |
|---|---|
| names a recipe ("dùng bashcut.vlog:product-ad", or a slash command, §9) | recipe → writes plan data → `bc:edit-workflow` from stage 1 |
| asks generally ("làm video quảng cáo cho kênh X") | `bc:edit-workflow` stage 0 picks the recipe from its routing table (§8) and reads it with `skills get` |
| has no plugin | `bc:edit-workflow` with kit defaults; the hand-off report names the missing recipe (`plugins search`) |

`bashcut.vlog:plan` stays the recipe picker for vlogs; the routing table in the kit only maps a request to a plugin
skill name and is the same few lines for every plugin.

## 4. Plan fields a recipe writes

All optional, all inside `plan` (free-form today, `ProjectPlan.validateNotes` only requires an object). A recipe
writes only what differs from the defaults, so plans stay small.

```json
{
  "recipe": {"skill": "bashcut.vlog:product-ad", "version": "0.0.1"},
  "promise": {"hook": "Can one prompt cut a whole ad?", "payoff": "Yes — follow @handle for the next one"},
  "stages": {
    "voiceover": {"required": true},
    "motion-graphics": {"required": true, "why": "price card, CTA card"},
    "captions": {"rules": ["no captions while a title or card is on screen"]},
    "colour": {"required": false, "why": "screen recording"}
  },
  "checks": [
    {"id": "one-message", "text": "The video says one thing", "source": "kit"},
    {"id": "cta-handle", "text": "@handle and logo visible in the last 3 s", "source": "bashcut.vlog:product-ad"}
  ],
  "askAtIntake": ["truthSource", "placement", "channelName"]
}
```

- `promise` is generic (every video opens a question and must close it), not an ad field. The kit's critic checks it
  for every recipe; this replaces the ad-only "hook and CTA as a pair".
- `stages` keys are the stage ids of §5. `required: false` with `why` marks a stage `n/a` up front.
- `checks`: at most ~8 per recipe, one line each. The kit's generic checks (§6) are always added; a recipe adds only
  its own.
- `askAtIntake`: brief fields the recipe will not guess (§8).

`ProjectPlan.summary` (in `context get`) adds `recipe.skill`, `promise`, the count of `checks` and the stages marked
required or `n/a`, so the rules survive a context reset without re-reading the recipe.

## 5. Checklist

The checklist is **derived**, not hand-written: BashCut builds it from the plan and the run log. New read command
`run checklist` (also a compact form in `context get` › `workflow.checklist`):

```json
{"stages": [
  {"id": "survey", "skill": "bc:footage-survey", "skillRead": true, "status": "done",
   "evidence": ["survey/contact-sheet.png", "media transcribe job 41"]},
  {"id": "voiceover", "skill": "bc:voiceover", "skillRead": false, "status": "skipped",
   "reason": "user supplied speech", "required": true},
  {"id": "colour", "status": "n/a", "reason": "screen recording", "by": "recipe"}
],
 "audits": {"strategy": "changes", "draft": null, "process": null},
 "open": ["voiceover: required stage skipped", "draft audit missing"]}
```

| Field | Written by |
|---|---|
| `skill`, `required`, `n/a` | the plan (recipe) or the kit's stage table |
| `skillRead` | BashCut / the hook (§6.1) — never the agent |
| `status`, `evidence`, `reason` | the agent: `run append stage --stage S --status done\|skipped --evidence "a;b" [--reason]` |
| `audits` | the auditor's `run append audit` (§6.2) |

Rules: `done` without `--evidence` is stored as `unverified`; `skipped` needs `--reason`. `open` lists what still
needs attention; the hand-off report starts from it.

Stage ids (fixed, matching the kit's table): `intake, survey, story, rough-cut, rhythm, voiceover, sound, captions,
colour, effects, review, export, learn`.

## 6. What makes it trustworthy

### 6.1 Skill reads recorded by the tool

- **Plugin skills:** `skills.get` appends `{kind: "skill", name, origin, author}` to the run log
  (`ProjectDocument+Skills.swift`). Same pattern as gate entries today.
- **Kit skills** are Claude Code skills, invisible to BashCut. The kit plugin ships a `PostToolUse` hook on `Skill`
  (matcher `bc:.*`) that runs `bashcut run append skill --name <skill>`. Agents without hooks (Codex, chat agents)
  fall back to `run append skill` themselves, stored with `verified: false`.
- `run append` refuses `kind: skill` from an agent when the hook path is available (same as `gate`).

### 6.2 Three audits by a fresh agent

| Point | Packet | Checks |
|---|---|---|
| **strategy** — after stage 2 | brief, plan (options, promise, sections), story sheet | one message, `promise.payoff` answers `promise.hook`, fits the brief, recipe checks that apply to a plan |
| **draft** — stage 10 | `review packet` (exists) + `plan.checks` | generic checks + recipe checks, as a viewer |
| **process** — stage 12 | `run checklist`, `run log`, `timeline changes` | skipped required stages, `done` without evidence, claims in the summary not backed by the log; writes the lessons for `bc:self-learn` |

- `review packet --point strategy|draft|process` builds each folder; the auditor gets only the folder and `bc:review`.
- The verdict: `run append audit --point P --verdict pass|changes|fail --findings N --by critic`.
- **A gate set to `skip` is replaced by its audit:** G2 skip → strategy audit required; G5 skip → draft audit required.
  With `ask`/`notify` the audit still runs (cheap) and its verdict goes in the gate summary.
- No sub-agent available: the agent runs the audit itself from the packet only and the verdict is stored
  `by: self`, shown as weaker in the checklist.

Generic checks (kit, every video): one message; `promise.payoff` answers `promise.hook`; text and speech in the
first 3 s say the same thing; understandable with sound off; captions never repeat on-screen text; nothing on
screen the brief did not ask for: no credits, no "AI voice", "minh hoạ", "stock" or effect labels.

### 6.3 Review result with three states

`ReviewSummary` gets `status: pass | fail | incomplete`:

- `fail`: `errors > 0`.
- `incomplete`: no errors but `unsetLimits` or `notChecked` is not empty — the editorial checks did not run.
- `pass`: neither.

`passed` stays for compatibility and equals `status == "pass"` (today it is `errors == 0`). CLI exit code: 0 pass,
1 fail, 2 incomplete.

## 7. What blocks

Only two guards, both for agent authors; the user in the app is never blocked:

1. `export start` with a non-draft preset: needs a **draft** audit verdict `pass` (or one the user overrode at G5)
   for the current revision range. Error `audit_missing` with `remediation.command: "review packet --point draft"`.
2. `checkpoint request G2`, or the first `rough-cut` stage entry when G2 is `skip`: needs the recipe skill read when
   `plan.recipe` is set, and a **strategy** audit. Error `recipe_unread` / `audit_missing`.

Everything else (skipped stages, missing evidence) lands in `run checklist` › `open` and the hand-off report.

## 8. Intake: ask once

Replaces both "never end a turn on a question" (kit) and "ask, never guess" (recipes):

- Before `project create`, one round of at most 4 questions: what the prompt does not say among language, platform,
  length, and the recipe's `askAtIntake` fields.
- No answer (the user is away, or said "don't ask"): decide, write the field as `inferred` in the brief, and add it to
  the strategy audit's packet so the critic checks the guess. Never ask again later.
- Routing table in `bc:edit-workflow` stage 0, a few lines per plugin, no recipe content:

| Request | With the plugin | Without |
|---|---|---|
| ad, TVC, "quảng cáo", "video bán hàng" | `bashcut.vlog:product-ad` | kit defaults |
| vlog, trip, food, a day, review, tutorial, podcast clips | `bashcut.vlog:plan` (picks the recipe) | kit defaults |

## 9. Context budget

- `bc:edit-workflow` shrinks: tool rules (`--base-rev`, errors, scope, permissions, no ffmpeg) move to
  `AgentInstructions.swift`, which every agent gets from the MCP server regardless of the entry skill.
- A recipe skill states its own rules and the plan data it writes; it does not repeat the process.
- `context get` › `workflow.next`: `{stage, skill, skillRead}` — the one skill to read now.
- Optional, later: `agent kit-update` exposes enabled plugin skills' descriptions to Claude Code
  (`/bc-vlog:product-ad`), so a request can match a recipe directly.

## 10. Work

**Phase 1 — kit and plugins (text only)**
- `bashcut-agent-kit`: `edit-workflow` (routing table, plan fields, checklist commands, three audits, intake rule),
  `review` (status, mandatory critic, strategy and process packets, generic checks), `captions-text` (no captions over
  titles or cards; `captions group --source heard` after cuts), `rough-cut` (cut on `resolve-range`, no manual
  padding), `audio-mix` (normalization limit on camera-mic speech: lower gain per loud line).
- `bashcut-plugins/vlog`: `plan` writes `recipe`, `promise`, `stages`, `checks`, `askAtIntake`; every recipe gets a
  short "Plan data" section (product-ad first: channel teaser arc, channel name/@handle/logo in the brief);
  `hook-script` defines `promise`.
- Until Phase 2 lands, the kit's commands degrade: `run checklist` missing → the agent keeps the checklist in
  `project set-data checklist` and the process audit reads it.

**Phase 2 — `bash-cut`**
- `skills.get` logs reads; `run append` accepts `status/evidence/reason` on `stage`, and kinds `skill`, `audit`.
- `run checklist`; `context get` › `workflow.checklist`, `workflow.next`; `ProjectPlan.summary` adds §4 fields.
- `review packet --point`; `ReviewSummary.status`; the two guards of §7.
- Kit plugin hook (`bashcut-agent-kit/hooks/hooks.json`).
- Lesson fixes: re-transcribe after a codec conversion (proxy job invalidates the transcript); removing linked
  audio never removes its video; a limiter for speech normalization.

**Phase 3**
- Move tool rules from `edit-workflow` to `AgentInstructions.swift`; optional plugin-skill exposure (§9).

**Verify:** re-run the lesson-1 prompt on a fresh project, once with the vlog plugin and once without; expect a
strategy audit that flags two messages before the rough cut, `review run` `incomplete` on an empty profile, and a
checklist with no `done` lacking evidence.

## 11. Decisions

1. The §7 guards apply whatever `agentPermissions` say (`allowAll` included): they are about quality, not
   permission. The user overrides by approving G5 in the app.
2. Recipe `checks` stay ≤ 8 per recipe; user-defined checks are later work (`knowledge set-pref checks`).
3. A self-run audit (`by: self`) satisfies the §7 guards, so the run never stalls without sub-agents, but the
   checklist and the hand-off report mark it as self-audited.
4. Re-transcribing after a codec conversion waits for the conversion work on `feat/one-prompt-quality`
   (`MediaConverter`), which owns that code path.
