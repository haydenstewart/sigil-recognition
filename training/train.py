"""
Sigil/sign classifier training.

Pipeline:
  templates.json (exported from Studio)  ->  synthetic dataset
  ->  train two small MLPs (1024 -> 64 -> N)
  ->  int8-quantize the weight matrices
  ->  emit SigilModel.lua and SignModel.lua

Run:
  pip install torch numpy
  python train.py

Outputs (next to this script):
  SigilModel.lua, SignModel.lua  -- paste contents over the placeholder
                                     ModuleScripts in ReplicatedStorage.SpellSystem.Recognition.
"""

from __future__ import annotations

import base64
import json
import math
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

# ---------- knobs ----------
GRID_SIZE = 32                     # must equal Roblox Config.TemplateResolution
HIDDEN = 64
SAMPLES_PER_CLASS = 800
OTHER_SAMPLES_MULT = 1.5           # _other class gets 1.5x more samples
EPOCHS = 30
BATCH = 64
LR = 1e-3
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

OTHER_ID = "_other"

ROOT = Path(__file__).resolve().parent
TEMPLATES_PATH = ROOT / "templates.json"


# ---------- template loader ----------
def load_templates(path: Path) -> tuple[dict, dict]:
    """Returns (sigils_dict, signs_dict). Each entry: {id: {"grid": np.ndarray (H,W) uint8, "rotationInvariant": bool}}."""
    with open(path, "r", encoding="utf-8") as f:
        raw = json.load(f)

    def parse(group: dict) -> dict:
        out = {}
        for sid, entry in group.items():
            bits = entry["bits"]
            size = entry["size"]
            assert len(bits) == size and all(len(r) == size for r in bits), f"{sid}: bad shape"
            grid = np.zeros((size, size), dtype=np.uint8)
            for y in range(size):
                for x in range(size):
                    if bits[y][x] == "1":
                        grid[y, x] = 1
            # NOTE: do NOT recenter here. The templates were already produced by Lua's
            # Normalizer which fills the longer axis to 100% of GRID_SIZE. Re-running
            # recenter (which fills only ~85%) introduces a scale mismatch between
            # training data and what inference produces, and the model fails on
            # narrow shapes like Wind's S-curve.
            assert grid.shape == (GRID_SIZE, GRID_SIZE), f"{sid}: expected {GRID_SIZE}x{GRID_SIZE}, got {grid.shape}"
            out[sid] = {
                "grid": grid,
                "rotationInvariant": entry.get("rotationInvariant", False),
            }
        return out

    return parse(raw["sigils"]), parse(raw["signs"])


def bbox(grid: np.ndarray) -> tuple[int, int, int, int] | None:
    ys, xs = np.where(grid > 0)
    if len(xs) == 0:
        return None
    return ys.min(), xs.min(), ys.max(), xs.max()


def recenter(grid: np.ndarray, target: int) -> np.ndarray:
    """Crop to bbox, scale to fit the larger axis into `target`, paste centered."""
    bb = bbox(grid)
    if bb is None:
        return np.zeros((target, target), dtype=np.uint8)
    y0, x0, y1, x1 = bb
    h = y1 - y0 + 1
    w = x1 - x0 + 1
    crop = grid[y0:y1 + 1, x0:x1 + 1]
    span = max(h, w)
    out = np.zeros((target, target), dtype=np.uint8)
    # scale crop so span fits into ~ 0.85 * target (leave a little margin)
    target_span = int(round(target * 0.85))
    scale = target_span / span
    new_h = max(1, int(round(h * scale)))
    new_w = max(1, int(round(w * scale)))
    resampled = nearest_resize(crop, new_h, new_w)
    oy = (target - new_h) // 2
    ox = (target - new_w) // 2
    out[oy:oy + new_h, ox:ox + new_w] = resampled
    return out


def nearest_resize(grid: np.ndarray, new_h: int, new_w: int) -> np.ndarray:
    h, w = grid.shape
    ys = (np.linspace(0, h - 1, new_h)).round().astype(int)
    xs = (np.linspace(0, w - 1, new_w)).round().astype(int)
    return grid[ys][:, xs]


