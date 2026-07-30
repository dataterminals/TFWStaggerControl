-- Replay recorded tester timelines through the real main.lua.
--
--   lua replay.lua [path/to/ue4ss/TFWStaggerControl/Scripts]
--
-- Exits non-zero if any timeline suppresses a different number of activations than recorded, so it
-- works as a regression gate. See README.md for what this does and does not prove.

local here = arg[0]:match("^(.*)[/\\][^/\\]+$") or "."
package.path = here .. "/?.lua;" .. package.path

local stub      = require("stub")
local timelines = require("timelines")

local SCRIPTS = arg[1] or (here .. "/../../ue4ss/TFWStaggerControl/Scripts")

local function replay(tl)
    stub.at(stub.secs(tl.events[1][1]) - 60)   -- the mod loads a minute before the first event
    stub.load_mod(SCRIPTS)

    local abilities = {}
    for _, e in ipairs(tl.events) do
        stub.at(stub.secs(e[1]))
        if e[2] == "A" then
            abilities[#abilities + 1] = stub.fire_activation()
        elseif e[2] == "R" then
            stub.fire_restart()
        else
            stub.fire_damage(e[3], e[4], e[5])
        end
    end

    local cancelled = 0
    for _, a in ipairs(abilities) do if a.cancelled then cancelled = cancelled + 1 end end
    return cancelled, #abilities
end

local failed = false
for _, tl in ipairs(timelines) do
    local cancelled, total = replay(tl)
    local ok = (cancelled == tl.cancels and total == tl.activations)
    failed = failed or not ok
    io.write(("%s  %s\n"):format(ok and "PASS" or "FAIL", tl.name))
    io.write(("      %d/%d activations cancelled (expected %d/%d)\n")
        :format(cancelled, total, tl.cancels, tl.activations))
    for _, l in ipairs(stub.verdict_lines()) do io.write("        " .. l .. "\n") end
end

if failed then
    io.write("\nTIMELINE REGRESSION — the decision logic no longer reproduces recorded behaviour.\n")
    os.exit(1)
end
io.write("\nall timelines reproduce as recorded\n")
