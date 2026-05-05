# sigil-recognition

A Roblox spell system where you draw glyphs on a piece of paper and a tiny neural net figures out what spell you're casting.

## Demo

**Non-directional cast** — sigil drawn inside the ring with no shaping signs, so the spell resolves as an AoE form:

![non-directional cast](media/contained.gif)

**Directional cast** — adding a column (T) sign points the spell along that axis, here as a horizontal beam:

![directional cast](media/directional.gif)

## How it works

You click a "spell paper" part in the world and the camera tilts overhead. You scribble a glyph — a triangle for fire, a wavy line for water, etc. — and you can add smaller marks around it to control how the spell behaves: an arrow makes it sustained, a T points it in a direction, no marks at all means it just explodes.

After every stroke I run the canvas through a short pipeline:

1. Flood-fill from the canvas border to figure out what's "inside" the ring you drew (if you've drawn one yet).
2. Split that inside ink into 4-connected components — your central glyph plus any little marks beside it.
3. Run each component through a sign classifier; whatever isn't a sign gets merged back into a single sigil mask and run through the sigil classifier.
4. Recover orientation: sigils get a geometric "where does the dominant prong point" estimate, signs get one by trying 12 rotations through the model and taking the best score.
5. Glow the paper for a second so you can stop drawing if you didn't mean to cast, then fire the cast remote to the server.

The fun design choice here is that a spell's *form* comes from the signs, not the sigil. A fire sigil with no signs is just a chaotic AoE fireball. Add column signs lined up in a direction and it's a beam pointing that way. Add a levitation arrow and it sustains as a hovering orb. The sigil chooses the element; the signs shape it.

## Repo layout

```
src/                                 Roblox source (Rojo-compatible)
  SpellSystem/
    Config.lua                       single source of truth for tunables
    Util/Bresenham.lua               line / disk / stroke / circle primitives
    Canvas/
      GridBuffer.lua                 N×N binary grid (the fundamental data type)
      Canvas.lua                     attaches a SurfaceGui to a Part
    Recognition/
      RingDetector.lua               flood-fill border to find enclosed ink
      ComponentFinder.lua            4-connected components
      Normalizer.lua                 bbox-crop + nearest-neighbor resample
      SigilMatcher.lua               entry point for sigil classification
      SignMatcher.lua                entry point for sign classification (rotation-aware)
      Inference.lua                  int8-quantized MLP forward pass in pure Luau
      MLMatcher.lua                  ML classifier wrapping Inference
      SigilModel.lua                 generated weights (~88 KB, pasted from train.py)
      SignModel.lua                  generated weights
    Sigils/                          one module per sigil, self-registering
      Registry.lua, Fire.lua, Water.lua, Earth.lua, Wind.lua, ElementalVariants.lua
    Signs/
      Registry.lua, Column.lua, Levitation.lua
    Spells/
      Caster.lua                     evaluate / activate / glow lifecycle
      ElementalCombat.lua
    ClientEffects/                   VFX dispatched on cast
      Beam.lua, Explosion.lua, Shockwave.lua, Sustain.lua, MagicCombat.lua, Registry.lua
    VFX/AssetCatalog.lua
  StarterPlayerScripts/SpellClient.client.lua    canvas + input driver
  ServerScriptService/SpellServer.server.lua     authoritative cast handler

training/                            Python training pipeline
  train.py                           load templates → augment → train MLPs → quantize → emit Lua
  export_templates.luau              run in Studio's Command Bar to dump templates.json
  templates.json                     canonical 32×32 glyph for each registered sigil/sign
  requirements.txt                   torch, numpy

media/                               demo recordings
default.project.json                 Rojo project file (sync this repo into Studio)
CLAUDE.md                            architectural handoff notes (load-bearing details + gotchas)
```

## The model

Two MLPs — one for sigils, one for signs. Both are deliberately small:

```
input (32 × 32 = 1024)  →  Linear(64)  →  ReLU  →  Linear(C)  →  softmax
```

