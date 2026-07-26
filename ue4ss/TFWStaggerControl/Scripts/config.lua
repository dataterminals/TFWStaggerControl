-- TFWStaggerControl — user config
-- Edit these values, then relaunch the game (or re-run the mod). Human-editable on purpose.

return {
    -- Master switch. "off" = do nothing. "blanket" = ignore ALL stagger (the pak-only equivalent,
    -- and the cheapest way to smoke-test the core seam). "selective" = honor the per-type list +
    -- skill tags below. Start on "blanket" to prove the hook works, then move to "selective".
    mode = "blanket",   -- "off" | "blanket" | "selective"

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
    -- (Kept for completeness: two live rounds showed the damage type always arrives as a base-class
    -- CDO at ReceiveAnyDamage, so in practice the CAUSER tables below decide the family.)
    type_classes = {
        explosive = { "ExplosiveDamage", "GrenadeLauncher" },
        heavy     = { "TankMainGunDamage", "TurretProjectileDamage" },
        melee     = { "MeleeDamage", "AssaultInfantry" },
        ballistic = { "ProjectileDamage", "ShotgunDamage" },
        fall      = { "FallDamage" },
    },

    -- v0.1.5 — the LIVE per-type signal. The DamageCauser actor names itself: gunfire/launchers pass
    -- the weapon actor (BP_WPN_<code>), melee passes the attacking pawn (BP_AI_*). Checked IN ORDER
    -- (array), so WPN_GRL lands "explosive" before the generic weapon→ballistic fallback below.
    -- Confirmed needles from fenix's logs: WPN_SMG (gunfire), WPN_GRL (grenade launcher), BP_AI_
    -- (Crawler melee). The rest are educated guesses — every damage: log line teaches real names.
    causer_classes = {
        { family = "explosive", needles = { "WPN_GRL", "Grenade", "RPG", "Rocket", "Explos", "Barrel", "Mortar", "Mine" } },
        { family = "heavy",     needles = { "Tank", "Turret", "Cannon", "Artil" } },
        { family = "melee",     needles = { "BP_AI_" } },   -- the pawn itself as causer = a melee hit
        { family = "ballistic", needles = { "WPN_SMG", "WPN_AR", "WPN_RIF", "WPN_MG", "WPN_LMG", "WPN_HMG",
                                            "WPN_SNP", "WPN_SHG", "Shotgun", "Sniper", "Rifle", "Pistol" } },
    },
    causer_weapon_prefix = "BP_WPN_",   -- any unmatched weapon actor defaults to ballistic

    debug = true,   -- print decisions to the UE4SS console while dialing this in
}