# ---------- augmentations ----------
def rotate(grid: np.ndarray, angle_deg: float) -> np.ndarray:
    """Inverse-mapping nearest-neighbor rotation around center."""
    h, w = grid.shape
    cy, cx = h / 2, w / 2
    ang = math.radians(angle_deg)
    c, s = math.cos(-ang), math.sin(-ang)
    out = np.zeros_like(grid)
    for ty in range(h):
        for tx in range(w):
            dx = tx - cx
            dy = ty - cy
            sx = int(round(c * dx - s * dy + cx))
            sy = int(round(s * dx + c * dy + cy))
            if 0 <= sx < w and 0 <= sy < h:
                out[ty, tx] = grid[sy, sx]
    return out


def dilate(grid: np.ndarray, r: int) -> np.ndarray:
    if r <= 0:
        return grid.copy()
    out = grid.copy()
    h, w = grid.shape
    ys, xs = np.where(grid > 0)
    r2 = r * r
    for y, x in zip(ys, xs):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if dx * dx + dy * dy <= r2:
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w:
                        out[ny, nx] = 1
    return out


def translate(grid: np.ndarray, dy: int, dx: int) -> np.ndarray:
    out = np.zeros_like(grid)
    h, w = grid.shape
    ys, xs = np.where(grid > 0)
    for y, x in zip(ys, xs):
        ny, nx = y + dy, x + dx
        if 0 <= ny < h and 0 <= nx < w:
            out[ny, nx] = 1
    return out


def scale(grid: np.ndarray, factor: float) -> np.ndarray:
    """Scale the on-cells around the centroid."""
    if abs(factor - 1.0) < 1e-3:
        return grid.copy()
    h, w = grid.shape
    ys, xs = np.where(grid > 0)
    if len(xs) == 0:
        return grid.copy()
    cy, cx = ys.mean(), xs.mean()
    out = np.zeros_like(grid)
    for y, x in zip(ys, xs):
        ny = int(round(cy + (y - cy) * factor))
        nx = int(round(cx + (x - cx) * factor))
        if 0 <= ny < h and 0 <= nx < w:
            out[ny, nx] = 1
    return out


def drop_strokes(grid: np.ndarray, frac: float) -> np.ndarray:
    if frac <= 0:
        return grid.copy()
    out = grid.copy()
    ys, xs = np.where(grid > 0)
    if len(xs) == 0:
        return out
    keep = np.random.rand(len(xs)) > frac
    out[:, :] = 0
    yy = ys[keep]
    xx = xs[keep]
    out[yy, xx] = 1
    return out


def speckle(grid: np.ndarray, p_on: float, p_off: float) -> np.ndarray:
    out = grid.copy()
    h, w = grid.shape
    if p_on > 0:
        mask = np.random.rand(h, w) < p_on
        out = np.where(mask | (out > 0), 1, 0).astype(np.uint8)
    if p_off > 0:
        mask = np.random.rand(h, w) < p_off
        out = np.where(mask & (out > 0), 0, out).astype(np.uint8)
    return out


def augment(grid: np.ndarray, rot_range_deg: float) -> np.ndarray:
    """Apply a random combination of augmentations. `rot_range_deg`: half-range (e.g. 25 = ±25°, 180 = full)."""
    g = grid
    if rot_range_deg > 0:
        g = rotate(g, np.random.uniform(-rot_range_deg, rot_range_deg))
    if np.random.rand() < 0.7:
        g = scale(g, np.random.uniform(0.85, 1.15))
    if np.random.rand() < 0.7:
        g = translate(g, np.random.randint(-3, 4), np.random.randint(-3, 4))
    g = dilate(g, np.random.choice([0, 1, 2], p=[0.45, 0.4, 0.15]))
    if np.random.rand() < 0.4:
        g = drop_strokes(g, np.random.uniform(0.03, 0.12))
    g = speckle(g, p_on=np.random.uniform(0, 0.005), p_off=np.random.uniform(0, 0.02))
    return g


# ---------- random scribbles for the _other class ----------
def random_line(grid: np.ndarray) -> None:
    h, w = grid.shape
    y0 = np.random.randint(2, h - 2)
    x0 = np.random.randint(2, w - 2)
    y1 = np.random.randint(2, h - 2)
    x1 = np.random.randint(2, w - 2)
    n = max(abs(y1 - y0), abs(x1 - x0)) + 1
    for t in np.linspace(0, 1, n):
        y = int(round(y0 + (y1 - y0) * t))
        x = int(round(x0 + (x1 - x0) * t))
        if 0 <= y < h and 0 <= x < w:
            grid[y, x] = 1


