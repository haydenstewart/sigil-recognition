--!strict
-- Generic combat magic VFX/SFX. Server sends {id="magicCombat", element, shape, ...}; this module
-- chooses particles/sounds from the WFP raw asset catalog and layers simple Roblox geometry for readability.

local Debris       = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Registry     = require(script.Parent.Registry)
local AssetCatalog = require(script.Parent.Parent.VFX.AssetCatalog)

local ELEMENT = {
	fire = {
		color = Color3.fromRGB(255, 105, 35),
		secondary = Color3.fromRGB(255, 210, 80),
		terms = {"Fire", "Flare", "Impact", "Energy"},
	},
	water = {
		color = Color3.fromRGB(70, 170, 255),
		secondary = Color3.fromRGB(190, 245, 255),
		terms = {"Water", "Splash", "Circle", "Swirl"},
	},
	earth = {
		color = Color3.fromRGB(125, 95, 58),
		secondary = Color3.fromRGB(210, 190, 120),
		terms = {"Impact", "Smoke", "Dust", "Rock", "Ground"},
	},
	wind = {
		color = Color3.fromRGB(170, 240, 210),
		secondary = Color3.fromRGB(230, 255, 250),
		terms = {"Wind", "Swirl", "Slashes", "Smoke"},
	},
}

local SHAPE_TERMS = {
	burst = {"Impact", "Explosion", "Flare", "Circle"},
	beam = {"Beam", "Energy", "Lightning"},
	sustain = {"Circle", "Swirl", "Energy", "Flare"},
	projectile = {"Flare", "Energy", "Impact", "Form"},
	wall = {"Impact", "Smoke", "Grid", "Dust"},
	rain = {"Water", "Smoke", "Form", "Circle"},
	pull = {"Swirl", "Circle", "Energy"},
	slash = {"Slashes", "Beam", "Impact"},
}

local function mergeTerms(a: {string}, b: {string}?): {string}
	local out = {}
	for _, v in ipairs(a) do table.insert(out, v) end
	for _, v in ipairs(b or {}) do table.insert(out, v) end
	return out
end

local function elementProfile(element: string?)
	return ELEMENT[string.lower(tostring(element or ""))] or ELEMENT.fire
end

local function chooseTexture(terms: {string}, seed: number?): any
	return AssetCatalog.pick("FLIPBOOK", terms, seed)
		or AssetCatalog.pick("NOTFLIPBOOK", terms, seed)
		or AssetCatalog.pick(nil, terms, seed)
end

local function chooseSound(terms: {string}, seed: number?): any
	return AssetCatalog.pick("Sound", terms, seed)
		or AssetCatalog.pick("Sound", {"Magic", "Impact", "Beam"}, seed)
end

local function holder(name: string, origin: Vector3, life: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(origin)
	p.Parent = workspace
	Debris:AddItem(p, life)
	return p
end

local function attachEmitter(parent: Instance, textureRow: any, color: Color3, secondary: Color3, power: number, rate: number, speed: NumberRange, lifetime: NumberRange): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "MagicParticles"
	local uri = AssetCatalog.assetUri(textureRow)
	if uri then emitter.Texture = uri end
	emitter.Enabled = false
	emitter.Rate = rate
	emitter.LightEmission = 0.6
	emitter.LightInfluence = 0
	emitter.Color = ColorSequence.new(color, secondary)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.75, 0.18),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9 * power),
		NumberSequenceKeypoint.new(0.45, 2.4 * power),
		NumberSequenceKeypoint.new(1, 0.2 * power),
	})
	emitter.Speed = speed
	emitter.Lifetime = lifetime
	emitter.SpreadAngle = Vector2.new(180, 180)
	AssetCatalog.applyFlipbook(emitter, textureRow)
	emitter.Parent = parent
	return emitter
end

local function playSound(parent: Instance, terms: {string}, power: number, seed: number?)
	local row = chooseSound(terms, seed)
	local uri = AssetCatalog.assetUri(row)
	if not uri then return end
	local sound = Instance.new("Sound")
	sound.Name = "MagicCombatSFX"
	sound.SoundId = uri
	sound.Volume = math.clamp(0.45 + power * 0.35, 0.2, 1.4)
	sound.PlaybackSpeed = math.clamp(0.92 + power * 0.08, 0.75, 1.3)
	sound.RollOffMaxDistance = 80
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 5)
end

local function glowBall(origin: Vector3, color: Color3, radius: number, duration: number): Part
	local ball = holder("MagicGlow", origin, duration + 0.8)
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = color
	ball.Transparency = 0.2
	ball.Size = Vector3.new(0.25, 0.25, 0.25)
	TweenService:Create(ball, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = Vector3.new(radius, radius, radius),
	}):Play()
	task.delay(math.max(0.08, duration * 0.45), function()
		if ball.Parent then
			TweenService:Create(ball, TweenInfo.new(duration * 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
				Size = Vector3.new(radius * 1.35, radius * 1.35, radius * 1.35),
			}):Play()
		end
	end)
	return ball
