-- Recorded tester timelines — fixtures transcribed verbatim from UE4SS.log.
--
-- Times are the real log timestamps, so inter-event gaps are the real ones. That's the whole point:
-- every bug this harness has caught was a sub-millisecond ordering bug, and made-up timings would
-- have hidden it. When a new round comes back, add its timeline here rather than editing an old one
-- — the old rounds are regression cover.
--
-- Event forms:  { "<timestamp>", "A" }                        hit-react activation
--               { "<timestamp>", "D", <type>, <causer class>, <causer instance> }   ReceiveAnyDamage
--               { "<timestamp>", "R" }                        ClientRestart

-- Damage-type specs: { class, super, full name }
local EXPL = { "BP_ExplosiveDamage_FW_knockback_C", "FWKnockDownDamageType",
               "BP_ExplosiveDamage_FW_knockback_C /Game/FW/Weapons/BP_ExplosiveDamage_FW_knockback.Default__BP_ExplosiveDamage_FW_knockback_C" }
local KNOCK = { "FWKnockDownDamageType", "FWDamageType",
                "FWKnockDownDamageType /Script/FWGameCore.Default__FWKnockDownDamageType" }
local FWDMG = { "FWDamageType", "DamageType", "FWDamageType /Script/FWGameCore.Default__FWDamageType" }
local BASE  = { "DamageType", "Object", "DamageType /Script/Engine.Default__DamageType" }
local FALL  = { "BP_FallDamage_C", "FWGameDamageType",
                "BP_FallDamage_C /Game/FW/Weapons/BP_FallDamage.Default__BP_FallDamage_C" }
local MELEE = { "BP_MeleeDamage_FW_C", "FWGameDamageType",
                "BP_MeleeDamage_FW_C /Game/FW/Weapons/BP_MeleeDamage_FW.Default__BP_MeleeDamage_FW_C" }

local MECHGUN = "BP_WPN_MediumMech_MiniGun_Rear_C"
local CYBORG  = "BP_AI_Eurasia_Cyborg_C"
local RIFLE   = "BP_WPN_AI_HRF01a_C"

return {
    {
        name    = "2026-07-30 fenix, session 2 (v0.1.6)",
        note    = "one fall, one explosive stagger, then a mech-melee killshot that never staggers",
        cancels = 1, activations = 1,
        events  = {
            { "20:28:08.1535179", "D", FALL,  nil,                nil },
            { "20:28:27.7721434", "A" },
            { "20:28:27.7723955", "D", EXPL,  nil,                nil },
            { "20:28:27.9673163", "D", MELEE, "BP_Mech_MedMech_C", "BP_Mech_MedMech_C_2147434538" },
        },
    },
    {
        name    = "2026-07-30 fenix, session 3 (v0.1.6)",
        note    = "the round that exposed the two-sided ordering — the 20:38:30 cyborg melee "
               .. "broadcasts its damage line 0.67 ms BEFORE its own activation, where every "
               .. "explosive/knockdown hit broadcasts ~0.3 ms after. v0.1.6 leaks the last one.",
        cancels = 6, activations = 6,
        events  = {
            { "20:36:16.0865475", "A" },
            { "20:36:16.0868763", "D", EXPL,  nil,     nil },
            { "20:36:34.7393688", "A" },
            { "20:36:34.7397350", "D", KNOCK, MECHGUN, "BP_WPN_MediumMech_MiniGun_Rear_C_2147393680" },
            { "20:36:34.9362433", "D", KNOCK, MECHGUN, "BP_WPN_MediumMech_MiniGun_Rear_C_2147393680" },
            { "20:36:41.3958246", "D", KNOCK, MECHGUN, "BP_WPN_MediumMech_MiniGun_Rear_C_2147393680" },
            { "20:36:59.9096899", "A" },
            { "20:36:59.9099621", "D", EXPL,  nil,     nil },
            { "20:37:40.7896948", "A" },
            { "20:37:40.7899775", "D", EXPL,  nil,     nil },
            { "20:37:40.8791771", "D", EXPL,  nil,     nil },
            { "20:37:40.9176522", "D", EXPL,  nil,     nil },
            { "20:37:41.1335963", "D", EXPL,  nil,     nil },
            { "20:38:21.6663956", "A" },
            { "20:38:21.6667026", "D", EXPL,  nil,     nil },
            { "20:38:27.8525141", "D", EXPL,  nil,     nil },
            { "20:38:30.0181652", "D", BASE,  CYBORG,  "BP_AI_Eurasia_Cyborg_C_2147333323" },  -- trigger
            { "20:38:30.0188379", "A" },                                                       -- 0.67 ms later
            { "20:38:30.4305464", "D", KNOCK, MECHGUN, "BP_WPN_MediumMech_MiniGun_Rear_C_2147393678" },
            { "20:38:30.6745874", "D", FWDMG, RIFLE,   "BP_WPN_AI_HRF01a_C_2147394156" },
            { "20:38:30.8604666", "D", FWDMG, RIFLE,   "BP_WPN_AI_HRF01a_C_2147394156" },
            { "20:38:32.4141222", "D", BASE,  CYBORG,  "BP_AI_Eurasia_Cyborg_C_2147333323" },
        },
    },
}
