# WORKLOG

## 2026-07-20 — recon + scaffold (build 24097213 / 0.9.3.9.2)

Decoded the player stagger + skill systems from the shipped paks (4-way parallel datamine investigation).
Key result: **both parts pivot on one dormant shipping tag, `Ability.HitReactionBlocked`**, listed in
`GA_Player_HitReaction.ActivationBlockedTags` and granted by nothing in the base game. Verified by hand:
that tag appears in exactly one decoded asset; `BP_PlayerBase` stagger thresholds are all `999999` (amount
path dead); no stagger/poise attribute exists. Full evidence in `docs/findings.md`.

Design locked (see `docs/design-notes.md`):
- **Part 2 (skill tree)** = static pak, works standalone. Per-type + %% nodes grant skill tags; a
  full-immunity capstone grants `Ability.HitReactionBlocked` directly (functions with no UE4SS). Graft onto
  all 6 roots via `skillpatch`.
- **Part 1 (per-type)** = UE4SS Lua, because damage-type is a native decision. One hook on the hit-react
  reads the type + owned skill tags and blocks accordingly. Blanket mode = the pak-only equivalent.

Scaffolded the repo: docs, the UE4SS layer (first-cut `main.lua` + user `config.lua`), `skillpatch` copied
from ScavgirlCarryPerks, `build.sh` skeleton, `pak/` + `tools/` READMEs. `git init` done (local only).

### NEXT — in priority order

1. **Smoke-test the seam (2 min, no build).** Copy `ue4ss/TFWStaggerControl/` into RE-UE4SS `Mods/`, leave
   `config.lua mode = "blanket"`, launch via MO2, walk into an explosion / get meleed. Do you still stagger?
   - If stagger stops → the whole design is validated; proceed.
   - If not → the hook target is wrong; use `dump_object` on a live `GA_Player_HitReaction_C` and confirm
     which activation UFunction fires (the `>>> CONFIRM ON-BOX` marks in `main.lua`).
2. **Confirm per-type payload.** In `selective` mode, check the console log prints a real damage-type class
   name per hit (`incoming_damage_type_name`). If the payload doesn't carry the type, fall back to reading
   the ASC's last damage context. This decides whether per-type is possible (design-notes open question #2).
3. **Extend `skillpatch`** with clone-and-edit + DataTable row append (see `tools/README.md`), then author
   the StaggerResist GE/SD assets and finish `build.sh` steps 3–5.
4. **Build + static-verify the pak** (`retoc verify`), then in-game: capstone node unlocks, persists, and
   actually grants immunity. Confirm a new `PlayerSkill.Global.StaggerResist.*` tag resolves from
   `DT_PlayerSkillTags` alone (else reuse a spare tag).
5. **Multiplayer check** — confirm client-side suppression affects only the local player and isn't
   host-corrected.

### Decisions still owned by Deni
- Final node names / descriptions / icons (human-facing copy).
- Cost curve (deep Stamina-style 2500→43125 vs flat 2000/tier) and number of %% tiers.
- Whether to ship the pak's "blanket always-on" toggle variant in addition to the skill-gated capstone.
