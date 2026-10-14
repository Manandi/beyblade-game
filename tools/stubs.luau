-- Minimal Roblox stand-ins so BeyConfig can run under the plain `luau` CLI.
Color3 = {
	fromRGB = function(r, g, b) return { r, g, b } end,
	fromHex = function(h) assert(h:match("^#%x%x%x%x%x%x$"), "bad hex colour " .. h) return { h } end,
}
Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }
local seed = 12345
Random = { new = function()
	return { NextInteger = function(_, lo, hi)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return lo + math.floor(seed / 2147483648 * (hi - lo + 1))
	end }
end }

