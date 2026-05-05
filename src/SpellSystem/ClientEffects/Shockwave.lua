--!strict
-- Blocky expanding shockwave: a ring of cubes that pushes outward while fading.

local Debris       = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Registry = require(script.Parent.Registry)

local DEFAULT_SEGMENTS = 22
local DEFAULT_RADIUS   = 18
local DEFAULT_DURATION = 1.2
local DEFAULT_HEIGHT   = 1.6
local DEFAULT_DEPTH    = 2.4
local DEFAULT_COLOR    = Color3.fromRGB(255, 120, 30)

local function play(args)
	local origin = args.origin
	if not origin then return end
	local segments = math.floor(args.segments or DEFAULT_SEGMENTS)
	local radius   = args.radius or (DEFAULT_RADIUS * (args.power or 1))
	local duration = args.duration or DEFAULT_DURATION
	local color    = args.color or DEFAULT_COLOR

	local holder = Instance.new("Folder")
	holder.Name = "SpellShockwave"
	holder.Parent = workspace
	Debris:AddItem(holder, duration + 0.25)

	for i = 0, segments - 1 do
		local angle = (i / segments) * math.pi * 2
		local dirX, dirZ = math.cos(angle), math.sin(angle)
		local p = Instance.new("Part")
		p.Name = "Block"
		p.Size = Vector3.new(DEFAULT_DEPTH, DEFAULT_HEIGHT, DEFAULT_DEPTH)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Transparency = 0
		local startPos = origin + Vector3.new(dirX * 1.5, 0, dirZ * 1.5)
		p.CFrame = CFrame.lookAt(startPos, startPos + Vector3.new(dirX, 0, dirZ))
		p.Parent = holder

		local endPos = origin + Vector3.new(dirX * radius, 0, dirZ * radius)
		local endCF = CFrame.lookAt(endPos, endPos + Vector3.new(dirX, 0, dirZ))
		-- Grow + move outward fast, fade slowly so it lingers visibly.
		TweenService:Create(p,
			TweenInfo.new(duration, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
			{ CFrame = endCF, Transparency = 1, Size = Vector3.new(DEFAULT_DEPTH * 1.2, DEFAULT_HEIGHT * 0.5, DEFAULT_DEPTH * 3.2) }
		):Play()
	end
end

Registry.register("shockwave", play)

return true
