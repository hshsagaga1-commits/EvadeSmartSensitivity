-- EvadeSmartSensitivity v1.0
-- Adaptive camera sensitivity for touch/mobile.
-- Camera-only: does NOT write to HumanoidRootPart or alter movement controls.
-- Requires a client-side Lua environment that can execute LocalScripts APIs.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
assert(player, "Execute no cliente.")

local ENV = (type(getgenv) == "function" and getgenv()) or _G
local VERSION = "EvadeSmartSensitivity-1.0"
local GUI_NAME = "EvadeSmartSensitivityGui"
local RENDER_NAME = "EvadeSmartSensitivityRender"

local previousCleanup = ENV.__EvadeSmartSensitivityCleanup
if type(previousCleanup) == "function" then
    pcall(previousCleanup)
end

local enabled = true
local baseMultiplier = math.clamp(tonumber(ENV.ESS_Base) or 0.65, 0.25, 1.0)
local maxMultiplier = math.clamp(tonumber(ENV.ESS_Max) or 2.2, 1.0, 3.0)
local speedThreshold = math.clamp(tonumber(ENV.ESS_Threshold) or 1.35, 0.5, 3.0)
local smoothedSpeed = 0
local currentMultiplier = baseMultiplier
local lastRawCFrame
local lastOutputRotation
local lastCamera
local closed = false
local connections = {}
local gui, statusLabel, valueLabel, toggleButton
local panel

local function clamp(x, lo, hi)
    return math.max(lo, math.min(hi, x))
end

local function smoothstep(x)
    x = clamp(x, 0, 1)
    return x * x * (3 - 2 * x)
end

local function cleanup()
    if closed then return end
    closed = true
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(connections)
    pcall(function() RunService:UnbindFromRenderStep(RENDER_NAME) end)
    if gui then pcall(function() gui:Destroy() end) end
    ENV.__EvadeSmartSensitivityCleanup = nil
    ENV.EvadeSmartSensitivity = nil
end

local function makeCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 8)
    corner.Parent = parent
end

local function makeButton(parent, text, position, size, color)
    local button = Instance.new("TextButton")
    button.Position = position
    button.Size = size
    button.BackgroundColor3 = color
    button.BorderSizePixel = 0
    button.Text = text
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Font = Enum.Font.GothamSemibold
    button.TextSize = 12
    button.Parent = parent
    makeCorner(button, 7)
    return button
end

local function refresh()
    if not gui then return end
    if valueLabel then
        valueLabel.Text = string.format("Base %.2fx  |  Max %.2fx", baseMultiplier, maxMultiplier)
    end
    if statusLabel then
        statusLabel.Text = string.format("Velocidade: %.2f  |  Atual: %.2fx", smoothedSpeed, currentMultiplier)
    end
    if toggleButton then
        toggleButton.Text = enabled and "SENSIBILIDADE: ON" or "SENSIBILIDADE: OFF"
        toggleButton.BackgroundColor3 = enabled and Color3.fromRGB(38, 135, 88) or Color3.fromRGB(130, 58, 58)
    end
end

local playerGui = player:WaitForChild("PlayerGui")
for _, parent in ipairs({playerGui, game:GetService("CoreGui")}) do
    local stale = parent:FindFirstChild(GUI_NAME)
    if stale then pcall(function() stale:Destroy() end) end
end

gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000000
gui.Parent = playerGui

panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(260, 164)
panel.Position = UDim2.new(0.5, -130, 0.12, 0)
panel.BackgroundColor3 = Color3.fromRGB(22, 23, 28)
panel.BorderSizePixel = 0
panel.Active = true
panel.Parent = gui
makeCorner(panel, 12)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12, 7)
title.Size = UDim2.new(1, -24, 0, 24)
title.Text = "Evade Smart Sensitivity"
title.TextColor3 = Color3.fromRGB(245, 245, 250)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