end

local function shockRing(origin: Vector3, color: Color3, radius: number, duration: number)
	local ring = holder("MagicShockRing", origin, duration + 0.2)
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.05
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.08, 2.0, 2.0)
	ring.CFrame = CFrame.new(origin) * CFrame.Angles(0, 0, math.rad(90))
	TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.08, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
end

local function playBurst(args, profile, terms: {string})
	local origin = args.origin
	local power = args.power or 1
	local radius = args.radius or (10 * power)
	local h = holder("MagicBurst", origin, 3)
	local tex = chooseTexture(terms, 1)
	local emitter = attachEmitter(h, tex, profile.color, profile.secondary, power, 160, NumberRange.new(8 * power, 18 * power), NumberRange.new(0.55, 1.15))
	emitter:Emit(math.floor(70 * power))
	playSound(h, terms, power, 2)
	glowBall(origin, profile.color, radius, 0.7)
	shockRing(origin, profile.secondary, radius * 0.9, 0.65)
end

local function playBeam(args, profile, terms: {string})
	local origin = args.origin
	local dir = args.direction
	if not dir or dir.Magnitude < 1e-4 then dir = Vector3.new(1, 0, 0) end
	dir = dir.Unit
	local power = args.power or 1
	local length = args.length or (24 * power)
	local width = args.width or (1.6 * power)
	local beam = holder("MagicBeam", origin + dir * length * 0.5, 2.2)
	beam.Material = Enum.Material.Neon
	beam.Color = profile.color
	beam.Transparency = 0.1
	beam.Size = Vector3.new(width, width, length)
	beam.CFrame = CFrame.lookAt(origin + dir * length * 0.5, origin + dir * length)
	local tex = chooseTexture(terms, 3)
	local emitter = attachEmitter(beam, tex, profile.color, profile.secondary, power, 120, NumberRange.new(3 * power, 8 * power), NumberRange.new(0.4, 0.9))
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter:Emit(math.floor(55 * power))
	playSound(beam, terms, power, 4)
	TweenService:Create(beam, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(width * 0.25, width * 0.25, length),
	}):Play()
	shockRing(origin + dir * length, profile.secondary, 5 * power, 0.5)
end

local function playSustain(args, profile, terms: {string})
	local origin = args.origin
	local power = args.power or 1
	local radius = args.radius or (6 * power)
	local duration = args.duration or 4
	local orb = glowBall(origin, profile.color, radius * 0.8, duration)
	local tex = chooseTexture(terms, 5)
	local emitter = attachEmitter(orb, tex, profile.color, profile.secondary, power, 80, NumberRange.new(1, 4 * power), NumberRange.new(0.9, 1.7))
	emitter.Enabled = true
	playSound(orb, terms, power, 6)
	task.delay(duration, function() if emitter.Parent then emitter.Enabled = false end end)
end

local function playProjectile(args, profile, terms: {string})
	local origin = args.origin
	local dir = args.direction
	if not dir or dir.Magnitude < 1e-4 then dir = Vector3.new(1, 0, 0) end
	dir = dir.Unit
	local power = args.power or 1
	local length = args.length or (28 * power)
	local travel = math.clamp(length / 72, 0.28, 0.65)
	local proj = glowBall(origin, profile.color, 1.6 * power, travel + 0.45)
	local tex = chooseTexture(terms, 7)
	local emitter = attachEmitter(proj, tex, profile.color, profile.secondary, power, 120, NumberRange.new(0.5, 2.0), NumberRange.new(0.25, 0.55))
	emitter.Enabled = true
	playSound(proj, terms, power, 8)
	TweenService:Create(proj, TweenInfo.new(travel, Enum.EasingStyle.Linear), { CFrame = CFrame.new(origin + dir * length) }):Play()
	task.delay(travel, function()
		if emitter.Parent then emitter.Enabled = false end
		playBurst({ origin = origin + dir * length, power = power * 0.75, radius = 5 * power }, profile, terms)
	end)
end

local function playWall(args, profile, terms: {string})
	local origin = args.origin
	local dir = args.direction
	if not dir or dir.Magnitude < 1e-4 then dir = Vector3.new(0, 0, -1) end
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 1e-4 then dir = Vector3.new(0, 0, -1) end
	dir = dir.Unit
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local power = args.power or 1
	local count = 7
	for i = 1, count do
		local offset = (i - (count + 1) / 2) * 2.2 * power
		local block = holder("MagicWallBlock", origin + right * offset + Vector3.new(0, 1.4, 0), 5)
		block.Material = Enum.Material.Neon
		block.Color = profile.color
		block.Transparency = 0.15
		block.Size = Vector3.new(1.8 * power, 0.2, 1.0 * power)
		block.CFrame = CFrame.lookAt(block.Position, block.Position + dir)
		TweenService:Create(block, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = Vector3.new(1.8 * power, 3.2 * power, 1.0 * power),
			Position = block.Position + Vector3.new(0, 1.2 * power, 0),
		}):Play()
		TweenService:Create(block, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 3.4), {
			Transparency = 1,
		}):Play()
	end
	local h = holder("MagicWallFX", origin, 3)
	attachEmitter(h, chooseTexture(terms, 9), profile.color, profile.secondary, power, 120, NumberRange.new(2, 7), NumberRange.new(0.8, 1.4)):Emit(math.floor(45 * power))
	playSound(h, terms, power, 10)
