--!strict
-- High-level spell pipeline: evaluate a grid state -> find a match; activate runs the sigil's onCast.
-- Also provides glow/cancel helpers for the paper part.

local TweenService = game:GetService("TweenService")

local Config          = require(script.Parent.Parent.Config)
local GridBuffer      = require(script.Parent.Parent.Canvas.GridBuffer)
local RingDetector    = require(script.Parent.Parent.Recognition.RingDetector)
local ComponentFinder = require(script.Parent.Parent.Recognition.ComponentFinder)
local SigilMatcher    = require(script.Parent.Parent.Recognition.SigilMatcher)
local SignMatcher     = require(script.Parent.Parent.Recognition.SignMatcher)
local Registry        = require(script.Parent.Parent.Sigils.Registry)

local Caster = {}

export type SignInfo = {
	id: string?,                 -- nil if component didn't match any registered sign
	score: number,
	direction: Vector2?,         -- grid-space unit vector (y-down)
	rotation: number?,
	center: Vector2,             -- grid-space centroid
	size: number,                -- cell count
}

export type CastResult = {
	id: string,
	accuracy: number,
	direction: Vector2?,
	directionality: number,
	insideCount: number,
	ringCount: number,
	sigilCount: number,
	signs: { SignInfo },         -- non-central components, matched where possible
}

-- Pure evaluation of the grid.
-- Pipeline:
--   ring -> ring-interior ink -> connected components -> classify each as sign or sigil-ink
--   -> matcher sees the COMBINED sigil-ink (all non-sign components merged into one mask).
--
-- Why combine instead of picking the largest central component:
--   Sigils with decorative pieces (Wind's hash marks, Water's flanking drops) are intentionally
--   drawn as multiple disconnected components. Feeding only the central element to the matcher
--   would let players cast Wind by drawing just an S, which defeats the visual identity of the
--   glyph. Combining all non-sign components forces the player to draw the full sigil for it
--   to match.
function Caster.evaluate(grid: GridBuffer.GridBuffer): (CastResult?, string?)
	local ring = RingDetector.detect(grid)
	if not ring.found then return nil, ring.reason or "no ring" end

	local sigilMaskFull = ring.sigilMask :: GridBuffer.GridBuffer
	local sigilCountFull = sigilMaskFull:count()
	if sigilCountFull < 8 then return nil, "empty ring (no sigil)" end
	local maxFilled = ring.insideCount * Config.MaxInsideFillRatio
	if sigilCountFull > maxFilled then return nil, "interior too dense" end

	local components = ComponentFinder.find(sigilMaskFull)
	if #components == 0 then return nil, "no components" end

	-- First pass: classify each component. Signs are recognised T/arrow shapes; everything
	-- else (above the noise floor) becomes part of the sigil ink mask. Sign classification is
	-- limited to peripheral components so large central glyph pieces do not get eaten by the
	-- sign classifier when new hand-authored sigils are added before the next ML training pass.
	local N = grid.size
	local sigilInk = GridBuffer.new(N)
	local signs: { SignInfo } = {}
	local bbox = ring.bbox :: { minX: number, minY: number, maxX: number, maxY: number }
	local ringCx = (bbox.minX + bbox.maxX) / 2
	local ringCy = (bbox.minY + bbox.maxY) / 2
	local ringRadius = math.max(bbox.maxX - bbox.minX, bbox.maxY - bbox.minY) / 2
	local centralSignBlockRadius = ringRadius * 0.66
	for _, comp in ipairs(components) do
		if comp.count < 4 then continue end -- ignore tiny noise specks
		local dx = comp.cx - ringCx
		local dy = comp.cy - ringCy
		local centerOffset = math.sqrt(dx * dx + dy * dy)
		local isCentralGlyphPiece = comp.count >= 12 and centerOffset <= centralSignBlockRadius
		local m = if isCentralGlyphPiece then nil else SignMatcher.match(comp.mask)
		if m then
			table.insert(signs, {
				id = m.id,
				score = m.score,
				direction = m.direction,
				rotation = m.rotation,
				center = Vector2.new(comp.cx, comp.cy),
				size = comp.count,
			})
		else
			comp.mask:forEachOn(function(x, y) sigilInk:set(x, y, 1) end)
		end
	end

	local sigilCount = sigilInk:count()
	if sigilCount < Config.SigilMinCells then
		return nil, string.format("sigil ink too small (%d cells, need %d) -- only signs?", sigilCount, Config.SigilMinCells)
	end

	local match, matchReason = SigilMatcher.match(sigilInk)
	if not match then return nil, matchReason or "no sigil match" end

	return {
		id = match.id,
		accuracy = match.accuracy,
		direction = match.direction,
		directionality = match.directionality,
		insideCount = ring.insideCount,
		ringCount = (ring.ringMask :: GridBuffer.GridBuffer):count(),
		sigilCount = sigilCount,
		signs = signs,
	}
