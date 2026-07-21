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

This is statically airtight but **not yet game-verified.** Before shipping, confirm:

1. **The linchpin:** owning `Ability.HitReactionBlocked` actually stops stagger in a live match. (Cheapest
   test: the UE4SS layer in `blanket` mode — see [`../WORKLOG.md`](../WORKLOG.md).)
2. **Lua can read the incoming damage type** from the `Event.HitReaction.Player.Weapon` payload / effect
   context at activation time (the hinge for per-type selectivity).
3. **A brand-new `PlayerSkill.Global.StaggerResist.*` tag** added only to `DT_PlayerSkillTags` resolves for
   unlock/save — or whether native `DefaultGameplayTags.ini` registration is also needed (fallback: reuse a
   spare shipped tag).
4. **A node grafted onto a root** unlocks, persists in save, and its GE is applied on purchase (implied by
   ScavgirlCarryPerks' RIG04 graft, but that was mid-tree, not top-level-under-root).
5. **Multiplayer:** TFW is host-authoritative over EOS P2P. Hit-react runs on the local player's pawn, so
   client-side suppression *probably* affects only the local player — confirm it isn't silently corrected
   by the host, and that the skill-tag path behaves for a non-host.
