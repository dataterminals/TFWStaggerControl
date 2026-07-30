# TFWStaggerControl

A two-part stagger mod for **The Forever Winter** (UE 5.4.2, build 24097213).

1. **Stop the stagger** — disable the player hit-reaction/stagger for specific damage types (explosions,
   heavy weapons, melee/knockdown, …), or all of them.
2. **Train against it** — a new skill-tree line that raises your resistance to being staggered: per-type
   immunity nodes, a graded shrug-off-chance line, and a full-immunity capstone.

> **Working name / draft copy.** `TFWStaggerControl` is a placeholder repo name and this README is
> engineering substance, not final public wording — the author writes the Nexus-facing name, descriptions,
> and node text.

## How it works (one sentence)

Player stagger is a GameplayAbility (`GA_Player_HitReaction`) that the game already gates behind a dormant
tag, **`Ability.HitReactionBlocked`** — nothing in the base game ever grants it. Both parts of this mod
control that one tag. Full mechanism + evidence: [`docs/design-notes.md`](docs/design-notes.md) ·
[`docs/findings.md`](docs/findings.md).

## Two deliverables

| | Deliverable | Needs UE4SS? | Does |
|---|---|---|---|
| **Skill tree** | static pak (`pak/` → `dist/`) | no | new resistance skill line grafted onto all 6 character roots; the full-immunity capstone works on pure data |
| **Per-type + graded** | UE4SS Lua (`ue4ss/`) | yes (RE-UE4SS via MO2) | one hook reads the incoming damage type + your owned skill tags and blocks stagger per-type / by % |

The pak stands alone. The Lua is an optional upgrade that unlocks per-type selectivity and graded % — the
things pure data can't express (damage type is decided in native code, and there's no stagger *attribute*).

## Status

**Part 1 (UE4SS) is proven in live fire. Part 2 (the pak) is not built yet.**

Intercepting `GA_Player_HitReaction` and cancelling it does stop player stagger — verified on an
independent machine across five tester rounds. Blanket mode cancelled 7/7 activations; per-type
**selective** mode cancelled 6/7 in its first outing, and v0.1.7 closes the one miss (the triggering
damage line can arrive on either side of the activation, and the previous build only looked one way).
Current test build: [`dist/TFWStaggerControl_v0.1.7_manual.zip`](dist/TFWStaggerControl_v0.1.7_manual.zip).

Damage families are classified from the damage-type class where it survives, and from the
`DamageCauser` actor where it doesn't — both paths have called every live hit correctly so far.

**Not suppressed, by design:** the physics launch that throws you ("fly away") and fall damage are
separate systems, out of the hit-react seam's reach. Possible future work, separate hunt.

The skill-tree pak is the remaining build work — `build.sh` steps 1–2 are ready, asset authoring
isn't. Round-by-round evidence and open questions: [`WORKLOG.md`](WORKLOG.md).

## Layout

| Path | Contents |
|---|---|
| `docs/` | design + mechanism (`design-notes.md`), raw datamine evidence (`findings.md`) |
| `ue4ss/TFWStaggerControl/` | the Lua layer — drop into RE-UE4SS `Mods/` (or deploy via MO2). `Scripts/config.lua` is user-editable |
| `pak/` | the static-pak source (skill-tree assets); built by `build.sh` |
| `tools/skillpatch/` | UAssetAPI grafter (from ScavgirlCarryPerks) + the extensions this mod needs |
| `tools/replay/` | offline harness: replays recorded tester timelines through `main.lua` with UE4SS stubbed |
| `build.sh` | decode → author → graft → `retoc` pack → verify |
| `dist/` | built pak output |

## Build

- **UE4SS layer:** no build. Copy `ue4ss/TFWStaggerControl/` into your RE-UE4SS `Mods/` (or take a
  ready-made zip from `dist/`). `Scripts/config.lua` ships `mode = "selective"`; `"blanket"` disables
  all combat stagger, `"off"` makes it a pure logger.
- **Decision logic:** `bash tools/replay/run.sh` replays recorded tester timelines through the real
  `main.lua` against a stubbed UE4SS — catches ordering/classification regressions without a launch.
- **Pak:** `bash build.sh` (needs `retoc`, the game, .NET 8 SDK, the datamine `.usmap`). Steps 1–2 are
  ready; the asset-authoring step (3–5) is the next work item — see `tools/README.md`.

## Credit / prior art

Built on the `forever-winter-datamine` toolkit; skill-graft technique and `skillpatch` from
[ScavgirlCarryPerks](../ScavgirlCarryPerks); modding vectors from FWBehaviorLab's field guide.
