--!nonstrict
-- GameConfig: tuning for combat, battles, the villain, progression and saving. Pure data (no Roblox APIs).
-- Movement tuning stays in BeyConfig.Movement; parts, rarities and crate odds stay in BeyConfig.

local GameConfig = {}

-- What each stat does (bey stats = the three parts' stats x the level multiplier; see BeyConfig.ComputeStats):
--   Attack   more damage dealt per hit (AttackScale per point) and a little more top speed
--   Defense  less damage taken (DefenseScale per point) and less knockback taken
--   Stamina  a bigger spin pool (SpinPerStamina per point) and slower passive spin loss
--   Balance  less knockback taken and less self-damage when your slam lands, and a little more top speed
GameConfig.Combat = {
	BaseSpin = 100, -- spin pool before Stamina
	SpinPerStamina = 4,
	BaseDrain = 0.9, -- spin lost per second just by spinning
	DrainReductionPerStamina = 0.02, -- each Stamina point slows that drain by 2% (capped)
	MaxDrainReduction = 0.6,

	ContactDistance = 4.4, -- centres closer than this = the beys are touching (bodies are 4-stud balls)
	SeparationDistance = 5.4, -- must separate this far before the same pair can register a new hit
	HitCooldown = 0.35, -- and at least this long between hits for the same pair
	MinImpactSpeed = 6, -- closing speeds below this are a nudge, not a hit
	DamagePerSpeed = 0.42, -- damage per stud/s of closing speed above the minimum
	MinHitDamage = 1,
	MaxHitDamage = 22,
	AttackScale = 0.04,
	DefenseScale = 0.04,
	KnockbackPerSpeed = 1.0,
	MaxKnockback = 80,
	KnockbackResistPerPoint = 0.02, -- per point of Defense + Balance, capped
	MaxKnockbackResist = 0.6,

	SlamRadius = 9, -- a landing slam hits beys within this distance
	SlamMinFallSpeed = 45, -- the server must have seen the slammer falling at least this fast
	SlamFallWindow = 0.6, -- ... within this many seconds before the landing report
	SlamBaseDamage = 10,
	SlamDamagePerSpeed = 0.1,
	SlamMaxDamage = 26,
	SlamKnockback = 55,
	SlamRecoil = 3, -- spin the slammer itself loses, reduced by Balance
	SlamCooldown = 1.0, -- server-side minimum between accepted slams (client cooldown is longer)

	RequestsPerSecond = 8, -- rate limit for battle requests from one player
	LowSpinFraction = 0.25, -- below this the HUD warns and the bey wobbles
	VisualSpinMin = 6, -- cosmetic hub spin (rad/s) at 0 spin and at full spin
	VisualSpinMax = 40,
}

GameConfig.Battle = {
	Countdown = 3,
	Duration = 90, -- then the higher spin share wins
	DrawMargin = 0.02, -- spin shares this close at timeout = draw
	ResultTimeout = 45, -- the result screen closes itself after this
	RingOutRadius = 42.5, -- past the rim (42): a bey inside the bowl never gets beyond ~41, one on the rim ledge is out
	RingOutBelowY = -10,
	RingOutGrace = 0.4, -- seconds a bey must stay outside before it counts (falling below the floor counts at once)
	StartRadius = 12, -- where the two beys start, either side of the centre
}

GameConfig.Difficulty = {
	-- Speed: villain top-speed multiplier. Windup: seconds of warning before an attack. Aggression: 0..1 how often it
	-- attacks when in range. Damage: multiplier on its hits. Reward: multiplier on rewards for beating it.
	Easy = { Speed = 0.85, Windup = 1.0, Aggression = 0.45, Damage = 0.8, Reward = 0.8 },
	Normal = { Speed = 0.95, Windup = 0.75, Aggression = 0.7, Damage = 1.0, Reward = 1.0 },
	Hard = { Speed = 1.08, Windup = 0.55, Aggression = 0.95, Damage = 1.15, Reward = 1.5 },
}

GameConfig.Villain = {
	Id = "rook",
	Name = "Rook the Grinder",
	Parts = { Layer = "layer_skyrend", Disc = "disc_bulwarkring", Driver = "driver_spikegrip" }, -- all Uncommon
	Level = 3,
	Difficulty = "Normal",
	-- After this many wins against it, the next rematch uses Hard (shown to the player).
	HardAfterWins = 3,
}

GameConfig.Progression = {
	MaxLevel = 50, -- matches BeyConfig.MaxLevel
	XPCurveBase = 60, -- XP needed for level L is XPCurveBase * (L-1)^1.6 (rounded)
	XPCurvePower = 1.6,
	Rewards = { -- per battle outcome, before the difficulty multiplier
		win = { XP = 40, Shards = 30 },
		loss = { XP = 15, Shards = 8 },
		draw = { XP = 25, Shards = 15 },
	},
	-- The Workshop sells parts for Shards (earned only by playing). This is the deterministic route to the cap:
	-- every rarity up to Legendary can be bought, and level 50 gives the full level multiplier. Ultra Legendary is
	-- never sold for Shards (it is the paid tier, and paid crates are disabled for now).
	Prices = { Common = 20, Uncommon = 60, Rare = 150, Epic = 350, Legendary = 800 },
	RecentBattleMemory = 30, -- battle ids remembered per player to refuse duplicate rewards
	MinLossSecondsForReward = 20, -- a loss pays nothing if the battle lasted less than this (stops ring-out farming)
}

GameConfig.Data = {
	StoreName = "SpinforgePlayers_v1",
	AutosaveInterval = 120,
	LockTimeout = 600, -- a session lock older than this (seconds) is treated as abandoned
	LoadAttempts = 4,
	RetryWait = 2,
}

return GameConfig