end

export type PeekComponent = {
	size: number,
	center: Vector2,
	centerOffset: number,  -- distance from ring center
	signId: string?,
	signScore: number,
	signDirection: Vector2?,
	isCentralCandidate: boolean,  -- passes size + centrality filters
}

export type PeekResult = {
	ringFound: boolean,
	ringReason: string?,
	components: { PeekComponent },
}

-- Non-judgemental inspection: find every component inside the ring (if any) and try to classify
-- each one as a sign. Used for live debug prints so the player can see sign detection working
-- even before they've drawn a valid sigil.
function Caster.peek(grid: GridBuffer.GridBuffer): PeekResult
	local ring = RingDetector.detect(grid)
	if not ring.found or not ring.sigilMask or not ring.bbox then
		return { ringFound = false, ringReason = ring.reason, components = {} }
	end
	local sigilMask = ring.sigilMask :: GridBuffer.GridBuffer
	local bbox = ring.bbox :: { minX: number, minY: number, maxX: number, maxY: number }
	local ringCx = (bbox.minX + bbox.maxX) / 2
	local ringCy = (bbox.minY + bbox.maxY) / 2
	local ringRadius = math.max(bbox.maxX - bbox.minX, bbox.maxY - bbox.minY) / 2
	local maxCenterOffset = ringRadius * 0.4

	local out: { PeekComponent } = {}
	for _, c in ipairs(ComponentFinder.find(sigilMask)) do
		if c.count < 4 then continue end
		local dx = c.cx - ringCx
		local dy = c.cy - ringCy
		local offset = math.sqrt(dx * dx + dy * dy)
		local m = SignMatcher.match(c.mask)
		table.insert(out, {
			size = c.count,
			center = Vector2.new(c.cx, c.cy),
			centerOffset = offset,
			signId = m and m.id or nil,
			signScore = m and m.score or 0,
			signDirection = m and m.direction or nil,
			isCentralCandidate = offset <= maxCenterOffset and c.count >= Config.SigilMinCells,
		})
	end
	table.sort(out, function(a, b) return a.size > b.size end)
	return { ringFound = true, components = out }
end

-- Dispatch activation to the registered sigil onCast.
function Caster.activate(id: string, context: {[string]: any})
	local entry = Registry.get(id)
	if not entry then
		warn("[Caster] unknown sigil id: " .. tostring(id))
		return
	end
	entry.onCast(context)
end

-- Glow pulse on the paper. Idempotent: replaces any existing glow.
function Caster.beginGlow(paperPart: BasePart, color: Color3?, duration: number?)
	local existing = paperPart:FindFirstChild("SpellGlow")
	if existing then existing:Destroy() end
	local hl = Instance.new("Highlight")
	hl.Name = "SpellGlow"
	hl.Adornee = paperPart
	hl.FillColor = color or Config.GlowColor
	hl.OutlineColor = color or Config.GlowColor
	hl.FillTransparency = 1
	hl.OutlineTransparency = 1
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = paperPart
	local d = duration or Config.CastDelay
	TweenService:Create(hl,
		TweenInfo.new(d, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FillTransparency = 0.35, OutlineTransparency = 0 }
	):Play()
end

function Caster.endGlow(paperPart: BasePart)
	local existing = paperPart:FindFirstChild("SpellGlow")
	if not existing then return end
	local tween = TweenService:Create(existing,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FillTransparency = 1, OutlineTransparency = 1 }
	)
	tween:Play()
	tween.Completed:Connect(function() existing:Destroy() end)
end

return Caster
