--!strict
-- Tiny MLP inference for sigil/sign classification.
-- Network: input(N*N) -> Linear(H) -> ReLU -> Linear(C) -> softmax
-- Weights are int8-quantized, base64-encoded, decoded once into a Roblox `buffer`.
--
-- Designed to be cheap enough to run server-side on every cast (~5–10 ms for
-- 1024->64->C with C<=8 in Luau on a modern Roblox server).

local GridBuffer = require(script.Parent.Parent.Canvas.GridBuffer)

local Inference = {}

-- ===== base64 decode (no external dependency) =====
local B64_LOOKUP: { [number]: number } = {}
do
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, #alphabet do
		B64_LOOKUP[string.byte(alphabet, i)] = i - 1
	end
end

local function b64decode(s: string): buffer
	local len = #s
	if len == 0 then return buffer.create(0) end
	assert(len % 4 == 0, "b64decode: length must be a multiple of 4")
	local pad = 0
	if string.sub(s, len, len) == "=" then pad = pad + 1 end
	if string.sub(s, len - 1, len - 1) == "=" then pad = pad + 1 end
	local outLen = (len // 4) * 3 - pad
	local buf = buffer.create(outLen)
	local pos = 0
	for i = 1, len, 4 do
		local a = B64_LOOKUP[string.byte(s, i)] or 0
		local b = B64_LOOKUP[string.byte(s, i + 1)] or 0
		local c = B64_LOOKUP[string.byte(s, i + 2)] or 0
		local d = B64_LOOKUP[string.byte(s, i + 3)] or 0
		local n = a * 262144 + b * 4096 + c * 64 + d
		if pos < outLen then
			buffer.writeu8(buf, pos, math.floor(n / 65536) % 256); pos = pos + 1
		end
		if pos < outLen then
			buffer.writeu8(buf, pos, math.floor(n / 256) % 256); pos = pos + 1
		end
		if pos < outLen then
			buffer.writeu8(buf, pos, n % 256); pos = pos + 1
		end
	end
	return buf
end

-- ===== model schema =====
export type LayerWeights = {
	rows: number,           -- output dim
	cols: number,           -- input dim
	scale: number,          -- dequant: float = scale * int8
	q: string,              -- base64 of rows*cols int8s, row-major
}

export type Model = {
	classes: { string },
	inputSize: number,      -- expected grid edge length (typically Config.TemplateResolution)
	w1: LayerWeights,
	b1: { number },
	w2: LayerWeights,
	b2: { number },
	-- decoded lazily on first predict
	_w1: buffer?,
	_w2: buffer?,
}

local function ensureDecoded(m: Model)
	if not m._w1 then m._w1 = b64decode(m.w1.q) end
	if not m._w2 then m._w2 = b64decode(m.w2.q) end
end

-- ===== flatten 2D grid to a length-(N*N) input vector (row-major, 0/1) =====
local function flatten(grid: GridBuffer.GridBuffer): { number }
	local N = grid.size
	local out = table.create(N * N, 0)
	local k = 1
	for y = 1, N do
		local row = grid.cells[y]
		for x = 1, N do
			out[k] = row[x] ~= 0 and 1 or 0
			k = k + 1
		end
	end
	return out
end

-- ===== y = (W * x) * scale + b ; W is rows x cols int8 in `buf` =====
local function linear(buf: buffer, rows: number, cols: number, scale: number,
                      bias: { number }, x: { number }, y: { number })
	for r = 0, rows - 1 do
		local acc = 0
		local base = r * cols
		for c = 0, cols - 1 do
			local w = buffer.readi8(buf, base + c)
			if w ~= 0 then
				acc = acc + w * x[c + 1]
			end
		end
		y[r + 1] = acc * scale + bias[r + 1]
	end
end

local function relu(v: { number })
	for i = 1, #v do
		if v[i] < 0 then v[i] = 0 end
	end
end

local function softmax(logits: { number }): { number }
	local mx = -math.huge
	for i = 1, #logits do
		if logits[i] > mx then mx = logits[i] end
	end
	local sum = 0
	local out = table.create(#logits, 0)
	for i = 1, #logits do
		local e = math.exp(logits[i] - mx)
		out[i] = e
		sum = sum + e
	end
	if sum > 0 then
		for i = 1, #out do out[i] = out[i] / sum end
	end
	return out
end

export type Result = {
	id: string,                       -- top class
	score: number,                    -- top class probability
	scores: { [string]: number },     -- full distribution
}

-- Predict against a normalized grid. Grid edge must equal model.inputSize.
-- Returns nil if the model is empty (untrained placeholder).
function Inference.predict(model: Model, grid: GridBuffer.GridBuffer): Result?
	if not model.classes or #model.classes == 0 then return nil end
	if grid.size ~= model.inputSize then
		warn(string.format("Inference.predict: grid size %d != model.inputSize %d", grid.size, model.inputSize))
		return nil
	end
	ensureDecoded(model)

	local x = flatten(grid)
	local hidden = table.create(model.w1.rows, 0)
	linear(model._w1 :: buffer, model.w1.rows, model.w1.cols, model.w1.scale, model.b1, x, hidden)
	relu(hidden)

	local logits = table.create(model.w2.rows, 0)
	linear(model._w2 :: buffer, model.w2.rows, model.w2.cols, model.w2.scale, model.b2, hidden, logits)
	local probs = softmax(logits)

	local bestI, bestP = 1, probs[1]
	for i = 2, #probs do
		if probs[i] > bestP then bestP = probs[i]; bestI = i end
	end

	local scores: { [string]: number } = {}
	for i, p in ipairs(probs) do scores[model.classes[i]] = p end

	return { id = model.classes[bestI], score = bestP, scores = scores }
end

return Inference
