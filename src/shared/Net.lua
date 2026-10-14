--!nonstrict
-- Net: the game's remotes, in one place. The server creates them (idempotent: safe after a re-install or a
-- script restart); clients wait for them with a time limit and a clear error instead of hanging forever.
--
-- Client -> server
--   Request      RemoteEvent    { action = "rematch" | "leave" | "forfeit" | "exitPractice" | "setting" | "tutorialDone", ... }
--   SlamLanded   RemoteEvent    (no arguments: the server checks the fall it observed itself)
--   Workshop     RemoteFunction { action = "buy" | "equip", part = id } -> { ok, reason, profile }
-- Server -> client
--   BattleEvent  RemoteEvent    { kind = "queued" | "countdown" | "started" | "hit" | "slam" | "finished" | "closed" | "openWorkshop", ... }
--   Knockback    RemoteEvent    Vector3 velocity change for the client-owned bey
--   Profile      RemoteEvent    PlayerData.snapshot
--   Toast        RemoteEvent    string

local Net = {}

Net.FOLDER = "SpinforgeRemotes"
Net.EVENTS = { "Request", "SlamLanded", "BattleEvent", "Knockback", "Profile", "Toast" }
Net.FUNCTIONS = { "Workshop" }

function Net.setup(replicatedStorage)
	local folder = replicatedStorage:FindFirstChild(Net.FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Net.FOLDER
		folder.Parent = replicatedStorage
	end
	local remotes = {}
	for _, name in ipairs(Net.EVENTS) do
		local r = folder:FindFirstChild(name)
		if not (r and r:IsA("RemoteEvent")) then
			if r then
				r:Destroy()
			end
			r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
		remotes[name] = r
	end
	for _, name in ipairs(Net.FUNCTIONS) do
		local r = folder:FindFirstChild(name)
		if not (r and r:IsA("RemoteFunction")) then
			if r then
				r:Destroy()
			end
			r = Instance.new("RemoteFunction")
			r.Name = name
			r.Parent = folder
		end
		remotes[name] = r
	end
	return remotes
end

-- Client side. Returns the remotes table, or nil + message if the server never created them.
function Net.waitFor(replicatedStorage, timeout)
	local folder = replicatedStorage:WaitForChild(Net.FOLDER, timeout)
	if not folder then
		return nil, "the server scripts did not start (no " .. Net.FOLDER .. "). Re-run the installer and check Output for red errors."
	end
	local remotes = {}
	for _, name in ipairs(Net.EVENTS) do
		remotes[name] = folder:WaitForChild(name, timeout)
		if not remotes[name] then
			return nil, "remote " .. name .. " is missing"
		end
	end
	for _, name in ipairs(Net.FUNCTIONS) do
		remotes[name] = folder:WaitForChild(name, timeout)
		if not remotes[name] then
			return nil, "remote " .. name .. " is missing"
		end
	end
	return remotes
end

return Net
