#!/usr/bin/env bash
# Build the TFWStaggerControl static pak (the skill tree). The UE4SS Lua layer needs NO build —
# copy ue4ss/TFWStaggerControl/ into your RE-UE4SS Mods folder (or deploy via MO2).
#
# Pipeline (mirrors ScavgirlCarryPerks): decode templates -> author new GE/SD assets ->
# graft entry nodes onto all 6 character roots (skillpatch) -> retoc pack -> verify.
#
# Adjust the paths below for this machine, then run:  bash build.sh
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'   # stop Git-Bash mangling /Game/... args

REPO="H:/Github Repositories/TFWStaggerControl"
DATAMINE="H:/Github Repositories/forever-winter-datamine"
GAME_PAKS="H:/SteamLibrary/steamapps/common/The Forever Winter/Windows/ForeverWinter/Content/Paks"
AES="0x84B2244BE0AF90C22976D739FA0665569219F4CEA119CEA37C81F2D9ABEE4795"
RETOC="H:/Github Repositories/UnkillablesRebalanceFix/tools/retoc/retoc.exe"
USMAP="$DATAMINE/datamine/mappings/ForeverWinter-5.4.2.usmap"
SPDLL="$REPO/tools/skillpatch/bin/Release/net8.0/skillpatch.dll"

SKILLS_REL="ForeverWinter/Content/FW/Player/Skills"
ROOTS=(
  "EarlyAccessTrees/ScavGirl/SD_Skill_EarlyAccess_ScavGirl_ROOT"
  "EarlyAccessTrees/OldMan/SD_Skill_EarlyAccess_OldMan_Root"
  "EarlyAccessTrees/BagMan/SD_Skill_EarlyAccess_BagMan_Root"
  "EarlyAccessTrees/Gunhead/SD_Skill_EarlyAccess_Gunhead_Root"
  "EarlyAccessTrees/MaskMan/SD_Skill_EarlyAccess_MaskMan_Root"
  "EarlyAccessTrees/Shaman/SD_Skill_EarlyAccess_Shaman_Root"
)
# Template assets we clone to author the new nodes/effects:
TEMPLATE_SD="ActiveCharacters/Global/GlobalSkills/Stamina/SD_Skill_Global_Stamina_Lvl_01"
TEMPLATE_GE="ActiveCharacters/Global/GlobalSkills/Stamina/GE_Skill_Global_Stamina_Lvl_01"

echo "[1/5] build skillpatch (UAssetAPI grafter)"
dotnet build -c Release -v q --nologo "$REPO/tools/skillpatch/skillpatch.csproj" >/dev/null

echo "[2/5] extract the 6 roots + templates to legacy .uasset"
rm -rf "$REPO/pak/staging/legacy"; mkdir -p "$REPO/pak/staging/legacy"
for r in "${ROOTS[@]}"; do
  "$RETOC" -a "$AES" to-legacy --version UE5_4 -f "$(basename "$r")" "$GAME_PAKS" "$REPO/pak/staging/legacy" >/dev/null 2>&1
done
"$RETOC" -a "$AES" to-legacy --version UE5_4 -f "SD_Skill_Global_Stamina_Lvl_01" "$GAME_PAKS" "$REPO/pak/staging/legacy" >/dev/null 2>&1
"$RETOC" -a "$AES" to-legacy --version UE5_4 -f "GE_Skill_Global_Stamina_Lvl_01"  "$GAME_PAKS" "$REPO/pak/staging/legacy" >/dev/null 2>&1

echo "[3/5] author new StaggerResist GE + SD assets   >>> TODO (asset-authoring tool)"
# Clone TEMPLATE_GE -> GE_Skill_Global_StaggerResist_* : swap the granted tag to the resistance tag
#   (per-type/%%  nodes) or to Ability.HitReactionBlocked (the pak-only full-immunity capstone).
# Clone TEMPLATE_SD -> SD_Skill_Global_StaggerResist_* : set SkillName/Description/Texture, ValueOfXP,
#   ChildSkills chain, SkillEffects -> the new GE class, SkillTag -> PlayerSkill.Global.StaggerResist.*
# Also append the new SkillTags as rows to DT_PlayerSkillTags.
# This step needs an extension to tools/skillpatch (clone+edit + DataTable row append). See tools/README.md.

echo "[4/5] graft entry node onto each root's ChildSkills   >>> TODO (after step 3 authors the node)"
# for r in "${ROOTS[@]}"; do
#   SRC="$REPO/pak/staging/legacy/$SKILLS_REL/$r.uasset"
#   dotnet "$SPDLL" add "$SRC" "$USMAP" "$REPO/pak/staging/build/$SKILLS_REL/$r.uasset" \
#     "/Game/FW/Player/Skills/ActiveCharacters/Global/GlobalSkills/StaggerResist/SD_Skill_Global_StaggerResist_Entry|SD_Skill_Global_StaggerResist_Entry"
# done
# cp "$REPO/pak/staging/legacy/scriptobjects.bin" "$REPO/pak/staging/build/"

echo "[5/5] repack + verify   >>> TODO"
# "$RETOC" to-zen --version UE5_4 "$REPO/pak/staging/build" "$REPO/dist/TFWStaggerControl/StaggerControl_P.utoc"
# "$RETOC" verify "$REPO/dist/TFWStaggerControl/StaggerControl_P.utoc"

echo "DONE (steps 1-2 ready; 3-5 pending the asset-authoring tool)."
