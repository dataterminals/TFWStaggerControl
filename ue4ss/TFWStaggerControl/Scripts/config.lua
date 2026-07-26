-- TFWStaggerControl — user config
-- Edit these values, then relaunch the game (or re-run the mod). Human-editable on purpose.

return {
    -- Master switch. "off" = do nothing. "blanket" = suppress ALL combat stagger (the proven-simple
    -- path: 7/7 live activations cancelled). "selective" = per-family control: each stagger is
    -- classified by what caused it and suppressed iff its family is ticked below (v0.1.6 defers the
    -- cancel to the damage line that lands ~0.5 ms after activation). With the default list below,
    -- selective should FEEL identical to blanket — plain gunfire never staggers anyway — while
    -- exercising the per-type machinery end to end.
    mode = "selective",   -- "off" | "blanket" | "selective"

    -- PART 1 — damage-type families to always ignore stagger from (used when mode == "selective").
    -- These are honored regardless of skill tree. Set true to make that family never stagger you.
    ignore_types = {
        explosive = true,   -- BP_ExplosiveDamage_FW, BP_ExplosiveDamage_FW_knockback, grenade launcher
        heavy     = true,   -- BP_TankMainGunDamage_FW, BP_TurretProjectileDamage_FW
        melee     = true,   -- BP_MeleeDamage_FW, BP_DamageType_AssaultInfantry(_Knockdown)
        ballistic = false,  -- BP_ProjectileDamage_FW, BP_ShotgunDamage_FW
        fall      = false,  -- BP_FallDamage
        other     = false,  -- anything unmatched (incl. environmental)
    },

    -- PART 2 (UE4SS behavior) — how much each owned skill tag contributes.
    -- Per-type immunity tags fully block that family; % tags stack into a shrug-off chance (0..1).
    skill = {
        -- PlayerSkill.Global.StaggerResist.Type.<Family>  → full immunity for that family
        type_immunity_tag = "PlayerSkill.Global.StaggerResist.Type.",  -- + Explosive/Heavy/Melee
        -- PlayerSkill.Global.StaggerResist.Chance_0N → each tier adds this much shrug-off chance
        chance_tag_prefix = "PlayerSkill.Global.StaggerResist.Chance_",
        chance_per_tier   = 0.20,   -- 5 tiers → 100% at max; tune to taste
        -- The pak "full immunity" capstone grants the real Ability.HitReactionBlocked directly,
        -- so it works with NO UE4SS and needs no logic here.
    },

    -- Map each damage-type family to the Blueprint class-name substrings that identify it.
    -- The type DOES arrive real for some sources — CONFIRMED live: BP_ExplosiveDamage_FW_knockback
    -- (with causer=nil, so this table is what catches explosions), BP_ShotgunDamage_FW,
    -- BP_FallDamage. Rapid-fire guns and melee arrive as base-class CDOs and fall to the CAUSER
    -- tables below. Type gets first shot, causer decides the rest.
    type_classes = {
        explosive = { "ExplosiveDamage", "GrenadeLauncher" },
        heavy     = { "TankMainGunDamage", "TurretProjectileDamage" },
        melee     = { "MeleeDamage", "AssaultInfantry" },
        ballistic = { "ProjectileDamage", "ShotgunDamage" },
        fall      = { "FallDamage" },
    },

    -- The CAUSER signal (checked when the type arrives erased). The DamageCauser actor names itself:
    -- gunfire/launchers pass the weapon actor (BP_WPN_<code>), melee passes the attacking pawn
    -- (BP_AI_*). Checked IN ORDER (array), so WPN_GRL lands "explosive" and Mech weapons land
    -- "heavy" before the generic weapon→ballistic fallback below.
    -- CONFIRMED from fenix's logs — ballistic: WPN_SMG05AI/SMG06AI, WPN_LMG03_AI, WPN_AI_HRF01a,
    -- WPN_AI_RFL01_LowTech, WPN_SHG05_AI, WPN_Exo_LeftStubbyGun (prefix fallback),
    -- WPN_Europa_Merkava_Machinegun, WPN_Drone; explosive: WPN_GRL00; heavy: WPN_20mmTurret,
    -- WPN_MediumMech_MiniGun_Rear + WPN_MediumMech_LongRifle (via "Mech" — both carry the native
    -- knockdown type); melee: BP_AI_Eurasia_Crawler. Explosions arrive causer=nil but with the REAL
    -- type class, so the type table above catches them. The rest are educated guesses.
    causer_classes = {
        { family = "explosive", needles = { "WPN_GRL", "Grenade", "RPG", "Rocket", "Explos", "Barrel", "Mortar", "Mine" } },
        { family = "heavy",     needles = { "Tank", "Turret", "Cannon", "Artil", "Mech" } },
        { family = "melee",     needles = { "BP_AI_" } },   -- the pawn itself as causer = a melee hit
        { family = "ballistic", needles = { "WPN_SMG", "WPN_AR", "WPN_RIF", "WPN_MG", "WPN_LMG", "WPN_HMG",
                                            "WPN_SNP", "WPN_SHG", "Shotgun", "Sniper", "Rifle", "Pistol", "Drone" } },
    },
    causer_weapon_prefix = "BP_WPN_",   -- any unmatched weapon actor defaults to ballistic

    debug = true,   -- print decisions to the UE4SS console while dialing this in
}
