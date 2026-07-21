-- TFWStaggerControl — UE4SS Lua layer (optional upgrade over the static pak)
--
-- One hook on the player hit-react ability. It decides block/allow from (1) config damage-type list
-- (Part 1) and (2) owned resistance skill tags (Part 2 graded/per-type). The static pak works without
-- this file; this file adds per-type selectivity and graded % that pure data can't express.
--
-- STATUS: first cut. The exact UFunction signatures below need to be confirmed ON-BOX with RE-UE4SS
-- (ConsoleCommandsMod: `dump_object`, and `FindAllOf`). Search points marked  >>> CONFIRM ON-BOX.
-- Reference for TFW UE4SS idioms: FWBehaviorLab/mods/FWStealth/Scripts/main.lua.

local cfg = require("config")

local HITREACT_ABILITY_CLASS = "GA_Player_HitReaction_C"          -- BP ability class name
local HITREACT_EVENT_TAG     = "Event.HitReaction.Player.Weapon"  -- what triggers it
local BLOCK_TAG              = "Ability.HitReactionBlocked"        -- the shipping ActivationBlockedTag

local function log(msg)
    if cfg.debug then print("[TFWStaggerControl] " .. msg) end
end

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

-- Classify a damage-type object/class name into one of our families (or "other").
local function classify_damage(type_name)
    if not type_name then return "other" end
    for family, needles in pairs(cfg.type_classes) do
        for _, needle in ipairs(needles) do
            if string.find(type_name, needle, 1, true) then return family end
        end
    end
    return "other"
end

-- Does the player's ASC own a gameplay tag (exact match)?  >>> CONFIRM ON-BOX: HasMatchingGameplayTag
-- is a UAbilitySystemComponent UFunction taking an FGameplayTag; building the tag struct from Lua may
-- need RequestGameplayTag. If tag reads are awkward, gate Part 2 on the pak capstone instead.
local function asc_has_tag(asc, tag_name)
    if not asc or not asc:IsValid() then return false end
    local ok, has = pcall(function()
        local tag = StaticFindObject("/Script/GameplayTags") -- placeholder; see note above
        return false
    end)
    return ok and has or false
end

-- Accumulated shrug-off chance (0..1) from owned Chance_0N tags.  >>> CONFIRM ON-BOX
local function graded_chance(asc)
    local chance = 0.0
    for tier = 1, 9 do
        local tag = string.format("%s%02d", cfg.skill.chance_tag_prefix, tier)
        if asc_has_tag(asc, tag) then chance = chance + cfg.skill.chance_per_tier end
    end
    if chance > 1.0 then chance = 1.0 end
    return chance
end

-- Read the incoming damage-type class from the hit-react ability's triggering event payload.
-- >>> CONFIRM ON-BOX: whether CurrentEventData (FGameplayEventData) carries the DamageType — check
-- .OptionalObject / .OptionalObject2 / .Instigator, or read the ASC's last damage context. This is
-- the open question that decides whether per-type selectivity is possible (see docs/design-notes.md #2).
local function incoming_damage_type_name(ability)
    local ok, name = pcall(function()
        local ev = ability.CurrentEventData
        if ev and ev.OptionalObject and ev.OptionalObject:IsValid() then
            return ev.OptionalObject:GetClass():GetFName():ToString()
        end
        return nil
    end)
    return ok and name or nil
end

-- ---------------------------------------------------------------------------
-- decision
-- ---------------------------------------------------------------------------

-- Return true to SUPPRESS the stagger for this activation.
local function should_block(ability)
    if cfg.mode == "off" then return false end
    if cfg.mode == "blanket" then return true end

    -- mode == "selective"
    local asc = nil
    local ok = pcall(function() asc = ability:GetAbilitySystemComponentFromActorInfo() end)  -- >>> CONFIRM
    local dmg_name = incoming_damage_type_name(ability)
    local family = classify_damage(dmg_name)
    log(("hit: type=%s family=%s"):format(tostring(dmg_name), family))

    -- Part 1: config list always ignores these families.
    if cfg.ignore_types[family] then
        log("blocked by config family " .. family); return true
    end

    -- Part 2: per-type immunity skill tags.
    local imm_tag = cfg.skill.type_immunity_tag ..
        (family:sub(1,1):upper() .. family:sub(2))   -- e.g. "...Type.Explosive"
    if asc_has_tag(asc, imm_tag) then
        log("blocked by skill immunity " .. imm_tag); return true
    end

    -- Part 2: graded % shrug-off.
    local chance = graded_chance(asc)
    if chance > 0 and math.random() < chance then
        log(("blocked by graded roll (chance=%.2f)"):format(chance)); return true
    end

    return false
end

-- ---------------------------------------------------------------------------
-- hook
-- ---------------------------------------------------------------------------
-- Strategy: intercept the hit-react ability activation and cancel/no-op it when should_block() is true.
-- We hook a UFunction on the ability. GA activation is often native; the reliable BP entry is the
-- ability's ActivateAbility / K2_ActivateAbility.  >>> CONFIRM ON-BOX which one fires:
--   dump_object on a live GA_Player_HitReaction_C instance and check its functions.
-- Alternative if activation can't be cancelled cleanly: on ClientRestart, add the loose tag
-- Ability.HitReactionBlocked to the player ASC for `mode=="blanket"` (lets the shipping gate do it),
-- and for selective mode toggle that loose tag per-hit just-in-time.

local HOOK_TARGETS = {
    "/Script/Engine.GameplayAbility:K2_ActivateAbility",
    -- fallbacks to try on-box:
    -- "/Script/GameplayAbilities.GameplayAbility:ActivateAbility",
    -- a montage-play UFunction inside GA_Player_HitReaction_C
}

local function is_our_ability(ctx)
    local ok, name = pcall(function() return ctx:get():GetClass():GetFName():ToString() end)
    return ok and name == HITREACT_ABILITY_CLASS
end

local function install_hooks()
    for _, target in ipairs(HOOK_TARGETS) do
        local ok = pcall(function()
            RegisterHook(target, function(self)
                if not is_our_ability(self) then return end
                local ability = self:get()
                if should_block(ability) then
                    log("SUPPRESS hit-react")
                    pcall(function() ability:K2_EndAbility() end)   -- >>> CONFIRM: EndAbility vs CancelAbility
                end
            end)
        end)
        log((ok and "hooked " or "FAILED to hook ") .. target)
    end
end

-- Install after the game/player is up. ClientRestart is the TFW-idiomatic re-init point (see FWStealth).
local ok = pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
        log("player restart — (re)installing hooks; mode=" .. cfg.mode)
        install_hooks()
    end)
end)
if not ok then log("WARNING: could not register ClientRestart hook; trying immediate install") end
install_hooks()

log("loaded. mode=" .. cfg.mode .. " (set to 'blanket' first to smoke-test the seam)")
