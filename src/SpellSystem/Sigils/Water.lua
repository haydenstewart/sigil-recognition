--!strict
-- Water sigil: two teardrops flanking a central horizontal wave (v2).
-- Stub onCast (placeholder visual + print) so the rest of the spell system has a
-- real entry to dispatch to; flesh out gameplay behavior later.

local RS           = game:GetService("ReplicatedStorage")

local Config       = require(script.Parent.Parent.Config)
local GridBuffer   = require(script.Parent.Parent.Canvas.GridBuffer)
local Bresenham    = require(script.Parent.Parent.Util.Bresenham)
local Registry     = require(script.Parent.Registry)
local RingDetector = require(script.Parent.Parent.Recognition.RingDetector)
local Normalizer   = require(script.Parent.Parent.Recognition.Normalizer)

-- Two teardrops flanking a sinusoidal wave. Each teardrop is a filled bulb with a
-- tapered tail pointing up, drawn at a size that reads clearly at in-game render
-- distance (small disks alone read as dots, not drops).
local function buildVisual(buf: GridBuffer.GridBuffer)
	local N = buf.size
	local cx, cy = N / 2, N / 2
	local R = N * 0.26
	local thickness = Config.StrokeRadius
	local function setp(x: number, y: number) buf:set(x, y, 1) end

	-- One teardrop: bulb (filled disk) + tail (line) above it, slightly tilted toward center.
	local function teardrop(dx: number, tilt: number)
		local bulbX = cx + dx
		local bulbY = cy + 2
		Bresenham.disk(bulbX, bulbY, 2, setp)
		-- Tail: from top of the bulb, sloping inward by `tilt` cells over its 4-cell length.
		local tailX0, tailY0 = bulbX, bulbY - 2
		local tailX1, tailY1 = bulbX + tilt, bulbY - 6
		Bresenham.stroke(tailX0, tailY0, tailX1, tailY1, thickness, setp)
	end
	teardrop(-R * 0.85,  1)   -- left drop, tail tilts right toward the center
	teardrop( R * 0.85, -1)   -- right drop, tail tilts left toward the center

	-- Wave between the drops: full period, amplitude tuned so the peaks are clearly above /
	-- below the bulb centers.
	local x0 = cx - R * 0.55
	local x1 = cx + R * 0.55
	local amp = 3.5
	local samples = 28
	local prevX, prevY
	for i = 0, samples do
		local t = i / samples
		local x = x0 + (x1 - x0) * t
		local y = cy + 2 + amp * math.sin(t * math.pi * 2)
		if prevX then
			Bresenham.stroke(prevX, prevY, x, y, thickness, setp)
		end
		prevX, prevY = x, y
	end
end

local function onCast(ctx: {[string]: any})
	local accuracy = ctx.accuracy or 0
	local paperCF = ctx.paperCFrame :: CFrame
	local signs = ctx.signs or {}
	print(string.format("[Water.onCast] signs=%d acc=%.2f", #signs, accuracy))
	local playEffect = RS:FindFirstChild("SpellRemotes") and RS.SpellRemotes:FindFirstChild("PlayEffect")
	if playEffect then
		playEffect:FireAllClients({
			id = "shockwave",
			origin = paperCF.Position + Vector3.new(0, 1, 0),
			power = math.clamp(accuracy, 0.5, 1.2),
		})
	end
end

-- Template covers the full glyph (wave + drops). Caster.evaluate combines all non-sign
-- components into one mask before matching, so the trained model sees the same shape
-- whether or not the drops happen to be a separate connected component.
local function buildTemplate(): GridBuffer.GridBuffer
	local N = Config.GridSize
	local canvas = GridBuffer.new(N)
	local cx, cy = N / 2, N / 2
	Bresenham.thickCircle(cx, cy, N * 0.45, Config.StrokeRadius, function(x, y) canvas:set(x, y, 1) end)
	buildVisual(canvas)
	local ring = RingDetector.detect(canvas)
	assert(ring.found and ring.sigilMask, "water template: ring not detected in canonical rendering")
	local norm = Normalizer.normalize(ring.sigilMask :: GridBuffer.GridBuffer, Config.TemplateResolution)
	assert(norm, "water template: normalization failed")
	return norm :: GridBuffer.GridBuffer
end

local FULL_TEMPLATE = buildTemplate()

Registry.register({
	id          = "water",
	template    = FULL_TEMPLATE,
	buildVisual = buildVisual,
	onCast      = onCast,
})

return true
