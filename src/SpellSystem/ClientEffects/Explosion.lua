--!strict
-- 360° AoE fire explosion. Fires off the SpellAssets.Fire2 particle emitter at the origin
-- in a short burst, plus a glowing core part that fades.

local Debris       = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local RS           = game:GetService("ReplicatedStorage")

local Registry = require(script.Parent.Registry)

local function getTemplate(): ParticleEmitter?
	local assets = RS:FindFirstChild("SpellAssets")
	return assets and assets:FindFirstChild("Fire2") or nil
end

local function play(args)
	local origin = args.origin
	if not origin then return end
	local power = args.power or 1
	local radius = args.radius or (10 * power)

	local holder = Instance.new("Part")
	holder.Name = "SpellExplosion"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Transparency = 0
	holder.Material = Enum.Material.Neon
	holder.Color = Color3.fromRGB(255, 140, 50)
	holder.Size = Vector3.new(1, 1, 1)
	holder.Shape = Enum.PartType.Ball
	holder.CFrame = CFrame.new(origin)
	holder.Parent = workspace
	Debris:AddItem(holder, 2.2)

	-- Fire emitter in a burst
	local template = getTemplate()
	if template then
		local fire = template:Clone()
		fire.Enabled = false
		fire.Rate = 200
		fire.SpreadAngle = Vector2.new(180, 180)
		fire.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0,   2 * power),
			NumberSequenceKeypoint.new(0.4, 4 * power),
			NumberSequenceKeypoint.new(1,   0.2 * power),
		})
		fire.Speed = NumberRange.new(8 * power, 14 * power)
		fire.Parent = holder
		fire:Emit(60 * power)
	end

	-- Two-stage animation: pop out fast, then fade out over a longer tail so it's actually visible.
	TweenService:Create(holder,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(radius, radius, radius) }
	):Play()
	TweenService:Create(holder,
		TweenInfo.new(1.8, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Transparency = 1 }
	):Play()
end

Registry.register("explosion", play)

return true
