-- Appended after the stubs and BeyConfig by run_tests.sh.
print("BeyConfig loaded; parts:", (function() local n = 0 for _ in pairs(BeyConfig.Parts) do n += 1 end return n end)())

for boxId in pairs(BeyConfig.Boxes) do
	local rows, total = BeyConfig.GetDisplayOdds(boxId), 0
	for _, r in ipairs(rows) do total += r.Percent end
	assert(math.abs(total - 100) < 1e-9, boxId .. " display odds total " .. total)
	print(boxId, #rows .. " display rows, total " .. total .. "%")
end

local N = 400000
local rng = Random.new()
for boxId, box in pairs(BeyConfig.Boxes) do
	local counts = {}
	for _ = 1, N do
		local ids = BeyConfig.RollBox(boxId, rng)
		local r = BeyConfig.Parts[ids[1]].Rarity
		if box.Kind == "Bey" then
			for _, id in ipairs(ids) do assert(BeyConfig.Parts[id].Rarity == r, "mixed rarities in a full bey") end
			assert(#ids == 3)
		else
			assert(#ids == 1)
		end
		counts[r] = (counts[r] or 0) + 1
	end
	print(boxId .. " simulated vs stated (%):")
	for _, rarity in ipairs(BeyConfig.Rarities) do
		local sim = (counts[rarity] or 0) / N * 100
		local want = box.Odds[rarity] / 100
		print(string.format("  %-15s %7.3f  %7.3f", rarity, sim, want))
		assert(math.abs(sim - want) < math.max(0.15, want * 0.15), rarity .. " off")
	end
end

local starter = BeyConfig.ComputeStats(BeyConfig.StarterBey, 1)
local maxed = BeyConfig.ComputeStats(BeyConfig.StarterBey, BeyConfig.MaxLevel)
print(string.format("starter L1 attack %.1f, L50 attack %.1f", starter.Attack, maxed.Attack))

for _, slot in ipairs(BeyConfig.Slots) do
	local best, ul = 0, 0
	for _, p in pairs(BeyConfig.Parts) do
		if p.Slot == slot then
			local t = 0 for _, s in ipairs(BeyConfig.StatNames) do t += p.Stats[s] end
			if p.Rarity == "Legendary" then best = math.max(best, t) end
			if p.Rarity == "UltraLegendary" then ul = t end
		end
	end
	print(string.format("%-6s best legendary %d, ultra %d (+%.1f%%)", slot, best, ul, (ul / best - 1) * 100))
end

-- Every part must have a design with a style that its slot's builder knows.
for id, part in pairs(BeyConfig.Parts) do
	local d = BeyDesigns.Parts[id]
	assert(d, "no design for " .. id)
	assert(BeyDesigns.Styles[part.Slot][d.Style], id .. ": unknown " .. part.Slot .. " style " .. tostring(d.Style))
	assert(d.Primary and d.Accent, id .. ": missing colours")
	if part.Slot == "Layer" then assert(d.Count and d.Count >= 3 and d.Count <= 8, id .. ": bad blade count") end
end
for id in pairs(BeyDesigns.Parts) do assert(BeyConfig.Parts[id], "design for unknown part " .. id) end
-- Two parts of one slot should not look identical (style + colours).
local seen = {}
for id, part in pairs(BeyConfig.Parts) do
	local d = BeyDesigns.Parts[id]
	local key = part.Slot .. d.Style .. tostring(d.Count) .. d.Primary[1] .. d.Accent[1]
	assert(not seen[key], id .. " looks identical to " .. tostring(seen[key]))
	seen[key] = id
end
print("designs OK for all parts")
print("ALL OK")
