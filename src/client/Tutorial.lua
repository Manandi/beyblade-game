--!nonstrict
-- Tutorial: short contextual hints shown while you control a bey, until you've done each thing once:
-- drive, lean in, brake, launch off the lip, slam. Each hint advances when the controller reports the action.
-- Finishing it tells the server (saved in Settings.TutorialDone). Settings can replay it.

local UserInputService = game:GetService("UserInputService")

local Tutorial = {}
Tutorial.__index = Tutorial

local function steps()
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local pad = UserInputService.GamepadEnabled
	local aim = touch and "Drag on the right side of the screen" or pad and "Push the right stick" or "Move the mouse"
	return {
		{ id = "moved", title = "Drive", body = touch and "Use the left thumbstick to drive. Your bey goes where the camera faces." or pad and "Left stick drives. Your bey goes where the camera faces." or "W A S D to drive. Your bey goes where the camera faces." },
		{ id = "leaned", title = "Lean in for speed", body = aim .. " DOWN to tip the nose down. You go faster." },
		{ id = "braked", title = "Lean back to brake", body = aim .. " UP to tip the nose back. You slow down and stop." },
		{ id = "launched", title = "Launch off the lip", body = "Drive up the stadium wall and lift the nose just as you reach the steep lip. Nose up = higher." },
		{ id = "slammed", title = "Slam", body = (touch and "Tap SLAM" or pad and "Press the right trigger" or "Click") .. " while in the air to dive down. Land it next to your opponent." },
	}
end

function Tutorial.new(hud, remotes)
	local self = setmetatable({}, Tutorial)
	self.hud = hud
	self.remotes = remotes
	self.done = true -- until the profile says otherwise
	self.index = 1
	self.active = false
	self.steps = steps()
	return self
end

function Tutorial:setProfile(p)
	local wasDone = self.done
	self.done = p.Settings.TutorialDone
	if wasDone and not self.done then
		self.index = 1
		self.steps = steps()
	end
	self:_render()
end

-- Shown only while the player controls a bey.
function Tutorial:setActive(active)
	self.active = active
	self:_render()
end

function Tutorial:signal(id)
	if self.done or not self.active then
		return
	end
	local step = self.steps[self.index]
	if step and step.id == id then
		self.index += 1
		if self.index > #self.steps then
			self.done = true
			self.remotes.Request:FireServer({ action = "tutorialDone" })
			self.hud:hideHint()
			self.hud:toast("Tutorial complete! Challenge the villain from the hub.")
			return
		end
		self:_render()
	end
end

function Tutorial:_render()
	local step = self.steps[self.index]
	if self.done or not self.active or not step then
		self.hud:hideHint()
		return
	end
	self.hud:showHint(("TUTORIAL %d/%d"):format(self.index, #self.steps), step.title, step.body)
end

return Tutorial
