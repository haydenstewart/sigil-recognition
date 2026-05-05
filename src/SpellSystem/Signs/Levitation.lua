--!strict
-- Levitation sign: a stem with a chevron arrowhead at the tip ("↑" shape).
-- Canonical orientation points UP. Match tries 12 rotations so the player can aim freely.
-- Spatially distinct from Column: column is a T (bar + stem), levitation is an arrow (stem + chevron).
-- Presence of a levitation sign around a sigil produces a SUSTAINED spell instead of a column.

local Config     = require(script.Parent.Parent.Config)
local GridBuffer = require(script.Parent.Parent.Canvas.GridBuffer)
local Bresenham  = require(script.Parent.Parent.Util.Bresenham)
local Normalizer = require(script.Parent.Parent.Recognition.Normalizer)
local Registry   = require(script.Parent.Registry)

-- An arrow: vertical stem, chevron at the tip (two short diagonals meeting at the tip).
--     /\
--    /  \
--     |
--     |
--     |
local function buildVisual(buf: GridBuffer.GridBuffer)
	local N = buf.size
	local cx, cy = N / 2, N / 2
	local thickness = Config.StrokeRadius
	local stemLen  = math.max(4, math.floor(N * 0.45))
	local headLen  = math.max(3, math.floor(N * 0.22))
	local headWide = math.max(2, math.floor(N * 0.20))
	local tipY = math.floor(cy - stemLen * 0.5)
	local botY = tipY + stemLen
	local function stroke(x0, y0, x1, y1)
		Bresenham.stroke(x0, y0, x1, y1, thickness, function(x, y) buf:set(x, y, 1) end)
	end
	stroke(cx, tipY, cx, botY)                       -- stem
	stroke(cx, tipY, cx - headWide, tipY + headLen)  -- chevron left
	stroke(cx, tipY, cx + headWide, tipY + headLen)  -- chevron right
end

local function buildTemplate(): GridBuffer.GridBuffer
	local t = GridBuffer.new(Config.TemplateResolution)
	buildVisual(t)
	local norm = Normalizer.normalize(t, Config.TemplateResolution)
	return norm or t
end

Registry.register({
	id          = "levitation",
	template    = buildTemplate(),
	buildVisual = buildVisual,
	rotationInvariant = false,
	description = "Arrow sign. Drawn around a sigil to sustain the spell in place.",
})

return true
