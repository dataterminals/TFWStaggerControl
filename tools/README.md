# tools/

## skillpatch/

C# / UAssetAPI tool copied from `ScavgirlCarryPerks`. Today it can **inspect / add / remove** entries in an
`FWSkillDefinition.ChildSkills` array, synthesising the cross-package import chain so a node in one package
can reference a node in another. That is exactly the **graft** step (append our entry node to each root).

Build: `dotnet build -c Release tools/skillpatch/skillpatch.csproj` (.NET 8 SDK). Modes:
```
skillpatch inspect <in.uasset> <usmap>
skillpatch imports <in.uasset> <usmap>
skillpatch add     <in.uasset> <usmap> <out.uasset> "<pkgPath>|<objName>" ...
skillpatch patch   <in.uasset> <usmap> <out.uasset> <removeName> ...
```

### Extensions needed for this mod (next work)

1. **Clone-and-edit** — duplicate a template asset (`SD_Skill_Global_Stamina_Lvl_01`,
   `GE_Skill_Global_Stamina_Lvl_01`) into a new package with a new object name, and set fields:
   - SD: `SkillName`, `SkillDescription`, `SkillTexture`, `ValueOfXP`, `ChildSkills`, `SkillEffects`
     (soft class ref → the new `GE_*_C`), `SkillTag`.
   - GE: swap the granted tag in `TargetTagsGameplayEffectComponent.InheritableGrantedTagsContainer`
     (to `Ability.HitReactionBlocked` for the capstone, or `PlayerSkill.Global.StaggerResist.*` otherwise).
2. **DataTable row append** — add each new `SkillTag` as a `GameplayTagTableRow` row to `DT_PlayerSkillTags`.
   (Heavier than the ChildSkills append; verify it serialises cleanly — open question in `../docs/design-notes.md`.)

UAssetAPI byte-identical round-trip is proven for DataAssets/DataTables (per FWBehaviorLab), so both are
in-scope; do a no-op save/load test first.

## retoc (not committed)

`retoc.exe` mounts/extracts (`to-legacy`) and repacks (`to-zen`) IoStore paks. Copies live in sibling repos
(`UnkillablesRebalanceFix/tools/retoc/`, `AllWeaponsUnlockableFix/tools/retoc/`). `build.sh` points at one.
AES key + usmap are in `../build.sh`.
