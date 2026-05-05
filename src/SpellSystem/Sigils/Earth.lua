--!strict
-- Earth sigil: down-pointing triangle with two flanking dots above the top edge.
-- Inverted Fire triangle, no central line. The two dots above the top vertices are
-- the distinguishing feature vs. an upside-down fire glyph.

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

	local triHalfW = R * 0.866
	local topY     = cy - R * 0.5
	local apexX    = cx
	local apexY    = cy + R

	-- A horizontal bar that extends past the triangle's top vertices on both sides,
	-- giving the sigil its distinctive "top shelf" look from the reference glyph.
	local barExt    = 4                          -- how far the bar pokes out beyond each top vertex
	local barLeftX  = cx - triHalfW - barExt
	local barRightX = cx + triHalfW + barExt

	local function stroke(x0, y0, x1, y1)
		Bresenham.stroke(x0, y0, x1, y1, thickness, setp)
	end

	-- Top bar (extends past the triangle).
	stroke(barLeftX, topY, barRightX, topY)
	-- Triangle: top edge sits coincident with the inner section of the bar; two slanted
	-- sides converging to the apex.
	stroke(cx - triHalfW, topY, apexX,        apexY)
	stroke(cx + triHalfW, topY, apexX,        apexY)

	-- Two flanking dots, sized big enough to read clearly. Placed just inside the bar's
	-- ends so they look like punctuation on the bar (matches the reference glyph).
	Bresenham.disk(barLeftX  + 1, topY - 2, 2, setp)
	Bresenham.disk(barRightX - 1, topY - 2, 2, setp)
end

local function onCast(ctx: {[string]: any})
	local accuracy = ctx.accuracy or 0
	local paperCF = ctx.paperCFrame :: CFrame
	local signs = ctx.signs or {}
	print(string.format("[Earth.onCast] signs=%d acc=%.2f", #signs, accuracy))
	local playEffect = RS:FindFirstChild("SpellRemotes") and RS.SpellRemotes:FindFirstChild("PlayEffect")
	if playEffect then
		playEffect:FireAllClients({
			id = "shockwave",
			origin = paperCF.Position + Vector3.new(0, 1, 0),
			power = math.clamp(accuracy, 0.5, 1.2),
		})
	end
end

local function buildTemplate(): GridBuffer.GridBuffer
	local N = Config.GridSize
	local canvas = GridBuffer.new(N)
	local cx, cy = N / 2, N / 2
	Bresenham.thickCircle(cx, cy, N * 0.45, Config.StrokeRadius, function(x, y) canvas:set(x, y, 1) end)
	buildVisual(canvas)
	local ring = RingDetector.detect(canvas)
	assert(ring.found and ring.sigilMask, "earth template: ring not detected in canonical rendering")
	local norm = Normalizer.normalize(ring.sigilMask :: GridBuffer.GridBuffer, Config.TemplateResolution)
	assert(norm, "earth template: normalization failed")
	return norm :: GridBuffer.GridBuffer
end

local FULL_TEMPLATE = buildTemplate()

Registry.register({
	id          = "earth",
	template    = FULL_TEMPLATE,
	buildVisual = buildVisual,
	onCast      = onCast,
})

return true
