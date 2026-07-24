# HANDOFF — read me first

*Bootstrap context for a fresh session opened with cwd = this repo. Self-contained on purpose: the
per-project memory is keyed to the old cwd (`H:\Github Repositories`) and does **not** follow into this
subfolder, so nothing below assumes memory. Deeper detail is in [`docs/`](docs/) and [`WORKLOG.md`](WORKLOG.md).*

## What this is

A two-part stagger mod for **The Forever Winter** (UE 5.4.2, build 24097213):
1. **Disable stagger** for specific damage types (explosions, heavy weapons, melee/knockdown, or all).
2. **A skill-tree line** that raises resistance to being staggered (per-type immunity + graded %% + a
   full-immunity capstone).

Repo is **public**: https://github.com/dataterminals/TFWStaggerControl (`master`, in sync, 2 scaffold commits
+ this handoff).

## The one load-bearing finding (do NOT re-derive — it's proven)

Player stagger is a GameplayAbility, **`GA_Player_HitReaction`** (native parent `FWPlayerGA_HitReaction`,
`/Script/FWPlayer`), triggered by GameplayEvent `Event.HitReaction.Player.Weapon`. It ships
`ActivationBlockedTags = ["Ability.HitReactionBlocked"]` — a dormant tag **nothing in the base game grants**
(verified: appears in exactly one decoded asset). **Own that tag → no stagger. Both parts control it.**

Three things this rules out:
- **Amount thresholds are dead.** `BP_PlayerBase` `StaggerDamageThreshhold`/`Low…`/`Tiny…` are all `999999`.
- **No stagger/poise attribute exists** (exhaustive grep empty). So a skill GE can't *scale* resistance — it
  can only grant tags.
- **Damage type = class identity, not a flag.** `FWKnockDownDamageType` (staggers) vs `FWGameDamageType`
  (normal); no `bStagger` bool; weapons have no `DamageTypeClass` field. → per-type selectivity is a native
  decision, so it **must** be done at runtime (UE4SS), not in a static pak.

Full evidence: [`docs/findings.md`](docs/findings.md). Architecture + rationale: [`docs/design-notes.md`](docs/design-notes.md).

## Architecture (one seam, two deliverables)

- **Static pak (no dependency)** — the skill tree: new `FWSkillDefinition` nodes grafted onto all 6 character
  roots. Per-type + %% nodes grant `PlayerSkill.Global.StaggerResist.*` tags (UE4SS honors them); a
  **full-immunity capstone** grants `Ability.HitReactionBlocked` directly, so it works with **no UE4SS**.
- **UE4SS Lua (optional upgrade)** — one hook on `GA_Player_HitReaction` reads the incoming damage type +
  owned skill tags and blocks per-type / by %. `mode="blanket"` = disable all stagger (the pak-only equivalent
  and the seam smoke-test).

## Current state (2026-07-24)