end

local function playRain(args, profile, terms: {string})
	local origin = args.origin
	local power = args.power or 1
	local radius = args.radius or (10 * power)
	local duration = args.duration or 2.2
	local cloud = holder("MagicRainCloud", origin + Vector3.new(0, 12 * power, 0), duration + 1)
	attachEmitter(cloud, chooseTexture(terms, 11), profile.color, profile.secondary, power, 180, NumberRange.new(18 * power, 26 * power), NumberRange.new(0.6, 1.0)).Enabled = true
	playSound(cloud, terms, power, 12)
	for i = 1, 18 do
		local angle = (i / 18) * math.pi * 2
		local dist = radius * (0.25 + (i % 5) / 6)
		local streak = holder("MagicRainStreak", cloud.Position + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist), duration + 0.5)
		streak.Material = Enum.Material.Neon
		streak.Color = profile.secondary
		streak.Transparency = 0.1
		streak.Size = Vector3.new(0.18 * power, 4.0 * power, 0.18 * power)
		TweenService:Create(streak, TweenInfo.new(0.45 + (i % 4) * 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = Vector3.new(streak.Position.X, origin.Y + 0.3, streak.Position.Z),
			Transparency = 1,
		}):Play()
	end
	task.delay(duration, function()
		for _, child in ipairs(cloud:GetChildren()) do
			if child:IsA("ParticleEmitter") then child.Enabled = false end
		end
	end)
end

local function playPull(args, profile, terms: {string})
	local origin = args.origin
	local power = args.power or 1
	local radius = args.radius or (12 * power)
	local h = holder("MagicPullFX", origin, 2.5)
	attachEmitter(h, chooseTexture(terms, 13), profile.color, profile.secondary, power, 140, NumberRange.new(4, 12), NumberRange.new(0.8, 1.5)):Emit(math.floor(60 * power))
	playSound(h, terms, power, 14)
	for i = 1, 14 do
		local angle = (i / 14) * math.pi * 2
		local start = origin + Vector3.new(math.cos(angle) * radius, 1.0 + (i % 3), math.sin(angle) * radius)
		local shard = holder("MagicPullShard", start, 1.2)
		shard.Material = Enum.Material.Neon
		shard.Color = profile.secondary
		shard.Size = Vector3.new(0.25, 0.25, 2.2 * power)
		shard.CFrame = CFrame.lookAt(start, origin)
		TweenService:Create(shard, TweenInfo.new(0.8, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
			Position = origin + Vector3.new(0, 1.4, 0),
			Transparency = 1,
		}):Play()
	end
	shockRing(origin, profile.color, radius, 0.75)
end

local function playSlash(args, profile, terms: {string})
	local origin = args.origin
	local dir = args.direction
	if not dir or dir.Magnitude < 1e-4 then dir = Vector3.new(1, 0, 0) end
	dir = dir.Unit
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local power = args.power or 1
	local length = args.length or (16 * power)
	local h = holder("MagicSlashFX", origin, 2)
	attachEmitter(h, chooseTexture(terms, 15), profile.color, profile.secondary, power, 90, NumberRange.new(6, 14), NumberRange.new(0.35, 0.75)):Emit(math.floor(40 * power))
	playSound(h, terms, power, 16)
	for i = -1, 1 do
		local slash = holder("MagicSlash", origin + right * i * 0.9 + dir * length * 0.35 + Vector3.new(0, 1.2, 0), 1.2)
		slash.Material = Enum.Material.Neon
		slash.Color = profile.secondary
		slash.Transparency = 0.05
		slash.Size = Vector3.new(0.3 * power, 0.3 * power, length * (1 - math.abs(i) * 0.18))
		slash.CFrame = CFrame.lookAt(slash.Position, slash.Position + dir) * CFrame.Angles(0, 0, math.rad(22 * i))
		TweenService:Create(slash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = slash.Position + dir * 4 * power,
			Transparency = 1,
		}):Play()
	end
end

local SHAPE_PLAYERS = {
	burst = playBurst,
	beam = playBeam,
	sustain = playSustain,
	projectile = playProjectile,
	wall = playWall,
	rain = playRain,
	pull = playPull,
	slash = playSlash,
}

local function play(args)
	local origin = args.origin
	if not origin then return end
	local shape = tostring(args.shape or "burst")
	local profile = elementProfile(args.element)
	local terms = mergeTerms(profile.terms, SHAPE_TERMS[shape])
	local fn = SHAPE_PLAYERS[shape] or playBurst
	fn(args, profile, terms)
end

Registry.register("magicCombat", play)

return true
