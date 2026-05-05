-- SpellToolServer: creates a temporary drawable paper when the StarterPack tool is activated.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")

local SpellSystem = RS:WaitForChild("SpellSystem")
local Config = require(SpellSystem.Config)

local remotes = RS:WaitForChild("SpellRemotes")
local OpenToolPaper = remotes:WaitForChild("OpenToolPaper")

local papersByUserId = {}
local lastRequestByUserId = {}

local function rootOf(player)
	local char = player.Character
	return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
end

local function makePaper(player)
	local root = rootOf(player)
	if not root then return nil end

	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 1e-4 then look = Vector3.new(0, 0, -1) end
	look = look.Unit

	local paper = papersByUserId[player.UserId]
	if not paper or not paper.Parent then
		paper = Instance.new("Part")
		paper.Name = "SpellPaper_Tool_" .. player.UserId
		paper.Anchored = true
		paper.CanCollide = false
		paper.CanQuery = true
		paper.CanTouch = false
		paper.Material = Enum.Material.SmoothPlastic
		paper.Color = Config.PaperColor
		paper.Size = Vector3.new(Config.PaperSize, Config.PaperThickness, Config.PaperSize)
		paper:SetAttribute("OwnerUserId", player.UserId)
		paper.Parent = workspace
		CollectionService:AddTag(paper, Config.PaperTag)

		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = Config.ClickDistance
		click.Parent = paper
		papersByUserId[player.UserId] = paper
	end

	local pos = root.Position + look * 5 + Vector3.new(0, 0.15, 0)
	paper.CFrame = CFrame.lookAt(pos, pos + look, Vector3.yAxis)
	return paper
end

OpenToolPaper.OnServerEvent:Connect(function(player)
	local now = os.clock()
	local last = lastRequestByUserId[player.UserId] or 0
	if now - last < 0.5 then return end
	lastRequestByUserId[player.UserId] = now

	local paper = makePaper(player)
	if paper then OpenToolPaper:FireClient(player, paper) end
end)

Players.PlayerRemoving:Connect(function(player)
	local paper = papersByUserId[player.UserId]
	if paper then paper:Destroy() end
	papersByUserId[player.UserId] = nil
	lastRequestByUserId[player.UserId] = nil
end)
