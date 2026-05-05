--!strict
-- Attaches a SurfaceGui canvas to a Part. Provides set/clear/worldToGrid helpers.
-- Designed to be modular: call Canvas.attach(paperPart) and the rest is self-contained.

local Config     = require(script.Parent.Parent.Config)
local GridBuffer = require(script.Parent.GridBuffer)
local Bresenham  = require(script.Parent.Parent.Util.Bresenham)

local Canvas = {}
Canvas.__index = Canvas

-- ====== private helpers ======

local function buildSurfaceGui(part: BasePart, size: number): SurfaceGui
	local gui = part:FindFirstChild("CanvasGui") :: SurfaceGui?
	if gui then return gui end
	gui = Instance.new("SurfaceGui")
	gui.Name = "CanvasGui"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(size, size)
	gui.PixelsPerStud = 0
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Adornee = part
	gui.Parent = part
	return gui
end

local function buildBackground(gui: SurfaceGui): Frame
	local bg = gui:FindFirstChild("Background") :: Frame?
	if bg then return bg end
	bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Config.PaperColor
	bg.BorderSizePixel = 0
	bg.Parent = gui
	return bg
end

local function buildPixelRoot(parentFrame: Frame): Frame
	local root = parentFrame:FindFirstChild("PixelRoot") :: Frame?
	if root then return root end
	root = Instance.new("Frame")
	root.Name = "PixelRoot"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = parentFrame
	return root
end

local function buildPixels(root: Frame, size: number): {[number]: {[number]: Frame}}
	local pixels = {}
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	for y = 1, size do
		pixels[y] = {}
	end
	-- SurfaceGui on Top face empirically maps UI X -> part local -Z, UI Y -> part local +X
	-- (axes swapped AND X inverted vs what you'd expect). So pixel (gx, gy) at UI(size-gy+0.5, gx-0.5)
	-- puts gx along the screen's X axis and gy along the screen's Y axis under a top-down (-Z up) camera.
	local pad = 0.5
	for y = 1, size do
		for x = 1, size do
			local f = Instance.new("Frame")
			f.Name = string.format("p_%d_%d", x, y)
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Size = UDim2.fromOffset(1 + pad, 1 + pad)
			f.Position = UDim2.fromOffset(size - y + 0.5, x - 0.5)
			f.BackgroundColor3 = Config.DrawColor
			f.BorderSizePixel = 0
			f.Visible = false
			f.ZIndex = 2
			f.Parent = root
			pixels[y][x] = f
		end
	end
	return pixels
end

-- ====== public class ======

export type Canvas = typeof(setmetatable({} :: {
	part: BasePart,
	gui: SurfaceGui,
	bg: Frame,
	pixelRoot: Frame,
	pixels: {[number]: {[number]: Frame}},
	buffer: GridBuffer.GridBuffer,
	size: number,
}, Canvas))

function Canvas.attach(part: BasePart): Canvas
	local size = Config.GridSize
	local gui       = buildSurfaceGui(part, size)
	local bg        = buildBackground(gui)
	local pixelRoot = buildPixelRoot(bg)
	local pixels    = buildPixels(pixelRoot, size)

	local self = setmetatable({
		part = part,
		gui = gui,
		bg = bg,
		pixelRoot = pixelRoot,
		pixels = pixels,
		buffer = GridBuffer.new(size),
		size = size,
	}, Canvas)
	return self
end

function Canvas:setCell(x: number, y: number, v: number?)
	if x < 1 or y < 1 or x > self.size or y > self.size then return end
	local val = v or 1
	self.buffer:set(x, y, val)
	local pixel = self.pixels[y][x]
	pixel.Visible = val ~= 0
end

function Canvas:clear()
	self.buffer:clear()
	for y = 1, self.size do
		local row = self.pixels[y]
		for x = 1, self.size do row[x].Visible = false end
	end
end

-- Stroke between two grid points (inclusive), using Config.StrokeRadius.
-- `value` defaults to 1 (ink). Pass 0 to erase along the stroke.
function Canvas:strokeBetween(x0: number, y0: number, x1: number, y1: number, value: number?)
	local r = Config.StrokeRadius
	local v = value == nil and 1 or value
	local f = function(x: number, y: number) self:setCell(x, y, v) end
	if r <= 0 then
		Bresenham.line(x0, y0, x1, y1, f)
	else
		Bresenham.stroke(x0, y0, x1, y1, r, f)
	end
end

-- Convert a world-space point on the paper's top face into grid coords (1-based).
-- Grid convention: (1, 1) = visual top-left, (N, N) = visual bottom-right, y grows downward.
-- The formulas here are the inverse of the rendering formulas above — so a click lands
-- on the SAME pixel the user sees under the cursor (matters because UDim offsets get floored
-- and the X-flip / axis-swap on Top face shifts things by half a cell if not handled).
function Canvas:worldToGrid(worldPos: Vector3): (number, number, boolean)
	local local_ = self.part.CFrame:PointToObjectSpace(worldPos)
	local sz = self.part.Size
	-- UI-space position of the click (SurfaceGui Top face: UI X <-> local -Z, UI Y <-> local +X)
	local uiX = (sz.Z / 2 - local_.Z) / sz.Z * self.size
	local uiY = (local_.X + sz.X / 2) / sz.X * self.size
	local inside = uiX >= 0 and uiX <= self.size and uiY >= 0 and uiY <= self.size
	-- Invert the render formulas: pixel (gx, gy) lives at UI (size - gy, gx - 1) after flooring.
	local gy = math.clamp(self.size - math.floor(uiX), 1, self.size)
	local gx = math.clamp(math.floor(uiY) + 1, 1, self.size)
	return gx, gy, inside
end

-- Convert a grid-space 2D direction (y grows DOWN) into a world direction on the paper's plane.
-- Grid +X -> local +X. Grid +Y (visual-down) -> local +Z (visual-down under -Z up camera).
function Canvas:gridDirToWorld(dir: Vector2): Vector3
	local localDir = Vector3.new(dir.X, 0, dir.Y)
	return self.part.CFrame:VectorToWorldSpace(localDir)
end

-- Paint the canvas from a pre-populated GridBuffer (used for the reference paper).
function Canvas:paintFromBuffer(buf: GridBuffer.GridBuffer)
	local s = math.min(self.size, buf.size)
	for y = 1, s do
		local row = buf.cells[y]
		for x = 1, s do
			local on = row[x] ~= 0
			self.buffer:set(x, y, on and 1 or 0)
			self.pixels[y][x].Visible = on
		end
	end
end

return Canvas
