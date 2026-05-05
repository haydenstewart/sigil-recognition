--!strict
-- Ten additional elemental sigils. Each entry follows the existing Sigils.Registry format:
-- buildVisual -> template -> onCast. The shared ElementalCombat module handles spell gameplay/VFX.

local Config          = require(script.Parent.Parent.Config)
local GridBuffer      = require(script.Parent.Parent.Canvas.GridBuffer)
local Bresenham       = require(script.Parent.Parent.Util.Bresenham)
local Registry        = require(script.Parent.Registry)
local RingDetector    = require(script.Parent.Parent.Recognition.RingDetector)
local Normalizer      = require(script.Parent.Parent.Recognition.Normalizer)
local ElementalCombat = require(script.Parent.Parent.Spells.ElementalCombat)

local function stroke(buf: GridBuffer.GridBuffer, x0: number, y0: number, x1: number, y1: number, r: number?)
	Bresenham.stroke(x0, y0, x1, y1, r or Config.StrokeRadius, function(x, y) buf:set(x, y, 1) end)
end

local function disk(buf: GridBuffer.GridBuffer, x: number, y: number, radius: number)
	Bresenham.disk(x, y, radius, function(px, py) buf:set(px, py, 1) end)
end

local function arc(buf: GridBuffer.GridBuffer, cx: number, cy: number, rx: number, ry: number, a0: number, a1: number, samples: number, r: number?)
	local prevX, prevY
	for i = 0, samples do
		local t = i / samples
		local a = a0 + (a1 - a0) * t
		local x = cx + math.cos(a) * rx
		local y = cy + math.sin(a) * ry
		if prevX then stroke(buf, prevX, prevY, x, y, r) end
		prevX, prevY = x, y
	end
end

local function rotatedStroke(buf: GridBuffer.GridBuffer, cx: number, cy: number, x0: number, y0: number, x1: number, y1: number, angle: number, r: number?)
	local c, s = math.cos(angle), math.sin(angle)
	local function rot(x: number, y: number): (number, number)
		local dx, dy = x - cx, y - cy
		return cx + c * dx - s * dy, cy + s * dx + c * dy
	end
	local ax, ay = rot(x0, y0)
	local bx, by = rot(x1, y1)
	stroke(buf, ax, ay, bx, by, r)
end

local function buildTemplate(buildVisual: (GridBuffer.GridBuffer) -> ()): GridBuffer.GridBuffer
	local N = Config.GridSize
	local canvas = GridBuffer.new(N)
	local cx, cy = N / 2, N / 2
	Bresenham.thickCircle(cx, cy, N * 0.45, Config.StrokeRadius, function(x, y) canvas:set(x, y, 1) end)
	buildVisual(canvas)
	local ring = RingDetector.detect(canvas)
	assert(ring.found and ring.sigilMask, "elemental variant template: ring not detected")
	local norm = Normalizer.normalize(ring.sigilMask :: GridBuffer.GridBuffer, Config.TemplateResolution)
	assert(norm, "elemental variant template: normalization failed")
	return norm :: GridBuffer.GridBuffer
end