def random_arc(grid: np.ndarray) -> None:
    h, w = grid.shape
    cy = np.random.randint(8, h - 8)
    cx = np.random.randint(8, w - 8)
    r = np.random.randint(3, 10)
    a0 = np.random.uniform(0, 2 * math.pi)
    span = np.random.uniform(math.pi / 3, 7 * math.pi / 4)
    n = int(r * span * 1.5) + 4
    for t in np.linspace(0, 1, n):
        a = a0 + span * t
        y = int(round(cy + math.sin(a) * r))
        x = int(round(cx + math.cos(a) * r))
        if 0 <= y < h and 0 <= x < w:
            grid[y, x] = 1


def random_blob(grid: np.ndarray) -> None:
    h, w = grid.shape
    n = np.random.randint(8, 30)
    cy = np.random.randint(6, h - 6)
    cx = np.random.randint(6, w - 6)
    for _ in range(n):
        y = cy + np.random.randint(-4, 5)
        x = cx + np.random.randint(-4, 5)
        if 0 <= y < h and 0 <= x < w:
            grid[y, x] = 1


def make_other(rng: random.Random) -> np.ndarray:
    """Generate a random scribble that should NOT match any sigil/sign."""
    g = np.zeros((GRID_SIZE, GRID_SIZE), dtype=np.uint8)
    for _ in range(rng.randint(1, 4)):
        kind = rng.random()
        if kind < 0.5:
            random_line(g)
        elif kind < 0.85:
            random_arc(g)
        else:
            random_blob(g)
    g = dilate(g, rng.choice([0, 1, 2]))
    return g


# ---------- dataset builder ----------
@dataclass
class Dataset:
    X: np.ndarray   # (N, 1024) float32
    y: np.ndarray   # (N,)       int64
    classes: list[str]


def build_dataset(templates: dict, *, rot_range_deg: float, label: str) -> Dataset:
    rng = random.Random(42)
    np.random.seed(42)
    classes = list(templates.keys()) + [OTHER_ID]
    X_chunks, y_chunks = [], []

    for ci, cname in enumerate(classes):
        if cname == OTHER_ID:
            samples = [make_other(rng) for _ in range(int(SAMPLES_PER_CLASS * OTHER_SAMPLES_MULT))]
        else:
            base = templates[cname]["grid"]
            samples = [augment(base, rot_range_deg) for _ in range(SAMPLES_PER_CLASS)]
        X_chunks.append(np.stack(samples).reshape(len(samples), -1).astype(np.float32))
        y_chunks.append(np.full(len(samples), ci, dtype=np.int64))

    X = np.concatenate(X_chunks, axis=0)
    y = np.concatenate(y_chunks, axis=0)

    perm = np.random.permutation(len(y))
    X = X[perm]
    y = y[perm]
    print(f"[{label}] dataset: {len(y)} samples across {len(classes)} classes -> {classes}")
    return Dataset(X=X, y=y, classes=classes)


# ---------- model ----------
class MLP(nn.Module):
    def __init__(self, in_dim: int, hidden: int, n_classes: int):
        super().__init__()
        self.fc1 = nn.Linear(in_dim, hidden)
        self.fc2 = nn.Linear(hidden, n_classes)

    def forward(self, x):
        return self.fc2(F.relu(self.fc1(x)))


def train(ds: Dataset, label: str) -> MLP:
    n_classes = len(ds.classes)
    model = MLP(GRID_SIZE * GRID_SIZE, HIDDEN, n_classes).to(DEVICE)
    opt = torch.optim.Adam(model.parameters(), lr=LR)

    X = torch.from_numpy(ds.X).to(DEVICE)
    y = torch.from_numpy(ds.y).to(DEVICE)
    n = len(y)

    for epoch in range(EPOCHS):
        perm = torch.randperm(n, device=DEVICE)
        total_loss = 0.0
        correct = 0
        for i in range(0, n, BATCH):
            idx = perm[i:i + BATCH]
            xb = X[idx]
            yb = y[idx]
            logits = model(xb)
            loss = F.cross_entropy(logits, yb)
            opt.zero_grad()
            loss.backward()
            opt.step()
            total_loss += loss.item() * len(idx)
            correct += (logits.argmax(1) == yb).sum().item()
        if epoch == 0 or (epoch + 1) % 5 == 0 or epoch == EPOCHS - 1:
            print(f"[{label}] epoch {epoch+1:2d}/{EPOCHS}  loss={total_loss/n:.4f}  acc={correct/n:.3f}")
    return model


