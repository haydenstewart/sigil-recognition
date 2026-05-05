--!strict
-- Shared gameplay side for elemental sigil variants. Sigil modules describe an element + spell shape;
-- this module handles sign aiming, damage, simple server barriers, and client VFX dispatch.

local Players = game:GetService("Players")
local Debris  = game:GetService("Debris")
local RS      = game:GetService("ReplicatedStorage")

local ElementalCombat = {}

export type SpellSpec = {
	id: string,
	displayName: string,
	element: string,
	shape: string,
	columnShape: string?,
	radius: number?,
	length: number?,
	damage: number?,
	tickDamage: number?,
	duration: number?,
	width: number?,
}

local ELEMENT_COLOR = {
	fire = Color3.fromRGB(255, 105, 35),
	water = Color3.fromRGB(70, 170, 255),
	earth = Color3.fromRGB(125, 95, 58),
	wind = Color3.fromRGB(170, 240, 210),
}

local ELEMENT_SECONDARY = {
	fire = Color3.fromRGB(255, 210, 80),
	water = Color3.fromRGB(190, 245, 255),
	earth = Color3.fromRGB(210, 190, 120),
	wind = Color3.fromRGB(230, 255, 250),
}

local function rootOf(char: Model?): BasePart?
	if not char then return nil end
	return (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: BasePart?
end

local function casterRoot(ctx: {[string]: any}): BasePart?
	local player = ctx.player
	if typeof(player) == "Instance" and player:IsA("Player") then
		return rootOf(player.Character)
	end
	return nil
end

local function damageCharacter(char: Model?, amount: number, caster: Player?)
	if caster and char == caster.Character then return end
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then hum:TakeDamage(amount) end
end

local function applyArea(origin: Vector3, radius: number, damage: number, caster: Player?)
	for _, plr in ipairs(Players:GetPlayers()) do
		local root = rootOf(plr.Character)
		if root and (root.Position - origin).Magnitude <= radius then
			damageCharacter(plr.Character, damage, caster)
		end
	end
end

local function applyLine(origin: Vector3, dir: Vector3, length: number, radius: number, damage: number, caster: Player?)
	if dir.Magnitude < 1e-4 then return end
	dir = dir.Unit
	for _, plr in ipairs(Players:GetPlayers()) do
		local root = rootOf(plr.Character)
		if root then
			local delta = root.Position - origin
			local along = delta:Dot(dir)
			if along >= -2 and along <= length then
				local radial = (delta - dir * along).Magnitude
				if radial <= radius then damageCharacter(plr.Character, damage, caster) end
			end
		end
	end
end

local function applyAreaDot(origin: Vector3, radius: number, duration: number, tickDamage: number, caster: Player?)
	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			task.wait(0.5)
			elapsed += 0.5
			applyArea(origin, radius, tickDamage, caster)
		end
	end)
end

local function gridDirToWorld(dir: Vector2, paperCF: CFrame): Vector3
	local localDir = Vector3.new(dir.X, 0, dir.Y)
	return paperCF:VectorToWorldSpace(localDir)
end

local function fallbackDirection(ctx: {[string]: any}, paperCF: CFrame): Vector3
	local root = casterRoot(ctx)
	if root then
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if look.Magnitude > 1e-4 then return look.Unit end
	end
	local look = Vector3.new(paperCF.LookVector.X, 0, paperCF.LookVector.Z)
	if look.Magnitude > 1e-4 then return look.Unit end
	return Vector3.new(1, 0, 0)
end

local function signDirection(ctx: {[string]: any}, paperCF: CFrame): (Vector3, boolean, boolean)
	local signs = ctx.signs or {}
	local hasLevitation = false
	local sumX, sumY, total = 0, 0, 0
	for _, s in ipairs(signs) do
		if s.id == "levitation" then
			hasLevitation = true
		elseif s.id == "column" and s.direction then
			local weight = math.max(0.5, s.score or 1)
			sumX += s.direction.X * weight
			sumY += s.direction.Y * weight
			total += weight
		end
	end
	if total > 0 then
		local mag = math.sqrt(sumX * sumX + sumY * sumY)
		if mag >= total * 0.35 then
			local world = gridDirToWorld(Vector2.new(sumX / mag, sumY / mag), paperCF)
			world = Vector3.new(world.X, 0, world.Z)
			if world.Magnitude > 1e-4 then return world.Unit, true, hasLevitation end
		end
	end
	local rawDir = ctx.direction
	if typeof(rawDir) == "Vector2" then
		local world = gridDirToWorld(rawDir, paperCF)
		world = Vector3.new(world.X, 0, world.Z)
		if world.Magnitude > 1e-4 then return world.Unit, false, hasLevitation end
	end
	return fallbackDirection(ctx, paperCF), false, hasLevitation
