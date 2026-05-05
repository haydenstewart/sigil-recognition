--!strict
-- Signs registry. Mirrors Sigils.Registry but for keystone/sign modifiers.
-- Signs shape the FORM of a spell (column, dispersion, levitation, ...).

local GridBuffer = require(script.Parent.Parent.Canvas.GridBuffer)

export type SignEntry = {
	id: string,
	template: GridBuffer.GridBuffer,              -- canonical template at Config.TemplateResolution
	buildVisual: (GridBuffer.GridBuffer) -> (),   -- draw canonical glyph (for reference paper / future docs)
	rotationInvariant: boolean?,                  -- if true, matcher skips rotation search
	description: string?,
}

local Registry = {}
local entries: { SignEntry } = {}
local byId: { [string]: SignEntry } = {}

function Registry.register(entry: SignEntry)
	assert(entry.id and entry.template and entry.buildVisual, "sign entry missing fields")
	if byId[entry.id] then return end
	table.insert(entries, entry)
	byId[entry.id] = entry
end

function Registry.get(id: string): SignEntry?
	return byId[id]
end

function Registry.all(): { SignEntry }
	return entries
end

-- Require every child ModuleScript of Signs/ except this Registry.
function Registry.loadAll()
	local parent = script.Parent
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("ModuleScript") and child ~= script then
			require(child)
		end
	end
end

return Registry