valueLabel = Instance.new("TextLabel")
valueLabel.BackgroundTransparency = 1
valueLabel.Position = UDim2.fromOffset(12, 34)
valueLabel.Size = UDim2.new(1, -24, 0, 18)
valueLabel.TextColor3 = Color3.fromRGB(190, 195, 205)
valueLabel.Font = Enum.Font.Gotham
valueLabel.TextSize = 11
valueLabel.TextXAlignment = Enum.TextXAlignment.Left
valueLabel.Parent = panel

local baseDown = makeButton(panel, "Base -", UDim2.fromOffset(12, 59), UDim2.fromOffset(72, 27), Color3.fromRGB(63, 75, 100))
local baseUp = makeButton(panel, "Base +", UDim2.fromOffset(88, 59), UDim2.fromOffset(72, 27), Color3.fromRGB(63, 75, 100))
local maxDown = makeButton(panel, "Max -", UDim2.fromOffset(164, 59), UDim2.fromOffset(40, 27), Color3.fromRGB(90, 73, 115))
local maxUp = makeButton(panel, "Max +", UDim2.fromOffset(208, 59), UDim2.fromOffset(40, 27), Color3.fromRGB(90, 73, 115))

statusLabel = Instance.new("TextLabel")
statusLabel.BackgroundTransparency = 1
statusLabel.Position = UDim2.fromOffset(12, 91)
statusLabel.Size = UDim2.new(1, -24, 0, 17)
statusLabel.TextColor3 = Color3.fromRGB(180, 190, 205)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 10
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = panel

toggleButton = makeButton(panel, "SENSIBILIDADE: ON", UDim2.fromOffset(12, 116), UDim2.new(1, -24, 0, 32), Color3.fromRGB(38, 135, 88))
toggleButton.Activated:Connect(function()
    enabled = not enabled
    lastRawCFrame, lastOutputRotation = nil, nil
    refresh()
end)

baseDown.Activated:Connect(function()
    baseMultiplier = clamp(math.floor((baseMultiplier - 0.05) * 100 + 0.5) / 100, 0.25, 1.0)
    if baseMultiplier >= maxMultiplier then maxMultiplier = math.min(3.0, baseMultiplier + 0.1) end
    ENV.ESS_Base, ENV.ESS_Max = baseMultiplier, maxMultiplier
    refresh()
end)
baseUp.Activated:Connect(function()
    baseMultiplier = clamp(math.floor((baseMultiplier + 0.05) * 100 + 0.5) / 100, 0.25, 1.0)
    if baseMultiplier >= maxMultiplier then maxMultiplier = math.min(3.0, baseMultiplier + 0.1) end
    ENV.ESS_Base, ENV.ESS_Max = baseMultiplier, maxMultiplier
    refresh()
end)
maxDown.Activated:Connect(function()
    maxMultiplier = clamp(math.floor((maxMultiplier - 0.1) * 10 + 0.5) / 10, math.max(1.0, baseMultiplier + 0.1), 3.0)
    ENV.ESS_Base, ENV.ESS_Max = baseMultiplier, maxMultiplier
    refresh()
end)
maxUp.Activated:Connect(function()
    maxMultiplier = clamp(math.floor((maxMultiplier + 0.1) * 10 + 0.5) / 10, math.max(1.0, baseMultiplier + 0.1), 3.0)
    ENV.ESS_Base, ENV.ESS_Max = baseMultiplier, maxMultiplier
    refresh()
end)

