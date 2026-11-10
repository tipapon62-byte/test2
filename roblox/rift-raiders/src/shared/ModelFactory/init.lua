-- ModelFactory: builds every creature, egg and prop procedurally from parts (no asset ids).
--
-- Every returned Model: PrimaryPart "Root" (anchored, invisible, non-colliding) at the bottom centre,
-- facing Root's -Z; all other parts unanchored + massless and joined with Motor6Ds named after their
-- Part1, so `model:PivotTo(groundCFrame)` places it and the client animates via Motor6D.Transform.
-- Models are built at the origin and returned unparented; no tags or scripts are added.

local GameConfig = require(script.Parent.GameConfig)
local Mutation = require(script.Mutation)
local Pet = require(script.Pet)
local Egg = require(script.Egg)
local Guardian = require(script.Guardian)
local Props = require(script.Props)

local ModelFactory = {}

export type PetOpts = { Size: string?, Mutation: string?, Tier: number? }
export type EggOpts = { Size: string?, Mutation: string? }

function ModelFactory.BuildPet(speciesId: string, opts: PetOpts?): Model
	return Pet.Build(speciesId, opts)
end

function ModelFactory.BuildEgg(biomeId: string, rarity: string, opts: EggOpts?): Model
	return Egg.Build(biomeId, rarity, opts)
end

function ModelFactory.BuildGuardian(biomeId: string): Model
	return Guardian.Build(biomeId)
end

-- Attribute "PadTopY": height above Root where an egg's bottom sits.
function ModelFactory.BuildIncubator(): Model
	return Props.Incubator()
end

function ModelFactory.BuildFuseMachine(): Model
	return Props.FuseMachine()
end

-- Has a part named "Screen" (front face = -Z) for a server-side SurfaceGui.
function ModelFactory.BuildShopTerminal(): Model
	return Props.ShopTerminal()
end

function ModelFactory.BuildBearTrap(): Model
	return Props.BearTrap()
end

function ModelFactory.SetTrapClosed(model: Model, closed: boolean)
	Props.SetTrapClosed(model, closed)
end

-- Part "Handle" = grip centre; the bat extends along Handle's +Y axis.
function ModelFactory.BuildFoamBat(): Model
	return Props.FoamBat()
end

function ModelFactory.ApplyMutation(model: Model, mutationId: string?)
	Mutation.Apply(model, mutationId)
end

local TRAIL_NAME = "RR_Trail"
local A0_NAME, A1_NAME = "RR_TrailTop", "RR_TrailBottom"

-- Replaces the character's trail. Returns nil (and removes any trail) for "None" or unknown ids.
function ModelFactory.MakeTrail(character: Model, trailId: string): Trail?
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return nil
	end
	for _, name in { TRAIL_NAME, A0_NAME, A1_NAME } do
		local old = hrp:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local cfg = GameConfig.Economy.Trails[trailId]
	if not cfg or trailId == "None" then
		return nil
	end
	local colors = cfg.Colors or { Color3.new(1, 1, 1) }
	local a0 = Instance.new("Attachment")
	a0.Name = A0_NAME
	a0.Position = Vector3.new(0, 0.9, 0.45)
	a0.Parent = hrp
	local a1 = Instance.new("Attachment")
	a1.Name = A1_NAME
	a1.Position = Vector3.new(0, -0.9, 0.45)
	a1.Parent = hrp
	local trail = Instance.new("Trail")
	trail.Name = TRAIL_NAME
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(colors[1], colors[2] or colors[1])
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.7, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new(1, 0.25)
	trail.Lifetime = 0.55
	trail.MinLength = 0.1
	trail.LightEmission = 0.7
	trail.LightInfluence = 0.3
	trail.FaceCamera = true
	trail.Parent = hrp
	return trail
end

return ModelFactory