| Piece | State |
|---|---|
| Docs (`design-notes.md`, `findings.md`) | ✅ done |
| UE4SS layer (`ue4ss/TFWStaggerControl/Scripts/{main,config}.lua`) | ✅ first cut, `mode="blanket"`, **unverified** |
| `tools/skillpatch/` (UAssetAPI grafter from ScavgirlCarryPerks) | ✅ copied; needs clone-and-edit + DataTable-append extension |
| Pak build (`build.sh`) | ⚠️ steps 1–2 ready; asset-authoring (3–5) not built |
| **Staged on MO2** | ✅ `H:\MO2Instance_ModData\ForeverWinter\mods\TFWStaggerControl\` (Root Builder mod) — **not yet enabled** (MO2 was open; `modlist.txt` untouched) |
| **In-game verification** | ❌ **none — this is the blocker** |

## THE immediate next action — the 2-minute smoke test

Everything downstream assumes owning `Ability.HitReactionBlocked` actually stops stagger. Prove it first:

1. In MO2 (instance **The Forever Winter**, profile **Default**): **F5** to refresh, tick **TFWStaggerControl**
   (near the `TFWWorkbench`/`RE-UE4SS` cluster). `config.lua` is already `mode="blanket"`.
2. Launch through MO2 (Root Builder `autobuild` copies it into `Binaries\Win64` on launch).
3. Take an explosion / melee hit — **do you still stagger?**

**Read the log** MO2 catches at:
`H:\MO2Instance_ModData\ForeverWinter\overwrite\Root\Windows\ForeverWinter\Binaries\Win64\ue4ss\UE4SS.log`
- Look for `Mod 'TFWStaggerControl' has enabled.txt, starting mod`, then `[TFWStaggerControl] loaded. mode=blanket`
  and `hooked …` vs `FAILED to hook …`.

**Interpreting it:**
- No stagger in-game → seam confirmed → **finish the pak** (extend `skillpatch`: clone-and-edit + DataTable
  row append; author the `GE_/SD_` StaggerResist assets; graft the 6 roots; `retoc` pack + `verify`) and lock
  the hook target in `main.lua`.
- `FAILED to hook`, or hooks register but you still stagger → the hook UFunction target is wrong (expected on
  first try — see the `>>> CONFIRM ON-BOX` markers in `main.lua`). Fix via `dump_object` on a live
  `GA_Player_HitReaction_C` (ConsoleCommandsMod) to find the real activation function, then re-hook.

## Where everything lives (absolute paths — sibling repos, not in this cwd)

- **Decode any asset:** `cd "H:/Github Repositories/forever-winter-datamine" && python -m fwdata get <AssetName>`
  → JSON at `datamine/decoder/out/cache/24097213/dump/misc/<AssetName>.json`. Master asset list:
  `datamine/decoder/out/filelist.txt`. (Use specific names; a broad substring decodes hundreds.)
- **Prior art:** `H:/Github Repositories/ScavgirlCarryPerks` (the `skillpatch` graft + `docs/design-notes.md`);
  `H:/Github Repositories/FWBehaviorLab/docs/field-guide.md` (the two modding vectors);
  `FWBehaviorLab/mods/FWStealth` (Lua-mod layout analog).
- **Build toolchain:** `.NET` SDK 8 + 10; `retoc.exe` at `H:/Github Repositories/UnkillablesRebalanceFix/tools/retoc/retoc.exe`;
  AES `0x84B2244BE0AF90C22976D739FA0665569219F4CEA119CEA37C81F2D9ABEE4795`;
  usmap `H:/Github Repositories/forever-winter-datamine/datamine/mappings/ForeverWinter-5.4.2.usmap`.
- **Game:** `H:\SteamLibrary\steamapps\common\The Forever Winter`. **MO2 instance data:** `H:\MO2Instance_ModData\ForeverWinter`.

## Quick asset reference

- Roots (graft targets): `SD_Skill_EarlyAccess_{ScavGirl_ROOT, OldMan_Root, BagMan_Root, Gunhead_Root,
  MaskMan_Root, Shaman_Root}` under `/Game/FW/Player/Skills/EarlyAccessTrees/<Char>/`. All 6 needed (Gunhead's
  root omits the shared Global lines).
- `FWSkillDefinition` fields: `SkillName`, `SkillDescription`, `SkillTexture`, `ChildSkills`, `ValueOfXP`,
  `SkillEffects` (→ `GE_*_C`), `SkillTag`. Tag-granting GE pattern = `GE_Skill_Global_Stamina_Lvl_01`
  (`InheritableGrantedTagsContainer`, `DurationPolicy Infinite`, no modifiers). Enum typo to copy verbatim:
  `EGameplayModOp::Multiplicitive`.
- Skill tags register in `DT_PlayerSkillTags` (270-row `GameplayTagTableRow`).
- Cost curve: Stamina 2500 → 8125 → … → 43125 (5 tiers); flat 2000 for weapon-expert/rig.
- Damage families → classes: explosive `BP_ExplosiveDamage_FW(_knockback)`, `…GrenadeLauncher…`; heavy
  `BP_TankMainGunDamage_FW`, `BP_TurretProjectileDamage_FW`; melee/knockdown `BP_MeleeDamage_FW`,
  `BP_DamageType_AssaultInfantry(_Knockdown)`; ballistic `BP_ProjectileDamage_FW`, `BP_ShotgunDamage_FW`.

## Decisions still owned by Deni (don't invent these)

Node **names / descriptions / icons**; the **cost curve** (deep Stamina-style vs flat); number of **%% tiers**;
whether to also ship a pak **"blanket always-on"** toggle variant.

## Gotchas

- **Memory doesn't follow** to this cwd — re-save any durable facts in this session's own namespace; this doc
  is the source of truth meanwhile.
- **Windows git:** global `autocrlf=true` (`.gitattributes` here keeps `*.sh`/`*.lua` LF); commit with
  `git commit -F <file>` — PowerShell mangles `-m "…"`.
- **Never edit `modlist.txt` while MO2 is open** (it rewrites on close). Enable via the checkbox instead.
- **Root Builder** copy-mode has a cache/backup that can permanently restore files into the game folder —
  don't "Clear/rebuild" it casually. Adding a mod (what we did) is safe.
- **Multiplayer:** TFW is host-authoritative over EOS P2P; confirm client-side suppression affects only the
  local player.
- **Game dir is clean by design** — read the MO2 mod store, never the game folder, to see what's installed.
