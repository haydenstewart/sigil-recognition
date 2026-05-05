-- SpellServer: registers sigils, validates client cast requests, dispatches activation.
-- Drawing & visuals live on the client; the server is the authority for what a spell does.

local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local SpellSystem = RS:WaitForChild("SpellSystem")
local Config       = require(SpellSystem.Config)
local Registry     = require(SpellSystem.Sigils.Registry)
local SignRegistry = require(SpellSystem.Signs.Registry)
local Caster       = require(SpellSystem.Spells.Caster)

Registry.loadAll()
SignRegistry.loadAll()

local remotes = RS:WaitForChild("SpellRemotes")
local CastRemote = remotes:WaitForChild("Cast")

CastRemote.OnServerEvent:Connect(function(player, data)
	if typeof(data) ~= "table" then return end
	local id = tostring(data.sigilId or "")
	if id == "" then return end
	local paper = data.paper
	if typeof(paper) ~= "Instance" or not paper:IsA("BasePart") then return end
	if not CollectionService:HasTag(paper, Config.PaperTag) then return end
	local char = player.Character
	if char and char.PrimaryPart then
		if (paper.Position - char.PrimaryPart.Position).Magnitude > (Config.ClickDistance + 8) then
			return
		end
	end
	local direction = nil
	if typeof(data.direction) == "Vector2" then direction = data.direction end

	-- Sanitize signs: accept only the fields we expect, drop anything else.
	local signs = {}
	if typeof(data.signs) == "table" then
		for _, raw in ipairs(data.signs) do
			if typeof(raw) == "table" then
				table.insert(signs, {
					id = typeof(raw.id) == "string" and raw.id or nil,
					score = tonumber(raw.score) or 0,
					direction = typeof(raw.direction) == "Vector2" and raw.direction or nil,
					center = typeof(raw.center) == "Vector2" and raw.center or nil,
					size = tonumber(raw.size) or 0,
				})
			end
		end
	end

	Caster.activate(id, {
		player = player,
		paper = paper,
		paperCFrame = paper.CFrame,
		accuracy = tonumber(data.accuracy) or 0,
		directionality = tonumber(data.directionality) or 1,
		direction = direction,
		signs = signs,
	})
end)

print("[SpellServer] ready.")
print("  sigils:")
for _, s in ipairs(Registry.all()) do print("    -", s.id) end
print("  signs:")
for _, s in ipairs(SignRegistry.all()) do print("    -", s.id) end
