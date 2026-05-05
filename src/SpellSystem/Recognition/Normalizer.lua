--!strict
-- Crop a mask to its bounding box and resample to a fixed template size.
-- Resampling is nearest-neighbor; cells in the target are "on" if the source
-- has any set cells within the mapped region (handles shrinking accurately).

local GridBuffer = require(script.Parent.Parent.Canvas.GridBuffer)

local Normalizer = {}

-- Resample `src` (within its bbox) into a `targetSize`x`targetSize` GridBuffer.
function Normalizer.normalize(src: GridBuffer.GridBuffer, targetSize: number): GridBuffer.GridBuffer?
	local minX, minY, maxX, maxY = src:bbox()
	if not minX then return nil end
	local w = (maxX :: number) - (minX :: number) + 1
	local h = (maxY :: number) - (minY :: number) + 1
	-- Use the longer axis to keep aspect, centering the shorter axis.
	local span = math.max(w, h)
	local offX = math.floor((span - w) / 2)
	local offY = math.floor((span - h) / 2)

	local out = GridBuffer.new(targetSize)
	-- For each target cell, compute its corresponding src region and check if any cell is on.
	local step = span / targetSize
	for ty = 1, targetSize do
		local sy0 = (minY :: number) - offY + math.floor((ty - 1) * step)
		local sy1 = (minY :: number) - offY + math.floor(ty * step) - 1
		if sy1 < sy0 then sy1 = sy0 end
		for tx = 1, targetSize do
			local sx0 = (minX :: number) - offX + math.floor((tx - 1) * step)
			local sx1 = (minX :: number) - offX + math.floor(tx * step) - 1
			if sx1 < sx0 then sx1 = sx0 end
			local on = 0
			for y = sy0, sy1 do
				for x = sx0, sx1 do
					if src:get(x, y) ~= 0 then on = 1; break end
				end
				if on == 1 then break end
			end
			if on == 1 then out:set(tx, ty, 1) end
		end
	end
	return out
end

-- Dilate a mask by a disk of the given radius, returning a new mask of the same size.
function Normalizer.dilate(src: GridBuffer.GridBuffer, r: number): GridBuffer.GridBuffer
	local out = GridBuffer.new(src.size)
	if r <= 0 then
		src:forEachOn(function(x, y) out:set(x, y, 1) end)
		return out
	end
	local r2 = r * r
	src:forEachOn(function(x, y)
		for dy = -r, r do
			for dx = -r, r do
				if dx*dx + dy*dy <= r2 then
					out:set(x + dx, y + dy, 1)
				end
			end
		end
	end)
	return out
end

-- IoU of two equally-sized masks.
function Normalizer.iou(a: GridBuffer.GridBuffer, b: GridBuffer.GridBuffer): number
	assert(a.size == b.size, "iou: size mismatch")
	local inter, union = 0, 0
	for y = 1, a.size do
		local ra, rb = a.cells[y], b.cells[y]
		for x = 1, a.size do
			local av, bv = ra[x], rb[x]
			if av ~= 0 or bv ~= 0 then
				union = union + 1
				if av ~= 0 and bv ~= 0 then inter = inter + 1 end
			end
		end
	end
	if union == 0 then return 0 end
	return inter / union
end

-- Centroid of set cells in grid coords (float).
-- Rotate mask by `angle` radians around its center (inverse mapping + nearest-neighbor sampling).
function Normalizer.rotate(src: GridBuffer.GridBuffer, angle: number): GridBuffer.GridBuffer
	local N = src.size
	local out = GridBuffer.new(N)
	local cx, cy = N / 2, N / 2
	local c, s = math.cos(-angle), math.sin(-angle)
	for ty = 1, N do
		for tx = 1, N do
			local dx = tx - cx
			local dy = ty - cy
			local sx = math.floor(c * dx - s * dy + cx + 0.5)
			local sy = math.floor(s * dx + c * dy + cy + 0.5)
			if src:get(sx, sy) ~= 0 then
				out:set(tx, ty, 1)
			end
		end
	end
	return out
end

function Normalizer.centroid(src: GridBuffer.GridBuffer): (number, number, number)
	local sx, sy, n = 0, 0, 0
	src:forEachOn(function(x, y) sx = sx + x; sy = sy + y; n = n + 1 end)
	if n == 0 then return 0, 0, 0 end
	return sx / n, sy / n, n
end

return Normalizer
