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

### Extension needed for this mod (next work)

**Clone-and-edit** — duplicate a template asset into a new package with a new object name, and set fields:

- **SD** (`SD_Skill_Global_Stamina_Lvl_01`) — a flat `FWSkillDefinition` DataAsset, 7 properties:
  `SkillName`, `SkillDescription`, `SkillTexture`, `ValueOfXP`, `ChildSkills`, `SkillEffects` (soft class
  ref → the new `GE_*_C`), `SkillTag`. Leaf nodes simply omit `ChildSkills` — see
  `SD_Skill_Global_Stamina_Lvl_05`.
- **GE** (`GE_Skill_Global_Stamina_Lvl_01`) — the fiddly one: a `BlueprintGeneratedClass` with **three**
  exports (the BPGC, its CDO `Default__GE_*_C`, and a `TargetTagsGameplayEffectComponent_0` subobject),
  wired by `ClassDefaultObject` and a `GEComponents` array. The granted tag appears in two places —
  the CDO's `InheritableOwnedTagsContainer` and the component's `InheritableGrantedTagsContainer` —
  each holding both `CombinedTags` and `Added`. Renaming is mostly a name-map rewrite, since the
  internal wiring is by export index.

**No DataTable append is needed.** The tree borrows already-registered orphan tags rather than adding
its own, so `DT_PlayerSkillTags` is never modified — see the tag-budget section in
`../docs/design-notes.md` for which tags and why (short version: `FastReplication=True`).

UAssetAPI byte-identical round-trip is proven for DataAssets (per FWBehaviorLab); do a no-op save/load
test on the BPGC before trusting the clone.

## retoc (not committed)

`retoc.exe` mounts/extracts (`to-legacy`) and repacks (`to-zen`) IoStore paks. Copies live in sibling repos
(`UnkillablesRebalanceFix/tools/retoc/`, `AllWeaponsUnlockableFix/tools/retoc/`). `build.sh` points at one.
AES key + usmap are in `../build.sh`.