local function fireBurst(buf: GridBuffer.GridBuffer)
	local N = buf.size
	local cx, cy = N / 2, N / 2
	local R = N * 0.25
	local pts = {
		{cx, cy - R},
		{cx + R * 0.45, cy - R * 0.20},
		{cx + R * 0.15, cy + R * 0.70},
		{cx, cy + R},
		{cx - R * 0.18, cy + R * 0.68},
		{cx - R * 0.48, cy - R * 0.15},
	}
	for i = 1, #pts do
		local a = pts[i]
		local b = pts[(i % #pts) + 1]
		stroke(buf, a[1], a[2], b[1], b[2])
	end
	stroke(buf, cx, cy + R * 0.55, cx, cy - R * 0.15)
	stroke(buf, cx - R * 0.18, cy + R * 0.28, cx + R * 0.16, cy - R * 0.10)
end

local function fireLance(buf: GridBuffer.GridBuffer)
	local N = buf.size
	local cx, cy = N / 2, N / 2
	local R = N * 0.27
	stroke(buf, cx, cy + R * 0.95, cx, cy - R * 0.95)
	stroke(buf, cx, cy - R * 0.95, cx - R * 0.35, cy - R * 0.35)
	stroke(buf, cx, cy - R * 0.95, cx + R * 0.35, cy - R * 0.35)
	stroke(buf, cx - R * 0.32, cy + R * 0.35, cx - R * 0.62, cy - R * 0.05)
	stroke(buf, cx + R * 0.32, cy + R * 0.35, cx + R * 0.62, cy - R * 0.05)
	stroke(buf, cx - R * 0.22, cy + R * 0.70, cx + R * 0.22, cy + R * 0.70)
end

local function waterBubble(buf: GridBuffer.GridBuffer)
	local N = buf.size
	local cx, cy = N / 2, N / 2
	local R = N * 0.22
	Bresenham.thickCircle(cx, cy, R, Config.StrokeRadius, function(x, y) buf:set(x, y, 1) end)
	arc(buf, cx, cy + 1, R * 0.62, R * 0.30, math.pi * 0.05, math.pi * 1.95, 34)
	stroke(buf, cx - R * 0.65, cy, cx + R * 0.65, cy)
	disk(buf, cx - R * 0.85, cy - R * 0.85, 2)
	disk(buf, cx + R * 0.72, cy - R * 0.72, 2)
end

local function waterTide(buf: GridBuffer.GridBuffer)
	local N = buf.size
	local cx, cy = N / 2, N / 2
	local R = N * 0.27
	for row = -1, 1 do
		local yBase = cy + row * 5
		local prevX, prevY
		for i = 0, 28 do
			local t = i / 28
			local x = cx - R + R * 2 * t
			local y = yBase + math.sin(t * math.pi * 2) * 3
			if prevX then stroke(buf, prevX, prevY, x, y) end
			prevX, prevY = x, y
		end
	end
	stroke(buf, cx, cy - R * 1.05, cx - R * 0.20, cy - R * 0.45)
	stroke(buf, cx, cy - R * 1.05, cx + R * 0.20, cy - R * 0.45)
	disk(buf, cx, cy - R * 0.38, 2)
end

local function earthWall(buf: GridBuffer.GridBuffer)
	local N = buf.size
	local cx, cy = N / 2, N / 2
	local R = N * 0.25
	local left, right = cx - R, cx + R
	local top, bottom = cy - R * 0.72, cy + R * 0.72
	stroke(buf, left, top, right, top)
	stroke(buf, right, top, right, bottom)
	stroke(buf, right, bottom, left, bottom)
	stroke(buf, left, bottom, left, top)
	stroke(buf, left, cy, right, cy)
	stroke(buf, cx, top, cx, cy)
	stroke(buf, cx - R * 0.45, cy, cx - R * 0.45, bottom)
	stroke(buf, cx + R * 0.45, cy, cx + R * 0.45, bottom)
end

local function earthSpike(buf: GridBuffer.GridBuffer)
	local N = buf.size
	local cx, cy = N / 2, N / 2
	local R = N * 0.26
	stroke(buf, cx, cy - R, cx + R * 0.68, cy)
	stroke(buf, cx + R * 0.68, cy, cx, cy + R)
	stroke(buf, cx, cy + R, cx - R * 0.68, cy)
	stroke(buf, cx - R * 0.68, cy, cx, cy - R)
	stroke(buf, cx - R * 0.55, cy + R * 0.25, cx - R * 0.15, cy + R * 0.95)
	stroke(buf, cx, cy + R * 0.35, cx, cy + R * 1.18)
	stroke(buf, cx + R * 0.55, cy + R * 0.25, cx + R * 0.15, cy + R * 0.95)
end

local function earthQuake(buf: GridBuffer.GridBuffer)
	local N = buf.size
	local cx, cy = N / 2, N / 2
	local R = N * 0.27
	stroke(buf, cx - R, cy - R * 0.55, cx + R, cy - R * 0.55)
	stroke(buf, cx - R * 0.8, cy + R * 0.62, cx + R * 0.8, cy + R * 0.62)
	local pts = {
		{cx - R * 0.30, cy - R},
		{cx + R * 0.05, cy - R * 0.35},
		{cx - R * 0.18, cy - R * 0.05},
		{cx + R * 0.20, cy + R * 0.32},
		{cx - R * 0.02, cy + R},
	}
	for i = 1, #pts - 1 do
		stroke(buf, pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2])
	end
	disk(buf, cx - R * 0.80, cy - R * 0.15, 2)
	disk(buf, cx + R * 0.78, cy + R * 0.18, 2)
end

local function windGust(buf: GridBuffer.GridBuffer)
	local N = buf.size
	local cx, cy = N / 2, N / 2
	local R = N * 0.27
	for lane = -1, 1 do
		local y = cy + lane * 6
		arc(buf, cx - R * 0.1, y, R, 7, math.pi * 1.05, math.pi * 1.85, 24)
		stroke(buf, cx - R * 0.92, y, cx + R * 0.62, y + lane * 1.5)
		disk(buf, cx + R * 0.76, y + lane * 1.5, 1)
	end
end

local function windVortex(buf: GridBuffer.GridBuffer)
	local N = buf.size
	local cx, cy = N / 2, N / 2
	local maxR = N * 0.26
	local prevX, prevY
	for i = 0, 64 do
		local t = i / 64
		local a = t * math.pi * 2.35
		local r = maxR * t
		local x = cx + math.cos(a) * r
		local y = cy + math.sin(a) * r
		if prevX then stroke(buf, prevX, prevY, x, y) end
		prevX, prevY = x, y
	end
	arc(buf, cx, cy, maxR * 0.92, maxR * 0.92, math.rad(205), math.rad(330), 18)
	arc(buf, cx, cy, maxR * 0.62, maxR * 0.62, math.rad(25), math.rad(155), 18)
end

local function windBlade(buf: GridBuffer.GridBuffer)
	local N = buf.size
	local cx, cy = N / 2, N / 2
	local R = N * 0.27
	arc(buf, cx, cy, R * 0.95, R * 0.58, math.rad(205), math.rad(25), 34)
	arc(buf, cx + R * 0.08, cy, R * 0.62, R * 0.36, math.rad(205), math.rad(25), 28)
	rotatedStroke(buf, cx, cy, cx - R * 0.70, cy + R * 0.50, cx + R * 0.72, cy - R * 0.50, math.rad(-12))
	rotatedStroke(buf, cx, cy, cx - R * 0.55, cy + R * 0.78, cx + R * 0.52, cy - R * 0.22, math.rad(-12))
end

local SPELLS = {
	{
		id = "fire_burst",
		displayName = "Fire Burst",
		element = "fire",
		shape = "burst",
		columnShape = "beam",
		radius = 11,
		damage = 34,
		duration = 2.2,
		buildVisual = fireBurst,
		description = "Short-range fire AoE. Column signs convert it into a beam; levitation sustains it.",
	},
	{
		id = "fire_lance",
		displayName = "Fire Lance",
		element = "fire",
		shape = "projectile",
		columnShape = "beam",
		length = 30,
		radius = 7,
		damage = 32,
		buildVisual = fireLance,
		description = "Forward fire projectile with an impact burst.",
	},
	{
		id = "water_bubble",
		displayName = "Water Bubble",
		element = "water",
		shape = "sustain",
		radius = 8,
		tickDamage = 4,
		duration = 4.5,
		buildVisual = waterBubble,
		description = "Sustained water sphere that pressures enemies in its area.",
	},
	{
		id = "water_tide",
		displayName = "Water Tide",
		element = "water",
		shape = "rain",
		columnShape = "beam",
		radius = 12,
		length = 24,
		tickDamage = 5,
		duration = 2.8,
		buildVisual = waterTide,
		description = "Falling water field. Column signs focus it into a water beam.",
	},
	{
		id = "earth_wall",
		displayName = "Earth Wall",
		element = "earth",
		shape = "wall",
		length = 18,
		width = 3,
		damage = 18,
		buildVisual = earthWall,
		description = "Raises a temporary barrier and knocks damage through the front line.",
	},
	{
		id = "earth_spike",
		displayName = "Earth Spike",
		element = "earth",
		shape = "projectile",
		columnShape = "beam",
		length = 26,
		radius = 7,
		damage = 38,
		buildVisual = earthSpike,
		description = "A heavy spike launched forward, bursting at the end point.",
	},
	{
		id = "earth_quake",
		displayName = "Earth Quake",
		element = "earth",
		shape = "burst",
		radius = 14,
		damage = 30,
		buildVisual = earthQuake,
		description = "Wide ground shockwave centered on the paper.",
	},
	{
		id = "wind_gust",
		displayName = "Wind Gust",
		element = "wind",
		shape = "beam",
		length = 32,
		width = 4,
		damage = 22,
		buildVisual = windGust,
		description = "A directional gust lane that can be aimed with column signs.",
	},
	{
		id = "wind_vortex",
		displayName = "Wind Vortex",
		element = "wind",
		shape = "pull",
		radius = 13,
		damage = 21,
		tickDamage = 3,
		buildVisual = windVortex,
		description = "A swirl burst that punishes clustered enemies around the cast point.",
	},
	{
		id = "wind_blade",
		displayName = "Wind Blade",
		element = "wind",
		shape = "slash",
		length = 22,
		width = 4,
		damage = 28,
		buildVisual = windBlade,
		description = "Fast cutting wind slashes in the aimed direction.",
	},
}

for _, spec in ipairs(SPELLS) do
	local captured = spec
	Registry.register({
		id = captured.id,
		template = buildTemplate(captured.buildVisual),
		buildVisual = captured.buildVisual,
		onCast = function(ctx) ElementalCombat.cast(captured, ctx) end,
		element = captured.element,
		displayName = captured.displayName,
		description = captured.description,
	} :: any)
end

return true
