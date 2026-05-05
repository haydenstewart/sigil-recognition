--!strict
-- Match a single sign component against registered sign templates.
-- Tries multiple rotations so the user can orient the sign freely (e.g., T pointing
-- outward/inward around a sigil). Returns the best-matching sign + its rotation angle.

local Config     = require(script.Parent.Parent.Config)
local GridBuffer = require(script.Parent.Parent.Canvas.GridBuffer)
local Normalizer = require(script.Parent.Normalizer)
local Registry   = require(script.Parent.Parent.Signs.Registry)
local MLMatcher  = require(script.Parent.MLMatcher)

local SignMatcher = {}

export type SignMatch = {
	id: string,
	score: number,
	rotation: number,             -- radians, 0 = template orientation
	direction: Vector2,           -- unit vector the sign "points", in grid coords (y-down)
	sizeCells: number,            -- number of ink cells in the source component
}

-- Finer rotation search (12 steps = 30° each) catches hand-drawn orientations more reliably.
local ROTATIONS = {}
do
	for i = 0, 11 do ROTATIONS[i + 1] = (i / 12) * math.pi * 2 - math.pi end
end

-- Matches a component mask. Returns nil if no sign matches well, or if the top two candidate
-- sign types are within `SignMatchMargin` of each other (ambiguous shape -> reject rather
-- than risk misclassifying a T as an arrow or vice versa).
function SignMatcher.match(componentMask: GridBuffer.GridBuffer): SignMatch?
	-- Prefer the trained MLP if its model module has been populated. Falls through to
	-- the original IoU rotation-search loop below when the model is the placeholder.
	local _, signModelReady = MLMatcher.isReady()
	if signModelReady then
		return MLMatcher.matchSign(componentMask)
	end

	local normalized = Normalizer.normalize(componentMask, Config.TemplateResolution)
	if not normalized then return nil end

	local dilation = Config.SignMatchDilation or Config.MatchDilation

	-- Record the best score per sign-id (best across all rotations).
	local bestPerId: { [string]: { score: number, rot: number } } = {}
	for _, entry in ipairs(Registry.all()) do
		local dilatedTemplate = Normalizer.dilate(entry.template, dilation)
		local angles = entry.rotationInvariant and { 0 } or ROTATIONS
		local best = { score = 0, rot = 0 }
		for _, angle in ipairs(angles) do
			local rotated = Normalizer.rotate(normalized, angle)
			local dilatedDrawn = Normalizer.dilate(rotated, dilation)
			local score = Normalizer.iou(dilatedDrawn, dilatedTemplate)
			if score > best.score then
				best.score = score
				best.rot = angle
			end
		end
		bestPerId[entry.id] = best
	end

	-- Find top-1 and top-2 sign ids by score.
	local bestId: string? = nil
	local bestScore = 0
	local bestRot = 0
	local secondScore = 0
	for id, rec in pairs(bestPerId) do
		if rec.score > bestScore then
			secondScore = bestScore
			bestScore = rec.score
			bestId = id
			bestRot = rec.rot
		elseif rec.score > secondScore then
			secondScore = rec.score
		end
	end

	if not bestId or bestScore < (Config.SignMatchThreshold or Config.MatchThreshold) then return nil end

	-- Reject ambiguous shapes: the winner must beat the runner-up by a minimum margin.
	local margin = Config.SignMatchMargin or 0.06
	if bestScore - secondScore < margin then return nil end

	-- Direction the sign "points": template's canonical direction is (0, -1) (up in grid).
	-- Applying the inverse of the rotation used to match gives us the drawn direction.
	local ang = -bestRot
	local templateUp = Vector2.new(0, -1)
	local c, s = math.cos(ang), math.sin(ang)
	local dir = Vector2.new(c * templateUp.X - s * templateUp.Y, s * templateUp.X + c * templateUp.Y)

	return {
		id = bestId :: string,
		score = bestScore,
		rotation = bestRot,
		direction = dir,
		sizeCells = componentMask:count(),
	}
end

return SignMatcher
