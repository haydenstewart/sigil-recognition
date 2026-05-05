--!strict
-- Fire sigil: triangle pointing up + central vertical line.
-- Registers itself into the Sigils.Registry at require time.

local Players      = game:GetService("Players")
local Debris       = game:GetService("Debris")
local RS           = game:GetService("ReplicatedStorage")

local Config       = require(script.Parent.Parent.Config)
local GridBuffer   = require(script.Parent.Parent.Canvas.GridBuffer)
local Bresenham    = require(script.Parent.Parent.Util.Bresenham)
local Registry     = require(script.Parent.Registry)
local RingDetector = require(script.Parent.Parent.Recognition.RingDetector)
local Normalizer   = require(script.Parent.Parent.Recognition.Normalizer)

-- Draws the canonical fire glyph into `buf`. Coordinates are grid cells (y grows down).
-- The triangle is inscribed in a circle of radius R centered at the buffer center.
-- Thickness matches Config.StrokeRadius so the canonical form looks like a hand-drawn inking.
-- R is sized to leave comfortable room for up to 4 Column signs at the cardinal points inside the ring.
local function buildVisual(buf: GridBuffer.GridBuffer)
	local N = buf.size
	local cx, cy = N / 2, N / 2
	local R = N * 0.26

	local apex = { x = cx,               y = cy - R }
	local bl   = { x = cx - R * 0.866,   y = cy + R * 0.5 }
	local br   = { x = cx + R * 0.866,   y = cy + R * 0.5 }

	local thickness = Config.StrokeRadius
	local function stroke(p, q)
		Bresenham.stroke(p.x, p.y, q.x, q.y, thickness, function(x, y) buf:set(x, y, 1) end)
	end
	stroke(apex, bl)
	stroke(bl,   br)
	stroke(br,   apex)

	-- Central vertical line: starts below the baseline, ends near the triangle mid.
	local vbot = { x = cx, y = cy + R * 0.8 }
	local vtop = { x = cx, y = cy - R * 0.1 }
	stroke(vbot, vtop)
end



-- Mirror Canvas:gridDirToWorld: grid +X -> local +X, grid +Y -> local +Z (visual down).
local function gridDirToWorld(dir: Vector2, paperCF: CFrame): Vector3
	local localDir = Vector3.new(dir.X, 0, dir.Y)
	return paperCF:VectorToWorldSpace(localDir)
end

