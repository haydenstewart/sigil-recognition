-- SpellClient: drives paper interaction, drawing input, local recognition, and casts to server.
-- Canvas rendering is client-local (drawing doesn't replicate). Cast requests do.

local Players               = game:GetService("Players")
local UserInputService      = game:GetService("UserInputService")
local ContextActionService  = game:GetService("ContextActionService")
local TweenService          = game:GetService("TweenService")
local CollectionService     = game:GetService("CollectionService")
local RS                    = game:GetService("ReplicatedStorage")

local SpellSystem = RS:WaitForChild("SpellSystem")
local Config         = require(SpellSystem.Config)
local Canvas         = require(SpellSystem.Canvas.Canvas)
local Registry       = require(SpellSystem.Sigils.Registry)
local SignRegistry   = require(SpellSystem.Signs.Registry)
local Caster         = require(SpellSystem.Spells.Caster)
local GridBuffer     = require(SpellSystem.Canvas.GridBuffer)
local Bresenham      = require(SpellSystem.Util.Bresenham)
local EffectRegistry = require(SpellSystem.ClientEffects.Registry)

Registry.loadAll()
SignRegistry.loadAll()
EffectRegistry.loadAll()

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotes = RS:WaitForChild("SpellRemotes")
local CastRemote    = remotes:WaitForChild("Cast")
local PlayEffect    = remotes:WaitForChild("PlayEffect")
local OpenToolPaper = remotes:WaitForChild("OpenToolPaper")

-- VFX dispatch: server fires one FireAllClients per effect (may be several per cast).
PlayEffect.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	local id = data.id
	if type(id) ~= "string" then return end
	EffectRegistry.play(id, data)
end)

-- ========= Canvas setup per paper =========

local canvases: {[BasePart]: any} = {}

-- Render the canonical version of any registered sigil onto a reference paper:
-- outer ring + the sigil's buildVisual at its canonical orientation.
local function paintCanonicalGlyph(canvas, sigilId: string)
	local N = Config.GridSize
	local buf = GridBuffer.new(N)
	local cx, cy = N / 2, N / 2
	local radius = N * 0.45
	Bresenham.thickCircle(cx, cy, radius, 1, function(x, y) buf:set(x, y, 1) end)
	local entry = Registry.get(sigilId)
	if entry then
		entry.buildVisual(buf)
	else
		warn("[SpellClient] paintCanonicalGlyph: unknown sigil id " .. sigilId)
	end
	canvas:paintFromBuffer(buf)
end

-- Directional example: a fire sigil with three Column (T) signs arranged around it,
-- all in canonical orientation (bar on top, stem down). All three point "up" so the net
-- directional bias is up; firing this glyph produces a directed beam instead of an AoE.
local function paintDirectionalGlyph(canvas)
	local N = Config.GridSize
	local buf = GridBuffer.new(N)
	local cx, cy = N / 2, N / 2
	local radius = N * 0.48
	Bresenham.thickCircle(cx, cy, radius, 1, function(x, y) buf:set(x, y, 1) end)
	local fire = Registry.get("fire")
	if fire then fire.buildVisual(buf) end

	local function drawSmallT(tx: number, ty: number)
		local half = 3
		local stemLen = 6
		local barY = ty - stemLen * 0.4
		local botY = barY + stemLen
		local function stroke(x0, y0, x1, y1)
			Bresenham.stroke(x0, y0, x1, y1, Config.StrokeRadius, function(x, y) buf:set(x, y, 1) end)
		end
		stroke(tx - half, barY, tx + half, barY)
		stroke(tx, barY, tx, botY)
	end
	-- Three Ts placed in the open interior around the fire sigil, each at canonical orientation
	-- (bar up, stem down). All three "point up", so the net direction is up -> fire beam up.
	-- Positions chosen to stay clear of both the fire triangle edges and the ring's thick band.
	drawSmallT(13, 32)     -- left of the triangle
	drawSmallT(51, 32)     -- right of the triangle
	drawSmallT(32, 56)     -- below the triangle base

	canvas:paintFromBuffer(buf)
end

