# pak/ — the static-pak deliverable (the skill tree)

This is the no-dependency half: new `FWSkillDefinition` nodes + `GE_Skill` effects grafted onto all six
character skill-tree roots. Built by [`../build.sh`](../build.sh) via `retoc` + `skillpatch`.

- `staging/` — build scratch (extracted templates, work-in-progress cook). Gitignored.
- Output lands in `../dist/TFWStaggerControl/` as a `_P.{pak,ucas,utoc}` triple.

## What gets authored here (assets to create)

New package: `/Game/FW/Player/Skills/ActiveCharacters/Global/GlobalSkills/StaggerResist/`

| Asset | Purpose | Grants |
|---|---|---|
| `GE_Skill_Global_StaggerResist_Immunity` | pak-only full-immunity capstone effect | `Ability.HitReactionBlocked` (real; works with no UE4SS) |
| `GE_Skill_Global_StaggerResist_Type_Explosive` / `_Heavy` / `_Melee` | per-type immunity effects | `PlayerSkill.Global.StaggerResist.Type.*` (UE4SS honors) |
| `GE_Skill_Global_StaggerResist_Chance_0N` | graded % effects | `PlayerSkill.Global.StaggerResist.Chance_0N` (UE4SS honors) |
| `SD_Skill_Global_StaggerResist_*` | the skill nodes pointing at the GEs above | (their `SkillTag`) |

Each new `SkillTag` must also be appended as a row to `DT_PlayerSkillTags` (see `../docs/findings.md`).

## Naming / cost conventions (from the shipped tree)

- `SkillTag` namespace: `PlayerSkill.Global.StaggerResist.*` (mirrors `PlayerSkill.Global.Stamina_01`).
- `ValueOfXP`: follow the Stamina curve (2500 → 8125 → … → 43125) for a "deep investment" line, or a flat
  2000/tier (weapon-expert style) for a cheaper line. **The author sets the final costs + names + icons.**
- Graft target: each root's `ChildSkills` (all 6 — Gunhead's root omits the shared Global lines).

> The clone-and-edit asset authoring (step 3 in `build.sh`) needs a small extension to `skillpatch`
> — see [`../tools/README.md`](../tools/README.md). Until then, the fastest in-game proof of the whole
> approach is the UE4SS layer in `blanket` mode (no build required).
