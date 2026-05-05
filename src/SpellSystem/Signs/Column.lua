--!strict
-- Column sign: a T-shape. Canonical orientation points "up" (top bar on top, stem going down).
-- When combined with an elemental sigil, the spell shoots as a column/beam in the sign's direction.

local Config     = require(script.Parent.Parent.Config)
local GridBuffer = require(script.Parent.Parent.Canvas.GridBuffer)
local Bresenham  = require(script.Parent.Parent.Util.Bresenham)
local Normalizer = require(script.Parent.Parent.Recognition.Normalizer)
local Registry   = require(script.Parent.Registry)

-- T-shape. Bar near the top, stem going down. Proportions tuned to a hand-drawn T
-- (bar and stem roughly similar length, bar slightly shorter than stem).
local function buildVisual(buf: GridBuffer.GridBuffer)
	local N = buf.size
	local cx, cy = N / 2, N / 2
	local thickness = Config.StrokeRadius
	local half    = math.max(2, math.floor(N * 0.18))
	local stemLen = math.max(3, math.floor(N * 0.40))
	local topY = math.floor(cy - stemLen * 0.45)
	local botY = topY + stemLen
	local function stroke(x0, y0, x1, y1)
		Bresenham.stroke(x0, y0, x1, y1, thickness, function(x, y) buf:set(x, y, 1) end)
	end
	stroke(cx - half, topY, cx + half, topY)
	stroke(cx, topY,        cx, botY)
end

local function buildTemplate(): GridBuffer.GridBuffer
	local big = GridBuffer.new(Config.TemplateResolution)
	buildVisual(big)
	local norm = Normalizer.normalize(big, Config.TemplateResolution)
	assert(norm, "column template normalization failed")
	return norm :: GridBuffer.GridBuffer
end

Registry.register({
	id          = "column",
	template    = buildTemplate(),
	buildVisual = buildVisual,
	rotationInvariant = false,
	description = "Channels the spell into a beam/column in the direction the T points.",
})

return true
