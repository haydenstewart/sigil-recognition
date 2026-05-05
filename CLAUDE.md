# Spell System — Handoff Notes

You are continuing work on a Roblox spell-drawing system that recognises hand-drawn glyphs ("sigils") and casts spells with effects modulated by surrounding "signs". A previous session built the recognition pipeline, trained a small MLP classifier, and wired it into the cast flow. This file is the load-bearing context you need to be useful immediately.

## The two halves

You will work across two environments simultaneously:

1. **A Roblox Studio session** (project name: `hat`, separate from the user's other studio called `baki test 3.3`). Access it via the Roblox Studio MCP tools — `list_roblox_studios`, `set_active_studio`, `script_read`, `multi_edit`, `execute_luau`, etc. **Always confirm the active studio is `hat` before editing.** All spell-system code lives at `game.ReplicatedStorage.SpellSystem`.

2. **A Python training pipeline** at `C:\Users\haste\.claude\sigil_training\` — this folder. Templates exported from Studio go to `templates.json`; `train.py` produces `SigilModel.lua` and `SignModel.lua` which get pasted into Studio.

## Architecture map

`game.ReplicatedStorage.SpellSystem` contains:

- `Config` — single source of truth for tunables (`GridSize=64`, `TemplateResolution=32`, `SigilMinCells=60`, `MatchThreshold=0.45`, `CastDelay=1.0`, etc.). Read this first when reasoning about anything numeric.
- `Util.Bresenham` — `line` / `disk` / `stroke` (thick line via disk-stamping) / `circle` / `thickCircle`. The only drawing primitives.
- `Canvas/`
  - `GridBuffer` — N×N binary grid; `set/get/count/forEachOn/bbox/clone`. The fundamental data type.
  - `Canvas` — attaches a `SurfaceGui` to a paper Part with one Frame per cell, plus `setCell` / `clear` / `strokeBetween` / `worldToGrid` / `paintFromBuffer`.
- `Recognition/`
  - `RingDetector` — flood-fill from canvas border to mark "outside"; classifies drawn cells as `ringMask` (touching outside) vs `sigilMask` (enclosed ink).
  - `ComponentFinder` — 4-connected components of any GridBuffer.
  - `Normalizer` — `normalize` (bbox-crop + nearest-neighbour resample to target square, keeping aspect, centering shorter axis), `dilate`, `iou`, `rotate`, `centroid`. The 32×32 normalization used here fills the LONGER axis to 100% of the target — important, see gotchas.
  - `SigilMatcher` — entry point: `match(sigilInk) -> (MatchResult?, reason?)`. Delegates to `MLMatcher` if the model is loaded, else falls back to dilated-IoU template matching.
  - `SignMatcher` — entry point: `match(componentMask) -> SignMatch?`. Same model-or-fallback pattern; sweeps 12 rotations.
  - `Inference` — int8-quantised MLP forward pass (Linear → ReLU → Linear → softmax). Loads weights from `Model` table via base64 decode into a `buffer`. ~5 ms/forward.
  - `MLMatcher` — wraps `Inference` to expose `matchSigil` / `matchSign` returning the same types as the legacy IoU matchers. Holds the `_other` reject-class handling.
  - `SigilModel` / `SignModel` — auto-generated weight modules (replaced by `train.py`). Look like `{ classes={...}, inputSize=32, w1={rows,cols,scale,q}, b1={...}, w2={...}, b2={...} }`.
- `Sigils/`
  - `Registry` — `register(entry)` / `get(id)` / `all()` / `loadAll()`. **`register` OVERWRITES existing entries** — important if you re-load (see gotchas).
  - `Fire`, `Water`, `Earth`, `Wind` — each registers `{id, template, buildVisual, onCast, verify?}` at require time. `template` is a 32×32 GridBuffer of the canonical glyph after running through RingDetector + Normalizer.
- `Signs/`
  - `Registry` — same pattern.
  - `Column` (T-shape, modulates direction), `Levitation` (arrow, switches to sustain mode).
- `Spells/`
  - `Caster` — `evaluate(grid)` runs the full pipeline; `activate(id, ctx)` dispatches to the sigil's `onCast`; `peek(grid)` returns inspection-only data for live debug; `beginGlow` / `endGlow` for the cast-pending paper highlight.
- `ClientEffects/` — VFX dispatched to all clients on cast (shockwave, beam, explosion, sustain, etc.).

Other locations:
- `game.StarterPlayer.StarterPlayerScripts.SpellClient` — the canvas+input driver. Renders reference papers (one canonical glyph per paper), handles draw mode, calls `Caster.evaluate` after each stroke, dispatches to the server.
- `game.Workspace` — has `SpellPaper` (writable) and several `SpellPaper_<Element>` reference parts (read-only displays) plus matching `_Label` parts.

## The cast pipeline end-to-end

1. Player clicks a `SpellPaper` → `SpellClient` enters draw mode (camera tween + tool GUI).
2. Each stroke hits `Canvas:strokeBetween`, which writes to the local `GridBuffer`.
3. After every `endStroke`, `Caster.evaluate(canvas.buffer)` runs:
   - `RingDetector.detect` → `ringMask` + `sigilMask` (inside-the-ring ink).
   - `ComponentFinder.find(sigilMask)` → list of 4-connected components.
   - For each component (size ≥ 4): try `SignMatcher.match`. If it matches, record as a sign; otherwise merge the component into a combined `sigilInk` mask.
   - `SigilMatcher.match(sigilInk)` → top sigil class + score. The matcher is the trained MLP.
4. If a sigil matched, `SpellClient` shows a glow (`Caster.beginGlow`), waits `Config.CastDelay = 1 s`, then fires the `Cast` RemoteEvent to the server with `{sigilId, accuracy, direction, signs, paper}`.
5. Server runs `Caster.activate(sigilId, ctx)` → the registered `onCast` runs damage/effects, fires `PlayEffect` to all clients.

## Gotchas that bit the previous session

These are non-obvious and I lost time on each. Read them before touching anything.

- **Studio's edit-mode `require` cache is sticky.** A failed require leaves a "module experienced an error while loading" cache entry that persists across source edits. The fix isn't `--no-cache` (no such flag); it's either: (a) close Studio's process completely and reopen the project, or (b) clone the ModuleScript to a sibling location and require the clone. The export snippet `export_templates.luau` deliberately clones the entire `Sigils` and `Signs` folders (Registry included) so it works regardless of cache state — read it if you need to do anything similar.
- **`local a, b: T1, T2 = ...` is INVALID Luau.** Multi-variable type annotation isn't supported. Errors as "module experienced an error while loading" with no useful trace. Use untyped multi-assignment, or one annotation per `local`.
- **Caster.evaluate combines non-sign components.** A previous design fed only the largest central component to the matcher, but that lets players cast Wind by drawing just an S without the hash marks (defeating the visual identity). The current design merges every non-sign component into one mask, so the model trains on and infers from the full glyph. **Don't revert to central-component-only without strong reason** — there was a whole training cycle wasted on this.
- **Templates and inference must see the same shape.** Lua's `Normalizer.normalize` fills the longer axis to 100% of the target. Python's `recenter` (in `train.py`) was shrinking inputs to 85%, causing wind to fail. The recenter call has been removed from the loader; don't add it back. If you change anything about how templates are produced in Lua, update the Python loader to match exactly.
- **Model weight files cannot flow through Claude's context.** ~88 KB of base64 tokenises at ~1 token per char ≈ 88 K tokens, far above the 25 K-token Read limit. The workflow is: `train.py` writes `SigilModel.lua` / `SignModel.lua` to disk → user manually copy-pastes into the Studio ModuleScript. Don't try to clever-route around this; just hand off the manual paste step clearly.
- **`Registry.register` OVERWRITES.** Earlier it dedup-skipped, which meant edits to a sigil's template wouldn't take effect without a Studio restart. The current overwrite behavior is intentional. If you're seeing stale entries, the issue is the `require` cache (above), not the registry.
- **Hash marks / drops are not signs.** SignMatcher's `_other` class catches anything that isn't a Column T or Levitation arrow, so Wind's hashes and Water's drops get correctly routed to `sigilInk` rather than the signs list. If you add a sign that looks like a horizontal dash, this breaks.

## Adding a new sigil — recipe

1. Create `ReplicatedStorage.SpellSystem.Sigils.<Name>` as a ModuleScript.
2. Mirror the structure of `Sigils.Fire`:
   - `buildVisual(buf)` draws the canonical glyph into a GridBuffer using `Bresenham` primitives (units in cells; `cx, cy = N/2, N/2`; `R = N * 0.26` is a reasonable inner radius that leaves room for signs around the sigil).
   - `buildTemplate()` renders a full canvas (ring + buildVisual), runs `RingDetector.detect`, then `Normalizer.normalize(ring.sigilMask, Config.TemplateResolution)`.
   - `onCast(ctx)` runs server-side effects. `ctx` has `{accuracy, direction, directionality, paperCFrame, signs}`.
   - Optional `verify(normalized, raw) -> (boolean, string?)` for per-class shape checks (Fire's verify enforces the central vertical line).
3. End the module with `Registry.register({id, template, buildVisual, onCast, verify?})` and `return true`.
4. (Optional) Add a reference paper in `Workspace`: tag a Part with `SpellReferencePaper`, name it `SpellPaper_<Name>`, and add a mapping in `SpellClient.SIMPLE_PAPER_TO_SIGIL`.
5. Re-export → re-train → paste new model files (see below).

## Training workflow

When you add or change sigils/signs, the model needs to be retrained.

```
# 1. Export templates from Studio
#    Open Studio's Command Bar (View > Command Bar), paste the contents of
#    sigil_training/export_templates.luau, run. Copy the printed JSON.
#    Save it as sigil_training/templates.json (overwriting the old one).

# 2. Train
cd C:\Users\haste\.claude\sigil_training
python train.py
# Produces SigilModel.lua and SignModel.lua next to train.py. ~30-60 s on CPU.

# 3. Paste into Studio
#    Open the generated SigilModel.lua, Ctrl+A, Ctrl+C.
#    In Studio open ReplicatedStorage.SpellSystem.Recognition.SigilModel,
#    Ctrl+A, Ctrl+V, Ctrl+S. Repeat for SignModel.

# 4. Verify
#    Run this in the Command Bar:
#      local Sig = require(game.ReplicatedStorage.SpellSystem.Recognition.SigilModel)
#      local Sign = require(game.ReplicatedStorage.SpellSystem.Recognition.SignModel)
#      print("Sigil:", #Sig.classes, table.concat(Sig.classes, ", "))
#      print("Sign:",  #Sign.classes, table.concat(Sign.classes, ", "))
```

The training script:
- Loads `templates.json` and treats each sigil/sign template as the canonical sample for its class.
- Adds an `_other` class generated from random scribbles (lines/arcs/blobs) to give the model a way to reject non-glyphs.
- Augments each canonical sample 800× per class with rotation, scale, translation, dilation (thickness), stroke-drop, and salt-and-pepper noise. Sigils rotate ±25°, signs rotate full ±180°.
- Trains a 1024 → 64 → C MLP, ~30 epochs, Adam, cross-entropy.
- Quantises both weight matrices to int8 per-tensor symmetric, base64-encodes, emits Luau modules.

## End-to-end test snippet (Command Bar)

Useful when verifying a fresh model. Drops a clone of the Sigils folder so the test isn't poisoned by stale require cache.

```lua
local SS = game.ReplicatedStorage.SpellSystem
local Config           = require(SS.Config)
local GridBuffer       = require(SS.Canvas.GridBuffer)
local Bresenham        = require(SS.Util.Bresenham)
local RingDetector     = require(SS.Recognition.RingDetector)
local ComponentFinder  = require(SS.Recognition.ComponentFinder)
local SigilMatcher     = require(SS.Recognition.SigilMatcher)
local SignMatcher      = require(SS.Recognition.SignMatcher)

local clone = SS.Sigils:Clone()
clone.Name = "Sigils__Test"; clone.Parent = SS
local Reg = require(clone.Registry)
for _, m in ipairs(clone:GetChildren()) do
    if m:IsA("ModuleScript") and m.Name ~= "Registry" then pcall(require, m) end
end

for _, name in ipairs({"fire", "water", "earth", "wind"}) do
    local entry = Reg.get(name); if not entry then continue end
    local N = Config.GridSize
    local canvas = GridBuffer.new(N)
    Bresenham.thickCircle(N/2, N/2, N * 0.45, Config.StrokeRadius, function(x,y) canvas:set(x,y,1) end)
    entry.buildVisual(canvas)
    local ring = RingDetector.detect(canvas)
    -- Replicate Caster.evaluate's component-merge logic
    local sigilInk = GridBuffer.new(N)
    for _, c in ipairs(ComponentFinder.find(ring.sigilMask)) do
        if c.count >= 4 and not SignMatcher.match(c.mask) then
            c.mask:forEachOn(function(x,y) sigilInk:set(x,y,1) end)
        end
    end
    local m, reason = SigilMatcher.match(sigilInk)
    print(name, m and string.format("-> %s (%.3f)", m.id, m.score) or ("NO MATCH: " .. tostring(reason)))
end
clone:Destroy()
```

## Open thread when this handoff was written

The previous session reverted `Caster.evaluate` to combine non-sign components and reverted each sigil's `buildTemplate` to the full-glyph form (water 112 cells, wind 179 cells — confirmed via `freshRegistry` test). The CentralComponent helper module was deleted because it's no longer used. **The user has NOT yet re-exported and retrained on these reverted templates.** The current pasted `SigilModel` was trained on the prior central-component-only templates, so right now Wind/Water classification is inconsistent with what the new pipeline expects.

The next step is straightforward: have the user run the training workflow above (export → train → paste), then run the end-to-end test snippet to confirm:
- Drawing the full glyph for each of fire/water/earth/wind matches with high score.
- Drawing only the central element (e.g. just an S inside a ring) returns NO MATCH or `_other`.

Once that's verified, the system is in a coherent state. Beyond that, the user's likely next directions are: (a) add more sigils + retrain, (b) flesh out water/earth/wind `onCast` to mirror Fire's sign-modulated spell forms, (c) collect player drawings via a debug logger and retrain on real data instead of pure synthetic augmentation.

## Don't do these

- Don't try to read `SigilModel.lua` or `SignModel.lua` with the Read tool (they blow the token budget).
- Don't suggest disabling HTTP enforcement or other security toggles to "make it easier".
- Don't add per-feature toggle flags or backwards-compat shims — the user prefers terse, direct edits over abstraction layers.
- Don't reintroduce the central-component-only template approach for Water/Wind without explicit user instruction; it's been considered and rejected.
