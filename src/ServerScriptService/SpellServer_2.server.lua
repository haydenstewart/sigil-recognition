-- Paste this into Roblox Studio's Command Bar (View > Command Bar) and run.
-- It will print a single JSON blob to the Output window. Copy that blob,
-- save it as templates.json next to train.py.
--
-- Re-run any time you add or change a sigil/sign and want to retrain.

local HttpService    = game:GetService("HttpService")
local SigilRegistry  = require(game.ReplicatedStorage.SpellSystem.Sigils.Registry)
local SignRegistry   = require(game.ReplicatedStorage.SpellSystem.Signs.Registry)

SigilRegistry.loadAll()
SignRegistry.loadAll()

local function gridToBits(grid)
	local rows = table.create(grid.size)
	for y = 1, grid.size do
		local chars = table.create(grid.size)
		for x = 1, grid.size do
			chars[x] = (grid:get(x, y) ~= 0) and "1" or "0"
		end
		rows[y] = table.concat(chars)
	end
	return rows
end

local out = { sigils = {}, signs = {} }
for _, e in ipairs(SigilRegistry.all()) do
	out.sigils[e.id] = { size = e.template.size, bits = gridToBits(e.template) }
end
for _, e in ipairs(SignRegistry.all()) do
	out.signs[e.id] = {
		size = e.template.size,
		bits = gridToBits(e.template),
		rotationInvariant = e.rotationInvariant and true or false,
	}
end

print(HttpService:JSONEncode(out))