`C` is however many sigils or signs are registered, plus an `_other` reject class. I quantize both weight matrices to int8 per-tensor, base64 the bytes, and emit a Lua module. At runtime the inference module decodes them once into a Roblox `buffer` and runs a hand-rolled `linear → relu → softmax`. A forward pass is around 5 ms in Luau on a server, which is comfortably fast enough to run after every stroke.

I tried a few approaches before landing on this. Pure dilated-IoU template matching (still in the codebase as a fallback) works fine on the canonical templates but falls apart on real player drawings — people draw too small, too tilted, with extra wiggles. You can dilate harder to make IoU more forgiving, but then your distinct glyphs start matching each other and everything turns into "fire." A small classifier learns the right invariances cheaply, and the `_other` class lets it answer "that's nothing" instead of always picking the closest registered glyph.

## Training

`train.py` does the whole loop — load templates, augment, train, quantize, emit Lua.

The data flow is annoying because PyTorch obviously can't run inside Roblox, so it goes:

1. Paste `training/export_templates.luau` into Studio's Command Bar — it dumps the canonical 32×32 grid for every registered glyph as JSON.
2. Save that as `training/templates.json` and run `python train.py`.
3. Each canonical template gets blown up to 800 synthetic samples via random rotation (sigils ±25°, signs full ±180°), scale ±15%, ±3 cell translation, dilation, stroke-drop, and a bit of salt-and-pepper noise. The `_other` class gets generated from random lines, arcs, and blobs.
4. ~30 epochs later you get `SigilModel.lua` and `SignModel.lua`. Copy-paste those over the placeholder ModuleScripts in Studio. Yes, manually — the files are ~88 KB of base64 each, too big for any pipe-it-in approach I had patience for.

```
cd training
pip install -r requirements.txt
python train.py
```

## Adding a sigil

Mirror `src/SpellSystem/Sigils/Fire.lua`. Each sigil is one self-contained module that registers itself when required:

- `buildVisual(buf)` draws the canonical glyph into a `GridBuffer` using the Bresenham primitives.
- `buildTemplate()` renders a full ring + visual on a 64×64 canvas, runs the ring detector, and normalizes the inside-ink down to 32×32. The matcher is trained against this output, so it has to match what runtime inference will see.
- `onCast(ctx)` runs the server-side effects. `ctx.signs` tells you what's around the sigil so you can shape the spell.
- Optional `verify(normalized, raw) -> bool` for a per-class structural check. Fire's verifier rejects shapes that don't have a long enough vertical line through the middle, since the classifier sometimes confidently picks "fire" for a bare triangle.

Then re-export, retrain, and re-paste the model files.

## What was hard

A few things that took longer than I'd like to admit:

- **Getting the trained model into Roblox.** No HTTP for model downloads, no native model format, no easy way to ship binary data into a Lua runtime. I ended up quantizing to int8, base64-ing the bytes, and emitting a Lua table that gets manually pasted in. Not elegant, but it works and the inference is genuinely fast.
- **Splitting noisy drawings into sigil + signs without hardcoding positions.** The flood-fill ring detector plus 4-connected components handles this without me having to declare regions like "signs go in these four boxes." A sign sticking partway out of the ring still gets routed correctly because the matcher only sees inside-the-ring ink in the first place.
- **Saying no.** A naive classifier always returns *something*, but players draw garbage all the time. The `_other` reject class plus a confidence threshold catches most of it; the per-class verifiers catch the rest — cases where the classifier confidently picks the wrong glyph because two glyphs share a gross shape (a triangle alone vs. a fire glyph with a line through it).
- **Keeping training and inference in lockstep.** The Lua normalizer fills the longer axis to 100% of the target size. I had a Python `recenter` step in the data loader that was filling to 85%, and Wind's narrow S-curve was failing classification because the train-time and infer-time shapes were subtly off. Removing the Python recenter fixed it. There are a handful of these synchronization points and it's worth the discipline of writing them down.

For the deeper architectural notes — the gotchas, the design decisions I half-regretted, the pieces that almost got built differently — see [`CLAUDE.md`](CLAUDE.md).
