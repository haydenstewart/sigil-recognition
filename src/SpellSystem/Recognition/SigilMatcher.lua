--!strict
-- Given a sigil mask extracted from the ring interior, find the best-matching registered sigil.
-- Also returns alterations (e.g., dominant prong direction for directional spells).

local Config     = require(script.Parent.Parent.Config)
local GridBuffer = require(script.Parent.Parent.Canvas.GridBuffer)
local Normalizer = require(script.Parent.Normalizer)
local Registry   = require(script.Parent.Parent.Sigils.Registry)
local MLMatcher  = require(script.Parent.MLMatcher)

local SigilMatcher = {}

export type MatchResult = {
	id: string,               -- e.g., "fire"
	score: number,            -- IoU, 0..1
	accuracy: number,          -- same as score, named for gameplay use
	direction: Vector2?,      -- unit vector in paper-grid space (x, y); y down. nil = omnidirectional
	directionality: number,   -- how pronounced the prong is (1.0 = none, >Config.DirectionalRatio = directional)
}

-- Compute dominant direction via sector-extremum ratio.
-- We partition the sigil's cells (relative to centroid) into angular sectors and keep the max radius per sector.
-- Comparing top-sector-max to second-sector-max captures "one prong extended beyond the others".
-- A symmetric triangle has 3 similar sector-maxes, so the ratio stays ~1.
local function computeDirection(sigil: GridBuffer.GridBuffer): (Vector2?, number)
	local cx, cy, n = Normalizer.centroid(sigil)
	if n < 8 then return nil, 1 end
	local SECTORS = 6                         -- 60° each
	local maxR = table.create(SECTORS, 0)
	local maxAng = table.create(SECTORS, 0)
	sigil:forEachOn(function(x, y)
		local dx, dy = x - cx, y - cy
		local r = math.sqrt(dx*dx + dy*dy)
		local a = math.atan2(dy, dx)             -- -π..π; y grows down
		local idx = math.floor(((a + math.pi) / (2 * math.pi)) * SECTORS) + 1
		if idx > SECTORS then idx = SECTORS end
		if idx < 1 then idx = 1 end
		if r > maxR[idx] then
			maxR[idx] = r
			maxAng[idx] = a
		end
	end)

	local sorted = {}
	for i = 1, SECTORS do
		if maxR[i] > 0 then table.insert(sorted, { r = maxR[i], a = maxAng[i] }) end
	end
	if #sorted < 2 then return nil, 1 end
	table.sort(sorted, function(p, q) return p.r > q.r end)

	local top = sorted[1]
	local second = sorted[2].r
	if second <= 0 then return nil, 1 end
	local ratio = top.r / second
	if ratio < Config.DirectionalRatio then return nil, ratio end
	return Vector2.new(math.cos(top.a), math.sin(top.a)), ratio
end

-- Matches an extracted sigil mask against all registered sigils. Returns (match?, reason?).
-- The reason is populated when we can't match, to help debugging noisy drawings.
function SigilMatcher.match(sigilMask: GridBuffer.GridBuffer): (MatchResult?, string?)
	-- Prefer the trained MLP if its model module has been populated. Falls through to
	-- the original dilated-IoU loop below when the model is still the placeholder, so the
	-- system stays functional during dev / before the first training run.
	local sigilModelReady = MLMatcher.isReady()
	if sigilModelReady then
		return MLMatcher.matchSigil(sigilMask)
	end

	local normalized = Normalizer.normalize(sigilMask, Config.TemplateResolution)
	if not normalized then return nil, "empty sigil" end

	local dilatedDrawn = Normalizer.dilate(normalized, Config.MatchDilation)

	local bestId, bestScore, bestEntry
	for _, entry in ipairs(Registry.all()) do
		local dilatedTemplate = Normalizer.dilate(entry.template, Config.MatchDilation)
		local score = Normalizer.iou(dilatedDrawn, dilatedTemplate)
		if bestScore == nil or score > bestScore then
			bestScore = score
			bestId = entry.id
			bestEntry = entry
		end
	end

	if not bestId then return nil, "no registered sigils" end
	if (bestScore :: number) < Config.MatchThreshold then
		return nil, string.format("best=%s score=%.2f (need %.2f)", bestId, bestScore, Config.MatchThreshold)
	end

	if bestEntry and bestEntry.verify then
		local ok = bestEntry.verify(normalized, sigilMask)
		if not ok then
			return nil, string.format("%s shape ok (%.2f) but required features missing", bestId, bestScore)
		end
	end

	local dir, ratio = computeDirection(sigilMask)
	return {
		id = bestId,
		score = bestScore :: number,
		accuracy = bestScore :: number,
		direction = dir,
		directionality = ratio,
	}
end

return SigilMatcher
