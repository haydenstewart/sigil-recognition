-- Paste this into Roblox Studio's Command Bar (View > Command Bar) and run.
-- It will print a single JSON blob to the Output window. Copy that blob,
-- save it as templates.json next to train.py.
--
-- Cache-busting strategy: clone the whole Sigils + Signs folders (including
-- their Registry modules) to temp locations and require *those* clones. The
-- sigil modules' relative requires (`script.Parent.Registry`) then resolve to
-- the cloned, freshly-loaded Registry, sidestepping any stale cache entries
-- from earlier failed requires in the current Studio session.

local HttpService = game:GetService("HttpService")
local SS          = game.ReplicatedStorage.SpellSystem

local function freshRegistry(originalFolder, cloneName)
	local cloneFolder = originalFolder:Clone()
	cloneFolder.Name = cloneName
	cloneFolder.Parent = originalFolder.Parent
	-- Fresh require of the cloned Registry: starts with empty `entries` / `byId`.
	local Reg = require(cloneFolder.Registry)
	for _, child in ipairs(cloneFolder:GetChildren()) do
		if child:IsA("ModuleScript") and child.Name ~= "Registry" then
			local ok, err = pcall(require, child)
			if not ok then
				warn("[export] failed to load " .. child.Name .. ": " .. tostring(err))
			end
		end
	end
	return Reg, cloneFolder
end

local SigilReg, sigilClone = freshRegistry(SS.Sigils, "Sigils__ExportClone")
local SignReg,  signClone  = freshRegistry(SS.Signs,  "Signs__ExportClone")

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
for _, e in ipairs(SigilReg.all()) do
	out.sigils[e.id] = { size = e.template.size, bits = gridToBits(e.template) }
end
for _, e in ipairs(SignReg.all()) do
	out.signs[e.id] = {
		size = e.template.size,
		bits = gridToBits(e.template),
		rotationInvariant = e.rotationInvariant and true or false,
	}
end

print(HttpService:JSONEncode(out))

-- Cleanup: remove the temp clones so they don't clutter the explorer.
sigilClone:Destroy()
signClone:Destroy()