-- Sustained example: fire sigil with four Levitation (arrow) signs at the cardinal points,
-- each pointing OUTWARD -- matching the WHA levitation seal layout. Any levitation sign
-- present causes the spell to sustain instead of becoming a column.
local function paintSustainGlyph(canvas)
	local N = Config.GridSize
	local buf = GridBuffer.new(N)
	local cx, cy = N / 2, N / 2
	local radius = N * 0.48
	Bresenham.thickCircle(cx, cy, radius, 1, function(x, y) buf:set(x, y, 1) end)
	local fire = Registry.get("fire")
	if fire then fire.buildVisual(buf) end

	-- Small arrow (stem + chevron tip), rotated around (tx, ty). Sized to fit comfortably inside
	-- the ring without merging into the fire sigil's triangle edges or the ring's thick pole band.
	local function drawRotatedArrow(tx: number, ty: number, angle: number)
		local stemLen  = 5
		local headWide = 2
		local headLen  = 2
		local tipY = ty - stemLen * 0.5
		local botY = tipY + stemLen
		local cosA, sinA = math.cos(angle), math.sin(angle)
		local function rot(px: number, py: number): (number, number)
			local dx, dy = px - tx, py - ty
			return tx + cosA * dx - sinA * dy, ty + sinA * dx + cosA * dy
		end
		local function stroke(x0, y0, x1, y1)
			Bresenham.stroke(x0, y0, x1, y1, Config.StrokeRadius, function(x, y) buf:set(x, y, 1) end)
		end
		local tipx, tipy = rot(tx, tipY)
		local botx, boty = rot(tx, botY)
		local hlx, hly = rot(tx - headWide, tipY + headLen)
		local hrx, hry = rot(tx + headWide, tipY + headLen)
		stroke(tipx, tipy, botx, boty)   -- stem
		stroke(tipx, tipy, hlx, hly)     -- chevron left
		stroke(tipx, tipy, hrx, hry)     -- chevron right
	end

	-- Three levitation arrows in the same safe positions used by the directional paper,
	-- each pointing OUTWARD from the sigil. Any levitation sign triggers sustain regardless
	-- of arrangement, so three arrows is sufficient and keeps the layout clean.
	drawRotatedArrow(13, 32, -math.pi / 2)   -- W: arrow points left (outward)
	drawRotatedArrow(51, 32,  math.pi / 2)   -- E: arrow points right (outward)
	drawRotatedArrow(32, 56,  math.pi)       -- S: arrow points down (outward)

	canvas:paintFromBuffer(buf)
end

-- Balanced-column example: fire sigil with four Column Ts around it, each pointing OUTWARD
-- (bars on the outer rim, stems converging toward the sigil). Mathematically the net direction
-- cancels to zero, so the analyzer falls through to the balanced "up" branch = straight-up beam.
local function paintBalancedGlyph(canvas)
	local N = Config.GridSize
	local buf = GridBuffer.new(N)
	local cx, cy = N / 2, N / 2
	local radius = N * 0.48
	Bresenham.thickCircle(cx, cy, radius, 1, function(x, y) buf:set(x, y, 1) end)
	local fire = Registry.get("fire")
	if fire then fire.buildVisual(buf) end

	local function drawRotatedT(tx: number, ty: number, angle: number)
		local half = 3
		local stemLen = 5
		local barY = ty - stemLen * 0.4
		local botY = barY + stemLen
		local cosA, sinA = math.cos(angle), math.sin(angle)
		local function rot(px, py)
			local dx, dy = px - tx, py - ty
			return tx + cosA * dx - sinA * dy, ty + sinA * dx + cosA * dy
		end
		local function stroke(x0, y0, x1, y1)
			Bresenham.stroke(x0, y0, x1, y1, Config.StrokeRadius, function(x, y) buf:set(x, y, 1) end)
		end
		local bLx, bLy = rot(tx - half, barY)
		local bRx, bRy = rot(tx + half, barY)
		local sTx, sTy = rot(tx,          barY)
		local sBx, sBy = rot(tx,          botY)
		stroke(bLx, bLy, bRx, bRy)
		stroke(sTx, sTy, sBx, sBy)
	end

	-- Four Ts at cardinal points, canonical orientation rotated so each bar sits on the outer rim.
	--   N canonical (arrow up = outward)
	--   E rotated +90 (arrow right = outward)
	--   S rotated 180 (arrow down = outward)
	--   W rotated -90 (arrow left = outward)
	drawRotatedT(32,  9, 0)
	drawRotatedT(55, 32,  math.pi / 2)
	drawRotatedT(32, 55, math.pi)
	drawRotatedT(9,  32, -math.pi / 2)

	canvas:paintFromBuffer(buf)
end

