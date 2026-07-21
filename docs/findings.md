# Datamine evidence — raw findings

*Decoded from build 24097213 via `forever-winter-datamine` (`python -m fwdata get <asset>`). Quoted field
names/values are verbatim from the JSON dumps. Nothing copyrighted is committed here — only our notes.*

## The hit-react ability — `GA_Player_HitReaction`

`/Game/FW/Player/GameplayAbilities/GA_Player_HitReaction`

```
SuperStruct           : Class'FWPlayerGA_HitReaction'  (/Script/FWPlayer)   ← native decision logic
AbilityTags           : ["Event.HitReaction.Player.Weapon"]
AbilityTriggers[0]    : { TriggerTag: "Event.HitReaction.Player.Weapon",
                          TriggerSource: EGameplayAbilityTriggerSource::GameplayEvent }
ActivationOwnedTags   : ["Event.HitReaction.Player.Weapon"]
ActivationBlockedTags : ["Ability.HitReactionBlocked"]      ← THE SWITCH (no vanilla granter)
```
BP body only handles montage playback / get-up / button-mash escape / SFX / cooldown / invuln.
`GetHitReactionMontage` casts avatar → `FWGamePlayerCharacter` (/Script/ForeverWinter) and calls its
**native** `GetHitReactionMontage` (no data map to edit).

Grep result: `"Ability.HitReactionBlocked"` occurs in **exactly one** decoded asset (this one).

## Player pawn / character — the disabled amount path

