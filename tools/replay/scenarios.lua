-- Synthetic scenarios — the cases no tester log contains yet.
--
--   lua scenarios.lua [path/to/ue4ss/TFWStaggerControl/Scripts]
--
-- Recorded timelines prove we still handle what actually happened. These prove we handle what could
-- happen next, and they exist mostly to pin down the one risk the v0.1.7 look-behind introduces: a
-- damage line that is NOT the trigger landing inside the look-behind window. Look-behind is
-- cancel-only so that case can't leak; scenarios 2, 3 and 6 are what hold that property in place.

local here = arg[0]:match("^(.*)[/\\][^/\\]+$") or "."
package.path = here .. "/?.lua;" .. package.path

local stub = require("stub")
local SCRIPTS = arg[1] or (here .. "/../../ue4ss/TFWStaggerControl/Scripts")

local EXPL  = { "BP_ExplosiveDamage_FW_knockback_C", "FWKnockDownDamageType" }
local KNOCK = { "FWKnockDownDamageType", "FWDamageType" }
local FWDMG = { "FWDamageType", "DamageType" }
local BASE  = { "DamageType", "Object" }

local CYBORG  = "BP_AI_Eurasia_Cyborg_C"
local RIFLE   = "BP_WPN_AI_HRF01a_C"
local MECHGUN = "BP_WPN_MediumMech_MiniGun_Rear_C"

local failed = false

-- steps: { offset_seconds, "A" | "R" | "D", <type>, <causer> }
-- `expect` is the fate of the LAST activation in the scenario.
local function scenario(name, expect, steps)
    stub.at(1000.0)
    stub.load_mod(SCRIPTS)
    local last
    for _, s in ipairs(steps) do
        stub.at(1000.0 + s[1])
        if s[2] == "A" then last = stub.fire_activation()
        elseif s[2] == "R" then stub.fire_restart()
        else stub.fire_damage(s[3], s[4]) end
    end
    local got = (last and last.cancelled) and "CANCELLED" or "allowed"
    local ok  = (got == expect)
    failed = failed or not ok
    io.write(("%s  %-56s -> %-9s (want %s)\n"):format(ok and "PASS" or "FAIL", name, got, expect))
    for _, l in ipairs(stub.verdict_lines()) do io.write("        " .. l .. "\n") end
end

-- 1. The v0.1.6 leak itself, isolated: melee damage line 0.67 ms BEFORE its own activation.
scenario("melee trigger lands BEFORE activation", "CANCELLED", {
    { 0.00000, "D", BASE, CYBORG },
    { 0.00067, "A" },
})

-- 2. THE RISK: a rifle round lands 1 ms before the activation, but the real trigger is the explosive
--    line 0.3 ms after it. Look-behind must not consume the decision.
scenario("coincident bullet in window, real trigger is forward", "CANCELLED", {
    { 0.0000, "D", FWDMG, RIFLE },
    { 0.0010, "A" },
    { 0.0013, "D", EXPL, nil },
})

-- 3. Same, with a causer-classified forward trigger rather than a type-classified one.
scenario("coincident bullet in window, forward trigger is heavy", "CANCELLED", {
    { 0.0000, "D", FWDMG, RIFLE },
    { 0.0010, "A" },
    { 0.0013, "D", KNOCK, MECHGUN },
})

-- 4. The unchanged forward path: prev damage is 18 s stale, trigger arrives after.
scenario("stale prev damage, normal forward ordering", "CANCELLED", {
    { 0.0000, "D", FWDMG, RIFLE },
    { 18.000, "A" },
    { 18.0003, "D", EXPL, nil },
})

-- 5. A hit just OUTSIDE the look-behind window is not the trigger, so it must not be used. With
--    nothing forward either, this parks and expires exactly as before.
scenario("prev damage 8 ms back (outside window), nothing forward", "allowed", {
    { 0.000, "D", BASE, CYBORG },
    { 0.008, "A" },
    { 0.500, "D", FWDMG, RIFLE },
})

-- 6. ballistic is unticked in the shipped config: a genuine ballistic trigger behind the activation
--    must still be ALLOWED. Cancel-only must not have become cancel-always.
scenario("ballistic trigger behind activation stays allowed", "allowed", {
    { 0.0000, "D", FWDMG, RIFLE },
    { 0.0007, "A" },
})

-- 7. A parked ability must never survive a respawn.
scenario("parked ability dropped on ClientRestart", "allowed", {
    { 0.00, "A" },
    { 0.05, "R" },
    { 0.06, "D", EXPL, nil },
})

if failed then
    io.write("\nSCENARIO FAILURES\n")
    os.exit(1)
end
io.write("\nall scenarios pass\n")
