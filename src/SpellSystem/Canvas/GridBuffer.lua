--!strict
-- 2D binary grid. Rows indexed by y, cols by x, both 1-based.
-- Used for drawn-cell state and for templates.

local GridBuffer = {}
GridBuffer.__index = GridBuffer

export type GridBuffer = typeof(setmetatable({} :: {
	size: number,
	cells: {[number]: {[number]: number}},
}, GridBuffer))

function GridBuffer.new(size: number): GridBuffer
	local self = setmetatable({
		size = size,
		cells = {},
	}, GridBuffer)
	for y = 1, size do
		local row = {}
		for x = 1, size do row[x] = 0 end
		self.cells[y] = row
	end
	return self
end

function GridBuffer:inBounds(x: number, y: number): boolean
	return x >= 1 and y >= 1 and x <= self.size and y <= self.size
end

function GridBuffer:set(x: number, y: number, v: number?)
	if not self:inBounds(x, y) then return end
	self.cells[y][x] = v or 1
end

function GridBuffer:get(x: number, y: number): number
	if not self:inBounds(x, y) then return 0 end
	return self.cells[y][x]
end

function GridBuffer:clear()
	for y = 1, self.size do
		local row = self.cells[y]
		for x = 1, self.size do row[x] = 0 end
	end
end

function GridBuffer:count(): number
	local c = 0
	for y = 1, self.size do
		local row = self.cells[y]
		for x = 1, self.size do c = c + row[x] end
	end
	return c
end

function GridBuffer:clone(): GridBuffer
	local copy = GridBuffer.new(self.size)
	for y = 1, self.size do
		local src, dst = self.cells[y], copy.cells[y]
		for x = 1, self.size do dst[x] = src[x] end
	end
	return copy
end

-- Iterate every set cell.
function GridBuffer:forEachOn(fn: (number, number) -> ())
	for y = 1, self.size do
		local row = self.cells[y]
		for x = 1, self.size do
			if row[x] ~= 0 then fn(x, y) end
		end
	end
end

-- Bounding box of set cells. Returns nil if empty.
function GridBuffer:bbox(): (number?, number?, number?, number?)
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	local any = false
	for y = 1, self.size do
		local row = self.cells[y]
		for x = 1, self.size do
			if row[x] ~= 0 then
				any = true
				if x < minX then minX = x end
				if y < minY then minY = y end
				if x > maxX then maxX = x end
				if y > maxY then maxY = y end
			end
		end
	end
	if not any then return nil, nil, nil, nil end
	return minX, minY, maxX, maxY
end

return GridBuffer
