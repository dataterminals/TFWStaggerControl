# TFWStaggerControl — design & mechanism

*The Forever Winter, UE 5.4.2, build 24097213 (0.9.3.9.2). Everything below was decoded from the
shipped paks (CUE4Parse via the `forever-winter-datamine` toolkit). Asset paths and values are real;
see [`findings.md`](findings.md) for the raw evidence.*

## The one seam both parts share

The player's stagger is **not** a stat and **not** an amount threshold. It is a GameplayAbility:

```
incoming hit → BP_PlayerBase damage graph sends GameplayEvent  Event.HitReaction.Player.Weapon
             → GA_Player_HitReaction  (BP over native FWPlayerGA_HitReaction, /Script/FWPlayer)
             → native FWGamePlayerCharacter::GetHitReactionMontage → play montage / stagger
```

`GA_Player_HitReaction` carries, in **shipping data**:

```
AbilityTriggers      = [{ TriggerTag: "Event.HitReaction.Player.Weapon", Source: GameplayEvent }]
ActivationBlockedTags = [ "Ability.HitReactionBlocked" ]        ← the switch
```

**If the player's AbilitySystemComponent owns `Ability.HitReactionBlocked`, the hit-react ability can
never activate — no stagger, no hit montage.** The tag exists only on this ability; nothing in the base
game ever grants it (verified: `Ability.HitReactionBlocked` appears in exactly one decoded asset). So it
is a free, conflict-proof kill switch, and **both parts of this mod work by controlling that tag.**