-- Map paper Part name -> rendering function. Sign-arrangement examples (Directional /
-- Sustain / Balanced) keep their custom painters; element pages just render their sigil.
local SIMPLE_PAPER_TO_SIGIL: {[string]: string} = {
	SpellPaper_Reference  = "fire",
	SpellPaper_Water      = "water",
	SpellPaper_Earth      = "earth",
	SpellPaper_Wind       = "wind",
	SpellPaper_FireBurst  = "fire_burst",
	SpellPaper_FireLance  = "fire_lance",
	SpellPaper_WaterBubble = "water_bubble",
	SpellPaper_WaterTide  = "water_tide",
	SpellPaper_EarthWall  = "earth_wall",
	SpellPaper_EarthSpike = "earth_spike",
	SpellPaper_EarthQuake = "earth_quake",
	SpellPaper_WindGust   = "wind_gust",
	SpellPaper_WindVortex = "wind_vortex",
	SpellPaper_WindBlade  = "wind_blade",
}

local function setupReferencePaper(p: BasePart)
	local canvas = Canvas.attach(p)
	local name = p.Name
	if name == "SpellPaper_Directional" then
		paintDirectionalGlyph(canvas)
	elseif name == "SpellPaper_Sustain" then
		paintSustainGlyph(canvas)
	elseif name == "SpellPaper_Balanced" then
		paintBalancedGlyph(canvas)
	else
		local sigilId = SIMPLE_PAPER_TO_SIGIL[name] or "fire"
		paintCanonicalGlyph(canvas, sigilId)
	end
	canvases[p] = canvas
end

local function setupDrawPaper(p: BasePart)
	local canvas = Canvas.attach(p)
	canvases[p] = canvas
end

for _, p in ipairs(CollectionService:GetTagged(Config.ReferenceTag)) do setupReferencePaper(p) end
CollectionService:GetInstanceAddedSignal(Config.ReferenceTag):Connect(setupReferencePaper)

for _, p in ipairs(CollectionService:GetTagged(Config.PaperTag)) do setupDrawPaper(p) end
CollectionService:GetInstanceAddedSignal(Config.PaperTag):Connect(setupDrawPaper)

-- ========= Draw mode state =========

local drawMode = {
	active = false,
	paper = nil :: BasePart?,
	canvas = nil :: any,
	savedCameraType = nil :: Enum.CameraType?,
	savedCameraCFrame = nil :: CFrame?,
	drawing = false,
	lastCell = nil :: Vector2?,
	pendingCastTask = nil :: thread?,
	pendingResult = nil :: any,
	tool = "draw" :: string,       -- "draw" or "erase"
	eraseBtn = nil :: TextButton?,  -- bound so we can update its look when toggled
}

local enterDrawMode: (BasePart) -> ()
local exitDrawMode:  () -> ()
local cancelPending:  () -> ()
local tryStartPending: () -> ()

cancelPending = function()
	if drawMode.pendingCastTask then
		task.cancel(drawMode.pendingCastTask)
		drawMode.pendingCastTask = nil
	end
	if drawMode.pendingResult and drawMode.paper then
		Caster.endGlow(drawMode.paper)
	end
	drawMode.pendingResult = nil
end

