--!nonstrict
-- Sounds: one place for every sound effect id. Empty ids are skipped (silent), so the game runs without any.
-- To add sound: in Studio open the Toolbox > Audio (or the Creator Store), pick Roblox-made or your own uploaded
-- sounds, copy the number from the asset URL and put "rbxassetid://<number>" here. Audio uploaded by other
-- people usually won't play in your game (Roblox audio privacy), so prefer Roblox's own SFX or your uploads.

local SoundService = game:GetService("SoundService")

local Sounds = {}

Sounds.Ids = {
	Hit = "", -- metal clash, short
	HitHeavy = "", -- bigger clash with a ring (empowered hits)
	Launch = "", -- ripcord whoosh at LET IT RIP
	Special = "", -- whoosh / roar when a special is used
	Awaken = "", -- big roar + choir hit
	Quake = "", -- deep boom
	Guard = "", -- shield hum
	Win = "", -- victory sting
	Lose = "", -- defeat sting
}

-- Plays a sound once (2D, not positional). volume 0..1, pitch ~1.
function Sounds.play(name, volume, pitch)
	local id = Sounds.Ids[name]
	if not id or id == "" then
		return
	end
	local ok = pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = volume or 0.6
		s.PlaybackSpeed = pitch or 1
		s.Parent = SoundService
		s.Ended:Connect(function()
			s:Destroy()
		end)
		s:Play()
	end)
	return ok
end

return Sounds
