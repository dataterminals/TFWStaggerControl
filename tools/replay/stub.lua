-- Fake UE4SS environment, so main.lua can be loaded and driven outside the game.
--
-- main.lua talks to the world through RegisterHook + UObject wrappers (every hook argument arrives
-- as something you call :get() on). None of that needs a game to exist — it just needs objects that
-- answer the same method calls. This module supplies them, plus a controllable clock, since every
-- interesting decision in the mod is about sub-millisecond ordering.
--
-- What this CANNOT tell you: whether K2_CancelAbility really kills the montage, whether the hook
-- targets resolve against real UFunctions, or whether a timing case exists that no log has shown.
-- Those need a launch. This only proves the decision logic given a known sequence of events.

local M = {}

M.ACTIVATE_HOOK = "/Game/FW/Player/GameplayAbilities/GA_Player_HitReaction.GA_Player_HitReaction_C:K2_ActivateAbility"
M.DAMAGE_HOOK   = "/Game/FW/Player/BP_PlayerBase.BP_PlayerBase_C:ReceiveAnyDamage"
M.RESTART_HOOK  = "/Script/Engine.PlayerController:ClientRestart"

-- ------------------------------------------------------------------ the clock
-- Replaces os.clock process-wide; main.lua reads it at call time, so this is enough.
local now = 0.0
os.clock = function() return now end

function M.at(t) now = t end

-- "20:36:16.0865475" -> seconds. Log timestamps go straight in as event times.
function M.secs(hhmmss)
    local h, m, s = hhmmss:match("^(%d+):(%d+):([%d%.]+)$")
    assert(h, "bad timestamp: " .. tostring(hhmmss))
    return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
end

-- --------------------------------------------------------------- fake UObjects
local function fname(s) return { ToString = function() return s end } end

function M.wrap(v) return { get = function() return v end } end

-- A UDamageType. `spec` is {class, super, fullname}; fullname defaults to the class.
function M.damage_type(spec)
    if not spec then return M.wrap(nil) end
    return M.wrap({
        IsValid     = function() return true end,
        GetFullName = function() return spec[3] or spec[1] end,
        GetClass    = function() return {
            GetFName       = function() return fname(spec[1]) end,
            GetSuperStruct = function() return { GetFName = function() return fname(spec[2]) end } end,
        } end,
    })
end

-- The DamageCauser actor. nil is meaningful — explosions genuinely arrive with no causer.
function M.actor(class_name, instance_name)
    if not class_name then return M.wrap(nil) end
    return M.wrap({
        IsValid  = function() return true end,
        GetFName = function() return fname(instance_name or (class_name .. "_1")) end,
        GetClass = function() return { GetFName = function() return fname(class_name) end } end,
    })
end

function M.new_ability()
    local a
    a = {
        cancelled = false,
        GetClass  = function() return { GetFName = function() return fname("GA_Player_HitReaction_C") end } end,
        K2_CancelAbility = function() a.cancelled = true end,
        K2_EndAbility    = function() a.cancelled = true end,
    }
    return a
end

-- ------------------------------------------------------------------ the mod
function M.load_mod(scripts_dir)
    M.hooks, M.lines = {}, {}
    package.loaded["config"] = nil
    package.path = scripts_dir .. "/?.lua;" .. package.path

    _G.print               = function(s) M.lines[#M.lines + 1] = tostring(s):gsub("\n$", "") end
    _G.RegisterHook        = function(target, fn) M.hooks[target] = fn end
    _G.FindAllOf           = function() return nil end
    _G.ExecuteWithDelay    = function() end
    _G.ExecuteInGameThread = function() end

    dofile(scripts_dir .. "/main.lua")
end

-- ------------------------------------------------------------------- driving
function M.fire_activation()
    local a = M.new_ability()
    M.hooks[M.ACTIVATE_HOOK](M.wrap(a))
    return a
end

function M.fire_damage(type_spec, causer_class, causer_inst, amount)
    M.hooks[M.DAMAGE_HOOK](M.wrap({}), M.wrap(amount or 0.0),
        M.damage_type(type_spec), M.wrap(nil), M.actor(causer_class, causer_inst))
end

function M.fire_restart() M.hooks[M.RESTART_HOOK]() end

-- Log lines that represent an outcome, for printing next to a failure. Matched narrowly on purpose:
-- the "loaded" banner quotes the word "expired" and would otherwise show up as a verdict.
local VERDICTS = { "SUPPRESS hit%-react", "allow hit%-react", "pending hit%-react expired" }

function M.verdict_lines()
    local out = {}
    for _, l in ipairs(M.lines) do
        for _, pat in ipairs(VERDICTS) do
            if l:find(pat) then out[#out + 1] = (l:gsub("%[TFWStaggerControl%] ", "")); break end
        end
    end
    return out
end

return M
