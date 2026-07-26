-- TFWStaggerControl — UE4SS Lua layer (optional upgrade over the static pak)
--
-- One hook on the player hit-react ability. It decides block/allow from (1) config damage-type list
-- (Part 1) and (2) owned resistance skill tags (Part 2 graded/per-type). The static pak works without
-- this file; this file adds per-type selectivity and graded % that pure data can't express.
--
-- STATUS: suppression PROVEN in live fire — 7/7 hit-react activations cancelled (explosive knockback
-- ×5, medium-mech rear minigun ×2), tester felt zero staggers. Trigger model: the GA fires ONLY on
-- FWKnockDownDamageType-lineage hits; 100+ plain gun hits fired it zero times. Types arrive REAL for
-- knockdown/shotgun/fall hits and ERASED (base CDOs) for rapid-fire guns — classification uses type
-- first, else the DamageCauser actor. Ordering (7/7): activation precedes the hit's own
-- ReceiveAnyDamage by ~0.5 ms, so selective mode defers its cancel to the damage hook (v0.1.6).
-- KNOWN SEPARATE PATHS (not this ability, not suppressed): the physics launch/ragdoll ("fly away")
-- and fall damage. Tools on-box: ConsoleCommandsMod `dump_object`/`set`, `FindAllOf`.

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

-- v0.1.5: classify by the DamageCauser actor instead — the damage-type class never survives to
-- ReceiveAnyDamage (two live rounds: every hit was a base-class CDO), but the causer names itself:
-- weapon actors are BP_WPN_<code> and melee arrives with the attacking PAWN (BP_AI_*) as causer.
-- Ordered needles (config array) so WPN_GRL lands "explosive" before the weapon→ballistic fallback.
local function classify_causer(causer_class)
    if not causer_class then return "other" end
    for _, entry in ipairs(cfg.causer_classes) do
        for _, needle in ipairs(entry.needles) do
            if string.find(causer_class, needle, 1, true) then return entry.family end
        end
    end
    if cfg.causer_weapon_prefix and string.find(causer_class, cfg.causer_weapon_prefix, 1, true) == 1 then
        return "ballistic"   -- an unmatched weapon actor is still a gun until a log line proves otherwise
    end
    return "other"
end

-- Set on each incoming hit by the ReceiveAnyDamage capture; read back by the hit-react hook and by
-- selective mode. Declared here (above the decision section) so all readers close over one local.
local last_damage = { name = nil, family = "unknown" }

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

-- (v0.1.5: the CurrentEventData payload reader is GONE — v0.1.2 proved the payload carries only the
-- generic trigger tag, and v0.1.4 proved the UDamageType arrives type-erased even upstream. The
-- family now comes exclusively from the ReceiveAnyDamage capture below; see docs/design-notes.md #2.)

-- ---------------------------------------------------------------------------
-- decision
-- ---------------------------------------------------------------------------

-- Return true (plus a reason) to SUPPRESS a hit-react whose triggering hit classified as `family`.
-- Part 1 = the config family list. Part 2 (skill tags) reuses the same seam once tag reads are
-- confirmed on-box (asc_has_tag is still a stub — it always returns false for now).
local function family_blocks(family, ability)
    if cfg.ignore_types[family] then return true, "config family " .. family end
    local asc = nil
    pcall(function() asc = ability and ability:GetAbilitySystemComponentFromActorInfo() end)  -- >>> CONFIRM ON-BOX
    local imm_tag = cfg.skill.type_immunity_tag ..
        (family:sub(1,1):upper() .. family:sub(2))   -- e.g. "...Type.Explosive"
    if asc_has_tag(asc, imm_tag) then return true, "skill immunity " .. imm_tag end
    local chance = graded_chance(asc)
    if chance > 0 and math.random() < chance then
        return true, ("graded roll (chance=%.2f)"):format(chance)
    end
    return false, nil
end

-- v0.1.6 — the live rounds killed the "decide at activation" plan: 7/7 observed activations logged
-- ~0.5 ms BEFORE the triggering hit's own ReceiveAnyDamage line (the GameplayEvent is sent from
-- inside damage processing, before the AnyDamage broadcast reaches BP). At activation time
-- last_damage still holds the PREVIOUS hit — deciding there is off-by-one. So selective mode parks
-- the live ability here and the damage hook (same frame, sub-ms later) classifies the real hit and
-- cancels. Same-frame cancel means the montage never renders a frame before it dies.
local pending = { ability = nil, at = 0.0 }
local PENDING_WINDOW_S = 0.10   -- the damage line lands <1 ms later; 100 ms is a generous ceiling

