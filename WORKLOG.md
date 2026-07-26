# WORKLOG

## 2026-07-26 (night) — ✅✅ SUPPRESSION PROVEN IN LIVE FIRE 7/7; trigger model + ordering nailed; v0.1.6 defers selective

Three v0.1.5 logs from fenix (two Ashen Mesa sessions: guns/exo/mechs, then mech + drones). Headlines:

- **The design works, end to end.** `GA_Player_HitReaction` activated **7 times** — explosive knockback
  ×5, medium-mech rear minigun ×2 (`amt=300`, native `FWKnockDownDamageType`) — and **all 7 were
  cancelled**. Fenix reports zero staggers. The one seam + cancel = the whole Part-1 mechanism, proven.
- **Trigger model:** the GA fires ONLY on `FWKnockDownDamageType`-lineage hits. 100+ plain gun hits
  (SMG05/06, LMG03, exo stubby gun, Merkava MG, drones, rifles, shotgun) → zero activations. Not every
  knockdown hit re-fires it (internal gating while active/ragdolled — several knockbacks logged with no
  activation). Crawler melee doesn't trigger it; v0.1.1's staggering melee source remains unidentified.
- **The type is only PARTIALLY erased (corrects the v0.1.4 verdict):** knockback explosions arrive with
  the REAL `BP_ExplosiveDamage_FW_knockback_C` and **`causer=nil`** (via=type saved them); shotgun =
  `BP_ShotgunDamage_FW_C`; fall = `BP_FallDamage_C`; mech knockdown weapons = native
  `FWKnockDownDamageType` with a causer. Rapid-fire guns stay erased → causer decides. The v0.1.5
  type-first-else-causer classifier called every live hit correctly (turret → heavy ✓).
- **ORDERING (the selective off-by-one):** all 7 activations logged ~0.5 ms BEFORE the triggering hit's
  own `ReceiveAnyDamage` line — the GameplayEvent is sent from inside damage processing, before the
  AnyDamage broadcast. So `last_damage` at activation time is the PREVIOUS hit (log shows e.g.
  `would_block=false` from a stale rifle when the trigger was explosive). Deciding at activation is
  wrong by one hit.
- **The "fly away" is a separate path.** Big knockback hits physics-launch the player (fenix: "big meha
  make scavgirl fly… almost die to falldamage" — launch → `BP_FallDamage` 856 in-log). Cancelling the GA
  kills the flinch, not the launch. Community corroboration (MxPmH1517): mech hits "skip the stagger
  frame and directly make you fall." Candidate future feature; out of the hit-react seam's reach.
- New confirmed causer names fed into config: SMG05AI, LMG03_AI, AI_HRF01a, AI_RFL01_LowTech, SHG05_AI,
  Exo_LeftStubbyGun (prefix-fallback ✓), Europa_Merkava_Machinegun, 20mmTurret (heavy ✓),
  MediumMech_MiniGun_Rear, MediumMech_LongRifle (4482-dmg killshot, no GA — death path), Drone.

**v0.1.6 — the deferred-selective build:**
- Selective mode now PARKS the activated ability (`pending`) and decides in the damage hook that fires
  sub-ms later with the real classification; blanket still cancels on the spot. Pending cleared on
  ClientRestart, 100 ms expiry window, `allow`/`SUPPRESS (deferred N ms)` logged either way.
- `should_block` replaced by `family_blocks(family, ability)` (config families live; skill-tag checks
  still stubbed). Dead `CurrentEventData` reader stayed gone; `hit-react:` line renamed to
  `prev_damage=`/`prev_family=` so nobody mistakes it for the trigger's own hit.
- Config: `mode="selective"` is the SHIPPED TEST DEFAULT (explosive/heavy/melee ticked, ballistic off —
  should feel identical to blanket since plain gunfire never staggers); heavy needles += "Mech";
  confirmed-name comments refreshed.
- **Next round asks:** does selective feel identical (no staggers except falls/fly-away)? Any visible
  flinch = the deferred cancel landed too late or a family misread — the `allow`/`deferred` log lines
  will say which. That's the one risk this build carries.

## 2026-07-26 (later) — v0.1.4 named round: type ERASED everywhere; the CAUSER is the signal; hit-react still silent

Textbook tester round (fenix: "old rifle fire / melee / die to grenade", in order, all three named in-log):

- **SMG fire** 15:11: 33 × `amt=30`, type=`Default__FWDamageType`, **causer=`BP_WPN_SMG06AI_C`** (2–3 shooters).
- **Crawler melee** 15:12: 6 × `amt=133`, type=engine `Default__DamageType`, **causer=`BP_AI_Eurasia_Crawler_C`**
  — for melee the attacking PAWN is the causer.
- **Grenade-launcher death** 15:13: 1 × `amt=1685`, type=engine `Default__DamageType`, **causer=`BP_WPN_GRL00_C`**.

Verdicts:

- **The damage-type class is dead as a signal — permanently.** 40/40 live hits (both rounds) arrived as
  base-class CDOs; the `BP_*Damage_FW` subclasses never reach `ReceiveAnyDamage`. Design-notes open
  question #2 is CLOSED: not in the event payload (v0.1.2), not in the `UDamageType` (v0.1.4).
- **The CAUSER is a clean, complete replacement**: weapon actors name themselves (`WPN_SMG06AI`,
  `WPN_GRL00`), melee is detectable as causer=`BP_AI_*` pawn. Per-type control pivots to causer names.
- **Hit-react: still ZERO activations** across 40 hits — Crawler melee and a lethal grenade never even
  tried to stagger. Stagger triggers are rarer than assumed (v0.1.1's staggering melee was a different
  enemy type). Still needed: one POSITIVE correlation case — a hit that fires the hit-react while the
  capture names it — which also proves the assumed damage-line-before-activation ordering.

**v0.1.5:** causer-based family classification is LIVE (ordered needle tables in config; unmatched
`BP_WPN_*` defaults to ballistic; feeds `last_damage.family` + the dry-run line). Selective mode now
reads the upstream capture; the dead `CurrentEventData` payload reader is removed. Blanket unchanged
and still the shipped default. Next round ask: hunt the BIG stuff — exo/heavy melee, tank/turret fire,
survivable near-miss explosions — and report anything that VISIBLY staggers (a visible stagger with no
`SUPPRESS` line = a second, un-hooked stagger path).

## 2026-07-26 — v0.1.3 live round: capture seam WORKS, but the type arrives ERASED; no control case

First tester log with the ReceiveAnyDamage capture (fenix, one hub → Tunnel2 → hub cycle):

- **Mechanics all green.** Both lazy hooks (`GA_Player_HitReaction_C:K2_ActivateAbility`,
  `BP_PlayerBase_C:ReceiveAnyDamage`) registered on the first ClientRestart; the probe found the live
  ability on all three spawns; the install-once guard held (no re-hook spam on later restarts).
- **The bad news: 9/9 captured hits logged `type=FWDamageType family=other`** — the native BASE class,
  never a `BP_*Damage_FW` subclass. Either those hits genuinely ship the base type, or the class is
  erased by the time ReceiveAnyDamage runs. Can't tell from this round alone, because —
- **No hit-react activation the whole session.** The 9 hits came as one rapid ~1.3 s burst (cadence
  smells like autofire or a DoT tick, not a grenade); nothing tried to stagger him through our hooked
  path, and there was no melee hit to serve as the known-good control. Fenix's "explosion and I haven't
  staggered" therefore can't be attributed to the mod from this log — nothing was suppressed.
- **v0.1.4 widens the capture to decide it:** damage amount, the type object's full name (CDO vs live
  instance) + super class (the native `FWKnockDownDamageType`-vs-`FWGameDamageType` split may be the
  real signal), and the `DamageCauser` actor class+name (grenade/projectile/enemy — a usable per-type
  signal even if the damage class stays erased). Decision logic untouched: blanket still suppresses;
  causer is log-only until real names come back.
