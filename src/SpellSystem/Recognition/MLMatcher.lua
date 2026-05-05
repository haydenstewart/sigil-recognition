--!strict
-- ML-based replacement for the IoU loops in SigilMatcher / SignMatcher.
-- Returns the SAME types as the existing matchers, so the swap inside each
-- of those modules is a one-liner.
--
-- Falls back to nil (with a reason) when the model is empty -- the existing
-- matcher can be left as a fallback by checking that case.

local Config        = require(script.Parent.Parent.Config)
local GridBuffer    = require(script.Parent.Parent.Canvas.GridBuffer)
local Normalizer    = require(script.Parent.Normalizer)
local Inference     = require(script.Parent.Inference)
local SigilModel    = require(script.Parent.SigilModel)
local SignModel     = require(script.Parent.SignModel)
local SigilRegistry = require(script.Parent.Parent.Sigils.Registry)

local MLMatcher = {}

-- Sentinel id used by the training script for "random scribble / not a sigil".
-- Predictions of this class are treated as no-match.
local OTHER_ID = "_other"

-- ===== prong direction (geometric, identical to SigilMatcher) =====
-- Sigil direction ("which way does the dominant prong point") is derived from
-- the shape itself, not learned -- moving it into the model would force every
-- retraining cycle to reproduce angle estimation. Easier to keep it here.
local function computeDirection(sigil: GridBuffer.GridBuffer): (Vector2?, number)
	local cx, cy, n = Normalizer.centroid(sigil)
	if n < 8 then return nil, 1 end
	local SECTORS = 6
	local maxR = table.create(SECTORS, 0)
	local maxAng = table.create(SECTORS, 0)
	sigil:forEachOn(function(x, y)
		local dx, dy = x - cx, y - cy
		local r = math.sqrt(dx * dx + dy * dy)
		local a = math.atan2(dy, dx)
		local idx = math.floor(((a + math.pi) / (2 * math.pi)) * SECTORS) + 1
		if idx > SECTORS then idx = SECTORS end
		if idx < 1 then idx = 1 end
		if r > maxR[idx] then maxR[idx] = r; maxAng[idx] = a end
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

export type SigilMatch = {
	id: string,
	score: number,
	accuracy: number,
	direction: Vector2?,
	directionality: number,
}

function MLMatcher.matchSigil(sigilMask: GridBuffer.GridBuffer): (SigilMatch?, string?)
	local normalized = Normalizer.normalize(sigilMask, Config.TemplateResolution)
	if not normalized then return nil, "empty sigil" end

	local result = Inference.predict(SigilModel, normalized)
	if not result then return nil, "sigil model not trained" end
	if result.id == OTHER_ID then
		return nil, string.format("classified as not-a-sigil (prob=%.2f)", result.score)
	end

	if result.score < Config.MatchThreshold then
		return nil, string.format("best=%s prob=%.2f (need %.2f)", result.id, result.score, Config.MatchThreshold)
	end

	-- Per-class verifiers (e.g., Fire's central vertical-line check) still apply.
	local entry = SigilRegistry.get(result.id)
	if entry and entry.verify then
		local ok = entry.verify(normalized, sigilMask)
		if not ok then
			return nil, string.format("%s shape ok (%.2f) but required features missing", result.id, result.score)
		end
	end

	local dir, ratio = computeDirection(sigilMask)
	return {
		id             = result.id,
		score          = result.score,
		accuracy       = result.score,
		direction      = dir,
		directionality = ratio,
	}
end

export type SignMatch = {
	id: string,
	score: number,
	rotation: number,
	direction: Vector2,
	sizeCells: number,
}

-- 12-step rotation sweep: a single forward pass on a rotation-augmented model
-- doesn't tell us which way the sign points. So we run the model at each of 12
-- rotations and keep the one with the highest probability for its top class.
-- Each forward pass is ~3-5 ms, so this stays well under 100 ms total.
local SIGN_ROTATIONS = 12

function MLMatcher.matchSign(componentMask: GridBuffer.GridBuffer): SignMatch?
	local normalized = Normalizer.normalize(componentMask, Config.TemplateResolution)
	if not normalized then return nil end
	if not SignModel.classes or #SignModel.classes == 0 then return nil end

	local bestScore, bestRot, bestId = 0, 0, nil :: string?
	for i = 0, SIGN_ROTATIONS - 1 do
		local angle = (i / SIGN_ROTATIONS) * math.pi * 2 - math.pi
		local rotated = (i == 0) and normalized or Normalizer.rotate(normalized, angle)
		local r = Inference.predict(SignModel, rotated)
		if r and r.id ~= OTHER_ID and r.score > bestScore then
			bestScore = r.score
			bestRot   = angle
			bestId    = r.id
		end
	end

	local threshold = Config.SignMatchThreshold or Config.MatchThreshold
	if not bestId or bestScore < threshold then return nil end

	-- Direction recovery: same math as SignMatcher (template canonical = (0,-1)).
	local ang = -bestRot
	local c, s = math.cos(ang), math.sin(ang)
	-- templateUp = (0, -1)
	local dir = Vector2.new(c * 0 - s * -1, s * 0 + c * -1)

	return {
		id        = bestId :: string,
		score     = bestScore,
		rotation  = bestRot,
		direction = dir,
		sizeCells = componentMask:count(),
	}
end

local function sigilModelCoversRegistry(): boolean
	if not SigilModel.classes or #SigilModel.classes == 0 then return false end
	local classSet: {[string]: boolean} = {}
	for _, id in ipairs(SigilModel.classes) do
		if id ~= OTHER_ID then classSet[id] = true end
	end
	local registered = 0
	for _, entry in ipairs(SigilRegistry.all()) do
		registered += 1
		if not classSet[entry.id] then return false end
	end
	return registered > 0
end

-- True once the model files have been overwritten with real weights.
-- If runtime sigils outgrow the trained class list, fall back to template matching so new
-- hand-authored sigils work immediately before the next training pass.
function MLMatcher.isReady(): (boolean, boolean)
	return sigilModelCoversRegistry(), (#SignModel.classes > 0)
end

return MLMatcher