-- Decide spell form from the signs around the sigil. Sign types matter (not just T arrangements):
--   • any LEVITATION (arrow) sign present        -> sustained spell (hovering orb).
--   • COLUMN (T) signs, net direction aligned     -> directed beam in that direction.
--   • COLUMN signs radially balanced (>=2 T's, no net bias) -> straight-up beam (stable column).
--   • no signs at all                             -> unstable AoE fireball.
-- The sigil channels raw elemental energy; signs are what shape it into a useful form. Without
-- any shaping sign the fire just explodes outward.
local GRID_CENTER = Config.GridSize / 2

local function analyzeSigns(signs: {any}): { mode: string, direction: Vector2? }
	local cols = {}
	local levitations = {}
	if signs then
		for _, s in ipairs(signs) do
			if s.id == "column" and s.direction and s.center then
				table.insert(cols, s)
			elseif s.id == "levitation" then
				table.insert(levitations, s)
			end
		end
	end

	if #levitations > 0 then
		return { mode = "sustain" }
	end

	if #cols == 0 then return { mode = "aoe" } end

	-- Weighted net direction of the column signs.
	local sumX, sumY, totalWeight = 0, 0, 0
	for _, s in ipairs(cols) do
		local w = math.max(0.5, s.score or 1)
		sumX = sumX + s.direction.X * w
		sumY = sumY + s.direction.Y * w
		totalWeight = totalWeight + w
	end
	local mag = math.sqrt(sumX * sumX + sumY * sumY)

	if totalWeight > 0 and mag >= 0.5 * totalWeight then
		return { mode = "directed", direction = Vector2.new(sumX / mag, sumY / mag) }
	end

	-- Low net magnitude with >=2 T's: radially symmetric column pattern = balanced column up.
	if #cols >= 2 then
		return { mode = "up" }
	end
	return { mode = "aoe" }
end

-- ======= server-side damage helpers =======

local function rootOf(char: Model?): BasePart?
	if not char then return nil end
	return (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: BasePart?
end

local function applyBurn(char: Model, totalTicks: number, tickDamage: number)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local torso = rootOf(char)
	if torso and not torso:FindFirstChild("SpellBurn") then
		local template = RS:FindFirstChild("SpellAssets") and RS.SpellAssets:FindFirstChild("Fire2")
		if template then
			local burn = template:Clone()
			burn.Name = "SpellBurn"
			burn.Enabled = true
			burn.Rate = 25
			burn.Parent = torso
			Debris:AddItem(burn, totalTicks + 0.5)
		end
	end
	task.spawn(function()
		for _ = 1, totalTicks do
			task.wait(1)
			if hum.Health <= 0 then return end
			hum:TakeDamage(tickDamage)
		end
	end)
end

local function hurt(char: Model, initial: number, burnTicks: number, burnDamage: number)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	hum:TakeDamage(initial)
	applyBurn(char, burnTicks, burnDamage)
end

local function applyAoE(origin: Vector3, radius: number, initial: number)
	for _, plr in ipairs(Players:GetPlayers()) do
		local root = rootOf(plr.Character)
		if root and (root.Position - origin).Magnitude <= radius then
			hurt(plr.Character :: Model, initial, 3, 5)
		end
	end
end

local function applyBeam(origin: Vector3, dir: Vector3, length: number, radius: number, initial: number)
	for _, plr in ipairs(Players:GetPlayers()) do
		local root = rootOf(plr.Character)
		if root then
			local delta = root.Position - origin
			local along = delta:Dot(dir)
			if along >= -2 and along <= length then
				local radial = (delta - dir * along).Magnitude
				if radial <= radius then
					hurt(plr.Character :: Model, initial, 3, 5)
				end
			end
		end
	end
end

-- ======= cast =======

local function applySustainedDoT(origin: Vector3, radius: number, duration: number, tickDamage: number)
	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			task.wait(0.5)
			elapsed = elapsed + 0.5
			for _, plr in ipairs(Players:GetPlayers()) do
				local root = rootOf(plr.Character)
				if root and (root.Position - origin).Magnitude <= radius then
					local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 then hum:TakeDamage(tickDamage) end
				end
			end
		end
	end)
end

local function onCast(ctx: {[string]: any})
	local accuracy = ctx.accuracy or 0
	local paperCF = ctx.paperCFrame :: CFrame
	local signs = ctx.signs or {}
	local analysis = analyzeSigns(signs)
	local power = math.clamp(accuracy, 0.5, 1.2)

	print(string.format("[Fire.onCast] mode=%s signs=%d acc=%.2f", analysis.mode, #signs, accuracy))
	for i, s in ipairs(signs) do
		local dir = s.direction and string.format("(%.2f, %.2f)", s.direction.X, s.direction.Y) or "nil"
		local center = s.center and string.format("(%.0f, %.0f)", s.center.X, s.center.Y) or "?"
		print(string.format("  sign #%d: id=%s score=%.2f dir=%s center=%s",
			i, tostring(s.id), s.score or 0, dir, center))
	end

	local origin = paperCF.Position + Vector3.new(0, 1.0, 0)
	local playEffect = RS:FindFirstChild("SpellRemotes") and RS.SpellRemotes:FindFirstChild("PlayEffect")

	if analysis.mode == "sustain" then
		-- SUSTAINED fire orb: hovers above the paper for a duration, damaging anyone too close.
		local radius = 6 * power
		local duration = 4.0
		local orbPos = paperCF.Position + Vector3.new(0, 3.5, 0)
		applySustainedDoT(orbPos, radius + 2, duration, 6 * power)
		print(string.format("[SPELL CAST] Fire SUSTAIN  acc=%.2f  radius=%.1f  %.1fs", accuracy, radius, duration))

		if playEffect then
			playEffect:FireAllClients({ id = "sustain", origin = orbPos, power = power, radius = radius, duration = duration })
			playEffect:FireAllClients({ id = "shockwave", origin = origin, power = power * 0.4 })
		end

	elseif analysis.mode == "directed" or analysis.mode == "up" then
		local worldDir
		if analysis.mode == "up" then
			-- Default with no column signs: shoot straight up (away from the ground).
			worldDir = Vector3.new(0, 1, 0)
		else
			worldDir = gridDirToWorld(analysis.direction :: Vector2, paperCF)
			worldDir = Vector3.new(worldDir.X, 0, worldDir.Z)
			if worldDir.Magnitude < 1e-4 then worldDir = Vector3.new(1, 0, 0) end
			worldDir = worldDir.Unit
		end
		local length = 22 * power

		applyBeam(origin, worldDir, length, 3.5, 30 * power)
		print(string.format("[SPELL CAST] Fire BEAM (%s)  acc=%.2f  dir=(%.2f,%.2f,%.2f)",
			analysis.mode, accuracy, worldDir.X, worldDir.Y, worldDir.Z))

		if playEffect then
			playEffect:FireAllClients({ id = "beam", origin = origin, direction = worldDir, power = power, length = length })
			playEffect:FireAllClients({ id = "shockwave", origin = origin + worldDir * length, power = power * 0.6 })
			playEffect:FireAllClients({ id = "shockwave", origin = origin, power = power * 0.4 })
		end

	else
		-- UNBALANCED / AOE fallback.
		local radius = 12 * power
		applyAoE(origin, radius, 35 * power)
		print(string.format("[SPELL CAST] Fireball (unbalanced)  acc=%.2f  radius=%.1f", accuracy, radius))

		if playEffect then
			playEffect:FireAllClients({ id = "explosion", origin = origin, power = power, radius = radius })
			playEffect:FireAllClients({ id = "shockwave", origin = origin, power = power })
		end
	end
end

-- Fire requires the central vertical line. Check operates on the RAW (pre-normalized) sigil mask
-- so it's unaffected by bbox scaling. We scan for the longest contiguous vertical run, but ONLY
-- in columns near the GRID CENTER -- so a T-stem (which has a long vertical run of its own but
-- is positioned off-center as a peripheral sign) can't satisfy this check. A fire sigil is
-- drawn centered inside the ring, so its line naturally lands in these center columns.
local FIRE_LINE_MIN_RUN = 10
local FIRE_LINE_CENTER_HALFWIDTH = 4

-- Template: render the canonical glyph + ring on a full-size canvas, extract the
-- inside-ink (sigilMask) and normalise. Caster.evaluate combines all non-sign
-- components inside the ring into one mask before matching, so this template's
-- shape is exactly what the matcher receives at runtime.
local function buildTemplate(): GridBuffer.GridBuffer
	local N = Config.GridSize
	local canvas = GridBuffer.new(N)
	local cx, cy = N / 2, N / 2
	Bresenham.thickCircle(cx, cy, N * 0.45, Config.StrokeRadius, function(x, y) canvas:set(x, y, 1) end)
	buildVisual(canvas)
	local ring = RingDetector.detect(canvas)
	assert(ring.found and ring.sigilMask, "fire template: ring not detected in canonical rendering")
	local norm = Normalizer.normalize(ring.sigilMask :: GridBuffer.GridBuffer, Config.TemplateResolution)
	assert(norm, "fire template: normalization failed")
	return norm :: GridBuffer.GridBuffer
end

local FULL_TEMPLATE = buildTemplate()

local function verify(_normalized: GridBuffer.GridBuffer, raw: GridBuffer.GridBuffer): boolean
	local minX, minY, maxX, maxY = raw:bbox()
	if not minX then return false end
	local gridCx = math.floor(Config.GridSize / 2)
	local lo = math.max(1, gridCx - FIRE_LINE_CENTER_HALFWIDTH)
	local hi = math.min(Config.GridSize, gridCx + FIRE_LINE_CENTER_HALFWIDTH)

	-- Scan every column near grid center for the longest contiguous run, tracking WHERE the run
	-- starts. A real fire line begins somewhere in the middle of the sigil's bbox and extends
	-- downward. A sign stem merged at the top (e.g., N sign touching the apex) starts at the
	-- bbox top; a sign stem merged at the bottom (S sign touching the base) starts well below
	-- the middle. We reject runs whose starting y is outside the bbox's middle band.
	local bestRun, bestStartY = 0, 0
	for x = lo, hi do
		local run = 0
		local runStart = 0
		for y = minY :: number, maxY :: number do
			if raw:get(x, y) ~= 0 then
				if run == 0 then runStart = y end
				run = run + 1
				if run > bestRun then
					bestRun = run
					bestStartY = runStart
				end
			else
				run = 0
			end
		end
	end
	if bestRun < FIRE_LINE_MIN_RUN then return false end

	local height = (maxY :: number) - (minY :: number) + 1
	local bandLo = (minY :: number) + math.floor(height * 0.30)
	local bandHi = (minY :: number) + math.floor(height * 0.70)
	return bestStartY >= bandLo and bestStartY <= bandHi
end

Registry.register({
	id          = "fire",
	template    = FULL_TEMPLATE,
	buildVisual = buildVisual,
	onCast      = onCast,
	verify      = verify,
})


return true
