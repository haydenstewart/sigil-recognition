--!strict
-- Raster helpers: integer line / thick stroke / circle.
-- Callbacks receive integer (x, y); callers decide coordinate meaning.

local Bresenham = {}

function Bresenham.line(x0: number, y0: number, x1: number, y1: number, fn: (number, number) -> ())
	x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
	local dx = math.abs(x1 - x0)
	local dy = math.abs(y1 - y0)
	local sx = x0 < x1 and 1 or -1
	local sy = y0 < y1 and 1 or -1
	local err = dx - dy
	local x, y = x0, y0
	while true do
		fn(x, y)
		if x == x1 and y == y1 then break end
		local e2 = 2 * err
		if e2 > -dy then err = err - dy; x = x + sx end
		if e2 <  dx then err = err + dx; y = y + sy end
	end
end

function Bresenham.disk(cx: number, cy: number, r: number, fn: (number, number) -> ())
	if r <= 0 then fn(math.floor(cx), math.floor(cy)); return end
	local r2 = r * r
	for dy = -r, r do
		for dx = -r, r do
			if dx*dx + dy*dy <= r2 then
				fn(math.floor(cx) + dx, math.floor(cy) + dy)
			end
		end
	end
end

-- Thick line by stamping a disk at each step. r=0 -> single-pixel.
function Bresenham.stroke(x0: number, y0: number, x1: number, y1: number, r: number, fn: (number, number) -> ())
	Bresenham.line(x0, y0, x1, y1, function(x, y)
		Bresenham.disk(x, y, r, fn)
	end)
end

-- Midpoint circle algorithm (outline only).
function Bresenham.circle(cx: number, cy: number, r: number, fn: (number, number) -> ())
	cx, cy, r = math.floor(cx), math.floor(cy), math.floor(r)
	local x, y = r, 0
	local err = 0
	while x >= y do
		fn(cx + x, cy + y); fn(cx + y, cy + x)
		fn(cx - y, cy + x); fn(cx - x, cy + y)
		fn(cx - x, cy - y); fn(cx - y, cy - x)
		fn(cx + y, cy - x); fn(cx + x, cy - y)
		y = y + 1
		if err <= 0 then err = err + 2 * y + 1 end
		if err  > 0 then x = x - 1; err = err - 2 * x + 1 end
	end
end

-- Thick circle by stamping disks along the outline.
function Bresenham.thickCircle(cx: number, cy: number, r: number, thickness: number, fn: (number, number) -> ())
	Bresenham.circle(cx, cy, r, function(x, y)
		Bresenham.disk(x, y, thickness, fn)
	end)
end

return Bresenham