`BP_PlayerBase` CDO (both builds 24097213 and 24045295):
```
TinyAccumilationThreshhold  = 999999.0    TinyDamageThreshhold   = 999999.0
LowAccumilationThreshhold   = 999999.0    LowDamageThreshhold    = 999999.0
HeavyAccumilationThreshhold = 999999.0    StaggerDamageThreshhold = 999999.0
HitReactsPreventFire        = false
AnimationDefinition -> FWCharacterAnimationDefinition 'DA_PlayerAnimData'
```
(For comparison, `enemies/BP_AI_CharacterBase`: Tiny/Low/Heavy accum 250/250/250, damage 250/500/750,
`TinyDamageHitReaction: true`, `UpgradeHitReacts: true` — the AI path is live; the player's is off.)

`DD_Player_Girl` (`FWGamePlayerCharacterDefinition`) carries data-side stagger fields:
`SecondsToResetStagger = 0.1`, `PlayerHitReactionMontage = {…}` — but no skill-tree/root field.

## Damage-type taxonomy — class identity, no flags

All are `BlueprintGeneratedClass`; the only Properties present are stock `UDamageType` fields
(`bCausedByWorld`, `bScaleMomentumByMass`, `DamageImpulse`, `DestructibleImpulse`); the only overridden
function is `GetCanDieFrom`. **No stagger/feedback bool exists.**

| Parent = `FWGameDamageType` (normal) | Parent = `FWKnockDownDamageType` (staggers) | Parent = engine `DamageType` |
|---|---|---|
| BP_MeleeDamage_FW | BP_ExplosiveDamage_FW_knockback | DmgTypeBP_Environmental |
| BP_ProjectileDamage_FW | BP_TankMainGunDamage_FW | |
| BP_ShotgunDamage_FW | BP_DamageType_AssaultInfantry_Knockdown | |
| BP_ExplosiveDamage_FW | | |
| BP_FallDamage | | |
| BP_TurretProjectileDamage_FW | | |
| BP_TobaccoDamage_FW | | |
| BP_AIdamageType_FW | | |
| BP_DamageType_AssaultInfantry | | |
| BP_DamageType_NoPlayerFeedback *(no props; "no feedback" is native class-identity)* | | |

- `BP_ExplosiveDamage_GrenadeLauncher_FW` decoded as a stub (Super=None) — likely a redirector; real parent
  not captured. Re-decode/verify before relying on it.
- `FWWeaponDefinition` (e.g. `DA_WPN_RFL01_v2`) has `WeaponDamage`, `WeaponPassiveEffects`,
  `AmmoTypeCaliber`, cue tags — **no `DamageTypeClass`**. Type is assigned by the firing ability/native, so
  it can't be repointed per-weapon in data.

## Skill system — fully data-driven

`FWSkillDefinition` (`/Script/FWPlayerSkills`), 7 authored fields:
```
SkillName        : FText
SkillDescription : FText
SkillTexture     : soft object path (icon)
ChildSkills      : [ hard refs to child FWSkillDefinition ]   ← tree edges (parent→child)
ValueOfXP        : float (unlock cost)
SkillEffects     : [ soft class path to a GE_*_C GameplayEffect ]
SkillTag         : single GameplayTag  (e.g. PlayerSkill.Global.Stamina_01)
```
Roots additionally set `bAlwaysUnlocked: true`, `AllowPurchase: false`. Normal nodes omit these. No
prerequisite / character-gating / UI-XY fields — layout is derived from topology, character gating is tree
membership.

Roots (`/Game/FW/Player/Skills/EarlyAccessTrees/<Char>/`):
```
SD_Skill_EarlyAccess_ScavGirl_ROOT   SkillTag PlayerSkill.ScavGirl.ROOT
SD_Skill_EarlyAccess_OldMan_Root     SkillTag PlayerSkill.OldMan.ROOT
SD_Skill_EarlyAccess_BagMan_Root     SkillTag PlayerSkill.BagMan.ROOT
SD_Skill_EarlyAccess_Gunhead_Root    SkillTag PlayerSkill.Gunhead.ROOT   ← omits the Global lines
SD_Skill_EarlyAccess_MaskMan_Root    SkillTag PlayerSkill.MaskMan.ROOT
SD_Skill_EarlyAccess_Shaman_Root     SkillTag PlayerSkill.Shaman.ROOT
```
A root's `ChildSkills` enumerates the entry node of each line in its tree. `SD_Prestige_HealthBoost_Lvl_02`
and `SD_Prestige_SpeedBuff_Lvl_06` are in all 6; `SD_Skill_Global_Stamina_Lvl_01` is in 5/6 (not Gunhead).

Tag-granting GE pattern (copy this for the resistance nodes):
```
GE_Skill_Global_Stamina_Lvl_01 : NO Modifiers[]; DurationPolicy Infinite;
  TargetTagsGameplayEffectComponent.InheritableGrantedTagsContainer grants "PlayerSkill.Global.Stamina_01"
```
Attribute-modifying GE pattern (for reference / an optional "toughness" node):
```
GE_BarDrink_02_IncomingDamage : Modifiers[0] = { Attribute "IncomingDamageModifier"
  (owner FWAttributeSet_Health), Op EGameplayModOp::Multiplicitive [sic], ScalableFloat 0.9, Infinite }
```
Note the shipped enum typo to copy verbatim: `EGameplayModOp::Multiplicitive`, `EGameplayModOp::Additive`.

Cost curve samples (`ValueOfXP`): Stamina line 2500 → 8125 → … → 43125 (5 tiers, tail has no ChildSkills);
weapon-expert flat 2000; rig nodes 2000.

Tag registry: `DT_PlayerSkillTags` (`/Game/FW/Player/Skills/DT_PlayerSkillTags`), RowStruct
`GameplayTagTableRow` (`/Script/GameplayTags`), 270 rows, each `{ Tag, DevComment }`.

Legacy/ignore: `DT_SkillTreeSystem` (`/Game/SkillTreeSystem/`, RowStruct `CharacterSkillData`) is an old
parallel system — **not** the live tree; do not edit it.

## Attribute sets (native C++, enumerated from GE modifiers)

```
FWAttributeSet_Health        (/Script/FWGameCore)     : Health, MaxHealth, IncomingDamageModifier
FWPlayerAttributeSet_SkillTree (/Script/FWPlayerSkills): MovementSpeedModifier, SprintSpeedModifier,
                                WeaponAccuracyModifier, MedKitHealingAmount,
                                RigVolumeCapacityModifier, RigWeightCapacityModifier,
                                RigMaxWeightCapacityModifier
```
Grep for `AttributeName` matching `Stagger|Poise|HitReact|Toughness|Flinch|Stability` → **zero hits.**
