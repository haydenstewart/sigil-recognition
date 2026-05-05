--!strict
-- Runtime adapter for the WFP raw click-data shards in Workspace.
-- Keeps the 9000-ish asset rip as data and lets spell effects request useful textures/sounds by tag.

local AssetCatalog = {}

export type AssetRow = {
	id: string,
	name: string,
	keywords: string,
	kind: string,
	fps: number,
	grid: string,
	gridX: number,
	gridY: number,
	flipbook: boolean,
	resolution: string,
}

local loaded = false
local rows: {AssetRow} = {}
local byKind: {[string]: {AssetRow}} = {}

local SHARD_PREFIX = "_WFPClickRaw_"
local SHARD_COUNT = 12

local function lower(s: any): string
	return string.lower(tostring(s or ""))
end

local function insertRow(id: string, raw: {[string]: any})
	local row: AssetRow = {
		id = id,
		name = tostring(raw.n or ""),
		keywords = tostring(raw.k or ""),
		kind = tostring(raw.t or ""),
		fps = tonumber(raw.f) or 1,
		grid = tostring(raw.g or "1x1"),
		gridX = tonumber(raw.x) or 1,
		gridY = tonumber(raw.y) or 1,
		flipbook = raw.fb == true,
		resolution = tostring(raw.r or ""),
	}
	table.insert(rows, row)
	local bucket = byKind[row.kind]
	if not bucket then
		bucket = {}
		byKind[row.kind] = bucket
	end
	table.insert(bucket, row)
end

function AssetCatalog.load()
	if loaded then return end
	loaded = true
	for i = 1, SHARD_COUNT do
		local shard = workspace:FindFirstChild(SHARD_PREFIX .. i)
		if shard and shard:IsA("ModuleScript") then
			local ok, data = pcall(require, shard)
			if ok and type(data) == "table" then
				for id, raw in pairs(data) do
					if type(id) == "string" and type(raw) == "table" then
						insertRow(id, raw)
					end
				end
			else
				warn("[AssetCatalog] failed to load shard " .. shard.Name .. ": " .. tostring(data))
			end
		end
	end
end

local function termScore(row: AssetRow, terms: {string}?): number
	if not terms or #terms == 0 then return 0 end
	local hay = lower(row.name .. " " .. row.keywords .. " " .. row.kind)
	local score = 0
	for _, term in ipairs(terms) do
		local t = lower(term)
		if t ~= "" and string.find(hay, t, 1, true) then
			score += 1
		end
	end
	return score
end

function AssetCatalog.find(kind: string?, terms: {string}?, limit: number?): {AssetRow}
	AssetCatalog.load()
	local source = kind and byKind[kind] or rows
	local scored = {}
	for _, row in ipairs(source or {}) do
		local score = termScore(row, terms)
		if not terms or #terms == 0 or score > 0 then
			table.insert(scored, { row = row, score = score })
		end
	end
	table.sort(scored, function(a, b)
		if a.score == b.score then return a.row.id < b.row.id end
		return a.score > b.score
	end)
	local out = {}
	local maxCount = limit or #scored
	for i = 1, math.min(maxCount, #scored) do
		table.insert(out, scored[i].row)
	end
	return out
end

function AssetCatalog.pick(kind: string?, terms: {string}?, seed: number?): AssetRow?
	local matches = AssetCatalog.find(kind, terms, 40)
	if #matches == 0 and kind then matches = AssetCatalog.find(nil, terms, 40) end
	if #matches == 0 then return nil end
	local index = ((seed or 1) - 1) % #matches + 1
	return matches[index]
end

function AssetCatalog.assetUri(row: AssetRow?): string?
	if not row then return nil end
	return "rbxassetid://" .. row.id
end

function AssetCatalog.applyFlipbook(emitter: ParticleEmitter, row: AssetRow?)
	if not row or not row.flipbook then return end
	if row.gridX == 2 and row.gridY == 2 then
		emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
	elseif row.gridX == 4 and row.gridY == 4 then
		emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	elseif row.gridX == 8 and row.gridY == 8 then
		emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid8x8
	else
		emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.None
	end
	if emitter.FlipbookLayout ~= Enum.ParticleFlipbookLayout.None then
		emitter.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
		emitter.FlipbookFramerate = NumberRange.new(math.clamp(row.fps, 1, 64))
	end
end

function AssetCatalog.stats(): {[string]: number}
	AssetCatalog.load()
	local out = { total = #rows }
	for kind, bucket in pairs(byKind) do
		out[kind] = #bucket
	end
	return out
end

return AssetCatalog
