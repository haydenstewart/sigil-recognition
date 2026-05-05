--!strict
-- Wind sigil: vertical S-curve flanked by three short horizontal hash marks on each side (v2).
-- The hashes are intentionally well clear of the S so ComponentFinder splits them out as
-- separate components -- they are visual flourish, not signs, and the matcher operates on
-- the *central* component (the S).

local RS           = game:GetService("ReplicatedStorage")

local Config       = require(script.Parent.Parent.Config)
local GridBuffer   = require(script.Parent.Parent.Canvas.GridBuffer)
local Bresenham    = require(script.Parent.Parent.Util.Bresenham)
local Registry     = require(script.Parent.Registry)
local RingDetector = require(script.Parent.Parent.Recognition.RingDetector)
local Normalizer   = require(script.Parent.Parent.Recognition.Normalizer)

local function buildVisual(buf: GridBuffer.GridBuffer)
	local N = buf.size
	local cx, cy = N / 2, N / 2
	local R = N * 0.26
	local thickness = Config.StrokeRadius
	local function setp(x: number, y: number) buf:set(x, y, 1) end

	-- Central vertical S: parametric (x oscillates one period as y traverses the height).
	local height = R * 1.5
	local width  = 4
	local samples = 32
	local prevX, prevY
	for i = 0, samples do
		local t = i / samples
		local y = cy - height / 2 + height * t
		local x = cx + width * math.sin(t * math.pi * 2)
		if prevX then
			Bresenham.stroke(prevX, prevY, x, y, thickness, setp)
		end
		prevX, prevY = x, y
	end

	-- Three short horizontal hash marks on each side. Longer than v1 so they read
	-- clearly as distinct dashes from in-game distance. Outer hashes are slightly
	-- shorter than the middle one to suggest a converging-air motif.
	local hashGapY = 5
	local sideX_left  = cx - R * 0.95
	local sideX_right = cx + R * 0.95
	local function dashes(centerX: number)
		for i = -1, 1 do
			local y = cy + i * hashGapY
			local halfLen = (i == 0) and 5 or 4   -- middle hash a bit longer
			Bresenham.stroke(centerX - halfLen, y, centerX + halfLen, y, thickness, setp)
		end
	end
	dashes(sideX_left)
	dashes(sideX_right)
end

local function onCast(ctx: {[string]: any})
	local accuracy = ctx.accuracy or 0
	local paperCF = ctx.paperCFrame :: CFrame
	local signs = ctx.signs or {}
	print(string.format("[Wind.onCast] signs=%d acc=%.2f", #signs, accuracy))
	local playEffect = RS:FindFirstChild("SpellRemotes") and RS.SpellRemotes:FindFirstChild("PlayEffect")
	if playEffect then
		playEffect:FireAllClients({
			id = "shockwave",
			origin = paperCF.Position + Vector3.new(0, 1, 0),
			power = math.clamp(accuracy, 0.5, 1.2),
		})
	end
end

-- Template covers the full glyph (S + hashes). Caster.evaluate combines all non-sign
-- components into one mask, so the model trains on "S + hashes" and inference also
-- needs both -- drawing just the S without the hashes will fail to match.
local function buildTemplate(): GridBuffer.GridBuffer
	local N = Config.GridSize
	local canvas = GridBuffer.new(N)
	local cx, cy = N / 2, N / 2
	Bresenham.thickCircle(cx, cy, N * 0.45, Config.StrokeRadius, function(x, y) canvas:set(x, y, 1) end)
	buildVisual(canvas)
	local ring = RingDetector.detect(canvas)
	assert(ring.found and ring.sigilMask, "wind template: ring not detected in canonical rendering")
	local norm = Normalizer.normalize(ring.sigilMask :: GridBuffer.GridBuffer, Config.TemplateResolution)
	assert(norm, "wind template: normalization failed")
	return norm :: GridBuffer.GridBuffer
end

local FULL_TEMPLATE = buildTemplate()

Registry.register({
	id          = "wind",
	template    = FULL_TEMPLATE,
	buildVisual = buildVisual,
	onCast      = onCast,
})

return true
