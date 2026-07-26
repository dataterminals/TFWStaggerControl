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

**Scaffolded; not yet game-verified.** The design is statically airtight but the core seam (owning
`Ability.HitReactionBlocked` actually stops stagger) needs an in-game smoke test — see
[`WORKLOG.md`](WORKLOG.md) for the 2-minute test and the open questions.

## Layout

| Path | Contents |
|---|---|
| `docs/` | design + mechanism (`design-notes.md`), raw datamine evidence (`findings.md`) |
| `ue4ss/TFWStaggerControl/` | the Lua layer — drop into RE-UE4SS `Mods/` (or deploy via MO2). `Scripts/config.lua` is user-editable |
| `pak/` | the static-pak source (skill-tree assets); built by `build.sh` |
| `tools/skillpatch/` | UAssetAPI grafter (from ScavgirlCarryPerks) + the extensions this mod needs |
| `build.sh` | decode → author → graft → `retoc` pack → verify |
| `dist/` | built pak output |

## Build

- **UE4SS layer:** no build. Copy `ue4ss/TFWStaggerControl/` into your RE-UE4SS `Mods/`. Set
  `Scripts/config.lua` `mode = "blanket"` first to smoke-test, then `"selective"`.
- **Pak:** `bash build.sh` (needs `retoc`, the game, .NET 8 SDK, the datamine `.usmap`). Steps 1–2 are
  ready; the asset-authoring step (3–5) is the next work item — see `tools/README.md`.

## Credit / prior art

Built on the `forever-winter-datamine` toolkit; skill-graft technique and `skillpatch` from
[ScavgirlCarryPerks](../ScavgirlCarryPerks); modding vectors from FWBehaviorLab's field guide.
