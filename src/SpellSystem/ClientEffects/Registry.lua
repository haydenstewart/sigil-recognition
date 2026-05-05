--!strict
-- Client-only registry of playable VFX. Each effect module registers itself at require time.
-- Server sends an Effect event with { id = "explosion", origin = Vector3, ... }; the client looks up
-- the registered function and plays it. Adding a new effect = drop a ModuleScript in ClientEffects/.

local Registry = {}

export type EffectArgs = {
	origin: Vector3,
	direction: Vector3?,
	power: number?,
	radius: number?,
	paper: BasePart?,
	[string]: any,
}

export type EffectFn = (EffectArgs) -> ()

local fns: { [string]: EffectFn } = {}

function Registry.register(id: string, fn: EffectFn)
	assert(type(id) == "string" and type(fn) == "function", "bad effect registration")
	fns[id] = fn
end

function Registry.play(id: string, args: EffectArgs)
	local fn = fns[id]
	if not fn then
		warn("[ClientEffects] unknown effect id: " .. tostring(id))
		return
	end
	local ok, err = pcall(fn, args)
	if not ok then
		warn("[ClientEffects] " .. id .. " errored: " .. tostring(err))
	end
end

function Registry.loadAll()
	local parent = script.Parent
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("ModuleScript") and child ~= script then
			require(child)
		end
	end
end

return Registry
