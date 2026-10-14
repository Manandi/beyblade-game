-- Minimal Roblox stand-ins so project modules can run under the plain `luau` CLI, plus a tiny test helper.
-- Only what the pure modules and BeyConfig use. These do NOT emulate Roblox physics or instances.

Color3 = {
	fromRGB = function(r, g, b) return { r, g, b } end,
	fromHex = function(h) assert(h:match("^#%x%x%x%x%x%x$"), "bad hex colour " .. h) return { h } end,
}

-- Vector3 with the operators and members the modules use (Magnitude, Unit, Dot, Cross, Lerp, arithmetic).
local V3 = {}
local function vec(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, V3)
end
local methods = {}
function methods.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function methods.Cross(a, b) return vec(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
function methods.Lerp(a, b, t) return vec(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end
V3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return vec(v.X / m, v.Y / m, v.Z / m) -- NaN for a zero vector, like Roblox
	end
	return methods[k]
end
V3.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__mul = function(a, b)
	if type(a) == "number" then return vec(b.X * a, b.Y * a, b.Z * a) end
	if type(b) == "number" then return vec(a.X * b, a.Y * b, a.Z * b) end
	return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b) return vec(a.X / b, a.Y / b, a.Z / b) end
V3.__unm = function(a) return vec(-a.X, -a.Y, -a.Z) end
V3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3.__tostring = function(a) return string.format("(%.3f, %.3f, %.3f)", a.X, a.Y, a.Z) end
Vector3 = { new = function(x, y, z) return vec(x or 0, y or 0, z or 0) end }
Vector3.zero = vec(0, 0, 0)
Vector3.yAxis = vec(0, 1, 0)
Vector3.xAxis = vec(1, 0, 0)
Vector3.zAxis = vec(0, 0, 1)

local seed = 12345
Random = { new = function()
	return { NextInteger = function(_, lo, hi)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return lo + math.floor(seed / 2147483648 * (hi - lo + 1))
	end }
end }

-- Test helper: T.test("name", fn); T.eq / T.near / T.ok; T.done() prints a summary and errors on failure.
T = { passed = 0, failed = 0 }
function T.test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		T.passed += 1
	else
		T.failed += 1
		print("  FAIL " .. name .. ": " .. tostring(err))
	end
end
function T.ok(cond, msg) if not cond then error(msg or "expected true", 2) end end
function T.eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
function T.near(a, b, eps, msg) if math.abs(a - b) > (eps or 1e-6) then error((msg or "") .. " expected ~" .. tostring(b) .. ", got " .. tostring(a), 2) end end
function T.finite(n) return n == n and n ~= math.huge and n ~= -math.huge end
function T.done()
	print(string.format("  %d passed, %d failed", T.passed, T.failed))
	if T.failed > 0 then error("TESTS FAILED") end
	print("TESTS PASSED")
end
