--!strict
-- Sigil registry. Add new sigils by calling Registry.register(entry) from their own ModuleScript.
-- The canonical call site is SpellSystem.Sigils.<Name> modules, all loaded at startup.

local GridBuffer = require(script.Parent.Parent.Canvas.GridBuffer)

export type SigilEntry = {
	id: string,                                   -- unique id, e.g., "fire"
	template: GridBuffer.GridBuffer,              -- canonical template at Config.TemplateResolution
	buildVisual: (GridBuffer.GridBuffer) -> (),   -- draw canonical glyph into given buffer (for reference paper)
	onCast: ({[string]: any}) -> (),              -- server-side activation
	verify: ((GridBuffer.GridBuffer, GridBuffer.GridBuffer) -> (boolean, string?))?, -- optional: rejects drawings missing required features. Receives (normalized, rawSigilMask)
}

local Registry = {}
local entries: {SigilEntry} = {}
local byId: {[string]: SigilEntry} = {}

function Registry.register(entry: SigilEntry)
	assert(entry.id and entry.template and entry.buildVisual and entry.onCast, "sigil entry missing fields")
	-- If this id was already registered (e.g. by an earlier load in the same Studio
	-- session that's now stale), replace the entry rather than skipping. Dedup-skip
	-- meant edits to a sigil's template wouldn't take effect without a full restart.
	local existing = byId[entry.id]
	if existing then
		for i, e in ipairs(entries) do
			if e == existing then entries[i] = entry; break end
		end
	else
		table.insert(entries, entry)
	end
	byId[entry.id] = entry
end

function Registry.get(id: string): SigilEntry?
	return byId[id]
end

function Registry.all(): {SigilEntry}
	return entries
end

-- Require every child ModuleScript of Sigils/ except this Registry.
-- Each such module is expected to call Registry.register(...) at the top level.
function Registry.loadAll()
	local parent = script.Parent
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("ModuleScript") and child ~= script then
			require(child)
		end
	end
end

return Registry