Two dead ends we ruled out (don't chase these):

- **Amount thresholds.** `BP_PlayerBase` has the same `StaggerDamageThreshhold` / `LowDamageThreshhold` /
  `TinyDamageThreshhold` schema the AI uses, but every value is `999999.0` — the amount-based path is
  deliberately disabled for the player. Editing them does nothing.
- **A stagger/poise attribute.** There is none. The player's two attribute sets are
  `FWAttributeSet_Health {Health, MaxHealth, IncomingDamageModifier}` and
  `FWPlayerAttributeSet_SkillTree {MovementSpeed…, WeaponAccuracy…, Rig…}`. No poise/toughness/flinch
  attribute exists, so a skill's GameplayEffect can't "scale stagger resistance" the way it scales stamina.

## Why per-damage-type needs UE4SS, but a skill tree doesn't

Damage types are Blueprint subclasses distinguished by **class identity**, not by a data flag:

| Base class | meaning | example subclasses |
|---|---|---|
| `FWGameDamageType` (`/Script/ForeverWinter`) | normal | Melee, Projectile, Shotgun, Explosive, Fall, TurretProjectile, AssaultInfantry |
| `FWKnockDownDamageType` (`/Script/FWGameCore`) | knocks down / staggers | Explosive_knockback, TankMainGun, AssaultInfantry_Knockdown |

No damage type has a `bStagger` / `bPlayerFeedback` bool (they override only `GetCanDieFrom`), and weapons
carry **no `DamageTypeClass` field** to repoint. So *whether a given hit staggers you* is decided in native
/ Kismet bytecode — you cannot express "ignore stagger from explosions only" as a static-pak data edit.
The only static-pak lever is **blanket** (grant the block tag unconditionally). Genuine per-type control
requires reading the incoming damage type at runtime → **UE4SS Lua**.

> **Runtime reality (2026-07-26, two live rounds):** the type arrives REAL for some sources and ERASED for
> others. Knockdown-class hits deliver the real class at `ReceiveAnyDamage` (`BP_ExplosiveDamage_FW_knockback_C`
> **with `causer=nil`**, native `FWKnockDownDamageType` on mech weapons), and shotgun/fall deliver
> `BP_ShotgunDamage_FW_C`/`BP_FallDamage_C`. Rapid-fire guns and melee arrive as base-class CDOs — for those
> the **`DamageCauser` actor class** names the hit (`BP_WPN_SMG06AI_C`, `BP_WPN_Exo_LeftStubbyGun_C`; melee
> passes the attacking pawn `BP_AI_*`). Classification = type first, else causer; both confirmed correct on
> every live hit.
>
> **Live trigger model:** most activations come from `FWKnockDownDamageType`-lineage hits — explosive
> knockback and the medium mech's rear minigun (300/hit) account for 12 of the 14 observed — and 100+
> plain gun hits fired it zero times. But **the lineage is not the rule**: a `BP_AI_Eurasia_Cyborg_C`
> melee hit carrying engine-base `Default__DamageType` (`super=Object`, 250 dmg) fired it too. Not every
> knockdown hit re-fires it either — there's internal gating while active/ragdolled.
>
> **Ordering is TWO-SIDED, and this is the subtle one.** The GameplayEvent is sent from inside damage
> processing on every path, but *where* differs: explosive/knockdown hits send it **before** the
> AnyDamage broadcast (activation logs ~0.3 ms early, 12/12), infantry melee sends it **after**
> (activation logs 0.67 ms late, 1/1). Selective mode must therefore resolve from both directions —
> look behind at the last damage line, then park for the next one (v0.1.7). v0.1.6 looked only forward
> and leaked the melee case.
>
> **Separate paths this seam does NOT control:** the physics launch/ragdoll ("fly away" on big knockback
> hits — confirmed live: the GA cancel suppresses the flinch but not the launch) and fall damage.
> Suppression itself is proven: blanket cancelled 7/7, selective 6/7 then patched to 7/7 offline.

The skill tree, by contrast, is **100% data** — see below.

## Architecture: one repo, two deliverables

```
                       ┌─────────────────────────────────────────────┐
   incoming hit ─────► │  GA_Player_HitReaction (ships block-tag gate) │
                       └─────────────────────────────────────────────┘
                              ▲                         ▲
        owns Ability.HitReactionBlocked ?         (native decision)
                              │                         │
        ┌─────────────────────┴───────┐      ┌──────────┴────────────────────┐
        │  STATIC PAK (no dependency)  │      │  UE4SS LUA (optional upgrade)  │
        │  the skill tree:             │      │  one hook on the hit-react:    │
        │   • per-type immunity nodes  │      │   • reads config damage list   │
        │   • % shrug-off nodes        │      │   • reads owned skill tags     │
        │   • full-immunity capstone   │◄─────┤   • per-type → block outright  │
        │     (grants block tag = works│ tags │   • graded → roll % to shrug   │
        │      with no UE4SS)          │      │   • blanket → always block     │
        └──────────────────────────────┘      └────────────────────────────────┘
```

### Part 2 — the resistance skill tree (static pak, works standalone)

New `FWSkillDefinition` nodes authored under
`/Game/FW/Player/Skills/ActiveCharacters/Global/GlobalSkills/StaggerResist/`, following the shipped
7-field schema (`SkillName`, `SkillDescription`, `SkillTexture`, `ChildSkills`, `ValueOfXP`,
`SkillEffects`, `SkillTag`). Each node's `SkillEffects` is an infinite-duration `GE_Skill_*` that grants a
gameplay tag via `TargetTagsGameplayEffectComponent.InheritableGrantedTagsContainer` — the exact pattern
`GE_Skill_Global_Stamina_Lvl_01` uses.

Two lines + a capstone:

- **Per-type immunity line** — nodes grant `PlayerSkill.Global.StaggerResist.Type.{Explosive,Heavy,Melee}`.
  Inert on their own (a skill tag no native code reads); the UE4SS layer honors them.
- **% shrug-off line** — nodes grant `PlayerSkill.Global.StaggerResist.Chance_01..0N`. Also UE4SS-honored.
- **Full-immunity capstone** — its GE grants the real `Ability.HitReactionBlocked`, so **this node alone
  works with no UE4SS** (pure data). It's the graceful-degradation path for pak-only users.

#### Tag budget — we borrow orphan tags rather than adding our own

Because of `FastReplication` (open question #3), the tree **adds no gameplay tags**. Instead it reuses
rows already registered in `DT_PlayerSkillTags` but backed by nothing — so the sorted global tag list
is byte-identical to an unmodded install, and `DT_PlayerSkillTags` itself is never edited.

How the candidates were found (2026-07-30, worth re-running after a game update):

1. Decode all 143 shipped `SD_Skill_*` and collect their `SkillTag` — only **81 distinct tags** for 270
   table rows. (`SkillTag` is *not* unique per asset: the four per-character copies of HRF Expert v1 all
   carry `PlayerSkill.Global.HRFExpert.v1`. The tag names the *skill concept*, so our shared nodes need
   one tag each, not one per root. Every shipped SD has one — the field is not optional.)
2. That leaves **189 unclaimed rows**, all of them tags for planned-but-unshipped skills.
3. Unclaimed is not the same as free — grep the pak filelist for each feature name. **`PlayerSkill.Prestige.*`
   is the trap**: 100 rows, by far the most tempting block, but Prestige has ~65 assets in the pak
   (audio, UI), so that system is partially built and its tags may go live. Same for HeadCannon,
   PneumaticJump, DeployableTurret.

**Chosen: `PlayerSkill.Global.FieldCommand.v1–v5` and `PlayerSkill.Global.QuickScavanger.v1–v5`** —
ten tags, zero assets behind either name anywhere in the pak, and referenced by nothing but
`DT_PlayerSkillTags` itself. The `Global` namespace also matches what these nodes are: shared across
all six roots.

Residual risk, stated plainly: if the developers ever ship Field Command or Quick Scavenger, a player
who bought our nodes will appear to own those skills. That is the price of not touching the tag list,
and it is a smaller and more local failure than a net-index desync. Re-check on each game update.

Mirror the shipped pattern when authoring: the GE grants **both** the borrowed skill tag (so the
purchase registers the way every stock skill does) **and** the functional tag — `Ability.HitReactionBlocked`
for the capstone, nothing extra for the UE4SS-honored nodes.

Grafting: append each line's entry node to the `ChildSkills` of **all six** character roots
(`SD_Skill_EarlyAccess_{ScavGirl_ROOT,OldMan_Root,BagMan_Root,Gunhead_Root,MaskMan_Root,Shaman_Root}`) via
the `skillpatch` cross-package import trick from ScavgirlCarryPerks. All six is required because Gunhead's
root omits the shared Global lines, so a single Stamina-tail graft would miss him. A tree node is shown iff
it is reachable via `ChildSkills` from a root — there is no separate registry to edit — but each new
`SkillTag` should be registered as a row in `DT_PlayerSkillTags` (270-row `GameplayTagTableRow` table).

### Part 1 — disable stagger for specific damage types (UE4SS Lua; pak blanket fallback)

One Lua hook on the hit-react ability. On each activation it decides *block or allow* from:
1. **config** — a flat list of damage-type families the player wants ignored (Part 1 proper), and
2. **owned skill tags** — per-type immunity + accumulated % (Part 2's UE4SS behavior).

The pak-only fallback for Part 1 is the same blanket block-tag GE (an always-on `GE` or the capstone),
which disables *all* stagger with no type selectivity.

## Open questions — must be settled with an in-game smoke test

Part 1 is settled in live fire. Everything still open belongs to Part 2 (the pak):

1. **PARTLY ANSWERED — and mind the gap.** *Suppressing the ability* stops stagger: proven, five tester
   rounds, blanket 7/7. But that is the **cancel-on-activation** path, which is what UE4SS does. The pak
   relies on a *different* mechanism — owning `Ability.HitReactionBlocked` so the shipping
   `ActivationBlockedTags` gate stops the ability from activating at all. That gate is stock GAS
   behaviour and the tag is right there in shipping data, so it should hold, **but nothing has tested
   it.** It is the single load-bearing assumption left, and the first pak build is what proves it —
   test it with UE4SS switched off, or the Lua layer will mask the result.
2. **ANSWERED (2026-07-26, refined 2026-07-30): per-type IS readable — via type when real, else causer.**
   The event payload carries only the trigger tag (v0.1.2). At `ReceiveAnyDamage`, rapid-fire guns and
   infantry melee arrive type-erased (base CDOs) but knockdown/shotgun/fall/mech-melee hits deliver the
   REAL class — and the **`DamageCauser` actor** covers the erased cases (`BP_WPN_SMG06AI_C` = gunfire;
   `BP_AI_*` pawn = melee; explosions arrive `causer=nil` but with the real type class). The ordering
   sub-question turned out to have **two** answers depending on the damage path — see the two-sided
   ordering note above; v0.1.7 resolves from both directions.
3. **ANSWERED (2026-07-30) — a DataTable row IS a real tag registration, but adding tags is not free.**
   The cooked `ForeverWinter/Config/DefaultGameplayTags.ini` (extract with `fwdata get
   DefaultGameplayTags --raw`) lists our table as a tag source:
   `+GameplayTagTableList=/Game/FW/Player/Skills/DT_PlayerSkillTags.DT_PlayerSkillTags`, alongside 1008
   inline `+GameplayTagList=` entries. So appending a row registers the tag. Two consequences:
   - **`Ability.HitReactionBlocked` is already registered** (inline in that ini), so the capstone's GE
     grants an existing tag and needs no new registration at all.
   - ⚠️ **`FastReplication=True`** in the same block. With fast replication, replicated `FGameplayTag`s
     serialize as an *index into the sorted global tag list*, so client and host must hold identical
     lists. A pak that adds a tag the host doesn't have shifts every index after it — which risks
     misread tags across the whole GAS layer, not just ours. **Prefer reusing an already-registered
     spare tag** for the node's `SkillTag`: 270 rows exist against only 143 shipped `SD_Skill_*`
     assets, so ~127 rows are unaccounted for and some should be free. Confirm a candidate is granted
     by nothing before reusing it, and treat "add a brand-new tag" as the multiplayer-risky path.
   Note this risk is **specific to the pak**. The UE4SS layer adds no tags — it cancels an ability
   locally — so Part 1 carries none of it.
4. **A node grafted onto a root** unlocks, persists in save, and its GE is applied on purchase (implied by
   ScavgirlCarryPerks' RIG04 graft, but that was mid-tree, not top-level-under-root).
5. **Multiplayer:** TFW is host-authoritative over EOS P2P. Hit-react runs on the local player's pawn, so
   client-side suppression *probably* affects only the local player — confirm it isn't silently corrected
   by the host, and that the skill-tag path behaves for a non-host. **See the `FastReplication` note in
   #3** — for the pak this is not just "does my skill work", it's "does adding a tag desync the shared
   tag index". Test the pak in co-op against an unmodded host before recommending it for multiplayer.
