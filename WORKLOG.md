# WORKLOG

## 2026-07-24 — smoke test never actually ran; hardened the blanket path into a diagnostic

**Finding (corrects the record).** Today's 11:42 `UE4SS.log` shows the loader enumerating the game's
`ue4ss\Mods\` and starting `TFWWorkbench` + `TFWQuestHUDToggle` — but **not `TFWStaggerControl`**. The mod
was staged in MO2 but never *enabled*, so Root Builder didn't deploy it. The seam smoke test is therefore
still **unrun** — any "did I stagger?" impression from that session is meaningless for us. Staging itself is
correct (blanket mode, proper Root Builder layout, staged `main.lua` == repo).

**Changed `main.lua`** (grounded in the two working in-instance mods, FWStealth / TFWQuestHUDToggle):
- Fixed a real bug — hook module was `/Script/Engine.GameplayAbility` → **`/Script/GameplayAbilities.GameplayAbility`**.
- Added the BP-generated class path as a 2nd target (a BP-overridden `K2_ActivateAbility` is a *distinct*
  UFunction from the engine base, so the base hook may miss it).
- Made blanket mode **diagnostic-first**: logs every hit-reaction-ish activation (`activate: class=…`), and a
  `probe()` (`FindAllOf` on `GA_Player_HitReaction_C` + `FWPlayerGA_HitReaction`) runs on each ClientRestart.
  One launch now answers: (1) mod loads? (2) ability discoverable + real name? (3) does the hook fire on a hit?
- Install-once guard (ClientRestart was re-registering hooks every respawn → duplicate stacking).
- Suppression now `K2_CancelAbility` (fallback `K2_EndAbility`). `luac -p` clean; re-staged to MO2.

**Blocker unchanged, now teed up.** Enable TFWStaggerControl in MO2 (F5 → tick the box; MO2 is open so don't
touch `modlist.txt`), launch, take an explosion/melee hit, read `UE4SS.log`. The probe/activate lines decide
the next step: hook fires + stagger stops → finish the pak; hook never fires while you stagger → activation is
native → pivot to the montage hook or the loose-tag grant.

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
