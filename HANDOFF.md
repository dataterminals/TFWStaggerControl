# HANDOFF — read me first

*Bootstrap context for a fresh session opened with cwd = this repo. Self-contained on purpose: the
per-project memory is keyed to the old cwd (the parent repos folder) and does **not** follow into this
subfolder, so nothing below assumes memory. Deeper detail is in [`docs/`](docs/) and [`WORKLOG.md`](WORKLOG.md).*

## What this is

A two-part stagger mod for **The Forever Winter** (UE 5.4.2, build 24097213):
1. **Disable stagger** for specific damage types (explosions, heavy weapons, melee/knockdown, or all).
2. **A skill-tree line** that raises resistance to being staggered (per-type immunity + graded %% + a
   full-immunity capstone).

Repo is **public**: https://github.com/dataterminals/TFWStaggerControl (`master`).

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

## Current state (2026-07-30)

| Piece | State |
|---|---|
| Docs (`design-notes.md`, `findings.md`) | ✅ done |
| UE4SS layer (`ue4ss/TFWStaggerControl/Scripts/{main,config}.lua`) | ✅ **v0.1.7, proven in live fire** — blanket 7/7, selective 6/7 then patched |
| `tools/replay/` (offline decision-logic harness) | ✅ replays recorded tester timelines against a stubbed UE4SS |
| `tools/skillpatch/` (UAssetAPI grafter from ScavgirlCarryPerks) | ✅ copied; **needs clone-and-edit + DataTable-append extension** |
| Pak build (`build.sh`) | ⚠️ steps 1–2 ready; asset-authoring (3–5) not built |
| **In-game verification (Part 1)** | ✅ five tester rounds on an independent machine |
| **In-game verification (Part 2)** | ❌ nothing to verify yet — the pak doesn't exist |

**Part 1 is done pending one confirmation round on v0.1.7.** Test builds ship as
`dist/TFWStaggerControl_v0.1.X_manual.zip` (game-root-relative tree + a plain-language install note);
the tester extracts to the game root, plays, and sends back `Binaries\Win64\ue4ss\UE4SS.log`.

### What Part 1 proved (so you don't re-litigate it)

- Cancelling `GA_Player_HitReaction` on activation **does** stop the stagger. Blanket cancelled 7/7.
- The BP-generated class path must be hooked, and **lazily** — the engine-base `K2_ActivateAbility`
  hook registers but never fires, and the BP class isn't loaded until the player pawn exists.
- **Damage family is recoverable**, which is what makes per-type control real: the damage-type class
  survives for knockdown/shotgun/fall/mech-melee hits, and where it's erased the `DamageCauser` actor
  names itself (`BP_WPN_<code>`, or the attacking pawn `BP_AI_*` for infantry melee).
- **The trigger event's ordering is two-sided.** Explosive/knockdown hits broadcast `ReceiveAnyDamage`
  ~0.3 ms *after* the activation; infantry melee broadcasts it ~0.7 ms *before*. v0.1.7 checks both.
- Fall damage and the physics launch ("fly away") are **separate systems** and are not suppressed.

## THE immediate next action — build the pak (Part 2)

Part 1 no longer blocks anything. The remaining work is the static skill tree:

1. **Extend `tools/skillpatch/`** with clone-and-edit + DataTable row append (see `tools/README.md`).
2. **Author the assets** — a tag-granting `GE_` per node (pattern: `GE_Skill_Global_Stamina_Lvl_01`) and
   the `SD_` skill definitions.
3. **Graft onto all 6 character roots**, register the new tags in `DT_PlayerSkillTags`.
4. **Pack + verify** (`retoc verify`), then in-game: node unlocks, persists, and the capstone actually
   grants immunity with **UE4SS switched off** — that's the test that matters, since the capstone is
   the whole no-dependency promise.
5. **Multiplayer check** — confirm suppression is local-only and not host-corrected.

Blocked on author decisions before step 2 (see below): node names/descriptions/icons, cost curve,
number of `%` tiers.

## Where everything lives (sibling repos & tools — paths relative to this repo's cwd)

- **Decode any asset:** `cd ../forever-winter-datamine && python -m fwdata get <AssetName>`
  → JSON at `datamine/decoder/out/cache/24097213/dump/misc/<AssetName>.json`. Master asset list:
  `datamine/decoder/out/filelist.txt`. (Use specific names; a broad substring decodes hundreds.)
- **Prior art:** `../ScavgirlCarryPerks` (the `skillpatch` graft + `docs/design-notes.md`);
  `../FWBehaviorLab/docs/field-guide.md` (the two modding vectors);
  `../FWBehaviorLab/mods/FWStealth` (Lua-mod layout analog).
- **Build toolchain:** `.NET` SDK 8 + 10; `retoc.exe` at `../UnkillablesRebalanceFix/tools/retoc/retoc.exe`;
  the TFW AES key (a community-known constant — in the datamine README);
  usmap `../forever-winter-datamine/datamine/mappings/ForeverWinter-5.4.2.usmap`.
- **Game:** `<Steam library>\steamapps\common\The Forever Winter`. **MO2 instance data:** `<MO2 instance>`.

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

## Decisions still owned by the author (don't invent these)

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
