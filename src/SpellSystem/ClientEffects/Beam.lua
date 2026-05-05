--!strict
-- Directed fire beam: a long neon part extending from origin along direction, with fire trailing.

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
	local dir = args.direction
	if not origin or not dir then return end
	if dir.Magnitude < 1e-4 then return end
	dir = dir.Unit

	local power = args.power or 1
	local length = args.length or (22 * power)
	local startWidth = 2.2

	local beam = Instance.new("Part")
	beam.Name = "SpellBeam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 120, 30)
	beam.Transparency = 0
	beam.Size = Vector3.new(startWidth, startWidth, length)
	-- Beam along its local -Z (the CFrame.lookAt orientation points -Z forward), so point -Z in dir direction.
	local midPos = origin + dir * (length * 0.5)
	beam.CFrame = CFrame.lookAt(midPos, midPos + dir)
	beam.Parent = workspace
	Debris:AddItem(beam, 2.0)

	local template = getTemplate()
	if template then
		local fire = template:Clone()
		fire.Enabled = false
		fire.Rate = 180
		fire.SpreadAngle = Vector2.new(20, 20)
		fire.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0,   2.5 * power),
			NumberSequenceKeypoint.new(0.5, 3.0 * power),
			NumberSequenceKeypoint.new(1,   0.2 * power),
		})
		fire.Speed = NumberRange.new(6 * power, 10 * power)
		fire.Parent = beam
		fire:Emit(70 * power)
	end

	TweenService:Create(beam,
		TweenInfo.new(1.6, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.4, 0.4, length), Transparency = 1 }
	):Play()
end

Registry.register("beam", play)

return true
