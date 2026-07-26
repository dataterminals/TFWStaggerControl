-- TFWStaggerControl — UE4SS Lua layer (optional upgrade over the static pak)
--
-- One hook on the player hit-react ability. It decides block/allow from (1) config damage-type list
-- (Part 1) and (2) owned resistance skill tags (Part 2 graded/per-type). The static pak works without
-- this file; this file adds per-type selectivity and graded % that pure data can't express.
--
-- STATUS: diagnostic-first. Hook targets still need ON-BOX confirmation, but this build LOGS what it
-- sees each launch (mod-load banner, FindAllOf probe, per-hit "activate:" lines) so a single run tells
-- us whether the K2_ActivateAbility hook is the right seam or we must pivot (montage hook / loose tag).
-- Tools on-box: ConsoleCommandsMod `dump_object`/`set`, `FindAllOf`. Idioms: FWStealth, TFWQuestHUDToggle.

local cfg = require("config")

local HITREACT_ABILITY_CLASS = "GA_Player_HitReaction_C"          -- BP ability class name
local HITREACT_EVENT_TAG     = "Event.HitReaction.Player.Weapon"  -- what triggers it
local BLOCK_TAG              = "Ability.HitReactionBlocked"        -- the shipping ActivationBlockedTag

local function log(msg)
    -- UE4SS Lua print does not append a newline; add one so each line stands alone in UE4SS.log
    -- (matches the working FWStealth / TFWQuestHUDToggle idiom).
    if cfg.debug then print("[TFWStaggerControl] " .. msg .. "\n") end
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
-- hook + on-box diagnostics
-- ---------------------------------------------------------------------------
-- Strategy: intercept the hit-react ability activation and cancel it when should_block() is true.
-- GA activation is often native; the reliable BP entry is K2_ActivateAbility ON THE GENERATED CLASS
-- (a BlueprintImplementableEvent overridden in a BP is a *distinct* UFunction from the engine base),
-- which is why we register both the base and the full BP path below.  >>> CONFIRM ON-BOX which fires.
--
-- This build is DIAGNOSTIC-FIRST: one launch answers the three open questions via UE4SS.log —
--   (1) does the mod load?                    -> the "loaded" banner
--   (2) is the ability discoverable + real name? -> the probe() lines on each respawn
--   (3) does the activation hook fire on a hit?  -> "activate: class=..." lines while you stagger
-- If (3) never logs a hit-react while you visibly stagger, activation is native (no BP override): pivot
-- to hooking the montage UFunction it calls (dump_object a live GA_Player_HitReaction_C) or to granting
-- the loose Ability.HitReactionBlocked tag so the shipping gate blocks it (see docs/design-notes.md).

local HOOK_TARGETS = {
    "/Script/GameplayAbilities.GameplayAbility:K2_ActivateAbility",  -- engine base UFunction (module fixed: was /Script/Engine)
    "/Game/FW/Player/GameplayAbilities/GA_Player_HitReaction.GA_Player_HitReaction_C:K2_ActivateAbility",  -- BP-generated override
    -- fallbacks to try on-box if neither fires (fully native activation):
    -- a montage-play UFunction inside GA_Player_HitReaction_C, found via dump_object.
}

-- Class name of the object a hook fired on (the ability). nil on failure.
local function activating_class_name(ctx)
    local ok, name = pcall(function() return ctx:get():GetClass():GetFName():ToString() end)
    return ok and name or nil
end

-- PART 1 — capture the incoming damage TYPE. The decoded BP_PlayerBase shows the real UDamageType
-- (BP_MeleeDamage_FW, BP_ExplosiveDamage_FW, …) arrives in the player's ReceiveAnyDamage, which maps it and
-- SendGameplayEventToActor(Event.HitReaction.Player.Weapon) to fire the ability. The type is NOT on the
-- ability (v0.1.2 confirmed the payload only carries the generic tag), so we grab it one step upstream:
-- hook ReceiveAnyDamage, stash the type, and read it back in the hit-react hook microseconds later.
-- Params verbatim from the dump: (Damage, DamageType, InstigatedBy, DamageCauser).
--
-- v0.1.4: fenix's first v0.1.3 round came back 9/9 `type=FWDamageType` — the native BASE class, never a
-- BP_*Damage_FW subclass — and the hit-react never activated during that burst (cadence looked like
-- autofire/DoT, not a grenade). Either those hits genuinely ship the base type, or the class is erased
-- at this seam. Widen the capture to decide: damage amount, the type object's full name (CDO vs live
-- instance) + its super class (the native FWKnockDownDamageType-vs-FWGameDamageType split may be the
-- real signal), and the DamageCauser actor class+name (grenade/projectile/enemy — a usable per-type
-- signal even if the damage class stays erased). Classification still keys off the type class alone;
-- causer is LOG-ONLY until real names come back. Decision logic untouched (blanket still suppresses).
local DAMAGE_HOOK    = "/Game/FW/Player/BP_PlayerBase.BP_PlayerBase_C:ReceiveAnyDamage"
local last_damage    = { name = nil, family = "unknown" }   -- set on each incoming hit, read by the hit-react hook
local damage_hook_ok = false