-- Drag the panel using its top strip.
local dragging, dragStart, panelStart, dragInput = false, nil, nil, nil
connections[#connections + 1] = panel.InputBegan:Connect(function(input)
    if (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1)
        and input.Position.Y <= panel.AbsolutePosition.Y + 30 then
        dragging, dragStart, panelStart, dragInput = true, input.Position, panel.Position, input
    end
end)
connections[#connections + 1] = UserInputService.InputChanged:Connect(function(input)
    if dragging and dragStart and panelStart and
        (input == dragInput or input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
        local delta = input.Position - dragStart
        panel.Position = UDim2.new(panelStart.X.Scale, panelStart.X.Offset + delta.X, panelStart.Y.Scale, panelStart.Y.Offset + delta.Y)
    end
end)
connections[#connections + 1] = UserInputService.InputEnded:Connect(function(input)
    if dragInput and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
        dragging, dragStart, panelStart, dragInput = false, nil, nil, nil
    end
end)

-- Use the camera's frame-to-frame angular speed as a proxy for finger speed.
-- Fast flicks build sensitivity; a sharp left-right reversal remains responsive
-- because speed uses absolute angular displacement, not signed yaw direction.
connections[#connections + 1] = RunService.RenderStepped:Connect(function(dt)
    if closed then return end
    local camera = workspace.CurrentCamera
    if not camera or camera.CameraType ~= Enum.CameraType.Scriptable then
        lastCamera, lastRawCFrame, lastOutputRotation = camera, nil, nil
        if statusLabel then statusLabel.Text = camera and "Aguardando camera Scriptable" or "Aguardando camera..." end
        return
    end

    local current = camera.CFrame
    if camera ~= lastCamera then
        lastCamera, lastRawCFrame, lastOutputRotation = camera, current, current.Rotation
        return
    end

    if not lastRawCFrame or not lastOutputRotation then
        lastRawCFrame, lastOutputRotation = current, current.Rotation
        return
    end

    local deltaRotation = lastRawCFrame.Rotation:ToObjectSpace(current.Rotation)
    local axis, angle = deltaRotation:ToAxisAngle()
    if angle > math.rad(100) then
        -- Ignore teleports/camera snaps rather than amplifying them.
        lastRawCFrame, lastOutputRotation = current, current.Rotation
        smoothedSpeed = 0
        return
    end

    dt = clamp(dt, 1 / 240, 1 / 20)
    local angularSpeed = math.abs(angle) / dt
    local normalizedSpeed = angularSpeed / math.rad(240)
    local smoothing = 1 - math.exp(-dt * 10)
    smoothedSpeed = smoothedSpeed + (normalizedSpeed - smoothedSpeed) * smoothing

    local speedFactor = smoothstep((smoothedSpeed - 0.20) / speedThreshold)
    local targetMultiplier = baseMultiplier + (maxMultiplier - baseMultiplier) * speedFactor
    local multiplierSmoothing = 1 - math.exp(-dt * (targetMultiplier > currentMultiplier and 13 or 9))
    currentMultiplier = currentMultiplier + (targetMultiplier - currentMultiplier) * multiplierSmoothing

    if not enabled then
        currentMultiplier = 1
        camera.CFrame = current
        lastRawCFrame, lastOutputRotation = current, current.Rotation
        refresh()
        return
    end

    local outputRotation
    if angle > 0.000001 then
        outputRotation = lastOutputRotation * CFrame.fromAxisAngle(axis, angle * currentMultiplier)
    else
        outputRotation = lastOutputRotation
    end

    camera.CFrame = CFrame.new(current.Position) * outputRotation
    lastRawCFrame = current
    lastOutputRotation = outputRotation
    refresh()
end)

ENV.EvadeSmartSensitivity = {
    Version = VERSION,
    SetEnabled = function(value) enabled = value ~= false; lastRawCFrame, lastOutputRotation = nil, nil; refresh() end,
    SetBase = function(value) baseMultiplier = clamp(tonumber(value) or baseMultiplier, 0.25, 1.0); if baseMultiplier >= maxMultiplier then maxMultiplier = math.min(3.0, baseMultiplier + 0.1) end; refresh(); return baseMultiplier end,
    SetMax = function(value) maxMultiplier = clamp(tonumber(value) or maxMultiplier, math.max(1.0, baseMultiplier + 0.1), 3.0); refresh(); return maxMultiplier end,
    Cleanup = cleanup,
}
ENV.__EvadeSmartSensitivityCleanup = cleanup
refresh()
print("[EvadeSmartSensitivity] " .. VERSION .. " carregado. Camera-only; sem alterar o personagem.")
return ENV.EvadeSmartSensitivity
