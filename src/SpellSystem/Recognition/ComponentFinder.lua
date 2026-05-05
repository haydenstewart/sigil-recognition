--!strict
-- Extract connected components (8-connected) from a binary mask. Used to split the
-- ring-interior ink into the central sigil plus separate sign components.

local GridBuffer = require(script.Parent.Parent.Canvas.GridBuffer)

local ComponentFinder = {}

export type Component = {
	mask: GridBuffer.GridBuffer,
	minX: number, minY: number, maxX: number, maxY: number,
	cx: number, cy: number,       -- centroid (float)
	count: number,
}

-- 4-connectivity (no diagonals): signs drawn close to the sigil's triangle stay as separate
-- components unless they actually share an axis-aligned edge cell. Diagonal near-misses don't
-- merge them -- which means T-stems adjacent to a triangle side don't get counted as part of
-- the sigil's vertical-line check.
local NEIGHBORS_4 = {
	{ 1,  0}, {-1,  0}, { 0,  1}, { 0, -1},
}

function ComponentFinder.find(src: GridBuffer.GridBuffer): { Component }
	local N = src.size
	local visited = {}
	for y = 1, N do visited[y] = {} end
	local components: { Component } = {}

	for sy = 1, N do
		for sx = 1, N do
			if src:get(sx, sy) ~= 0 and not visited[sy][sx] then
				local mask = GridBuffer.new(N)
				local queue = { sx, sy }
				visited[sy][sx] = true
				local minX, maxX = sx, sx
				local minY, maxY = sy, sy
				local sumX, sumY = 0, 0
				local cnt = 0
				while #queue > 0 do
					local y = table.remove(queue)
					local x = table.remove(queue)
					mask:set(x, y, 1)
					sumX, sumY = sumX + x, sumY + y
					cnt = cnt + 1
					if x < minX then minX = x end
					if x > maxX then maxX = x end
					if y < minY then minY = y end
					if y > maxY then maxY = y end
					for _, d in ipairs(NEIGHBORS_4) do
						local nx, ny = x + d[1], y + d[2]
						if nx >= 1 and ny >= 1 and nx <= N and ny <= N
							and not visited[ny][nx]
							and src:get(nx, ny) ~= 0 then
							visited[ny][nx] = true
							table.insert(queue, nx)
							table.insert(queue, ny)
						end
					end
				end
				table.insert(components, {
					mask = mask,
					minX = minX, minY = minY, maxX = maxX, maxY = maxY,
					cx = sumX / cnt, cy = sumY / cnt,
					count = cnt,
				})
			end
		end
	end

	return components
end

return ComponentFinder