- **Next round ask (sent with the build):** in one session — melee ×2 (control), a NAMED point-blank
  explosion ×2–3, plain rifle fire, plus one line giving the order. A visible stagger with no SUPPRESS
  line would mean a second, un-hooked stagger path — also decisive.

## 2026-07-24 (eve) — ✅ SEAM PROVEN in-game (via tester); per-type selectivity is next

**The load-bearing assumption is now verified on an independent machine.** Across three fast tester cycles:
- **v0.1.0** — engine-BASE `K2_ActivateAbility` hook registered but never fired on a stagger (two logs).
- **v0.1.1** — added a *lazy retry* of the BP-generated-class hook (it fails at mod-load because the player
  pawn doesn't exist yet). The retry registered `…GA_Player_HitReaction_C:K2_ActivateAbility` ~1 min after
  load; it then **fired 5–6× on the tester's melee hits, each `SUPPRESS`'d — and melee stopped staggering.**

So intercepting `GA_Player_HitReaction` and cancelling it **does** stop player stagger. Design validated.

**Mechanism detail worth keeping:** the BP implements `K2_ActivateAbility`; hooking the engine BASE
UFunction never catches the BP's override — you must hook the **generated class path**, and lazily (after
the pawn loads). This is why v0.1.0 saw nothing.

**Fall damage still staggers** — expected. Our trigger is `Event.HitReaction.Player.**Weapon**` (combat
hit-react). Fall/hard-landing stagger is a separate path; out of scope unless we choose to hunt it.

**Dead end removed:** v0.1.1's property sweep was junk — UE4SS returns a *non-nil placeholder* for missing
fields, so all 11 montage-name guesses false-positived (`GetFullName` failed on every one). v0.1.2 drops it;
any future reflection read now validates `IsValid()` + a real `GetFullName()` first.

**Next (author's pick): per-type selectivity.** v0.1.2 keeps blanket suppression but logs the triggering
payload (`CurrentEventData.*`, validated) on each caught hit, to test whether the damage family is reachable
at hit-react time (design-notes open question #2). If it's not exposed there, we pivot to hooking the damage
pipeline (where the `BP_*Damage_FW` type class is a parameter).

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

### Decisions still owned by the author
- Final node names / descriptions / icons (human-facing copy).
- Cost curve (deep Stamina-style 2500→43125 vs flat 2000/tier) and number of %% tiers.
- Whether to ship the pak's "blanket always-on" toggle variant in addition to the skill-gated capstone.