end

local function clientEffect(args: {[string]: any})
	local remotes = RS:FindFirstChild("SpellRemotes")
	local playEffect = remotes and remotes:FindFirstChild("PlayEffect")
	if playEffect and playEffect:IsA("RemoteEvent") then
		playEffect:FireAllClients(args)
	end
end

local function raiseServerWall(origin: Vector3, dir: Vector3, width: number, power: number, color: Color3)
	if dir.Magnitude < 1e-4 then return end
	dir = dir.Unit
	local right = Vector3.new(-dir.Z, 0, dir.X)
	for i = -3, 3 do
		local p = Instance.new("Part")
		p.Name = "MagicBarrier"
		p.Anchored = true
		p.CanCollide = true
		p.CanQuery = false
		p.CanTouch = false
		p.Material = Enum.Material.Rock
		p.Color = color
		p.Transparency = 0.35
		p.Size = Vector3.new(width, 4 * power, 1.0 * power)
		p.CFrame = CFrame.lookAt(origin + right * i * width + Vector3.new(0, 2 * power, 0), origin + right * i * width + dir)
		p.Parent = workspace
		Debris:AddItem(p, 5)
	end
end

function ElementalCombat.cast(spec: SpellSpec, ctx: {[string]: any})
	local accuracy = tonumber(ctx.accuracy) or 0
	local power = math.clamp(accuracy, 0.55, 1.25)
	local paperCF = ctx.paperCFrame :: CFrame
	local caster = ctx.player
	if typeof(caster) ~= "Instance" or not caster:IsA("Player") then caster = nil end

	local dir, hasColumn, hasLevitation = signDirection(ctx, paperCF)
	local shape = spec.shape
	if hasLevitation then
		shape = "sustain"
	elseif hasColumn and spec.columnShape then
		shape = spec.columnShape
	end

	local origin = paperCF.Position + Vector3.new(0, 1.1, 0)
	local element = string.lower(spec.element)
	local color = ELEMENT_COLOR[element] or ELEMENT_COLOR.fire
	local secondary = ELEMENT_SECONDARY[element] or ELEMENT_SECONDARY.fire
	local radius = (spec.radius or 9) * power
	local length = (spec.length or 22) * power
	local damage = (spec.damage or 24) * power
	local tickDamage = (spec.tickDamage or 4) * power
	local duration = spec.duration or 3.5
	local width = (spec.width or 2.5) * power

	print(string.format("[SPELL CAST] %s element=%s shape=%s acc=%.2f signs=%d", spec.displayName, element, shape, accuracy, #(ctx.signs or {})))

	if shape == "beam" then
		applyLine(origin, dir, length, width + 1.2, damage, caster :: Player?)
	elseif shape == "projectile" then
		applyLine(origin, dir, length, width, damage * 0.8, caster :: Player?)
		applyArea(origin + dir * length, radius * 0.55, damage * 0.65, caster :: Player?)
	elseif shape == "slash" then
		applyLine(origin, dir, length * 0.75, width + 2.0, damage * 0.9, caster :: Player?)
	elseif shape == "wall" then
		raiseServerWall(origin + dir * 4, dir, 1.8 * power, power, color)
		applyLine(origin, dir, length * 0.35, width + 3.0, damage * 0.55, caster :: Player?)
	elseif shape == "rain" then
		applyAreaDot(origin, radius, duration, tickDamage, caster :: Player?)
	elseif shape == "pull" then
		applyArea(origin, radius, damage * 0.7, caster :: Player?)
		applyAreaDot(origin, radius * 0.7, 1.5, tickDamage * 0.6, caster :: Player?)
	elseif shape == "sustain" then
		local sustainOrigin = origin + Vector3.new(0, 2.8, 0)
		applyAreaDot(sustainOrigin, radius + 2, duration, tickDamage, caster :: Player?)
		origin = sustainOrigin
	else
		applyArea(origin, radius, damage, caster :: Player?)
	end

	clientEffect({
		id = "magicCombat",
		spellId = spec.id,
		element = element,
		shape = shape,
		origin = origin,
		direction = dir,
		power = power,
		radius = radius,
		length = length,
		width = width,
		duration = duration,
		color = color,
		secondaryColor = secondary,
	})
end

return ElementalCombat
