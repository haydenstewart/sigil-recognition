--!strict
-- Sustained fire orb: a hovering, pulsing neon ball with continuous fire particles.
-- Triggered when all column signs point inward (Witch Hat Atelier "levitation" pattern).

local Debris       = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")
local RS           = game:GetService("ReplicatedStorage")

local Registry = require(script.Parent.Registry)

local function play(args)
	local origin = args.origin
	if not origin then return end
	local power = args.power or 1
	local radius = args.radius or (6 * power)
	local duration = args.duration or 4.0

	local orb = Instance.new("Part")
	orb.Name = "SpellSustain"
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb.CastShadow = false
	orb.Shape = Enum.PartType.Ball
	orb.Material = Enum.Material.Neon
	orb.Color = Color3.fromRGB(255, 120, 30)
	orb.Transparency = 0.1
	orb.Size = Vector3.new(0.5, 0.5, 0.5)
	orb.CFrame = CFrame.new(origin)
	orb.Parent = workspace
	Debris:AddItem(orb, duration + 1.0)

	-- Fire particles continuously while the orb is alive.
	local template = RS:FindFirstChild("SpellAssets") and RS.SpellAssets:FindFirstChild("Fire2")
	if template then
		local fire = template:Clone()
		fire.Enabled = true
		fire.Rate = 80
		fire.SpreadAngle = Vector2.new(180, 180)
		fire.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0,   2.0 * power),
			NumberSequenceKeypoint.new(0.4, radius * 0.9),
			NumberSequenceKeypoint.new(1,   0.3),
		})
		fire.Speed = NumberRange.new(2 * power, 4 * power)
		fire.Lifetime = NumberRange.new(1.0, 1.6)
		fire.Parent = orb
		-- Stop emitting a bit before debris removes the part, so remaining particles can fade out cleanly.
		task.delay(duration, function() if fire then fire.Enabled = false end end)
	end

	-- Pop in, then gentle pulse while alive, then fade.
	TweenService:Create(orb,
		TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = Vector3.new(radius, radius, radius) * 0.9 }
	):Play()
	task.delay(0.3, function()
		local start = os.clock()
		while orb.Parent and (os.clock() - start) < (duration - 0.3) do
			local t = (os.clock() - start)
			local pulse = 0.9 + 0.15 * math.sin(t * 6)
			orb.Size = Vector3.new(radius * pulse, radius * pulse, radius * pulse)
			RunService.Heartbeat:Wait()
		end
	end)
	task.delay(duration, function()
		if orb.Parent then
			TweenService:Create(orb,
				TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 }
			):Play()
		end
	end)
end

Registry.register("sustain", play)

return true
