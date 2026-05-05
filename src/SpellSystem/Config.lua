--!strict
-- Central config for the spell system. Tweak here to retune behavior.

local Config = {}

-- Grid & paper geometry
Config.GridSize = 64
Config.CellSize = 0.05          -- studs per grid cell
Config.PaperThickness = 0.05
Config.PaperSize = Config.GridSize * Config.CellSize -- 3.2 studs

-- Visual
Config.PaperColor   = Color3.fromRGB(240, 228, 196)
Config.DrawColor    = Color3.fromRGB(80, 18, 10)
Config.GlowColor    = Color3.fromRGB(255, 180, 60)
Config.StrokeRadius = 1                 -- 0 = 1-px, 1 = 3x3, 2 = 5x5

-- Interaction
Config.PaperTag          = "SpellPaper"
Config.ReferenceTag      = "SpellReferencePaper"
Config.ClickDistance     = 16
Config.CameraTweenTime   = 0.6
Config.CameraHeightStuds = 4.2          -- how far above paper the camera sits in draw mode

-- Recognition
Config.MinInteriorCells    = 60         -- interior open area must be at least this to count as a ring
Config.SigilMinCells       = 60         -- the central sigil component must have at least this many ink cells
Config.TemplateResolution  = 32         -- normalized sigil size for matching
Config.MatchThreshold      = 0.45       -- dilated-IoU to accept a sigil
Config.SignMatchThreshold  = 0.38       -- lower bar for signs (smaller, noisier)
Config.MaxInsideFillRatio  = 0.70       -- reject if interior is mostly filled (scribble)
Config.MatchDilation       = 1          -- pixel radius for dilated IoU (tolerance to position/thickness)
Config.SignMatchDilation   = 2          -- signs get extra dilation (usually small/noisy)
Config.SignMatchMargin     = 0.06       -- winning sign type must beat runner-up by this to count

-- Casting
Config.CastDelay = 1.0                  -- seconds of glow before activation
Config.DirectionalRatio = 1.15          -- prong-length ratio to count as directional beam

return Config
