--!strict
-- Detects a closed ring on a GridBuffer.
-- Approach: flood-fill from the border through unfilled cells to mark "outside".
-- Unfilled cells not reached by the flood are enclosed ("inside").
-- Drawn cells with no "outside" 4-neighbor are interior sigil cells; the rest bound the ring.

local Config     = require(script.Parent.Parent.Config)
local GridBuffer = require(script.Parent.Parent.Canvas.GridBuffer)

local RingDetector = {}

export type Result = {
	found: boolean,
	insideCells: {[number]: {[number]: boolean}}?,   -- [y][x]=true for enclosed unfilled cells
	sigilMask: GridBuffer.GridBuffer?,               -- drawn cells that are inside the ring
	ringMask: GridBuffer.GridBuffer?,                -- drawn cells bordering outside (the ring itself)
	bbox: {minX: number, minY: number, maxX: number, maxY: number}?, -- of the inside region
	insideCount: number,
	reason: string?,
}

local NEIGHBORS = {
	{ 1,  0}, {-1,  0}, { 0,  1}, { 0, -1},
}

function RingDetector.detect(grid: GridBuffer.GridBuffer): Result
	local N = grid.size
	local outside = {}
	for y = 1, N do outside[y] = {} end

	-- Seed: every border unfilled cell is outside.
	local stack = {}
	local function push(x: number, y: number)
		if x < 1 or y < 1 or x > N or y > N then return end
		if outside[y][x] then return end
		if grid:get(x, y) ~= 0 then return end
		outside[y][x] = true
		stack[#stack + 1] = x
		stack[#stack + 1] = y
	end

	for x = 1, N do push(x, 1); push(x, N) end
	for y = 1, N do push(1, y); push(N, y) end

	while #stack > 0 do
		local y = table.remove(stack)
		local x = table.remove(stack)
		for _, d in ipairs(NEIGHBORS) do
			push(x + d[1], y + d[2])
		end
	end

	-- Collect enclosed cells, compute bbox & count.
	local insideCells = {}
	for y = 1, N do insideCells[y] = {} end
	local insideCount = 0
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for y = 1, N do
		for x = 1, N do
			if grid:get(x, y) == 0 and not outside[y][x] then
				insideCells[y][x] = true
				insideCount = insideCount + 1
				if x < minX then minX = x end
				if y < minY then minY = y end
				if x > maxX then maxX = x end
				if y > maxY then maxY = y end
			end
		end
	end

	if insideCount < Config.MinInteriorCells then
		return {
			found = false,
			insideCount = insideCount,
			reason = "no enclosed region or too small (need " .. Config.MinInteriorCells .. " cells)",
		}
	end

	-- Classify drawn cells: flood-fill through 4-connected drawn cells, seeded at cells
	-- adjacent to "outside" (the ring perimeter). Anything reached is ring; everything else
	-- is sigil. This correctly treats thick rings (whose inner edge no longer touches outside)
	-- as ring, and leaves only the fully-enclosed ink as sigil.
	local ringMask  = GridBuffer.new(N)
	local sigilMask = GridBuffer.new(N)
	local ringQueue = {}
	grid:forEachOn(function(x, y)
		for _, d in ipairs(NEIGHBORS) do
			local nx, ny = x + d[1], y + d[2]
			if nx < 1 or ny < 1 or nx > N or ny > N or outside[ny][nx] then
				ringMask:set(x, y, 1)
				table.insert(ringQueue, x)
				table.insert(ringQueue, y)
				return
			end
		end
	end)
	while #ringQueue > 0 do
		local y = table.remove(ringQueue)
		local x = table.remove(ringQueue)
		for _, d in ipairs(NEIGHBORS) do
			local nx, ny = x + d[1], y + d[2]
			if nx >= 1 and ny >= 1 and nx <= N and ny <= N
				and grid:get(nx, ny) ~= 0
				and ringMask:get(nx, ny) == 0 then
				ringMask:set(nx, ny, 1)
				table.insert(ringQueue, nx)
				table.insert(ringQueue, ny)
			end
		end
	end
	grid:forEachOn(function(x, y)
		if ringMask:get(x, y) == 0 then sigilMask:set(x, y, 1) end
	end)

	return {
		found = true,
		insideCells = insideCells,
		sigilMask = sigilMask,
		ringMask = ringMask,
		bbox = { minX = minX, minY = minY, maxX = maxX, maxY = maxY },
		insideCount = insideCount,
	}
end

return RingDetector
