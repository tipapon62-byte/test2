-- SignService: any part with a "SignText" StringValue gets a floating label
-- (optional "SignColor" Color3Value and "SignSize" NumberValue = height in studs).
-- Labels update live when SignText changes (BiomeService renames zone titles at boot).
local SignService = {}

local function makeSign(part: BasePart)
	local textValue = part:FindFirstChild("SignText") :: StringValue?
	if not textValue or part:FindFirstChild("SignGui") then
		return
	end
	local colorValue = part:FindFirstChild("SignColor") :: Color3Value?
	local sizeValue = part:FindFirstChild("SignSize") :: NumberValue?
	local h = if sizeValue then sizeValue.Value else 5
	local bb = Instance.new("BillboardGui")
	bb.Name = "SignGui"
	bb.Size = UDim2.new(h * 6, 0, h, 0)
	bb.StudsOffset = Vector3.new(0, part.Size.Y / 2 + h / 2 + 0.5, 0)
	bb.MaxDistance = 500
	bb.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextStrokeTransparency = 0
	label.Parent = bb
	local function refresh()
		label.Text = textValue.Value
		label.TextColor3 = if colorValue then colorValue.Value else Color3.new(1, 1, 1)
	end
	refresh()
	textValue.Changed:Connect(refresh)
	if colorValue then
		colorValue.Changed:Connect(refresh)
	end
	bb.Parent = part
end

function SignService.Start()
	task.defer(function()
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") then
				makeSign(d)
			end
		end
	end)
end

return SignService