tryStartPending = function()
	cancelPending()
	if not drawMode.canvas or not drawMode.paper then return end
	local result, reason = Caster.evaluate(drawMode.canvas.buffer)
	if not result then
		if reason then print("[Spell] not ready:", reason) end
		return
	end
	-- Debug: dump what we recognised so the player can see sign detection as they draw.
	print(string.format("[Spell] READY: %s acc=%.2f signs=%d", result.id, result.accuracy, #result.signs))
	for i, s in ipairs(result.signs) do
		local dir = s.direction and string.format("(%.2f, %.2f)", s.direction.X, s.direction.Y) or "nil"
		local center = s.center and string.format("(%.0f, %.0f)", s.center.X, s.center.Y) or "?"
		print(string.format("  sign #%d: id=%s score=%.2f dir=%s center=%s size=%d",
			i, tostring(s.id), s.score or 0, dir, center, s.size or 0))
	end
	drawMode.pendingResult = result
	Caster.beginGlow(drawMode.paper, Config.GlowColor, Config.CastDelay)
	local capturedPaper = drawMode.paper
	drawMode.pendingCastTask = task.delay(Config.CastDelay, function()
		if drawMode.pendingResult ~= result then return end
		-- Serialize signs for the remote (strip unnecessary fields to keep payload tiny).
		local signsPayload = {}
		for _, s in ipairs(result.signs or {}) do
			table.insert(signsPayload, {
				id = s.id,
				score = s.score,
				direction = s.direction,
				center = s.center,
				size = s.size,
			})
		end
		CastRemote:FireServer({
			sigilId = result.id,
			accuracy = result.accuracy,
			direction = result.direction,
			directionality = result.directionality,
			paper = capturedPaper,
			signs = signsPayload,
		})
		if drawMode.canvas then drawMode.canvas:clear() end
		Caster.endGlow(capturedPaper)
		drawMode.pendingResult = nil
		drawMode.pendingCastTask = nil
		-- Pop back to the player so they can see the effects.
		exitDrawMode()
	end)
end

-- ========= Input raycast =========

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include

local function screenToPaperHit(sx: number, sy: number): Vector3?
	if not drawMode.paper then return nil end
	raycastParams.FilterDescendantsInstances = { drawMode.paper }
	local ray = camera:ViewportPointToRay(sx, sy)
	local result = workspace:Raycast(ray.Origin, ray.Direction * 100, raycastParams)
	if result and result.Instance == drawMode.paper then return result.Position end
	return nil
end

local function currentInkValue(): number
	return drawMode.tool == "erase" and 0 or 1
end

local function beginStroke(sx: number, sy: number)
	if not drawMode.active or not drawMode.canvas then return end
	local hit = screenToPaperHit(sx, sy)
	if not hit then return end
	cancelPending()
	local gx, gy = drawMode.canvas:worldToGrid(hit)
	drawMode.drawing = true
	drawMode.lastCell = Vector2.new(gx, gy)
	drawMode.canvas:setCell(gx, gy, currentInkValue())
end

local function continueStroke(sx: number, sy: number)
	if not drawMode.drawing or not drawMode.canvas then return end
	local hit = screenToPaperHit(sx, sy)
	if not hit then return end
	local gx, gy = drawMode.canvas:worldToGrid(hit)
	local v = currentInkValue()
	if drawMode.lastCell then
		drawMode.canvas:strokeBetween(drawMode.lastCell.X, drawMode.lastCell.Y, gx, gy, v)
	else
		drawMode.canvas:setCell(gx, gy, v)
	end
	drawMode.lastCell = Vector2.new(gx, gy)
end

-- Live per-stroke debug: dump every component and its sign classification so the player can see
-- whether the signs they've drawn are being recognised -- even before the sigil is complete.
local function peekDebug()
	if not drawMode.canvas then return end
	local peek = Caster.peek(drawMode.canvas.buffer)
	if not peek.ringFound then
		print(string.format("[Spell peek] no ring yet (%s)", tostring(peek.ringReason)))
		return
	end
	if #peek.components == 0 then
		print("[Spell peek] ring OK, no components inside")
		return
	end
	print(string.format("[Spell peek] ring OK; %d component(s):", #peek.components))
	for i, c in ipairs(peek.components) do
		local dir = c.signDirection and string.format("(%.2f, %.2f)", c.signDirection.X, c.signDirection.Y) or "nil"
		local role = c.isCentralCandidate and "sigil?" or "sign"
		local id = c.signId and string.format("sign=%s(%.2f)", c.signId, c.signScore) or "sign=?"
		print(string.format("  #%d %-7s size=%3d center=(%.0f,%.0f) off=%.1f %s dir=%s",
			i, role, c.size, c.center.X, c.center.Y, c.centerOffset, id, dir))
	end
end

local function endStroke()
	if not drawMode.drawing then return end
	drawMode.drawing = false
	drawMode.lastCell = nil
	peekDebug()
	tryStartPending()
end

-- ========= Camera / mode switch =========

local function styleButton(btn: TextButton, bg: Color3, fg: Color3)
	btn.BackgroundColor3 = bg
	btn.TextColor3 = fg
	btn.TextSize = 18
	btn.Font = Enum.Font.GothamBold
	btn.AutoButtonColor = true
	btn.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn
end

local function updateEraserButtonLook()
	local btn = drawMode.eraseBtn
	if not btn then return end
	if drawMode.tool == "erase" then
		btn.BackgroundColor3 = Color3.fromRGB(200, 80, 60)
		btn.Text = "Eraser  ON"
	else
		btn.BackgroundColor3 = Color3.fromRGB(60, 60, 68)
		btn.Text = "Eraser"
	end
end

local function makeToolsGui()
	local pg = player:WaitForChild("PlayerGui")
	local existing = pg:FindFirstChild("SpellExitGui")
	if existing then existing:Destroy() end
	local gui = Instance.new("ScreenGui")
	gui.Name = "SpellExitGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = pg

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundTransparency = 1
	panel.Size = UDim2.fromOffset(160, 200)
	panel.Position = UDim2.new(1, -176, 0, 16)
	panel.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Parent = panel

	local function addButton(name: string, text: string, bg: Color3, onClick: () -> ()): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.Size = UDim2.fromOffset(140, 44)
		b.Text = text
		styleButton(b, bg, Color3.fromRGB(240, 240, 240))
		b.Parent = panel
		b.MouseButton1Click:Connect(onClick)
		return b
	end

	addButton("Exit", "Exit (E)", Color3.fromRGB(28, 28, 32), function() exitDrawMode() end)
	addButton("Clear", "Clear", Color3.fromRGB(28, 28, 32), function()
		if drawMode.canvas then
			cancelPending()
			drawMode.canvas:clear()
		end
	end)
	local erase = addButton("Eraser", "Eraser", Color3.fromRGB(60, 60, 68), function()
		drawMode.tool = (drawMode.tool == "erase") and "draw" or "erase"
		updateEraserButtonLook()
	end)
	drawMode.eraseBtn = erase
	drawMode.tool = "draw"
	updateEraserButtonLook()
	return gui
end

enterDrawMode = function(paper: BasePart)
	if drawMode.active then return end
	local canvas = canvases[paper]
	if not canvas then return end
	drawMode.active = true
	drawMode.paper = paper
	drawMode.canvas = canvas
	drawMode.savedCameraType = camera.CameraType
	drawMode.savedCameraCFrame = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable

	local target = paper.Position
	local camPos = target + Vector3.new(0, Config.CameraHeightStuds, 0)
	local endCF = CFrame.lookAt(camPos, target, Vector3.new(0, 0, -1))
	TweenService:Create(
		camera,
		TweenInfo.new(Config.CameraTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = endCF }
	):Play()

	ContextActionService:BindAction("ExitSpellDraw", function(_, state)
		if state == Enum.UserInputState.Begin then exitDrawMode() end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.E, Enum.KeyCode.Escape)

	makeToolsGui()
end

exitDrawMode = function()
	if not drawMode.active then return end
	cancelPending()
	drawMode.active = false
	drawMode.drawing = false
	drawMode.lastCell = nil
	drawMode.eraseBtn = nil
	drawMode.tool = "draw"
	local savedCF = drawMode.savedCameraCFrame
	local savedType = drawMode.savedCameraType or Enum.CameraType.Custom
	ContextActionService:UnbindAction("ExitSpellDraw")
	local pg = player:FindFirstChild("PlayerGui")
	if pg then
		local g = pg:FindFirstChild("SpellExitGui")
		if g then g:Destroy() end
	end
	drawMode.paper = nil
	drawMode.canvas = nil
	-- Quick tween back to the player camera, then hand control back to the default camera system.
	if savedCF then
		local tween = TweenService:Create(
			camera,
			TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = savedCF }
		)
		tween.Completed:Connect(function()
			camera.CameraType = savedType
		end)
		tween:Play()
	else
		camera.CameraType = savedType
	end
end

-- ========= Click-to-enter on papers =========

local function bindClickForPaper(paper: BasePart)
	local cd = paper:FindFirstChildOfClass("ClickDetector")
	if not cd then return end
	cd.MouseClick:Connect(function(clicker)
		if clicker ~= player then return end
		enterDrawMode(paper)
	end)
end

for _, p in ipairs(CollectionService:GetTagged(Config.PaperTag)) do bindClickForPaper(p) end
CollectionService:GetInstanceAddedSignal(Config.PaperTag):Connect(bindClickForPaper)

OpenToolPaper.OnClientEvent:Connect(function(paper)
	if typeof(paper) ~= "Instance" or not paper:IsA("BasePart") then return end
	if not canvases[paper] then setupDrawPaper(paper) end
	bindClickForPaper(paper)
	enterDrawMode(paper)
end)

-- ========= Input dispatch =========


-- IMPORTANT: Use UserInputService:GetMouseLocation() instead of InputObject.Position for mouse.
-- GetMouseLocation returns viewport-relative coords (no topbar inset), matching what
-- camera:ViewportPointToRay expects. InputObject.Position for MouseMovement includes the inset,
-- which causes a ~36px visual offset between cursor and rendered stroke.
-- Touch Position is already inset-free, so it can be used directly.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not drawMode.active then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local p = UserInputService:GetMouseLocation()
		beginStroke(p.X, p.Y)
	elseif input.UserInputType == Enum.UserInputType.Touch then
		beginStroke(input.Position.X, input.Position.Y)
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if not drawMode.drawing then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		local p = UserInputService:GetMouseLocation()
		continueStroke(p.X, p.Y)
	elseif input.UserInputType == Enum.UserInputType.Touch then
		continueStroke(input.Position.X, input.Position.Y)
	end
end)

UserInputService.InputEnded:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		endStroke()
	end
end)

print("[SpellClient] ready. Click a paper to draw.")