# ---------- quantize + emit Lua ----------
def quantize_int8(W: np.ndarray) -> tuple[np.ndarray, float]:
    """Per-tensor symmetric int8 quantization. Returns (int8_array, scale)."""
    m = float(np.max(np.abs(W)))
    if m == 0:
        return np.zeros_like(W, dtype=np.int8), 1.0
    scale = m / 127.0
    q = np.round(W / scale).clip(-127, 127).astype(np.int8)
    return q, scale


def emit_lua_model(model: MLP, classes: list[str], out_path: Path) -> None:
    W1 = model.fc1.weight.detach().cpu().numpy()  # (H, 1024)
    b1 = model.fc1.bias.detach().cpu().numpy()    # (H,)
    W2 = model.fc2.weight.detach().cpu().numpy()  # (C, H)
    b2 = model.fc2.bias.detach().cpu().numpy()    # (C,)

    q1, s1 = quantize_int8(W1)
    q2, s2 = quantize_int8(W2)

    # int8 -> raw bytes (little/big doesn't matter, single bytes) -> base64
    q1_b64 = base64.b64encode(q1.astype(np.int8).tobytes()).decode("ascii")
    q2_b64 = base64.b64encode(q2.astype(np.int8).tobytes()).decode("ascii")

    def fmt_bias(arr: np.ndarray) -> str:
        return ", ".join(f"{v:.6f}" for v in arr.tolist())

    classes_lua = ", ".join(f"\"{c}\"" for c in classes)

    lua = f'''--!strict
-- AUTO-GENERATED by sigil_training/train.py. Do not edit by hand --
-- changes will be overwritten the next time training runs.

return {{
\tclasses   = {{ {classes_lua} }},
\tinputSize = {GRID_SIZE},
\tw1 = {{ rows = {W1.shape[0]}, cols = {W1.shape[1]}, scale = {s1:.10g}, q = "{q1_b64}" }},
\tb1 = {{ {fmt_bias(b1)} }},
\tw2 = {{ rows = {W2.shape[0]}, cols = {W2.shape[1]}, scale = {s2:.10g}, q = "{q2_b64}" }},
\tb2 = {{ {fmt_bias(b2)} }},
}}
'''
    out_path.write_text(lua, encoding="utf-8")
    size_kb = out_path.stat().st_size / 1024
    print(f"  wrote {out_path.name}  ({size_kb:.1f} KB, {len(classes)} classes)")


# ---------- main ----------
def main() -> None:
    if not TEMPLATES_PATH.exists():
        raise SystemExit(
            f"templates.json not found at {TEMPLATES_PATH}\n"
            "Paste export_templates.luau into Studio's Command Bar, copy the printed\n"
            "JSON, save it as templates.json next to this script, then re-run."
        )

    sigils, signs = load_templates(TEMPLATES_PATH)
    print(f"loaded {len(sigils)} sigils + {len(signs)} signs from templates.json")
    print(f"device: {DEVICE}")

    if sigils:
        print("\n=== training sigil model ===")
        ds = build_dataset(sigils, rot_range_deg=25, label="sigil")
        model = train(ds, "sigil")
        emit_lua_model(model, ds.classes, ROOT / "SigilModel.lua")

    if signs:
        print("\n=== training sign model ===")
        # Signs train with FULL rotation augmentation (any rotation invariant => full circle).
        # Signs that are NOT rotation-invariant still use full circle here, because MLMatcher
        # recovers direction by rotating the input at inference time, not from the prediction.
        ds = build_dataset(signs, rot_range_deg=180, label="sign")
        model = train(ds, "sign")
        emit_lua_model(model, ds.classes, ROOT / "SignModel.lua")

    print("\nDone. Paste the contents of SigilModel.lua / SignModel.lua over the placeholder")
    print("ModuleScripts at ReplicatedStorage.SpellSystem.Recognition.{SigilModel,SignModel}.")


if __name__ == "__main__":
    main()