local function on_receive_any_damage(self, Damage, DamageType, InstigatedBy, DamageCauser)
    local amount
    pcall(function() amount = Damage:get() end)

    local type_name, type_full, type_super
    pcall(function()
        local dt = DamageType:get()
        if dt and dt:IsValid() then
            type_name = dt:GetClass():GetFName():ToString()
            local okf, full = pcall(function() return dt:GetFullName() end)
            if okf and type(full) == "string" then type_full = full end
            local oks, sup = pcall(function() return dt:GetClass():GetSuperStruct():GetFName():ToString() end)
            if oks and type(sup) == "string" then type_super = sup end
        end
    end)

    local causer_class, causer_name
    pcall(function()
        local c = DamageCauser:get()
        if c and c:IsValid() then
            causer_class = c:GetClass():GetFName():ToString()
            causer_name  = c:GetFName():ToString()
        end
    end)

    if not (type_name or causer_class) then return end
    local family = classify_damage(type_name)
    if type_name then
        last_damage.name   = type_name
        last_damage.family = family
    end
    log(("damage: amt=%s type=%s super=%s full=%s causer=%s (%s) family=%s"):format(
        tostring(amount), tostring(type_name), tostring(type_super), tostring(type_full),
        tostring(causer_class), tostring(causer_name), family))
end

local function install_damage_hook()
    if damage_hook_ok then return end
    local ok = pcall(function() RegisterHook(DAMAGE_HOOK, on_receive_any_damage) end)
    damage_hook_ok = ok
    log((ok and "hooked " or "FAILED to hook (will retry after the pawn loads) ") .. DAMAGE_HOOK)
end

local hook_ok = {}   -- target -> true once RegisterHook succeeds, so we retry only the ones that failed

local function install_hooks()
    for _, target in ipairs(HOOK_TARGETS) do
        if not hook_ok[target] then
            local ok = pcall(function()
                RegisterHook(target, function(self)
                    local cls = activating_class_name(self)
                    -- DIAGNOSTIC: surface any hit-reaction-ish activation (catches renames too) without
                    -- flooding the log with every ability the game fires.
                    local low = tostring(cls):lower()
                    if low:find("hitreact", 1, true) or low:find("reaction", 1, true) then
                        log(("activate: class=%s  via %s"):format(tostring(cls), target))
                    end
                    if cls ~= HITREACT_ABILITY_CLASS then return end
                    local ability = self:get()
                    -- Part 1: report the family captured upstream + what SELECTIVE mode WOULD decide (dry
                    -- run — blanket still suppresses everything below, so behavior is unchanged and safe).
                    local fam = last_damage.family or "unknown"
                    local sel_block = (fam ~= "unknown") and (cfg.ignore_types[fam] == true)
                    log(("hit-react: last_damage=%s family=%s selective_would_block=%s")
                        :format(tostring(last_damage.name), fam, tostring(sel_block)))
                    if should_block(ability) then
                        log("SUPPRESS hit-react — cancelling")
                        local okc = pcall(function() ability:K2_CancelAbility() end)
                        if not okc then pcall(function() ability:K2_EndAbility() end) end   -- >>> CONFIRM: cancel vs end
                    end
                end)
            end)
            hook_ok[target] = ok
            log((ok and "hooked " or "FAILED to hook (will retry after the ability class loads) ") .. target)
        end
    end
end

-- DIAGNOSTIC probe: confirm the hit-react ability class is still discoverable and log its identity.
-- FindAllOf is the proven discovery idiom in this game (FWStealth / TFWQuestHUDToggle).
local function probe()
    for _, cls in ipairs({ HITREACT_ABILITY_CLASS, "FWPlayerGA_HitReaction" }) do
        local found = FindAllOf(cls)
        if not found then
            log(("probe: FindAllOf(%s) -> none live yet"):format(cls))
        else
            local n, sample = 0, "?"
            for _, o in pairs(found) do
                if o:IsValid() then
                    n = n + 1
                    if sample == "?" then
                        local okn, full = pcall(function() return o:GetFullName() end)
                        if okn and full then sample = full end
                    end
                end
            end
            log(("probe: FindAllOf(%s) -> %d live (e.g. %s)"):format(cls, n, sample))
        end
    end
end

-- Per-target install is idempotent (hook_ok guard), so we re-run it on every ClientRestart to RETRY
-- targets that couldn't resolve at mod-load — notably the BP class /Game/.../GA_Player_HitReaction_C,
-- which isn't loaded until the player pawn exists. v0.1.0 (fenix) showed the engine-BASE
-- K2_ActivateAbility hook registers but NEVER fires on a stagger, so either activation is native OR the
-- base hook doesn't catch the BP's own K2_ActivateAbility override. The lazy BP-path hook decides it:
-- if it fires -> we can suppress; if it registers yet stays silent while you stagger -> native, and we
-- pivot (dump_object the live instance to find the montage/native seam; see docs/design-notes.md).
local ok = pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
        log("player restart; mode=" .. cfg.mode)
        install_hooks()          -- GA activation hooks (retry until the ability class is loaded)
        install_damage_hook()    -- ReceiveAnyDamage capture (retry until BP_PlayerBase is loaded)
        ExecuteWithDelay(1500, function() ExecuteInGameThread(probe) end)  -- defer: defs load lazily
    end)
end)
if not ok then log("WARNING: could not register ClientRestart hook") end
install_hooks()
install_damage_hook()

log("loaded v0.1.4 (wide damage capture). mode=" .. cfg.mode
    .. " — blanket still suppresses; per-hit log now carries amt/type/super/full/causer"
    .. " (v0.1.3 live round: 9/9 hits were base FWDamageType and the hit-react never fired)")