local function cancel_ability(ability, why)
    log("SUPPRESS hit-react — cancelling (" .. why .. ")")
    local okc = pcall(function() ability:K2_CancelAbility() end)
    if not okc then pcall(function() ability:K2_EndAbility() end) end   -- >>> CONFIRM: cancel vs end
end

-- ---------------------------------------------------------------------------
-- hook + on-box diagnostics
-- ---------------------------------------------------------------------------
-- Strategy: intercept the hit-react ability activation; blanket cancels on the spot, selective
-- parks the ability and cancels from the damage hook once the triggering hit is classified.
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
-- v0.1.4 asked "is the type real here?" — answer (refined over two rounds): SOMETIMES. Rapid-fire
-- guns and melee arrive type-erased (base CDOs) — for those the CAUSER names the hit
-- (BP_WPN_SMG06AI_C, BP_WPN_Exo_LeftStubbyGun_C, BP_AI_Eurasia_Crawler_C = melee pawn). But
-- knockdown-class hits DO deliver the real type (BP_ExplosiveDamage_FW_knockback_C with causer=nil,
-- native FWKnockDownDamageType on mech weapons), and shotguns/fall deliver BP_ShotgunDamage_FW_C /
-- BP_FallDamage_C. So classification gives the type first shot, then falls to the causer — both
-- paths confirmed correct on every live hit so far.
local DAMAGE_HOOK    = "/Game/FW/Player/BP_PlayerBase.BP_PlayerBase_C:ReceiveAnyDamage"
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
    local family, via = classify_damage(type_name), "type"
    if family == "other" then
        family = classify_causer(causer_class)
        via = (family ~= "other") and "causer" or "none"
    end
    last_damage.name   = causer_class or type_name
    last_damage.family = family
    log(("damage: amt=%s type=%s super=%s full=%s causer=%s (%s) family=%s via=%s"):format(
        tostring(amount), tostring(type_name), tostring(type_super), tostring(type_full),
        tostring(causer_class), tostring(causer_name), family, via))

    -- v0.1.6: resolve a parked selective-mode hit-react — THIS damage line is the hit that triggered
    -- it (activation precedes its own damage line by ~0.5 ms; see the decision section).
    if pending.ability then
        local age = os.clock() - pending.at
        local a = pending.ability
        pending.ability = nil
        if age <= PENDING_WINDOW_S then
            local block, why = family_blocks(family, a)
            if block then
                cancel_ability(a, ("%s, deferred %.1f ms"):format(why, age * 1000))
            else
                log(("allow hit-react — family=%s not blocked (deferred %.1f ms)"):format(family, age * 1000))
            end
        else
            log(("pending hit-react expired unresolved (%.0f ms) — allowed"):format(age * 1000))
        end
    end
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
                    -- NB: last_damage at this instant is the PREVIOUS hit — the trigger's own damage
                    -- line lands ~0.5 ms from now (7/7 live activations). Logged for the record only.
                    log(("hit-react: prev_damage=%s prev_family=%s mode=%s")
                        :format(tostring(last_damage.name), tostring(last_damage.family), cfg.mode))
                    if cfg.mode == "off" then return end
                    if cfg.mode == "blanket" then
                        cancel_ability(ability, "blanket")
                        return
                    end
                    -- selective: park it; the damage hook classifies the real hit and decides.
                    pending.ability = ability
                    pending.at = os.clock()
                    log("hit-react pending — awaiting the damage line to classify")
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
        pending.ability = nil    -- v0.1.6: never carry a parked hit-react across a spawn
        install_hooks()          -- GA activation hooks (retry until the ability class is loaded)
        install_damage_hook()    -- ReceiveAnyDamage capture (retry until BP_PlayerBase is loaded)
        ExecuteWithDelay(1500, function() ExecuteInGameThread(probe) end)  -- defer: defs load lazily
    end)
end)
if not ok then log("WARNING: could not register ClientRestart hook") end
install_hooks()
install_damage_hook()

log("loaded v0.1.6 (deferred selective). mode=" .. cfg.mode
    .. " — suppression PROVEN 7/7 live; selective now parks the activation and decides on the damage"
    .. " line that lands ~0.5 ms later (activation-before-damage ordering, observed 7/7)")
