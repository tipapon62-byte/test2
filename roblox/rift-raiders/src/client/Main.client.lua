-- Client bootstrap: loads the profile mirror, then starts every controller module.

local Client = script.Parent

local ClientData = require(Client:WaitForChild("Data"):WaitForChild("ClientData"))
ClientData.Init()
ClientData.WaitReady()

local controllers = Client:WaitForChild("Controllers")

for _, module in ipairs(controllers:GetChildren()) do
	if module:IsA("ModuleScript") then
		task.spawn(function()
			local ok, controller = pcall(require, module)
			if not ok then
				warn(("[Client] failed to load %s: %s"):format(module.Name, tostring(controller)))
				return
			end
			if type(controller) == "table" and type(controller.Start) == "function" then
				local started, err = pcall(controller.Start)
				if not started then
					warn(("[Client] %s.Start failed: %s"):format(module.Name, tostring(err)))
				end
			end
		end)
	end
end
