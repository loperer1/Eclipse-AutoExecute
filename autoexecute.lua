-- Environment Compatibility & Obfuscator Protection
print('[ECLIPSE] Script loading...')
local getgenv = (type(getgenv) == "function" and getgenv) or function() return _G end
local hookmetamethod = (type(hookmetamethod) == "function" and hookmetamethod) or function() return function() end end
local getnamecallmethod = (type(getnamecallmethod) == "function" and getnamecallmethod) or function() return "" end
local checkcaller = (type(checkcaller) == "function" and checkcaller) or function() return false end

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local localPlayer = Players.LocalPlayer
local VirtualUser = game:GetService("VirtualUser")

-- Wait for the game to fully load before running any script logic
if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- Singleton Enforcement: Prevents the script from executing multiple times 
-- (e.g., when the script fires multiple times on a server hop).
local executionId = tick()
getgenv()._eclipse2_execution_id = executionId
task.wait(0.5) -- Debounce window to catch simultaneous loads
if getgenv()._eclipse2_execution_id ~= executionId then
    warn("Eclipse: Redundant execution attempt blocked.")
    return
end


-- Anti-AFK Implementation (guarded â€” hookmetamethod can't be undone, don't stack it)
if not getgenv()._eclipse2_afk then
    getgenv()._eclipse2_afk = true
    localPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Hooks run once per executor session â€” calling hookmetamethod again stacks hooks
if not getgenv()._eclipse2_hooked then
    getgenv()._eclipse2_hooked = true

    for _, script in pairs(localPlayer.PlayerScripts:GetDescendants()) do
        if script:IsA("LocalScript") and (script.Name:match("\n") or script.Name:match("\a")) then
            script:Destroy()
        end
    end

    local _hEvents = ReplicatedStorage:WaitForChild("events", 5)
    local _hCS     = _hEvents and _hEvents:FindFirstChild("ClientSignal")

    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if method == "Kick" then
            if self == localPlayer then
                warn("[ECLIPSE] Blocked Kick call")
                return
            end
        elseif method == "FireServer" then
            if _hCS and self == _hCS then return end
        end
        return oldNamecall(self, ...)
    end)

    -- Fallback anti-kick: hook Player:Kick directly as a method
    local oldKick
    oldKick = hookmetamethod(localPlayer, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if method == "Kick" then
            warn("[ECLIPSE] Blocked direct Kick")
            return
        end
        return oldKick(self, ...)
    end)

    local oldIndex
    oldIndex = hookmetamethod(game, "__index", function(self, key)
        if key == "WalkSpeed" or key == "Health" or key == "JumpHeight" then
            if not checkcaller() and self:IsA("Humanoid") and self:IsDescendantOf(localPlayer.Character or workspace) then
                local real = oldIndex(self, key)
                if key == "WalkSpeed" and real >= 30 then return 16 end
                if key == "Health" and real > 100 then return 100 end
                if key == "JumpHeight" and real >= 8.1 then return 7.2 end
            end
        end
        return oldIndex(self, key)
    end)
end

local function resetCamera()
    pcall(function()
        local cam = workspace.CurrentCamera
        if cam then
            cam.CameraType = Enum.CameraType.Custom
            local char = localPlayer.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then cam.CameraSubject = hum end
            end
        end
    end)
end

local function getCharHeightOffset(char)
    local hum = char and char:FindFirstChild("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if hum and root then
        if hum.RigType == Enum.HumanoidRigType.R15 then
            return hum.HipHeight + (root.Size.Y / 2)
        end
    end
    return 3 -- Default standard height
end

-- Everything below runs fresh on every server (new GUI, new state, new loops)
print('[ECLIPSE] Top-level code OK, starting main...')
local function eclipse_main()

-- Cleanup previous execution
if getgenv().eclipse_autofarm2_cleanup then
    pcall(getgenv().eclipse_autofarm2_cleanup)
    task.wait(0.2)
end
resetCamera()



local _autofarmEnabled = false

-- FLY LOGIC INJECTION
local function maintainFlyState()
    local char = localPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    
    if _autofarmEnabled then
        local bv = root:FindFirstChild("AutoFarmVelocity")
        if not bv then
            bv = Instance.new("BodyVelocity")
            bv.Name = "AutoFarmVelocity"
            bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bv.Velocity = Vector3.new(0, 0, 0)
            bv.Parent = root
        end
        local bg = root:FindFirstChild("AutoFarmGyro")
        if not bg then
            bg = Instance.new("BodyGyro")
            bg.Name = "AutoFarmGyro"
            bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
            bg.CFrame = root.CFrame
            bg.P = 30000
            bg.Parent = root
        else
            -- keep gyro updated to current rotation so they don't snap back
            bg.CFrame = root.CFrame
        end
    else
        local bv = root:FindFirstChild("AutoFarmVelocity")
        if bv then bv:Destroy() end
        local bg = root:FindFirstChild("AutoFarmGyro")
        if bg then bg:Destroy() end
    end
end

-- Hook into RenderStepped to continuously enforce the fly state if they respawn
game:GetService("RunService").RenderStepped:Connect(function()
    if _autofarmEnabled then
        maintainFlyState()
    end
end)
local _autofarmRunning = true
local _autoHopEnabled = false
local _potatoMode = false
local _isBusy = false
local _isWaiting = false
local _clusterActive = false
local _startHolding = false  -- locks player at start position until first placement
local _holdId = 0            -- increment to kill any stale hold loops
local _startCF = nil
local activeConnections = {}

-- Webhook configuration & Persistence
local SETTINGS_FILE = "Eclipse/autofarm2_settings.json"
local WEBHOOK_URL = getgenv().eclipse2_webhook or ""
local WEBHOOK_ENABLED = getgenv().eclipse2_webhook_enabled or false

local probesPlaced      = 0
local probesRecovered   = 0
local probesDestroyed   = 0
local stormsTargeted    = 0
local deathsCount       = 0
local teleportCount     = 0
local SEND_INTERVAL     = 60   -- Webhook sends every 60 seconds
local _lastPlacementTime = 0  -- prevents pickup immediately after placement


local _stagingPlatform = nil
getgenv().eclipse_autofarm2_cleanup = function()
    _autofarmRunning = false
    _autofarmEnabled = false
    _startHolding = false
    if _stagingPlatform then pcall(function() _stagingPlatform:Destroy() end) _stagingPlatform = nil end
    for _, conn in pairs(activeConnections) do
        if conn and conn.Disconnect then pcall(function() conn:Disconnect() end) end
    end
    table.clear(activeConnections)
    pcall(function()
        local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root then root.Anchored = false end
    end)
    resetCamera()
end



local sessionTimeAccumulated = 0
local currentSessionStart = 0
local function getActiveSessionTime()
    if _autofarmEnabled and currentSessionStart > 0 then
        return sessionTimeAccumulated + (tick() - currentSessionStart)
    end
    return sessionTimeAccumulated
end

local _stormHeights = {}
local velocities = {}
local lastPositions = {}
local _isHopping = false
local function saveSettings()
    local data = {
        sessionTime = getActiveSessionTime(),
        moneyStart = sessionMoneyStart,
        probesPlaced = probesPlaced,
        probesRecovered = probesRecovered,
        probesDestroyed = probesDestroyed,
        deaths = deathsCount,
        hops = teleportCount,
        webhookUrl = WEBHOOK_URL,
        autoHop = _autoHopEnabled,
        isHopping = _isHopping
    }
    pcall(function()
        if not isfolder("Eclipse") then makefolder("Eclipse") end
        writefile(SETTINGS_FILE, HttpService:JSONEncode(data))
    end)
end

local function loadSettings()
    pcall(function()
        if isfile(SETTINGS_FILE) then
            local data = HttpService:JSONDecode(readfile(SETTINGS_FILE))
            
            -- Session stats should ONLY persist if we are automatically server hopping
            if data.isHopping then
                sessionTimeAccumulated = data.sessionTime or 0
                sessionMoneyStart = data.moneyStart
                probesPlaced = data.probesPlaced or 0
                probesRecovered = data.probesRecovered or 0
                probesDestroyed = data.probesDestroyed or 0
                deathsCount = data.deaths or 0
                teleportCount = data.hops or 0
                
                _isHopping = false
                -- Immediately save to clear the hopping flag
                task.spawn(saveSettings) 
            else
                -- Manual rejoin/execution -> Reset all session tracking!
                sessionTimeAccumulated = 0
                sessionMoneyStart = nil
                probesPlaced = 0
                probesRecovered = 0
                probesDestroyed = 0
                deathsCount = 0
                teleportCount = 0
                -- Clear graph history
                getgenv().eclipse2_money_history = nil
            end
            
            -- These configuration settings persist regardless of session
            WEBHOOK_URL = data.webhookUrl or ""
            _autoHopEnabled = false -- Temporarily disabled: data.autoHop or false
            
            getgenv().eclipse2_session_time = sessionTimeAccumulated
            getgenv().eclipse2_session_money = sessionMoneyStart
        end
    end)
end

loadSettings()

local lastPositions = {}
local velocities = {}
local VEHICLE_NAME  = "91TERRITORY-SCOUT" -- User's primary vehicle
local PROBE_TARGET  = 4                   -- Total probes to maintain at all times
local START_POS     = Vector3.new(-25904.4, 2.5, -25592.4)  -- Safe staging position (Under Map)


-- Fullbright & No Fog Automation (Elite Version)
local brightLoop
local function startFullbright()
    if brightLoop then brightLoop:Disconnect() end
    -- RenderStepped is most aggressive; runs before frame is drawn
    brightLoop = game:GetService("RunService").RenderStepped:Connect(function()
        pcall(function()
            local Lighting = game:GetService("Lighting")
            Lighting.Brightness = 2
            Lighting.ClockTime = 14
            Lighting.FogEnd = 100000
            Lighting.GlobalShadows = false
            Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
            Lighting.EnvironmentDiffuseScale = 1
            Lighting.EnvironmentSpecularScale = 1
            
            local atmos = Lighting:FindFirstChildWhichIsA("Atmosphere")
            if atmos then atmos.Density = 0 end
            
            local bloom = Lighting:FindFirstChildWhichIsA("BloomEffect")
            if bloom then bloom.Enabled = false end
        end)
    end)
end

task.spawn(startFullbright)

if CoreGui:FindFirstChild("TornadoAutofarmUI2") then CoreGui.TornadoAutofarmUI2:Destroy() end
local UI = Instance.new("ScreenGui"); UI.Name = "TornadoAutofarmUI2"; UI.Parent = CoreGui; UI.ResetOnSpawn = false

-- Pre-declare UI variables for scope
local MainFrame, ShowBtn, buildAndSend, ConsoleFrame -- Added ConsoleFrame

-- â”€â”€ STARTUP WARNING UI â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local WarnFrame = Instance.new("Frame")
WarnFrame.Name = "WarningModal"
WarnFrame.Size = UDim2.new(0, 400, 0, 300) -- INCREASED SIZE for Discord section
WarnFrame.Position = UDim2.new(0.5, -200, 0.5, -150)
WarnFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
WarnFrame.BorderSizePixel = 0
WarnFrame.ZIndex = 100
WarnFrame.Parent = UI
Instance.new("UICorner", WarnFrame).CornerRadius = UDim.new(0, 8)
local WarnStroke = Instance.new("UIStroke", WarnFrame)
WarnStroke.Color = Color3.fromRGB(255, 255, 255) -- WHITE OUTLINE
WarnStroke.Thickness = 2

local WarnTitle = Instance.new("TextLabel")
WarnTitle.Size = UDim2.new(1, 0, 0, 60)
WarnTitle.Position = UDim2.new(0, 0, 0, 5)
WarnTitle.BackgroundTransparency = 1
WarnTitle.Text = "Hello beta tester :D"
WarnTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
WarnTitle.TextSize = 18 -- INCREASED
WarnTitle.Font = Enum.Font.GothamBold
WarnTitle.ZIndex = 101
WarnTitle.Parent = WarnFrame

local WarnGradient = Instance.new("UIGradient")
WarnGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 22, 26)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 15, 18))
})
WarnGradient.Rotation = 45
WarnGradient.Parent = WarnFrame

-- Crescent Moon Logo for Warning Modal
local WarnLogoBox = Instance.new("Frame"); WarnLogoBox.Size = UDim2.new(0, 22, 0, 22)
WarnLogoBox.Position = UDim2.new(0, 15, 0, 14); WarnLogoBox.BackgroundTransparency = 1; WarnLogoBox.Parent = WarnFrame
local WarnMoonBase = Instance.new("Frame"); WarnMoonBase.Size = UDim2.new(1, 0, 1, 0)
WarnMoonBase.BackgroundColor3 = Color3.fromRGB(255, 255, 255); WarnMoonBase.BorderSizePixel = 0; WarnMoonBase.Parent = WarnLogoBox
Instance.new("UICorner", WarnMoonBase).CornerRadius = UDim.new(1, 0)
local WarnMoonMask = Instance.new("Frame"); WarnMoonMask.Size = UDim2.new(1, 0, 1, 0)
WarnMoonMask.Position = UDim2.new(0.35, 0, -0.15, 0)
WarnMoonMask.BackgroundColor3 = Color3.fromRGB(15, 15, 18); WarnMoonMask.BorderSizePixel = 0; WarnMoonMask.Parent = WarnMoonBase
Instance.new("UICorner", WarnMoonMask).CornerRadius = UDim.new(1, 0)

local WarnDesc = Instance.new("TextLabel")
WarnDesc.Size = UDim2.new(1, -40, 0, 80)
WarnDesc.Position = UDim2.new(0, 20, 0, 55)
WarnDesc.BackgroundTransparency = 1
WarnDesc.Text = "This script is currently in beta, issues and bugs can occur. And also remember that you need the Navara Scout & Twistedx Tower Probe for this autofarm to work correctly!"
WarnDesc.TextColor3 = Color3.fromRGB(210, 210, 210)
WarnDesc.TextSize = 15 -- INCREASED
WarnDesc.Font = Enum.Font.GothamMedium
WarnDesc.TextWrapped = true
WarnDesc.ZIndex = 101
WarnDesc.Parent = WarnFrame

-- News/Update Section
local NewsLabel = Instance.new("TextLabel")
NewsLabel.Size = UDim2.new(1, -40, 0, 36)
NewsLabel.Position = UDim2.new(0, 20, 1, -148)
NewsLabel.BackgroundTransparency = 1
NewsLabel.Text = "If you come across any bugs or issues please join our discord server!"
NewsLabel.TextColor3 = Color3.fromRGB(140, 140, 140)
NewsLabel.Font = Enum.Font.GothamMedium
NewsLabel.TextSize = 12
NewsLabel.ZIndex = 101
NewsLabel.Parent = WarnFrame

-- Discord Invite Section
local DiscInput = Instance.new("TextBox")
DiscInput.Size = UDim2.new(1, -120, 0, 36)
DiscInput.Position = UDim2.new(0, 20, 1, -104)
DiscInput.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
DiscInput.BorderSizePixel = 0
DiscInput.Text = "https://discord.gg/eclipsedhub"
DiscInput.ClearTextOnFocus = false
DiscInput.TextEditable = false
DiscInput.TextColor3 = Color3.fromRGB(200, 200, 200)
DiscInput.Font = Enum.Font.Code
DiscInput.TextSize = 12 -- INCREASED
DiscInput.ZIndex = 101
DiscInput.Parent = WarnFrame
Instance.new("UICorner", DiscInput).CornerRadius = UDim.new(0, 4)
local DiscStroke = Instance.new("UIStroke", DiscInput)
DiscStroke.Color = Color3.fromRGB(255, 255, 255); DiscStroke.Thickness = 1; DiscStroke.Transparency = 0.95

local DiscBtn = Instance.new("TextButton")
DiscBtn.Size = UDim2.new(0, 75, 0, 34)
DiscBtn.Position = UDim2.new(1, -95, 1, -104)
DiscBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 30) -- Dark Grey
DiscBtn.Text = "Discord"
DiscBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
DiscBtn.Font = Enum.Font.GothamBold
DiscBtn.TextSize = 11
DiscBtn.ZIndex = 101
DiscBtn.Parent = WarnFrame
Instance.new("UICorner", DiscBtn).CornerRadius = UDim.new(0, 4)
local DiscBtnStroke = Instance.new("UIStroke", DiscBtn)
DiscBtnStroke.Color = Color3.fromRGB(255, 255, 255); DiscBtnStroke.Thickness = 1; DiscBtnStroke.Transparency = 0.9

DiscBtn.MouseButton1Click:Connect(function()
    local link = "https://discord.gg/eclipsedhub"
    local setClipboard = setclipboard or (Syn and Syn.set_clipboard) or set_clipboard or print
    setClipboard(link)
    DiscBtn.Text = "Copied!"
    task.delay(2, function() DiscBtn.Text = "Discord" end)
end)

local WarnVersion = Instance.new("TextLabel")
WarnVersion.Size = UDim2.new(1, -40, 0, 15)
WarnVersion.Position = UDim2.new(0, 20, 1, -14)
WarnVersion.BackgroundTransparency = 1
WarnVersion.Text = "V 0.0.3.2"
WarnVersion.TextColor3 = Color3.fromRGB(255, 255, 255)
WarnVersion.Font = Enum.Font.GothamBold
WarnVersion.TextSize = 10
WarnVersion.TextXAlignment = Enum.TextXAlignment.Left
WarnVersion.ZIndex = 101
WarnVersion.Parent = WarnFrame

local CloseWarn = Instance.new("TextButton")
CloseWarn.Size = UDim2.new(1, -40, 0, 40)
CloseWarn.Position = UDim2.new(0, 20, 1, -55)
CloseWarn.BackgroundColor3 = Color3.fromRGB(255, 255, 255) -- White button
CloseWarn.Text = "Okay"
CloseWarn.TextColor3 = Color3.fromRGB(0, 0, 0)
CloseWarn.Font = Enum.Font.GothamBold
CloseWarn.TextSize = 14
CloseWarn.ZIndex = 101
CloseWarn.Parent = WarnFrame
Instance.new("UICorner", CloseWarn).CornerRadius = UDim.new(0, 4)

local function closeWarning()
    if WarnFrame then WarnFrame:Destroy() end
    -- Show Main UI elements
    if MainFrame then MainFrame.Visible = true end
    if ShowBtn then 
        if isMobile then
            ShowBtn.Visible = true
        else
            ShowBtn.Visible = false -- PC logic: hidden until panel hides
        end
    end

    -- Send Session Start Webhook if enabled (now triggered by User clicking Okay or auto-hop)
    if WEBHOOK_ENABLED and WEBHOOK_URL ~= "" then
        task.spawn(function()
            local requestFunc = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
            if requestFunc then
                pcall(function()
                    requestFunc({
                        Url = WEBHOOK_URL,
                        Method = "POST",
                        Headers = {["Content-Type"] = "application/json"},
                        Body = HttpService:JSONEncode({
                            username = "Eclipse Autofarm",
                            avatar_url = "https://i.postimg.cc/SxtVbHhh/8429be3ee09690842c1563546762df75.png",
                            content = "This is just to test your webhook works. Also keep in mind as this script is in beta so graphs, and data could be weird so just be aware."
                        })
                    })
                end)
            end
        end)
    end
end

CloseWarn.MouseButton1Click:Connect(closeWarning)

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Crescent moon show/hide button (matches header icon style)
-- On mobile: always visible. On PC: only visible when panel is hidden.
ShowBtn = Instance.new("TextButton")
ShowBtn.Name = "ToggleBtn"
local btnS = isMobile and 54 or 48
ShowBtn.Size = UDim2.new(0, btnS, 0, btnS)
ShowBtn.Position = UDim2.new(0, 20, 0, 20)  -- Moved to top-left to avoid misclicks
ShowBtn.BackgroundColor3 = Color3.fromRGB(15,15,18); ShowBtn.BorderSizePixel = 0
ShowBtn.Text = ""; ShowBtn.ZIndex = 50
ShowBtn.Active = true; ShowBtn.Parent = UI
Instance.new("UICorner", ShowBtn).CornerRadius = UDim.new(1,0)  -- circular
-- Moon icon inside button
local iconS = math.floor(btnS * 0.58)
local BtnMoonBox = Instance.new("Frame"); BtnMoonBox.Size = UDim2.new(0,iconS,0,iconS)
BtnMoonBox.Position = UDim2.new(0.5,-iconS/2,0.5,-iconS/2); BtnMoonBox.BackgroundTransparency = 1
BtnMoonBox.ZIndex = 51; BtnMoonBox.Parent = ShowBtn
local BtnMoonBase = Instance.new("Frame"); BtnMoonBase.Size = UDim2.new(1,0,1,0)
BtnMoonBase.BackgroundColor3 = Color3.fromRGB(255,255,255); BtnMoonBase.BorderSizePixel = 0
BtnMoonBase.ZIndex = 51; BtnMoonBase.Parent = BtnMoonBox
Instance.new("UICorner", BtnMoonBase).CornerRadius = UDim.new(1,0)
local BtnMoonMask = Instance.new("Frame"); BtnMoonMask.Size = UDim2.new(1,0,1,0)
BtnMoonMask.Position = UDim2.new(0.35,0,-0.15,0)
BtnMoonMask.BackgroundColor3 = Color3.fromRGB(15,15,18); BtnMoonMask.BorderSizePixel = 0
BtnMoonMask.ZIndex = 52; BtnMoonMask.Parent = BtnMoonBase
Instance.new("UICorner", BtnMoonMask).CornerRadius = UDim.new(1,0)
ShowBtn.Visible = false -- Initially hidden until warning is cleared

-- Log queue: messages are queued here and created on Heartbeat to ensure
-- the correct thread identity (avoids 'lacking capability Plugin' errors)
local _lastLogMsg = ""
local _lastLogTime = 0
local _rateLimitedMsgs = {}
local _logQueue = {}
local _logLabels = {}       -- tracked so oldest can be destroyed (prevents memory growth)
local MAX_LOG_LINES = 150   -- destroy oldest label when exceeded

local function uiLog(msg, t, rateLimit)
    local now = tick()
    if msg == _lastLogMsg and (now - _lastLogTime) < 5 then return end
    if rateLimit then
        local last = _rateLimitedMsgs[msg] or 0
        if now - last < rateLimit then return end
        _rateLimitedMsgs[msg] = now
    end
    _lastLogMsg = msg; _lastLogTime = now
    local safeMsg = tostring(msg):sub(1, 2000)
    table.insert(_logQueue, {msg = safeMsg, t = t or "default"})
end

-- Drain log queue at 10 Hz (Heartbeat at 60 fps is unnecessarily expensive)
task.spawn(function()
    while true do
        task.wait(0.1)
        while #_logQueue > 0 do
            local item = table.remove(_logQueue, 1)
            -- Wait for ConsoleFrame to exist
            while not ConsoleFrame do task.wait(0.1) end
            
            -- Container for proper hanging indent on wrapped lines
            local container = Instance.new("Frame")
            container.BackgroundTransparency = 1
            container.Size = UDim2.new(1, -12, 0, 0)
            container.AutomaticSize = Enum.AutomaticSize.Y
            container.Parent = ConsoleFrame
            
            local listLayout = Instance.new("UIListLayout")
            listLayout.FillDirection = Enum.FillDirection.Horizontal
            listLayout.SortOrder = Enum.SortOrder.LayoutOrder
            listLayout.Padding = UDim.new(0, 4)
            listLayout.Parent = container

            local color = Color3.fromRGB(180,180,180)
            if item.t == "success" then color = Color3.fromRGB(255,255,255)
            elseif item.t == "warning" then color = Color3.fromRGB(120,120,120)
            elseif item.t == "error" then color = Color3.fromRGB(200,80,80)
            elseif item.t == "action" then color = Color3.fromRGB(220,220,220) end

            local timeLbl = Instance.new("TextLabel")
            timeLbl.BackgroundTransparency = 1
            timeLbl.Size = UDim2.new(0, 52, 0, 12)
            timeLbl.Font = Enum.Font.Code
            timeLbl.Text = string.format("[%s]", os.date("%H:%M:%S"))
            timeLbl.TextColor3 = Color3.fromRGB(130, 130, 130)
            timeLbl.TextSize = 10
            timeLbl.TextXAlignment = Enum.TextXAlignment.Left
            timeLbl.TextYAlignment = Enum.TextYAlignment.Top
            timeLbl.LayoutOrder = 1
            timeLbl.Parent = container

            local msgLbl = Instance.new("TextLabel")
            msgLbl.BackgroundTransparency = 1
            msgLbl.Size = UDim2.new(1, -56, 0, 12)
            msgLbl.AutomaticSize = Enum.AutomaticSize.Y
            msgLbl.Font = Enum.Font.Code
            msgLbl.Text = item.msg
            msgLbl.TextColor3 = color
            msgLbl.TextSize = 10
            msgLbl.TextXAlignment = Enum.TextXAlignment.Left
            msgLbl.TextYAlignment = Enum.TextYAlignment.Top
            msgLbl.TextWrapped = true
            msgLbl.LayoutOrder = 2
            msgLbl.Parent = container

            table.insert(_logLabels, container)
            if #_logLabels > MAX_LOG_LINES then
                local oldest = table.remove(_logLabels, 1)
                if oldest and oldest.Parent then oldest:Destroy() end
            end
            ConsoleFrame.CanvasPosition = Vector2.new(0, ConsoleFrame.AbsoluteCanvasSize.Y)
        end
    end
end)

-- Main panel â€” smaller on mobile
local panelW = isMobile and 260 or 280
local panelH = isMobile and 320 or 340
MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0,panelW,0,panelH); MainFrame.Position = UDim2.new(0,10,0,10)
MainFrame.BackgroundColor3 = Color3.fromRGB(8,8,8); MainFrame.BorderSizePixel = 0
MainFrame.Visible = false -- Initially hidden until warning is cleared
MainFrame.Active = true; MainFrame.Parent = UI
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0,4)

-- Show/hide toggle logic
-- Mobile: button always stays visible. PC: button only shows when panel is hidden.
local function toggleUI()
    if not MainFrame or not ShowBtn then return end
    MainFrame.Visible = not MainFrame.Visible
    if isMobile then
        ShowBtn.Visible = true  -- always visible on mobile
    else
        ShowBtn.Visible = not MainFrame.Visible  -- only show when panel is hidden on PC
    end
end
ShowBtn.MouseButton1Click:Connect(toggleUI)

local AccentBar = Instance.new("Frame"); AccentBar.Size = UDim2.new(1,0,0,1)
AccentBar.BackgroundColor3 = Color3.fromRGB(255,255,255); AccentBar.BorderSizePixel = 0; AccentBar.Parent = MainFrame

local LogoBox = Instance.new("Frame"); LogoBox.Size = UDim2.new(0,20,0,20)
LogoBox.Position = UDim2.new(0,10,0,7); LogoBox.BackgroundTransparency = 1; LogoBox.Parent = MainFrame
local MoonBase = Instance.new("Frame"); MoonBase.Size = UDim2.new(1,0,1,0)
MoonBase.BackgroundColor3 = Color3.fromRGB(255,255,255); MoonBase.BorderSizePixel = 0; MoonBase.Parent = LogoBox
Instance.new("UICorner", MoonBase).CornerRadius = UDim.new(1,0)
local MoonMask = Instance.new("Frame"); MoonMask.Size = UDim2.new(1,0,1,0)
MoonMask.Position = UDim2.new(0.35,0,-0.15,0); MoonMask.BackgroundColor3 = Color3.fromRGB(8,8,8)
MoonMask.BorderSizePixel = 0; MoonMask.ZIndex = 2; MoonMask.Parent = MoonBase
Instance.new("UICorner", MoonMask).CornerRadius = UDim.new(1,0)

local Title = Instance.new("TextLabel"); Title.Size = UDim2.new(1,-40,0,26)
Title.Position = UDim2.new(0,36,0,4); Title.BackgroundTransparency = 1; Title.Text = "Eclipse Autofarm"
Title.Font = Enum.Font.GothamBold; Title.TextColor3 = Color3.fromRGB(255,255,255)
Title.TextSize = 13; Title.TextXAlignment = Enum.TextXAlignment.Left; Title.Parent = MainFrame

local MainVersion = Instance.new("TextLabel")
MainVersion.Size = UDim2.new(1, -24, 0, 12)
MainVersion.Position = UDim2.new(0, 12, 1, -18)
MainVersion.BackgroundTransparency = 1
MainVersion.Text = "V 0.0.3.2"
MainVersion.TextColor3 = Color3.fromRGB(255, 255, 255)
MainVersion.Font = Enum.Font.GothamBold
MainVersion.TextSize = 9
MainVersion.TextXAlignment = Enum.TextXAlignment.Left
MainVersion.ZIndex = 10
MainVersion.Parent = MainFrame

-- Close Button (X)
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 20, 0, 20)
CloseBtn.Position = UDim2.new(1, -26, 0, 7)
CloseBtn.BackgroundTransparency = 1
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(150, 150, 150)
CloseBtn.TextSize = 14
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Parent = MainFrame

CloseBtn.MouseEnter:Connect(function() CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255) end)
CloseBtn.MouseLeave:Connect(function() CloseBtn.TextColor3 = Color3.fromRGB(150, 150, 150) end)
CloseBtn.MouseButton1Click:Connect(function() toggleUI() end)

-- Enable/disable button (leaves room for server hop on the right)
local ToggleBtn = Instance.new("TextButton"); ToggleBtn.Size = UDim2.new(1,-96,0,44)
ToggleBtn.Position = UDim2.new(0,10,0,36); ToggleBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
ToggleBtn.BorderSizePixel = 0; ToggleBtn.Font = Enum.Font.GothamBold; ToggleBtn.Text = _autofarmEnabled and "DISABLE" or "ENABLE"
ToggleBtn.TextColor3 = Color3.fromRGB(255,255,255); ToggleBtn.TextSize = 13; ToggleBtn.Parent = MainFrame
Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(0,2)
local BtnAccent = Instance.new("Frame"); BtnAccent.Size = UDim2.new(0,2,1,0)
BtnAccent.BackgroundColor3 = _autofarmEnabled and Color3.fromRGB(255,255,255) or Color3.fromRGB(100,100,100)
BtnAccent.BorderSizePixel = 0; BtnAccent.Parent = ToggleBtn

-- Server hop button
local HopBtn = Instance.new("TextButton"); HopBtn.Size = UDim2.new(0,72,0,44)
HopBtn.Position = UDim2.new(1,-82,0,36); HopBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
HopBtn.BorderSizePixel = 0; HopBtn.Font = Enum.Font.GothamBold; HopBtn.Text = "HOP"
HopBtn.TextColor3 = Color3.fromRGB(255,255,255); HopBtn.TextSize = 12; HopBtn.Parent = MainFrame
Instance.new("UICorner", HopBtn).CornerRadius = UDim.new(0,2)
local HopAccent = Instance.new("Frame"); HopAccent.Size = UDim2.new(0,2,1,0)
HopAccent.BackgroundColor3 = Color3.fromRGB(80,80,80); HopAccent.BorderSizePixel = 0; HopAccent.Parent = HopBtn

-- Session stats bar: TIME | EARNED | HOURLY
local StatsFrame = Instance.new("Frame")
StatsFrame.Size = UDim2.new(1,-20,0,42); StatsFrame.Position = UDim2.new(0,10,0,86)
StatsFrame.BackgroundColor3 = Color3.fromRGB(4,4,4); StatsFrame.BorderSizePixel = 0; StatsFrame.Parent = MainFrame
Instance.new("UICorner", StatsFrame).CornerRadius = UDim.new(0,2)
local SStroke = Instance.new("UIStroke"); SStroke.Color = Color3.fromRGB(255,255,255)
SStroke.Thickness = 1; SStroke.Transparency = 0.95; SStroke.Parent = StatsFrame

local function makeStatCol(xScale, header)
    local col = Instance.new("Frame"); col.Size = UDim2.new(0.333,0,1,0)
    col.Position = UDim2.new(xScale,0,0,0); col.BackgroundTransparency = 1; col.Parent = StatsFrame
    local h = Instance.new("TextLabel"); h.Size = UDim2.new(1,0,0,14); h.Position = UDim2.new(0,0,0,5)
    h.BackgroundTransparency = 1; h.Text = header; h.Font = Enum.Font.GothamBold; h.TextSize = 8
    h.TextColor3 = Color3.fromRGB(90,90,90); h.TextXAlignment = Enum.TextXAlignment.Center; h.Parent = col
    local v = Instance.new("TextLabel"); v.Size = UDim2.new(1,0,0,16); v.Position = UDim2.new(0,0,0,22)
    v.BackgroundTransparency = 1; v.Text = "--"; v.Font = Enum.Font.GothamBold; v.TextSize = 11
    v.TextColor3 = Color3.fromRGB(255,255,255); v.TextXAlignment = Enum.TextXAlignment.Center; v.Parent = col
    return v
end
local statTimeVal   = makeStatCol(0,     "TIME")
local statEarnedVal = makeStatCol(0.333, "EARNED")
local statHourlyVal = makeStatCol(0.667, "HOURLY")

-- Auto Hop Toggle Row
local AutoHopFrame = Instance.new("Frame")
AutoHopFrame.Size = UDim2.new(1, -20, 0, 30)
AutoHopFrame.Position = UDim2.new(0, 10, 0, 134)
AutoHopFrame.BackgroundColor3 = Color3.fromRGB(4, 4, 4)
AutoHopFrame.BorderSizePixel = 0
AutoHopFrame.Parent = MainFrame
Instance.new("UICorner", AutoHopFrame).CornerRadius = UDim.new(0, 2)
local AHStroke = Instance.new("UIStroke")
AHStroke.Color = Color3.fromRGB(255, 255, 255); AHStroke.Thickness = 1; AHStroke.Transparency = 0.95; AHStroke.Parent = AutoHopFrame

local AHTitle = Instance.new("TextLabel")
AHTitle.Size = UDim2.new(1, -60, 1, 0)
AHTitle.Position = UDim2.new(0, 10, 0, 0)
AHTitle.BackgroundTransparency = 1
AHTitle.Text = "AUTO SERVER HOP:"
AHTitle.Font = Enum.Font.GothamBold
AHTitle.TextSize = 9
AHTitle.TextColor3 = Color3.fromRGB(150, 150, 150)
AHTitle.TextXAlignment = Enum.TextXAlignment.Left
AHTitle.Parent = AutoHopFrame

local AHToggle = Instance.new("TextLabel")
AHToggle.Size = UDim2.new(0, 90, 1, -10)
AHToggle.Position = UDim2.new(1, -95, 0, 5)
AHToggle.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
AHToggle.Text = "MAINTENANCE"
AHToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
AHToggle.Font = Enum.Font.GothamBold
AHToggle.TextSize = 9
AHToggle.Parent = AutoHopFrame
Instance.new("UICorner", AHToggle).CornerRadius = UDim.new(0, 2)

-- Potato Mode Toggle Row
local PotatoFrame = Instance.new("Frame")
PotatoFrame.Size = UDim2.new(1, -20, 0, 30)
PotatoFrame.Position = UDim2.new(0, 10, 0, 168)
PotatoFrame.BackgroundColor3 = Color3.fromRGB(4, 4, 4)
PotatoFrame.BorderSizePixel = 0
PotatoFrame.Parent = MainFrame
Instance.new("UICorner", PotatoFrame).CornerRadius = UDim.new(0, 2)
local PMStroke = Instance.new("UIStroke")
PMStroke.Color = Color3.fromRGB(255, 255, 255); PMStroke.Thickness = 1; PMStroke.Transparency = 0.95; PMStroke.Parent = PotatoFrame

local PMTitle = Instance.new("TextLabel")
PMTitle.Size = UDim2.new(1, -60, 1, 0)
PMTitle.Position = UDim2.new(0, 10, 0, 0)
PMTitle.BackgroundTransparency = 1
PMTitle.Text = "POTATO MODE:"
PMTitle.Font = Enum.Font.GothamBold
PMTitle.TextSize = 9
PMTitle.TextColor3 = Color3.fromRGB(150, 150, 150)
PMTitle.TextXAlignment = Enum.TextXAlignment.Left
PMTitle.Parent = PotatoFrame

local PMToggle = Instance.new("TextButton")
PMToggle.Size = UDim2.new(0, 40, 1, -10)
PMToggle.Position = UDim2.new(1, -45, 0, 5)
PMToggle.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
PMToggle.Text = "OFF"
PMToggle.TextColor3 = Color3.fromRGB(150, 150, 150)
PMToggle.Font = Enum.Font.GothamBold
PMToggle.TextSize = 9
PMToggle.Parent = PotatoFrame
Instance.new("UICorner", PMToggle).CornerRadius = UDim.new(0, 2)

local function applyPotatoMode(enabled)
    _potatoMode = enabled
    pcall(function()
        local Lighting = game:GetService("Lighting")

        -- Disable all post-processing effects
        for _, effect in ipairs(Lighting:GetChildren()) do
            if effect:IsA("PostEffect") then
                effect.Enabled = not enabled
            end
            if effect:IsA("Atmosphere") then
                if enabled then
                    effect.Density = 0; effect.Haze = 0; effect.Glare = 0; effect.Offset = 0
                else
                    effect.Density = 0.395; effect.Haze = 0
                end
            end
            if effect:IsA("Sky") then
                effect.CelestialBodiesShown = not enabled
            end
        end

        -- Shadows, ambient, etc.
        Lighting.GlobalShadows = not enabled
        if enabled then
            Lighting.FogEnd = 100000
            Lighting.Brightness = 2
        end

        -- Terrain tweaks
        local terrain = workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            terrain.Decoration = not enabled
            if enabled then
                terrain.WaterWaveSize = 0
                terrain.WaterWaveSpeed = 0
                terrain.WaterReflectance = 0
                terrain.WaterTransparency = 0
            end
        end

        -- RenderFidelity and quality settings
        pcall(function()
            settings().Rendering.QualityLevel = enabled and 1 or 0
            settings().Rendering.MeshPartDetailLevel = enabled and Enum.MeshPartDetailLevel.Level0 or Enum.MeshPartDetailLevel.DistanceBased
            local gs = game:GetService("UserGameSettings")
            gs.SavedQualityLevel = enabled and Enum.SavedQualitySetting.QualityLevel1 or Enum.SavedQualitySetting.Automatic
        end)

        if enabled then
            -- Disable all other player character visuals
            for _, player in pairs(game:GetService("Players"):GetPlayers()) do
                if player ~= localPlayer then
                    local char = player.Character
                    if char then
                        for _, part in pairs(char:GetDescendants()) do
                            pcall(function()
                                if part:IsA("BasePart") or part:IsA("MeshPart") then
                                    part.LocalTransparencyModifier = 1
                                end
                            end)
                        end
                    end
                end
            end

            -- Disable all visual particles, beams, trails, decals across workspace
            for _, v in pairs(workspace:GetDescendants()) do
                pcall(function()
                    if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") or v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles") then
                        v.Enabled = false
                    elseif v:IsA("Decal") or v:IsA("Texture") then
                        if v.Name ~= "EclipseLogoDecal" and (not v.Parent or not v.Parent.Name:match("Eclipse")) then
                            v.Transparency = 1
                        end
                    elseif v:IsA("BasePart") then
                        v.Material = Enum.Material.SmoothPlastic
                        v.Reflectance = 0
                        v.CastShadow = false
                    end
                end)
            end

            -- Hide all storm visual models (keep tornado_scan intact)
            local stormDir = workspace:FindFirstChild("storm_related")
            if stormDir then
                for _, v in pairs(stormDir:GetDescendants()) do
                    pcall(function()
                        if (v:IsA("BasePart") or v:IsA("MeshPart") or v:IsA("SpecialMesh")) and v.Name ~= "tornado_scan" then
                            v.LocalTransparencyModifier = 1
                        end
                    end)
                end
            end
        end
    end)
    uiLog("Potato Mode " .. (enabled and "ENABLED" or "DISABLED"), "action")
end


-- Persistent watcher: disable any particles/effects that spawn AFTER potato mode is on
local _potatoWatcher = nil
local _potatoPlayerWatcher = nil

local function startPotatoWatcher()
    if _potatoWatcher then _potatoWatcher:Disconnect() end
    _potatoWatcher = workspace.DescendantAdded:Connect(function(v)
        if not _potatoMode then return end
        
        -- Filter early synchronously to avoid creating thousands of defer closures for rain drops/debris!
        if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") or v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles") then
            v.Enabled = false
        elseif v:IsA("Decal") or v:IsA("Texture") then
            if v.Name ~= "EclipseLogoDecal" and (not v.Parent or not v.Parent.Name:match("Eclipse")) then
                v.Transparency = 1
            end
        elseif v:IsA("BasePart") then
            v.Material = Enum.Material.SmoothPlastic
            v.Reflectance = 0
            v.CastShadow = false
        end
    end)

    -- Also watch for new players joining (hide their characters)
    if _potatoPlayerWatcher then _potatoPlayerWatcher:Disconnect() end
    _potatoPlayerWatcher = game:GetService("Players").PlayerAdded:Connect(function(player)
        if not _potatoMode then return end
        player.CharacterAdded:Connect(function(char)
            task.wait(0.5)
            if not _potatoMode then return end
            for _, part in pairs(char:GetDescendants()) do
                pcall(function()
                    if part:IsA("BasePart") or part:IsA("MeshPart") then
                        part.LocalTransparencyModifier = 1
                    end
                end)
            end
        end)
    end)
end
startPotatoWatcher()

PMToggle.MouseButton1Click:Connect(function()
    _potatoMode = not _potatoMode
    PMToggle.Text = _potatoMode and "ON" or "OFF"
    PMToggle.BackgroundColor3 = _potatoMode and Color3.fromRGB(255, 165, 0) or Color3.fromRGB(25, 25, 25)
    PMToggle.TextColor3 = _potatoMode and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(150, 150, 150)
    applyPotatoMode(_potatoMode)
end)

-- â”€â”€ SPECTATE CAM ROW â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local FreecamFrame = Instance.new("Frame")
FreecamFrame.Size = UDim2.new(1, -20, 0, 30)
FreecamFrame.Position = UDim2.new(0, 10, 0, 202)
FreecamFrame.BackgroundColor3 = Color3.fromRGB(4, 4, 4)
FreecamFrame.BorderSizePixel = 0
FreecamFrame.Parent = MainFrame
Instance.new("UICorner", FreecamFrame).CornerRadius = UDim.new(0, 2)
local FCStroke = Instance.new("UIStroke")
FCStroke.Color = Color3.fromRGB(255,255,255); FCStroke.Thickness = 1; FCStroke.Transparency = 0.95; FCStroke.Parent = FreecamFrame

local FCTitle = Instance.new("TextLabel")
FCTitle.Size = UDim2.new(1, -55, 1, 0)
FCTitle.Position = UDim2.new(0, 10, 0, 0)
FCTitle.BackgroundTransparency = 1
FCTitle.Text = "SPECTATE STORM:"
FCTitle.Font = Enum.Font.GothamBold
FCTitle.TextSize = 9
FCTitle.TextColor3 = Color3.fromRGB(150, 150, 150)
FCTitle.TextXAlignment = Enum.TextXAlignment.Left
FCTitle.Parent = FreecamFrame

local FCToggle = Instance.new("TextButton")
FCToggle.Size = UDim2.new(0, 40, 1, -10)
FCToggle.Position = UDim2.new(1, -45, 0, 5)
FCToggle.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
FCToggle.Text = "OFF"
FCToggle.TextColor3 = Color3.fromRGB(150, 150, 150)
FCToggle.Font = Enum.Font.GothamBold
FCToggle.TextSize = 9
FCToggle.Parent = FreecamFrame
Instance.new("UICorner", FCToggle).CornerRadius = UDim.new(0, 2)

-- â”€â”€ SPECTATE ENGINE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Uses Roblox's built-in Custom camera and PlayerModule for universal support.
-- Reads mobile thumbstick & WASD to let the player fly the invisible anchor!
local _specActive = false
local _specAnchor = nil
local _specConn   = nil

local function stopSpectate()
    _specActive = false
    if _specConn then _specConn:Disconnect(); _specConn = nil end
    if _specAnchor then _specAnchor:Destroy(); _specAnchor = nil end
    pcall(function()
        local cam = workspace.CurrentCamera
        cam.CameraType = Enum.CameraType.Custom
        local hum = localPlayer.Character and localPlayer.Character:FindFirstChild("Humanoid")
        if hum then cam.CameraSubject = hum end
    end)
    FCToggle.Text = "OFF"
    FCToggle.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    FCToggle.TextColor3 = Color3.fromRGB(150, 150, 150)
end

local function startSpectate()
    -- Place anchor at the current world probe position (or storm if none)
    local startPos = nil
    local folder = workspace:FindFirstChild("player_related") and workspace.player_related:FindFirstChild("probes")
    if folder then
        local myId = tostring(localPlayer.UserId)
        local sum = Vector3.new(0,0,0); local cnt = 0
        for _, p in pairs(folder:GetChildren()) do
            local attr = p:GetAttribute("id") or p:GetAttribute("OwnerId") or p:GetAttribute("owner")
            if tostring(attr) == myId or p.Name:match(myId) then
                local part = p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart")
                if part then sum = sum + part.Position; cnt += 1 end
            end
        end
        if cnt > 0 then startPos = sum / cnt end
    end

    if not startPos then
        local sList = getTornadoes and getTornadoes() or {}
        for _, s in ipairs(sList) do
            local sc = s:FindFirstChild("tornado_scan") or s:FindFirstChild("scan")
            if sc then startPos = sc.Position; break end
        end
    end
    startPos = startPos or Vector3.new(0, 50, 0)

    -- Create invisible anchor
    local anchor = Instance.new("Part")
    anchor.Name = "SpectateCamAnchor"
    anchor.Size = Vector3.new(1, 1, 1)
    anchor.Transparency = 1
    anchor.CanCollide = false
    anchor.Anchored = true
    anchor.CastShadow = false
    anchor.Position = startPos + Vector3.new(0, 20, 0)
    anchor.Parent = workspace
    _specAnchor = anchor

    local cam = workspace.CurrentCamera
    cam.CameraType = Enum.CameraType.Custom
    cam.CameraSubject = anchor

    _specActive = true
    FCToggle.Text = "ON"
    FCToggle.BackgroundColor3 = Color3.fromRGB(100, 180, 255)
    FCToggle.TextColor3 = Color3.fromRGB(0, 0, 0)

    -- Hook into PlayerModule to read mobile thumbstick + WASD natively
    local controls = nil
    pcall(function()
        local pm = require(localPlayer.PlayerScripts:WaitForChild("PlayerModule"))
        controls = pm:GetControls()
    end)

    local RS = game:GetService("RunService")
    local UIS = game:GetService("UserInputService")
    local speed = 120  -- fly speed
    
    _specConn = RS.RenderStepped:Connect(function(dt)
        if not _specActive or not _specAnchor then return end
        
        local moveVec = controls and controls:GetMoveVector() or Vector3.new(0, 0, 0)
        
        -- PC vertical controls
        local up = 0
        if UIS:IsKeyDown(Enum.KeyCode.E) or UIS:IsKeyDown(Enum.KeyCode.Space) then up = 1 end
        if UIS:IsKeyDown(Enum.KeyCode.Q) or UIS:IsKeyDown(Enum.KeyCode.LeftShift) then up = -1 end
        
        local cf = cam.CFrame
        local fwd = cf.LookVector
        local right = cf.RightVector
        
        -- Fly relative to camera look direction
        local flyVec = fwd * -moveVec.Z + right * moveVec.X + Vector3.new(0, up, 0)
        
        if flyVec.Magnitude > 0 then
            _specAnchor.Position = _specAnchor.Position + flyVec * speed * dt
        end
    end)
end

FCToggle.MouseButton1Click:Connect(function()
    if _specActive then stopSpectate() else startSpectate() end
end)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- â”€â”€ TELEPORT POPUP â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local TeleportPopup = Instance.new("Frame")
TeleportPopup.Size = UDim2.new(0, 240, 0, 70)
TeleportPopup.Position = UDim2.new(1, 50, 0.5, -35) -- Hidden off-screen right
TeleportPopup.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
TeleportPopup.BorderSizePixel = 0
TeleportPopup.Parent = UI
Instance.new("UICorner", TeleportPopup).CornerRadius = UDim.new(0, 8)
local TPStroke = Instance.new("UIStroke")
TPStroke.Color = Color3.fromRGB(255,255,255); TPStroke.Thickness = 1; TPStroke.Transparency = 0.8; TPStroke.Parent = TeleportPopup

local TPLabel = Instance.new("TextLabel")
TPLabel.Size = UDim2.new(1, -20, 0, 30)
TPLabel.Position = UDim2.new(0, 10, 0, 5)
TPLabel.BackgroundTransparency = 1
TPLabel.Text = "Probes moved. Teleport to new location?"
TPLabel.Font = Enum.Font.GothamSemibold
TPLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
TPLabel.TextSize = 12
TPLabel.TextWrapped = true
TPLabel.TextXAlignment = Enum.TextXAlignment.Center
TPLabel.Parent = TeleportPopup

local TPYes = Instance.new("TextButton")
TPYes.Size = UDim2.new(0.43, 0, 0, 24)
TPYes.Position = UDim2.new(0.04, 0, 0, 38)
TPYes.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
TPYes.Text = "YES"
TPYes.Font = Enum.Font.GothamBold
TPYes.TextColor3 = Color3.fromRGB(10, 10, 10)
TPYes.TextSize = 11
TPYes.Parent = TeleportPopup
Instance.new("UICorner", TPYes).CornerRadius = UDim.new(0, 4)

local TPNo = Instance.new("TextButton")
TPNo.Size = UDim2.new(0.43, 0, 0, 24)
TPNo.Position = UDim2.new(0.53, 0, 0, 38)
TPNo.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
TPNo.Text = "NO"
TPNo.Font = Enum.Font.GothamBold
TPNo.TextColor3 = Color3.fromRGB(220, 220, 220)
TPNo.TextSize = 11
TPNo.Parent = TeleportPopup
Instance.new("UICorner", TPNo).CornerRadius = UDim.new(0, 4)

local _tpPopupActive = false
local function hideTeleportPopup()
    if not _tpPopupActive then return end
    _tpPopupActive = false
    local TS = game:GetService("TweenService")
    TS:Create(TeleportPopup, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = UDim2.new(1, 50, 0.5, -35)}):Play()
end

local function showTeleportPopup()
    if _tpPopupActive or not _specActive then return end
    _tpPopupActive = true
    local TS = game:GetService("TweenService")
    TS:Create(TeleportPopup, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(1, -250, 0.5, -35)}):Play()
    task.delay(10, function() hideTeleportPopup() end)
end

TPNo.MouseButton1Click:Connect(hideTeleportPopup)
TPYes.MouseButton1Click:Connect(function()
    hideTeleportPopup()
    if not _specActive then 
        startSpectate() 
    else
        local folder = workspace:FindFirstChild("player_related") and workspace.player_related:FindFirstChild("probes")
        if folder and _specAnchor then
            local myId = tostring(localPlayer.UserId)
            local sum = Vector3.new(0,0,0); local cnt = 0
            for _, p in pairs(folder:GetChildren()) do
                local attr = p:GetAttribute("id") or p:GetAttribute("OwnerId") or p:GetAttribute("owner")
                if tostring(attr) == myId or p.Name:match(myId) then
                    local part = p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart")
                    if part then sum = sum + part.Position; cnt += 1 end
                end
            end
            if cnt > 0 then _specAnchor.Position = (sum / cnt) + Vector3.new(0, 20, 0) end
        end
    end
end)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€


ConsoleFrame = Instance.new("ScrollingFrame") -- Assigned to outer scope
ConsoleFrame.Size = UDim2.new(1,-20,1,-286); ConsoleFrame.Position = UDim2.new(0,10,0,236)
ConsoleFrame.BackgroundColor3 = Color3.fromRGB(4,4,4); ConsoleFrame.BorderSizePixel = 0
ConsoleFrame.ScrollBarThickness = 1; ConsoleFrame.ScrollBarImageColor3 = Color3.fromRGB(255,255,255)
ConsoleFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y; ConsoleFrame.CanvasSize = UDim2.new(0,0,0,0)
ConsoleFrame.ClipsDescendants = true
ConsoleFrame.Parent = MainFrame
Instance.new("UICorner", ConsoleFrame).CornerRadius = UDim.new(0,2)
local ConsoleStroke = Instance.new("UIStroke"); ConsoleStroke.Color = Color3.fromRGB(255,255,255)
ConsoleStroke.Thickness = 1; ConsoleStroke.Transparency = 0.95; ConsoleStroke.Parent = ConsoleFrame
local ConsoleLayout = Instance.new("UIListLayout"); ConsoleLayout.Parent = ConsoleFrame
ConsoleLayout.SortOrder = Enum.SortOrder.LayoutOrder; ConsoleLayout.Padding = UDim.new(0,2)
local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0,8); pad.PaddingTop = UDim.new(0,8); pad.Parent = ConsoleFrame

-- Webhook Config Box
local WebhookFrame = Instance.new("Frame")
WebhookFrame.Size = UDim2.new(1, -20, 0, 36)
WebhookFrame.Position = UDim2.new(0, 10, 1, -44)
WebhookFrame.BackgroundColor3 = Color3.fromRGB(4, 4, 4)
WebhookFrame.BorderSizePixel = 0
WebhookFrame.ClipsDescendants = true -- Cuts off any overflowing text
WebhookFrame.Parent = MainFrame
Instance.new("UICorner", WebhookFrame).CornerRadius = UDim.new(0, 2)
local WebStroke = Instance.new("UIStroke")
WebStroke.Color = Color3.fromRGB(255, 255, 255); WebStroke.Thickness = 1; WebStroke.Transparency = 0.95; WebStroke.Parent = WebhookFrame

local WebTitle = Instance.new("TextLabel")
WebTitle.Size = UDim2.new(0, 50, 1, 0)
WebTitle.Position = UDim2.new(0, 8, 0, 0)
WebTitle.BackgroundTransparency = 1
WebTitle.Text = "URL:"
WebTitle.Font = Enum.Font.GothamBold
WebTitle.TextSize = 9
WebTitle.TextColor3 = Color3.fromRGB(150, 150, 150)
WebTitle.TextXAlignment = Enum.TextXAlignment.Left
WebTitle.Parent = WebhookFrame

local WebInput = Instance.new("TextBox")
WebInput.Size = UDim2.new(1, -110, 1, -10)
WebInput.Position = UDim2.new(0, 60, 0, 5)
WebInput.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
WebInput.BorderSizePixel = 0
local initialUrl = tostring(WEBHOOK_URL or ""):sub(1, 1000)
WebInput.Text = initialUrl
WebInput.PlaceholderText = "Paste URL here..."
WebInput.ClearTextOnFocus = false
WebInput.TextColor3 = Color3.fromRGB(255, 255, 255)
WebInput.TextSize = 10
WebInput.Font = Enum.Font.Code
WebInput.TextXAlignment = Enum.TextXAlignment.Left
WebInput.TextWrapped = false -- Prevents text from wrapping to next line
WebInput.Parent = WebhookFrame
Instance.new("UICorner", WebInput).CornerRadius = UDim.new(0, 2)

local WebToggle = Instance.new("TextButton")
WebToggle.Size = UDim2.new(0, 40, 1, -10)
WebToggle.Position = UDim2.new(1, -45, 0, 5)
WebToggle.BackgroundColor3 = WEBHOOK_ENABLED and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(25, 25, 25)
WebToggle.Text = WEBHOOK_ENABLED and "ON" or "OFF"
WebToggle.TextColor3 = WEBHOOK_ENABLED and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(150, 150, 150)
WebToggle.Font = Enum.Font.GothamBold
WebToggle.TextSize = 9
WebToggle.Parent = WebhookFrame
Instance.new("UICorner", WebToggle).CornerRadius = UDim.new(0, 2)

WebToggle.MouseButton1Click:Connect(function()
    WEBHOOK_ENABLED = not WEBHOOK_ENABLED
    WebToggle.Text = WEBHOOK_ENABLED and "ON" or "OFF"
    WebToggle.BackgroundColor3 = WEBHOOK_ENABLED and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(25, 25, 25)
    WebToggle.TextColor3 = WEBHOOK_ENABLED and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(150, 150, 150)
    getgenv().eclipse2_webhook_enabled = WEBHOOK_ENABLED
    saveSettings()
    uiLog("Webhook notifications " .. (WEBHOOK_ENABLED and "ENABLED" or "DISABLED"), "action")
    
    if WEBHOOK_ENABLED and WEBHOOK_URL ~= "" then
        task.spawn(function()
            local requestFunc = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
            if requestFunc then
                pcall(function()
                    requestFunc({
                        Url = WEBHOOK_URL,
                        Method = "POST",
                        Headers = {["Content-Type"] = "application/json"},
                        Body = HttpService:JSONEncode({
                            username = "Eclipse Dashboard",
                            avatar_url = "https://i.postimg.cc/SxtVbHhh/8429be3ee09690842c1563546762df75.png",
                            content = "This is just to test your webhook works."
                        })
                    })
                end)
            end
        end)
    end
end)

WebInput.FocusLost:Connect(function()
    WEBHOOK_URL = WebInput.Text
    getgenv().eclipse2_webhook = WEBHOOK_URL
    saveSettings()
    uiLog("Webhook URL updated", "success")
end)

-- Universal Clamped Draggable Function
local function makeDraggable(obj, threshold)
    local dragging = false
    local dragStart, startPos
    local threshold = threshold or 8
    local didDrag = false

    obj.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            didDrag = false
            dragStart = input.Position
            startPos = obj.AbsolutePosition
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            if not didDrag and delta.Magnitude > threshold then didDrag = true end
            if didDrag then
                local parent = obj.Parent
                local pSize = parent.AbsoluteSize
                local oSize = obj.AbsoluteSize
                
                local nX = math.clamp(startPos.X + delta.X, 0, pSize.X - oSize.X)
                local nY = math.clamp(startPos.Y + delta.Y, 0, pSize.Y - oSize.Y)
                
                obj.Position = UDim2.new(0, nX, 0, nY)
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            if didDrag and obj:IsA("TextButton") then
                local conn
                conn = obj.MouseButton1Click:Connect(function()
                    conn:Disconnect()
                end)
            end
            dragging = false
        end
    end)
end

makeDraggable(ShowBtn)
makeDraggable(MainFrame)

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Game notification helper (uses Eclipse's built-in notify system)
local _lastNotifyTime = {}
local function gameNotify(title, text, duration, cooldown)
    local now = tick()
    local key = title..text
    if cooldown and _lastNotifyTime[key] and (now - _lastNotifyTime[key]) < cooldown then return end
    _lastNotifyTime[key] = now
    pcall(function()
        local Remote = game:GetService("ReplicatedStorage").events.notify_plr
        firesignal(Remote.OnClientEvent, {
            ["duration"] = duration or 5,
            ["title"] = title,
            ["text"] = text,
        })
    end)
end

local function countWorldProbes()
    local count = 0
    local folder = workspace:FindFirstChild("player_related") and workspace.player_related:FindFirstChild("probes")
    if folder then
        local myId = tostring(localPlayer.UserId)
        for _, p in pairs(folder:GetChildren()) do
            local attr = p:GetAttribute("id") or p:GetAttribute("OwnerId") or p:GetAttribute("owner")
            if tostring(attr) == myId or p.Name:match(myId) then count += 1 end
        end
    end
    return count
end

local function countProbesInv()
    local n = 0
    local char = localPlayer.Character
    
    local probeAssets = game:GetService("ReplicatedStorage"):FindFirstChild("client_assets")
        and game:GetService("ReplicatedStorage").client_assets:FindFirstChild("vehicles")
        and game:GetService("ReplicatedStorage").client_assets.vehicles:FindFirstChild("probes")
        
    local function isProbe(t)
        if not t:IsA("Tool") then return false end
        local n = t.Name:lower()
        if n:match("probe") or n:match("twistex") or n:match("tower") or n:match("pod") or n:match("v2") then return true end
        if probeAssets and probeAssets:FindFirstChild(t.Name) then return true end
        return false
    end

    for _, t in ipairs(localPlayer.Backpack:GetChildren()) do
        if isProbe(t) then n += 1 end
    end
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if isProbe(t) then n += 1 end
        end
    end
    return n
end

local function spawnVehicle()
    -- Block vehicle spawn ONLY if probes are deployed in the world.
    -- If probes are just in inventory, it is safe to spawn.
    if countWorldProbes() > 0 then return end

    local hum = localPlayer.Character and localPlayer.Character:FindFirstChild("Humanoid")
    if hum and hum.SeatPart then return end -- Already in a car
    
    uiLog("Spawning vehicle: "..VEHICLE_NAME.."...", "action")
    pcall(function()
        local remote = ReplicatedStorage:FindFirstChild("events") and ReplicatedStorage.events:FindFirstChild("spawn_vehicle")
        if remote then 
            remote:FireServer(VEHICLE_NAME) 
        end
    end)
end


local function setFarmEnabled(enabled)
    _autofarmEnabled = enabled
    if enabled then
        if currentSessionStart == 0 then
            currentSessionStart = tick() -- Start/Resume timer
        end
        local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
        ToggleBtn.Text = "DISABLE"
        BtnAccent.BackgroundColor3 = Color3.fromRGB(255,255,255)
        uiLog("Autofarm enabled â€” teleporting to staging area...", "action")
        -- Teleport to fixed staging position, then lock there so the server sees us
        _startCF = CFrame.new(START_POS)
        if root then
            -- Create platform for under-map staging
            if not _stagingPlatform or not _stagingPlatform.Parent then
                _stagingPlatform = Instance.new("Part")
                _stagingPlatform.Name = "EclipsePlatform>.<"
                _stagingPlatform.Size = Vector3.new(30, 1, 30)
                _stagingPlatform.CFrame = _startCF * CFrame.new(0, -3.5, 0)
                _stagingPlatform.Anchored = true
                _stagingPlatform.Transparency = 1 -- Fully invisible base
                _stagingPlatform.CanCollide = true
                _stagingPlatform.Material = Enum.Material.SmoothPlastic
                _stagingPlatform.Parent = workspace
                
                -- Add Eclipse logo via SurfaceGui on top face (renders perfectly even on fully invisible parts)
                local sGui = Instance.new("SurfaceGui")
                sGui.Name = "EclipseLogoGui"
                sGui.Face = Enum.NormalId.Top
                sGui.CanvasSize = Vector2.new(512, 512)
                sGui.Active = false
                sGui.Parent = _stagingPlatform
                
                local img = Instance.new("ImageLabel")
                img.Name = "EclipseLogoImage"
                img.BackgroundTransparency = 1
                img.Size = UDim2.new(1, 0, 1, 0)
                img.Image = "rbxassetid://89815247912157"
                img.Parent = sGui
            end

            -- Gradual teleport: move in steps to avoid anti-cheat detection
            local currentCF = root.CFrame
            local targetCF = _startCF
            local steps = 8
            for step = 1, steps do
                if not root or not root.Parent then break end
                local alpha = step / steps
                root.CFrame = currentCF:Lerp(targetCF, alpha)
                task.wait(0.03)
            end
            if root and root.Parent then
                root.CFrame = targetCF
            end
            root.Velocity = Vector3.new(0, 0, 0)
            _startHolding = true
            _holdId = _holdId + 1
            local myHoldId = _holdId
            resetCamera()
            task.spawn(function()
                task.wait(0.5)
                if _autofarmEnabled then spawnVehicle() end
            end)
            task.spawn(function()
                while _startHolding and myHoldId == _holdId and _autofarmEnabled and root and root.Parent do
                    root.CFrame = _startCF
                    root.Velocity = Vector3.new(0, 0, 0)
                    game:GetService("RunService").RenderStepped:Wait()
                end
            end)
        end
    else
        -- Do not delete staging platform when disabled, keeping player safe from falling
        if currentSessionStart > 0 then
            sessionTimeAccumulated = sessionTimeAccumulated + (tick() - currentSessionStart)
            currentSessionStart = 0 -- Pause timer
            getgenv().eclipse2_session_time = sessionTimeAccumulated
        end
        _startHolding = false
        ToggleBtn.Text = "ENABLE"
        BtnAccent.BackgroundColor3 = Color3.fromRGB(60,60,60)
        uiLog("Autofarm disabled", "warning")
        local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root then
            root.Anchored = false
            if _startCF then
                uiLog("Returning to start position...", "action")
                root.CFrame = _startCF
                _startCF = nil
            end
        end
    end
end

ToggleBtn.MouseButton1Click:Connect(function()
    setFarmEnabled(not _autofarmEnabled)
end)

local _hopCooldown = false
local function serverHop()
    uiLog("[HOP] Button pressed", "action")
    if _hopCooldown then uiLog("[HOP] On cooldown", "warning"); return end
    _hopCooldown = true
    HopBtn.Text = "..."
    HopAccent.BackgroundColor3 = Color3.fromRGB(180, 180, 60)
    setFarmEnabled(false)
    task.spawn(function()
        task.wait(0.3)
        uiLog("[HOP] Arming queue...", "action")
        -- Queue script to auto-execute after teleport
        pcall(function()
            if type(queue_on_teleport) == "function" then
                queue_on_teleport("loadstring(game:HttpGet(\"https://raw.githubusercontent.com/loperer1/Eclipse-AutoExecute/refs/heads/main/autoexecute.lua\"))()")
                uiLog("[HOP] Queue armed.", "action")
            else
                uiLog("[HOP] queue_on_teleport not available.", "warning")
            end
        end)
        uiLog("[HOP] Preparing to teleport...", "action")
        teleportCount += 1
        _isHopping = true
        saveSettings()
        uiLog("[HOP] Calling Teleport...", "action")
        local ok, err = pcall(function()
            local HttpService = game:GetService("HttpService")
            local TeleportService = game:GetService("TeleportService")
            local req = game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Desc&limit=100")
            if req then
                local body = HttpService:JSONDecode(req)
                local servers = {}
                if body and body.data then
                    for _, v in pairs(body.data) do
                        if type(v) == "table" and v.maxPlayers and v.playing and v.id ~= game.JobId then
                            if v.playing < v.maxPlayers - 1 then
                                table.insert(servers, v.id)
                            end
                        end
                    end
                end
                if #servers > 0 then
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[math.random(1, #servers)], localPlayer)
                    return
                end
            end
            -- Fallback if API fails
            TeleportService:Teleport(game.PlaceId, localPlayer)
        end)
        if not ok then
            uiLog("[HOP] Teleport failed: " .. tostring(err), "error")
            _hopCooldown = false
            HopBtn.Text = "HOP"
            HopAccent.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
        else
            uiLog("[HOP] Teleport fired â€” loading new server...", "success")
            task.wait(8)
            -- Still here = teleport didn't fire despite no error
            uiLog("[HOP] Still in game after 8s â€” may need executor file save", "error")
            _hopCooldown = false
            HopBtn.Text = "HOP"
            HopAccent.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
        end
    end)
end
HopBtn.MouseButton1Click:Connect(serverHop)

-- â”€â”€ ANTI-STAFF DETECTION â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local STAFF_GROUP_ID = 4812298
local STAFF_ROLES = {
    ["Moderator"] = true,
    ["Administrator"] = true,
    ["Developer"] = true,
    ["Developer Alts"] = true,
    ["Siryzm"] = true,
    ["Willzuh"] = true
}

local function checkPlayerForStaff(player)
    if player == localPlayer then return end
    task.spawn(function()
        pcall(function()
            local role = player:GetRoleInGroup(STAFF_GROUP_ID)
            if STAFF_ROLES[role] then
                uiLog("STAFF DETECTED: " .. player.Name .. " (" .. role .. ")", "error")
                gameNotify("STAFF AVOIDANCE", "Disconnecting to avoid " .. player.Name .. " (" .. role .. ")", 5, 255)
                task.wait(0.5)
                localPlayer:Kick("\n\n[Eclipse Autofarm]\nStaff Detected in server!\nDisconnected to protect your account.\n\nStaff Member: " .. player.Name .. "\nRole: " .. role)
            end
        end)
    end)
end

for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
    checkPlayerForStaff(p)
end
game:GetService("Players").PlayerAdded:Connect(checkPlayerForStaff)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€




local _lastBuyTime = 0
local _buyInProgress = false



local function buyProbe(count)
    if _buyInProgress then return end
    if tick() - _lastBuyTime < 3 then return end

    local currentTotal = countProbesInv() + countWorldProbes()
    local needed = math.max(0, PROBE_TARGET - currentTotal)
    if needed == 0 then
        return
    end

    _buyInProgress = true
    _lastBuyTime = tick()

    local remote = ReplicatedStorage:FindFirstChild("remotes") and ReplicatedStorage.remotes:FindFirstChild("buy_probes")
    if not remote then
        uiLog("Buy failed: buy_probes not found", "error")
        _buyInProgress = false
        return
    end

    count = math.min(math.max(1, math.floor(tonumber(count) or 1)), needed)
    uiLog(("Buying %d probe(s)"):format(count), "action")

    for i = 1, count do
        if not _autofarmEnabled then
            uiLog("Stopping purchase", "warning")
            break
        end
        local ok, err = pcall(function()
            remote:InvokeServer({
                ["vehicle"] = VEHICLE_NAME,
                ["probe"] = "Twistex Tower Probe",
            })
        end)
        if not ok then uiLog("Purchase error: " .. tostring(err), "error") end
        if i < count then task.wait(0.3) end
    end

    task.wait(2.5)
    local afterTotal = countProbesInv() + countWorldProbes()
    local purchased = math.max(0, afterTotal - currentTotal)
    if purchased > 0 then
        uiLog(("Bought %d probe(s)"):format(purchased), "success")
    else
        uiLog("Purchase failed", "warning")
    end

    _buyInProgress = false
end

local function deleteProbe(name)
    if not name then return end
    uiLog("Cleaning up probe: "..tostring(name), "action")
    pcall(function()
        local remote = ReplicatedStorage:FindFirstChild("events") and ReplicatedStorage.events:FindFirstChild("delete_probe")
        if remote then
            remote:FireServer(tostring(name))
        end
    end)
end

local function getTornadoes()
    local storms = {}
    local stormDir = workspace:FindFirstChild("storm_related") and workspace.storm_related:FindFirstChild("storms")
    if stormDir then
        for _, storm in pairs(stormDir:GetChildren()) do
            local scan = storm:FindFirstChild("rotation") and storm.rotation:FindFirstChild("tornado_scan")
            if scan then
                table.insert(storms, {model=storm, scan=scan})
            end
        end
    end
    return storms
end

local function getTornadoWinds(storm)
    -- Helper to safely extract a number from a value that might be a string like "150 mph"
    local function parseNum(val)
        if type(val) == "number" then return val end
        if type(val) == "string" then
            local numStr = val:match("%d+%.?%d*")
            if numStr then return tonumber(numStr) end
        end
        return nil
    end

    -- Inner funnel winds: configs.tornado.winds
    local config = storm:FindFirstChild("configs") and storm.configs:FindFirstChild("tornado")
    local windsObj = config and config:FindFirstChild("winds")
    if windsObj and windsObj:IsA("ValueBase") then 
        local parsed = parseNum(windsObj.Value)
        if parsed then return parsed end
    end
    local attr = storm:GetAttribute("WindSpeed") or storm:GetAttribute("Winds") or storm:GetAttribute("Strength") or storm:GetAttribute("Wind") or storm:GetAttribute("mph")
    return parseNum(attr) or 100
end

-- Outer / environmental wind speed: configs.winds (separate from inner funnel winds).
-- When outer winds >= 70 mph the server rejects probe placement â€” skip those storms.
local function getOuterWinds(storm)
    local cfg = storm:FindFirstChild("configs")
    local obj = cfg and cfg:FindFirstChild("winds")
    if obj and obj:IsA("ValueBase") then return tonumber(obj.Value) or 0 end
    local attr = storm:GetAttribute("OuterWinds") or storm:GetAttribute("EnvWinds")
    return tonumber(attr) or 0
end

local function getTornadoRadius(storm)
    local config = storm:FindFirstChild("configs") and storm.configs:FindFirstChild("tornado")
    local sizeVal = 0
    local props = {"sfc", "width", "size"}

    -- 1. Check attributes on the storm model itself
    for _, p in ipairs(props) do
        local attr = storm:GetAttribute(p)
        if attr and tonumber(attr) then
            sizeVal = math.max(sizeVal, tonumber(attr))
        end
    end

    -- 2. Check children and attributes on the configs.tornado folder
    if config then
        for _, p in ipairs(props) do
            local obj = config:FindFirstChild(p)
            if obj and obj:IsA("ValueBase") and tonumber(obj.Value) then
                sizeVal = math.max(sizeVal, tonumber(obj.Value))
            end
            local attr = config:GetAttribute(p)
            if attr and tonumber(attr) then
                sizeVal = math.max(sizeVal, tonumber(attr))
            end
        end
    end

    -- Fallback: check base size if no surface size was found
    if sizeVal == 0 then
        local baseAttr = storm:GetAttribute("base")
        if baseAttr and tonumber(baseAttr) then
            sizeVal = math.max(sizeVal, tonumber(baseAttr))
        end
        
        if config then
            local baseObj = config:FindFirstChild("base")
            if baseObj and baseObj:IsA("ValueBase") and tonumber(baseObj.Value) then
                sizeVal = math.max(sizeVal, tonumber(baseObj.Value))
            end
            local baseAttr2 = config:GetAttribute("base")
            if baseAttr2 and tonumber(baseAttr2) then
                sizeVal = math.max(sizeVal, tonumber(baseAttr2))
            end
        end
    end
    
    if sizeVal > 0 then
        return sizeVal
    end
    
    local winds = getTornadoWinds(storm)
    return math.clamp(winds * 1.5, 100, 800)
end

-- Touchdown detector â€” monitors height ValueBase on each tornado config
local _touchdownTracked = {}
task.spawn(function()
    while _autofarmRunning do
        task.wait(0.5)
        local stormDir = workspace:FindFirstChild("storm_related") and workspace.storm_related:FindFirstChild("storms")
        if not stormDir then continue end
        for _, storm in pairs(stormDir:GetChildren()) do
            local config = storm:FindFirstChild("configs") and storm.configs:FindFirstChild("tornado")
            if not config then continue end
            local heightObj = config:FindFirstChild("height")
            if not heightObj or not heightObj:IsA("ValueBase") then continue end
            local sfcAttr = config:GetAttribute("sfc")
            local baseAttr = config:GetAttribute("base")
            local sfc = tonumber(sfcAttr) or 0
            local base = tonumber(baseAttr) or 0
            local key = storm.Name
            if heightObj.Value <= 0 then
                if not _touchdownTracked[key] then
                    _touchdownTracked[key] = true
                    local widthInfo = ""
                    if sfc > 0 or base > 0 then
                        widthInfo = (" | Width: %.0f (sfc) / %.0f (base)"):format(sfc, base)
                    end
                    uiLog("Touchdown: " .. storm.Name .. widthInfo, "success")
                end
            else
                _touchdownTracked[key] = false
            end
        end
    end
end)

local function exitVehicle()
    local char = localPlayer.Character
    local hum = char and char:FindFirstChild("Humanoid")
    if hum then
        hum.Sit = false
        if hum.SeatPart then hum.Jump = true end
        task.wait(0.3)
    end
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- ADVANCED PATHWAY PREDICTION ENGINE
-- Tracks position history, smoothed velocity, angular velocity (turn rate)
-- and projects a curved arc path rather than a simple straight line.
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local HISTORY_SIZE = 12         -- number of samples to keep (12 Ã— 0.25s = 3s window)
local stormHistory  = {}       -- [model] = {positions = ring buffer, times = ring buffer, head = index}
local stormSmoothed = {}       -- [model] = {vel = Vector3, heading = Vector3, angVel = number, speed = number}

local function getSmoothed(model)
    return stormSmoothed[model] or {vel=Vector3.new(),heading=Vector3.new(1,0,0),angVel=0,speed=0}
end

-- Pathway prediction: returns a predicted world position T seconds into the future
-- Uses stable linear prediction to prevent wild lateral offsets (false "El Reno" turns) on noisy slow storms
local function predictStormPos(model, T)
    local s = getSmoothed(model)
    local scan = model:FindFirstChild("rotation") and model.rotation:FindFirstChild("tornado_scan")
    if not scan then return model.PrimaryPart and model.PrimaryPart.Position or Vector3.new() end
    local origin = Vector3.new(scan.Position.X, 0, scan.Position.Z)
    local speed  = s.speed
    local h      = s.heading

    if speed < 0.5 then return Vector3.new(origin.X, scan.Position.Y, origin.Z) end

    -- Stable linear projection directly in the path of the heading
    return Vector3.new(origin.X + h.X*speed*T, scan.Position.Y, origin.Z + h.Z*speed*T)
end

task.spawn(function()
    while _autofarmRunning do
        -- Pause the prediction engine entirely when autofarm is off to save CPU
        if not _autofarmEnabled then task.wait(1); continue end
        local now = tick()
        local activeTornadoes = getTornadoes()
        local activeModels = {}
        for _, data in ipairs(activeTornadoes) do
            if not (data and data.scan and data.model) then continue end
            local model = data.model
            local pos   = data.scan.Position
            activeModels[model] = true

            -- Init ring buffer
            if not stormHistory[model] then
                stormHistory[model] = {
                    positions = {},
                    times     = {},
                    head      = 0,
                    count     = 0,
                }
            end
            local h = stormHistory[model]
            h.head = (h.head % HISTORY_SIZE) + 1
            h.positions[h.head] = pos
            h.times[h.head]     = now
            h.count = math.min((h.count or 0) + 1, HISTORY_SIZE)

            if h.count >= 2 then
                -- â”€â”€ Weighted velocity from last 3 samples (more recent = more weight) â”€â”€
                local vx, vz, wTotal = 0, 0, 0
                for off = 0, math.min(h.count, 3) - 2 do
                    local ia = ((h.head - off - 2) % HISTORY_SIZE) + 1
                    local ib = ((h.head - off - 1) % HISTORY_SIZE) + 1
                    local pa = h.positions[ia]; local ta = h.times[ia]
                    local pb = h.positions[ib]; local tb = h.times[ib]
                    if pa and pb and tb and ta and tb > ta then
                        local dt2 = tb - ta
                        -- off=0 is the most recent pair: give it the HIGHEST weight.
                        -- Previously this was (off+1) which was inverted â€” older pairs got more weight.
                        local maxOff = math.min(h.count, 3) - 2
                        local w = (maxOff - off) + 1
                        vx = vx + ((pb.X - pa.X) / dt2) * w
                        vz = vz + ((pb.Z - pa.Z) / dt2) * w
                        wTotal = wTotal + w
                    end
                end
                if wTotal > 0 then
                    vx = vx / wTotal; vz = vz / wTotal
                end
                local speed = math.sqrt(vx*vx + vz*vz)
                local hx, hz = 1, 0
                if speed > 0.5 then hx = vx/speed; hz = vz/speed end

                -- â”€â”€ EMA smooth velocity (50% weight to latest) â”€â”€
                local prev   = getSmoothed(model)
                local emaAlpha = 0.5
                local smoothVx = vx * emaAlpha + (prev.vel.X) * (1 - emaAlpha)
                local smoothVz = vz * emaAlpha + (prev.vel.Z) * (1 - emaAlpha)
                local smoothSpeed = math.sqrt(smoothVx*smoothVx + smoothVz*smoothVz)
                local smoothHx, smoothHz = 1, 0
                if smoothSpeed > 0.5 then smoothHx = smoothVx/smoothSpeed; smoothHz = smoothVz/smoothSpeed end

                velocities[model]    = Vector3.new(smoothVx, 0, smoothVz)
                stormSmoothed[model] = {
                    vel     = Vector3.new(smoothVx, 0, smoothVz),
                    heading = Vector3.new(smoothHx, 0, smoothHz),
                    angVel  = 0,
                    speed   = smoothSpeed,
                }
            end

            lastPositions[model] = pos
        end

        -- Clean up stale storm data for storms that no longer exist
        for model in pairs(stormHistory) do
            if not activeModels[model] then
                stormHistory[model] = nil
                stormSmoothed[model] = nil
                velocities[model] = nil
            end
        end

        task.wait(0.25)
    end
end)

-- Anti-kidnap: eject from any seat that isn't the player's own vehicle
local function setupSeatGuard(char)
    local hum = char:FindFirstChildWhichIsA("Humanoid")
    if not hum then return end
    hum.Seated:Connect(function(isSeated, seat)
        if not isSeated or not _autofarmEnabled then return end
        if not seat then return end
        local model = seat:FindFirstAncestorWhichIsA("Model")
        if model and model.Name:lower():match(VEHICLE_NAME:lower()) then return end
        task.wait(0.1)
        hum.Jump = true
        uiLog("Ejected from vehicle", "warning")
    end)
end
if localPlayer.Character then task.spawn(function() setupSeatGuard(localPlayer.Character) end) end
localPlayer.CharacterAdded:Connect(setupSeatGuard)

-- Death / auto-respawn (uses game healthbar fillbar)
task.spawn(function()
    local cooldown = false
    while _autofarmRunning do
        task.wait(1)
        if not _autofarmEnabled or cooldown then continue end
        local isDead = false
        pcall(function()
            local iface = localPlayer.PlayerGui:FindFirstChild("interface")
            local fb = iface and iface:FindFirstChild("healthbar") and iface.healthbar:FindFirstChild("fillbar")
            if fb and fb:IsA("GuiObject") and fb.Size.X.Scale <= 0 then isDead = true end
        end)
        if not isDead then
            local hum = localPlayer.Character and localPlayer.Character:FindFirstChild("Humanoid")
            if hum and hum.Health <= 0 then isDead = true end
        end
        if isDead then
            cooldown = true
            _isBusy = false; _isWaiting = false
            uiLog("Died", "error")
            deathsCount = deathsCount + 1
            local remote = ReplicatedStorage:FindFirstChild("events") and ReplicatedStorage.events:FindFirstChild("plr_respawn")
            if remote then pcall(function() remote:FireServer() end) end
            pcall(function()
                for _, gui in pairs(localPlayer.PlayerGui:GetChildren()) do
                    if gui:IsA("ScreenGui") and gui.Enabled then
                        for _, v in pairs(gui:GetDescendants()) do
                            if v:IsA("TextButton") and (v.Text:lower():match("respawn") or v.Name:lower():match("respawn")) then
                                v:Activate()
                            end
                        end
                    end
                end
            end)
            local t = 0
            while t < 10 do
                task.wait(1); t += 1
                local alive = false
                pcall(function()
                    local iface = localPlayer.PlayerGui:FindFirstChild("interface")
                    local fb = iface and iface:FindFirstChild("healthbar") and iface.healthbar:FindFirstChild("fillbar")
                    if fb and fb.Size.X.Scale > 0 then alive = true end
                end)
                if alive then break end
            end
            task.wait(2)
            
            -- Auto-teleport to staging area upon respawn, UNLESS we are currently placing probes
            if _autofarmEnabled and not _clusterActive then
                local char = localPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if root then
                    uiLog("Respawned. Returning to staging.", "action")
                    _startCF = CFrame.new(START_POS)
                    root.CFrame = _startCF
                    _startHolding = true
                    _holdId = _holdId + 1
                    local myHoldId = _holdId
                    task.spawn(function()
                        while _startHolding and myHoldId == _holdId and _autofarmEnabled and root and root.Parent do
                            root.CFrame = _startCF
                            root.Velocity = Vector3.new(0, 0, 0)
                    game:GetService("RunService").RenderStepped:Wait()
                        end
                    end)
                    spawnVehicle()
                end
            end
            
            cooldown = false
        end
    end
end)

-- Probe health monitor
local _forceHealthCheck = false
task.spawn(function()
    local lastHealth = {}; local lastSummaryTime = 0; local hasLoggedInitial = false
    local function getProbeName(page)
        for _, v in pairs(page:GetDescendants()) do
            if v:IsA("TextLabel") then
                local t = v.Text:lower()
                if not t:match("money") and not t:match("made") and not t:match("earnings") and #t > 1 then return v.Text end
            end
        end
        return "Unknown Probe"
    end
    while _autofarmRunning do
        task.wait(2)
        local iface = localPlayer.PlayerGui:FindFirstChild("interface")
        local pages = iface and iface:FindFirstChild("probe_menu") and iface.probe_menu:FindFirstChild("main") and iface.probe_menu.main:FindFirstChild("pages")
        if pages then
            local stats = {}
            for _, page in pairs(pages:GetChildren()) do
                if page:IsA("Frame") or page:IsA("CanvasGroup") then
                    local hb = page:FindFirstChild("health",true) and page.health:FindFirstChild("bar",true) and page.health.bar:FindFirstChild("bar",true)
                    if hb and hb:IsA("GuiObject") then
                        local hp = math.floor(hb.Size.X.Scale * 100)
                        local name = getProbeName(page)
                        local inGracePeriod = _lastPlacementTime and (tick() - _lastPlacementTime) < 15
                        if hp <= 0 and (not lastHealth[page] or lastHealth[page] > 0) and not inGracePeriod then
                            uiLog(name .. " destroyed", "error")
                            gameNotify("Probe Destroyed", name.." has been destroyed!", 6, 10)
                            probesDestroyed += 1
                        end
                        table.insert(stats, name.." ("..hp.."%)")
                        lastHealth[page] = hp
                    end
                end
            end
            if #stats > 0 then
                local shouldReport = not hasLoggedInitial or _forceHealthCheck or (_autofarmEnabled and tick() - lastSummaryTime > 30)
                if shouldReport then
                    uiLog("Probes: " .. table.concat(stats, " | "), "success")
                    hasLoggedInitial = true; lastSummaryTime = tick(); _forceHealthCheck = false
                end
            end
            for page in pairs(lastHealth) do if not page.Parent then lastHealth[page] = nil end end
        end
    end
end)

-- Probe pickup
local _pickupInProgress = false
local PICKUP_MIN_DELAY = 15  -- passive-loop guard only; explicit calls pass force=true to bypass
local _lastPickupStart = 0
local function pickupMyProbes(force)
    -- Emergency reset if stuck for > 60s
    if _pickupInProgress and tick() - _lastPickupStart > 60 then
        _pickupInProgress = false
    end
    if _pickupInProgress then return end
    if not force and tick() - _lastPlacementTime < PICKUP_MIN_DELAY then return end
    _pickupInProgress = true
    _lastPickupStart = tick()
    local char = localPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then _pickupInProgress = false; return end

    local folder = workspace:FindFirstChild("player_related") and workspace.player_related:FindFirstChild("probes")
    if not folder then _pickupInProgress = false; return end

    local myId = tostring(localPlayer.UserId)

    local myProbes = {}
    for _, probe in pairs(folder:GetChildren()) do
        local attr = probe:GetAttribute("id") or probe:GetAttribute("OwnerId") or probe:GetAttribute("owner")
        if (tostring(attr) == myId) or probe.Name:match(myId) then
            local prompt = probe:FindFirstChildWhichIsA("ProximityPrompt", true)
            local probeRoot = probe.PrimaryPart or probe:FindFirstChildWhichIsA("BasePart")
            if prompt and probeRoot then
                local promptPart = prompt.Parent and prompt.Parent:IsA("BasePart") and prompt.Parent or probeRoot
                table.insert(myProbes, {probe=probe, prompt=prompt, probeRoot=promptPart})
            end
        end
    end

    if #myProbes == 0 then _pickupInProgress = false; return end

    -- Sort nearest-first to minimise total teleport distance
    table.sort(myProbes, function(a, b)
        return (a.probeRoot.Position - root.Position).Magnitude
             < (b.probeRoot.Position - root.Position).Magnitude
    end)

    local originalCF = root.CFrame
    local wasInSky = originalCF.Y > 1000
    local collectedCount = 0
    local exitedVehicle = false

    local function tryPickup(data)
        local probe, prompt, probeRoot = data.probe, data.prompt, data.probeRoot
        if not probe.Parent or not probeRoot.Parent then return true end -- already gone

        -- Use dynamic radius-based safety margin for pickup
        for _, sd in ipairs(getTornadoes()) do
            local d = (Vector3.new(sd.scan.Position.X, 0, sd.scan.Position.Z)
                     - Vector3.new(probeRoot.Position.X, 0, probeRoot.Position.Z)).Magnitude
            local r = getTornadoRadius(sd.model)
            -- Tight margin for small storms â€” just clear the sfc radius + a small buffer
            local safetyMargin = r + math.clamp(r * 0.5, 50, 200)
            if d < safetyMargin then return nil end -- unsafe, skip for now
        end

        if not exitedVehicle then exitVehicle(); exitedVehicle = true end

        prompt.HoldDuration = 0
        prompt.MaxActivationDistance = 128

        -- Teleport to the part the prompt is on dynamically using character height offset
        local char = localPlayer.Character
        local hOffset = char and getCharHeightOffset(char) or 2
        local targetCF = CFrame.new(probeRoot.Position + Vector3.new(0, hOffset, 0))
        root.CFrame = targetCF
        root.Velocity = Vector3.new(0, 0, 0)

        -- Force standing state so proximity prompt interaction works
        local hum = char:FindFirstChild("Humanoid")
        if hum then
            hum.PlatformStand = false
            hum:ChangeState(Enum.HumanoidStateType.Landed)
        end

        local _holding = true
        local holdConn = {Disconnect = function() _holding = false end}
        task.spawn(function()
            while _holding and root and root.Parent do
                root.CFrame = targetCF
                root.Velocity = Vector3.new(0, 0, 0)
                    game:GetService("RunService").RenderStepped:Wait()
            end
        end)

        task.wait(0.15)  -- let server register new position before firing

        local invBefore = countProbesInv()
        local collected = false
        for i = 1, 10 do
            if not probe or not probe.Parent then collected = true; break end
            fireproximityprompt(prompt)
            task.wait(0.05)
            fireproximityprompt(prompt)
            task.wait(0.05)
            fireproximityprompt(prompt)
            task.wait(0.15)  -- was 0.2
            if countProbesInv() > invBefore then collected = true; break end
        end

        holdConn:Disconnect()
        return collected
    end

    -- First pass
    local failedProbes = {}
    for _, data in ipairs(myProbes) do
        if not _autofarmEnabled then break end
        local result = tryPickup(data)
        if result == true then
            collectedCount += 1
            probesRecovered += 1
        elseif result == false then
            table.insert(failedProbes, data) -- failed (not unsafe) â€” queue for retry
        end
        -- nil = unsafe, just skip silently
    end

    -- Second pass: retry any that failed on first attempt
    if #failedProbes > 0 and _autofarmEnabled then
        uiLog(("Retrying %d probe(s)"):format(#failedProbes), "action")
        task.wait(0.5)
        for _, data in ipairs(failedProbes) do
            if not _autofarmEnabled then break end
            local result = tryPickup(data)
            if result == true then
                collectedCount += 1
                probesRecovered += 1
            elseif result == false then
                uiLog("Probe unreachable. Skipping.", "warning")
            end
        end
    end

    if collectedCount > 0 then
        uiLog(("Recovered %d probe(s)"):format(collectedCount), "success")
        if not wasInSky then
            root.CFrame = originalCF
            root.Velocity = Vector3.new(0, 0, 0)
        end
    end
    _pickupInProgress = false
end

task.spawn(function()
    while _autofarmRunning do
        task.wait(5)
        if not _autofarmEnabled or _isBusy or _isWaiting or _pickupInProgress then continue end
        -- Only passively pick up if enough time has passed since last placement
        if _lastPlacementTime and (tick() - _lastPlacementTime) < PICKUP_MIN_DELAY then continue end
        pickupMyProbes()
    end
end)

-- Watchdog: reset stuck flags so pickup is never silently blocked
task.spawn(function()
    local busyStart = 0
    local waitStart = 0
    local pickupStart = 0
    while _autofarmRunning do
        task.wait(10)
        local now = tick()
        if _isBusy then
            if busyStart == 0 then busyStart = now end
            if now - busyStart > 45 then
                uiLog("Watchdog: Busy stuck. Resetting.", "warning")
                _isBusy = false; busyStart = 0
            end
        else busyStart = 0 end

        if _isWaiting then
            if waitStart == 0 then waitStart = now end
            if now - waitStart > 200 then
                uiLog("Watchdog: Waiting stuck. Resetting.", "warning")
                _isWaiting = false
                _startHolding = false  -- release position lock too
                local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
                if root then root.Anchored = false end
                waitStart = 0
            end
        else waitStart = 0 end

        if _pickupInProgress then
            if pickupStart == 0 then pickupStart = now end
            if now - pickupStart > 30 then
                uiLog("Watchdog: Pickup stuck. Resetting.", "warning")
                _pickupInProgress = false; pickupStart = 0
            end
        else pickupStart = 0 end
    end
end)

-- Module-level flags for game notifications (set once; were incorrectly re-connected each loop iteration)
local _needsMoreBuffer   = false
local _lastPlacementFailed = false
local _leavingStorms = {}
pcall(function()
    local remote = ReplicatedStorage:FindFirstChild("events") and ReplicatedStorage.events:FindFirstChild("notify_plr")
    if remote then
        remote.OnClientEvent:Connect(function(data)
            if not data or not data.text then return end
            local txt = data.text:lower()
            if txt:match("threshold") or txt:match("too high") then
                _needsMoreBuffer = true
            elseif txt:match("placement failed") then
                _lastPlacementFailed = true
            elseif (data.title and data.title:match("Destroyed")) or txt:match("destroyed") then
                uiLog("Event: " .. data.text, "error")
                probesDestroyed += 1
            end
        end)
    end
end)

-- Main autofarm loop
task.spawn(function()
    uiLog("Autofarm loaded. Ready.","action")
    local loggedWaiting = false; local firstRun = true; local _noStormTimer = nil; local lastHeartbeat = tick()
    while _autofarmRunning do
        task.wait(0.5)
        if not _autofarmEnabled then firstRun = true; continue end
        
        -- Heartbeat
        if tick() - lastHeartbeat > 30 then
            lastHeartbeat = tick()
        end

        -- Guard: if placement/watching is in progress, skip this tick entirely
        if _isBusy or _isWaiting then task.wait(0.5); continue end
        
        local char = localPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then continue end
        
        local probeAssets = ReplicatedStorage:FindFirstChild("client_assets")
            and ReplicatedStorage.client_assets:FindFirstChild("vehicles")
            and ReplicatedStorage.client_assets.vehicles:FindFirstChild("probes")
            
        -- Inventory check: use probeAssets if available, fall back to name match
        local function getProbes()
            local found = {}
            local function isProbe(t)
                if not t:IsA("Tool") then return false end
                local n = t.Name:lower()
                if n:match("probe") or n:match("twistex") or n:match("tower") or n:match("pod") or n:match("v2") then return true end
                if probeAssets and probeAssets:FindFirstChild(t.Name) then return true end
                return false
            end
            for _, t in ipairs(localPlayer.Backpack:GetChildren()) do
                if isProbe(t) then table.insert(found, t) end
            end
            for _, t in ipairs(char:GetChildren()) do
                if isProbe(t) then table.insert(found, t) end
            end
            return found
        end

        -- Shared probe-item check (respects probeAssets when present, falls back to name match)
        local function isProbeItem(t)
            if not t:IsA("Tool") then return false end
            local n = t.Name:lower()
            if n:match("probe") or n:match("twistex") or n:match("tower") or n:match("pod") or n:match("v2") then return true end
            if probeAssets and probeAssets:FindFirstChild(t.Name) then return true end
            return false
        end

        local worldCount = countWorldProbes()

        local storms = getTornadoes()
        local stormForming = false
        for _, stormData in ipairs(storms) do
            local config = stormData.model:FindFirstChild("configs") and stormData.model.configs:FindFirstChild("tornado")
            local hObj = config and config:FindFirstChild("height")
            if hObj and hObj:IsA("ValueBase") then
                local h = hObj.Value
                local lastH = _stormHeights[stormData.model.Name]
                _stormHeights[stormData.model.Name] = h
                if h > 0 and lastH and h < lastH - 0.2 then
                    stormForming = true
                end
            end
        end

        local probesToPlace = getProbes()

        -- On first run, try to collect any idle world probes
        if firstRun then
            firstRun = false
            if worldCount > 0 and #storms == 0 and not stormForming then
                uiLog("Collecting startup probes...", "action")
                pickupMyProbes(true)
                task.wait(1)
                if not _autofarmEnabled then continue end
                worldCount = countWorldProbes()
                probesToPlace = getProbes()
            end
        end

        -- Buy probes whenever inventory is low (not gated on storm presence)
        -- NEVER buy while probes are deployed in the world (spawning vehicle will delete them)
        local worldNow = countWorldProbes()
        local totalNow = countProbesInv() + worldNow
        if totalNow < PROBE_TARGET and not _buyInProgress and worldNow == 0 then
            local hum = localPlayer.Character and localPlayer.Character:FindFirstChild("Humanoid")
            local isSeated = hum and hum.SeatPart ~= nil
            if not isSeated then
                if totalNow == 0 then
                    -- Only spawn vehicle if we are safely at the staging area to avoid spawning it at a tornado
                    if (root.Position - START_POS).Magnitude < 1000 then
                        uiLog("No probes. Buying...", "action")
                        spawnVehicle()
                        task.wait(1)
                    else
                        uiLog("No probes. Returning to spawn to restock.", "warning")
                        _isBusy = false -- Force return to spawn loop
                        continue
                    end
                    if not _autofarmEnabled then continue end
                end
                buyProbe(PROBE_TARGET - totalNow)
                task.wait(1.0)
                probesToPlace = getProbes()
                if totalNow == 0 and countProbesInv() == 0 then
                    uiLog("Buy failed. Retrying...", "error")
                    task.wait(2); continue
                end
            end
        end

        _lastPlacementFailed = false
        -- Explicitly sort storms by windpower (highest winds first) with strict numeric fallbacks
        table.sort(storms, function(a, b)
            local windsA = tonumber(getTornadoWinds(a.model)) or 0
            local windsB = tonumber(getTornadoWinds(b.model)) or 0
            return windsA > windsB
        end)
        local targetFound = false
        local stormOverWater = false
        local skipLogTick = tick()
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        local excl = {char}
        if workspace:FindFirstChild("storm_related") then table.insert(excl, workspace.storm_related) end
        if workspace:FindFirstChild("player_related") then table.insert(excl, workspace.player_related) end
        rayParams.FilterDescendantsInstances = excl

        -- Helper: cast downward and find the first solid, collidable terrain surface.
        -- Skips non-collidable parts, then returns the first proper terrain hit.
        local function solidGroundRay(x, z)
            local origin = Vector3.new(x, 3000, z)
            local dir    = Vector3.new(0, -5000, 0)
            
            local excluded = {table.unpack(excl)}
            local hum = char:FindFirstChild("Humanoid")
            local seat = hum and hum.SeatPart
            local vehicle = seat and seat:FindFirstAncestorWhichIsA("Model")
            if vehicle then table.insert(excluded, vehicle) end
            
            local rp = RaycastParams.new()
            rp.FilterType = Enum.RaycastFilterType.Exclude
            rp.FilterDescendantsInstances = excluded

            -- Simple, reliable: skip non-collidable parts and map barriers (so it finds the ground under them)
            for _ = 1, 8 do
                local hit
                pcall(function() hit = workspace:Raycast(origin, dir, rp) end)
                if not hit then return nil end
                
                local isBarrier = false
                local mr = workspace:FindFirstChild("map_related")
                local barriers = mr and mr:FindFirstChild("barriers")
                if (barriers and hit.Instance:IsDescendantOf(barriers)) or hit.Instance.Name:lower():match("barrier") then
                    isBarrier = true
                end

                -- If the part can collide and is not a barrier, it's valid ground
                if hit.Instance:IsA("BasePart") and hit.Instance.CanCollide and not isBarrier then
                    return hit
                elseif hit.Instance:IsA("Terrain") then
                    return hit
                end
                -- Otherwise, exclude it and try again from just below
                table.insert(excluded, hit.Instance)
                rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                rp.FilterDescendantsInstances = excluded
                origin = hit.Position - Vector3.new(0, 0.1, 0)
            end
            return nil
        end

        for _, stormData in ipairs(storms) do
            local best = stormData.model
            local scan = stormData.scan
            
            local groundCheck = solidGroundRay(scan.Position.X, scan.Position.Z)
            local groundY = groundCheck and groundCheck.Position.Y or 0
            
            -- Skip reasons (Relaxed for forming storms so we can pre-position)
            local stormHeight = scan.Position.Y - groundY
            local isFormingThisStorm = false
            
            -- Check if this specific storm is the one we saw forming
            local config = best:FindFirstChild("configs") and best.configs:FindFirstChild("tornado")
            local heightObj = config and config:FindFirstChild("height")
            if heightObj and heightObj:IsA("ValueBase") then
                local h = heightObj.Value
                local lastH = _stormHeights[best.Name]
                if h > 0 and lastH and h < lastH - 0.2 then
                    isFormingThisStorm = true
                end
            end

            if isFormingThisStorm then
                uiLog("Targeting forming storm...", "action")
            end

            -- Touchdown check: consider it touched down early (height <= 250) so it targets faster
            local isTouchedDown = (heightObj and heightObj.Value <= 250)
            if stormHeight > 400 and not isFormingThisStorm and not isTouchedDown then
                if tick() - skipLogTick > 15 then
                    uiLog("Storm too high. Skipping.", "warning")
                    skipLogTick = tick()
                end
                continue 
            end

            -- Only skip if height is clearly above ground AND not descending AND not considered touched down
            if heightObj and heightObj:IsA("ValueBase") and heightObj.Value > 250 and not isFormingThisStorm and not isTouchedDown then 
                if tick() - skipLogTick > 15 then
                    uiLog("Funnel not touched down. Skipping.", "warning")
                    skipLogTick = tick()
                end
                continue 
            end

            -- [Storm out-of-bounds check moved below heading calculation for re-entering detection]


            local vel = velocities[best] or Vector3.new(0,0,0)
            local flatVel = Vector3.new(vel.X,0,vel.Z)
            local s = getSmoothed(best)
            -- Use smoothed heading from the prediction engine (much more stable than raw vel)
            local heading = s.speed > 0.5 and s.heading or (flatVel.Magnitude > 1 and flatVel.Unit or Vector3.new(1,0,0))
            local stormSpeed = s.speed

            -- Check if storm is out of bounds or heading towards barrier with no placement room
            local function checkIsStormOutOfBounds(scanPos)
                local mr = workspace:FindFirstChild("map_related")
                local barriers = mr and mr:FindFirstChild("barriers")
                if not barriers then return false end
                
                -- Raycast from spawn (definitely in-bounds) to the storm
                local startP = Vector3.new(START_POS.X, math.max(scanPos.Y, 50), START_POS.Z)
                local targetP = Vector3.new(scanPos.X, startP.Y, scanPos.Z)
                local bp = RaycastParams.new()
                bp.FilterType = Enum.RaycastFilterType.Include
                bp.FilterDescendantsInstances = {barriers}
                return workspace:Raycast(startP, targetP - startP, bp) ~= nil
            end

            local isOob = checkIsStormOutOfBounds(scan.Position)
            local isLeaving = _leavingStorms[best.Name] and (tick() - _leavingStorms[best.Name] < 45)
            local reEntering = false
            
            -- Direction from storm to map center (START_POS)
            local toMapCenter = (Vector3.new(START_POS.X, 0, START_POS.Z) - Vector3.new(scan.Position.X, 0, scan.Position.Z)).Unit
            if heading:Dot(toMapCenter) > 0.15 then
                reEntering = true
            end

            if (isOob or isLeaving) and not reEntering then
                if tick() - skipLogTick > 15 then
                    uiLog("Storm leaving map. Ignoring.", "warning")
                    skipLogTick = tick()
                end
                continue
            end

            -- Wait for forming/stationary storms to start moving and establish a stable path before placing
            if stormSpeed < 0.5 then
                if tick() - skipLogTick > 15 then
                    uiLog("Storm not moving. Skipping.", "warning")
                    skipLogTick = tick()
                end
                continue
            end

            local sfcRadius = getTornadoRadius(best)
            local winds = getTornadoWinds(best)

            -- Minimum wind threshold: probes don't earn below 65 mph
            local MIN_WINDS = 65
            if winds < MIN_WINDS then
                if tick() - skipLogTick > 15 then
                    uiLog("Winds too low. Ignoring.", "warning")
                    skipLogTick = tick()
                end
                continue
            end

            -- Outer wind check
            local MAX_OUTER_WINDS = 70  -- module-accessible threshold
            local outerWinds = getOuterWinds(best)
            if outerWinds >= MAX_OUTER_WINDS then
                if tick() - skipLogTick > 15 then
                    uiLog(("High outer winds (%d mph). Stepping back further."):format(math.floor(outerWinds)), "warning")
                    skipLogTick = tick()
                end
            end

            -- â”€â”€ SMART PLACEMENT DISTANCE â”€â”€
            -- Dynamically scale based on storm speed and wind severity. High-wind storms (200+ mph)
            -- have massive server-side rejection radiuses that require extreme lead distances.
            -- â”€â”€ SMART PLACEMENT DISTANCE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            -- Smoothed out wind scaling to prevent extreme over-placement on 300+ mph storms
            local speedFactor = math.max(stormSpeed, 15)

            -- Radius-based buffer (how far past the funnel edge to stand)
            local buffer
            if sfcRadius < 150 then buffer = 300
            elseif sfcRadius < 250 then buffer = 450
            elseif sfcRadius < 400 then buffer = 600
            elseif sfcRadius < 600 then buffer = 900
            else buffer = math.max(1200, math.floor(sfcRadius * 1.5)) end

            -- Time lead: distance the storm travels during the 3-second placement sequence
            local placementTimeLead = stormSpeed * 4 

            -- windFactor: scales smoothly from 1 to 6
            local windFactor = math.clamp(winds / 60, 1, 6)
            local targetDist = math.max(speedFactor * 12 * windFactor, sfcRadius + buffer) + placementTimeLead + 100

            -- Tiered high-wind bonuses (Reduced significantly)
            local highWindLog = nil
            if winds >= 150 or _needsMoreBuffer then
                local extra
                if _needsMoreBuffer       then extra = 1200
                elseif winds >= 400       then extra = 2000
                elseif winds >= 300       then extra = 1200
                elseif winds >= 200       then extra = 600
                else                           extra = 200   -- 150â€“199 mph
                end
                targetDist = targetDist + extra
                highWindLog = ("High winds (%d mph). Extra distance +%d."):format(math.floor(winds), extra)
                _needsMoreBuffer = false
            end

            -- Outer winds bonus: +15 studs per mph over 45, cap 800
            if outerWinds > 45 then
                local outerExtra = math.min(math.floor((outerWinds - 45) * 15), 800)
                targetDist = targetDist + outerExtra
            end


            -- Place directly in front of the storm along its stable heading
            local predictedPos = Vector3.new(scan.Position.X, scan.Position.Y, scan.Position.Z)
                + heading * targetDist
            local groundPos = predictedPos
            local foundValidSpot = false

            local function checkBarrier(tp)
                local mr = workspace:FindFirstChild("map_related")
                local barriers = mr and mr:FindFirstChild("barriers")
                if not barriers then return false end
                local startP = Vector3.new(scan.Position.X, math.max(scan.Position.Y, 50), scan.Position.Z)
                local targetP = Vector3.new(tp.X, startP.Y, tp.Z)
                local bp = RaycastParams.new()
                bp.FilterType = Enum.RaycastFilterType.Include
                bp.FilterDescendantsInstances = {barriers}
                return workspace:Raycast(startP, targetP - startP, bp) ~= nil
            end
            -- Search offsets: try exact spot first, scan forward AND laterally for valid ground
            -- We DO NOT scan backward (negative heading) because that eats into our carefully calculated safety buffer!
            local right = Vector3.new(-heading.Z, 0, heading.X) -- perpendicular to heading
            local offsets = {
                Vector3.new(0,0,0),
                heading*150,       heading*300,       heading*500,    heading*700,
                right*150,         right*-150,
                right*300,         right*-300,
                heading*150 + right*150,  heading*150 - right*150,
                heading*300 + right*200,  heading*300 - right*200
            }
            local hitBarrierCount = 0
            for _, off in ipairs(offsets) do
                local tp = predictedPos + off
                local ray = solidGroundRay(tp.X, tp.Z)
                if ray then
                    if checkBarrier(tp) then
                        hitBarrierCount += 1
                    else
                        local dToStorm = (Vector3.new(tp.X,0,tp.Z) - Vector3.new(scan.Position.X,0,scan.Position.Z)).Magnitude
                        -- Massive safety check: NEVER place anywhere near the visual funnel to avoid immediate death by suction
                        local minimumSafeDist = sfcRadius + math.max(300, targetDist * 0.25)
                        if dToStorm < minimumSafeDist then continue end 

                        groundPos = ray.Position
                        foundValidSpot = true
                        break
                    end
                end
            end
            if not foundValidSpot then 
                local isHeadingToBarrier = checkBarrier(predictedPos)
                if hitBarrierCount > 0 or isHeadingToBarrier then
                    uiLog("Leaving map. Skipping.", "warning", 20)
                    _leavingStorms[best.Name] = tick()
                else
                    uiLog("No valid spot. Waiting...", "warning", 10)
                end
                continue 
            end
            
            if highWindLog then uiLog(highWindLog, "warning") end
            targetFound = true; loggedWaiting = false; _isBusy = true
            stormsTargeted = stormsTargeted + 1
            uiLog(("Targeting %s (%d mph)"):format(best.Name, math.floor(winds)), "success")
            -- Warn player if winds are dangerously high (using user's exact snippet logic)
            if winds >= 250 then
                uiLog("Dangerous winds!", "error")
                gameNotify("Warning", "Windspeeds over probe placement threshold!", 5, 60)
            end
            exitVehicle()
            -- RELEASE start-position lock
            _startHolding = false
            
            -- Teleport to spot
            local charHeight = getCharHeightOffset(char)
            local holdCF = CFrame.new(groundPos + Vector3.new(0, charHeight, 0)) * CFrame.Angles(0, math.atan2(heading.X, heading.Z), 0)
            root.CFrame = holdCF
            root.Velocity = Vector3.new(0, 0, 0)

            local hum = char:FindFirstChild("Humanoid")
            if hum then
                hum.PlatformStand = false; hum.Sit = false
                hum:ChangeState(Enum.HumanoidStateType.Landed)
            end

            -- Let physics settle FIRST (no lock) so the server sees a grounded character
            task.wait(0.4)

            -- Now hold position with a gentle Heartbeat loop (NOT RenderStepped)
            -- RenderStepped fires 60x/sec and fights physics, preventing the server from seeing us as grounded
            local _holding1 = true
            local holdConn = {Disconnect = function() _holding1 = false end}
            table.insert(activeConnections, holdConn)
            task.spawn(function()
                while _holding1 and root and root.Parent do
                    root.CFrame = holdCF
                    root.Velocity = Vector3.new(0, 0, 0)
                    -- Extra: suppress Y velocity to fight tornado suction / liftoff at high outer winds
                    pcall(function()
                        if root.AssemblyLinearVelocity.Y > 0.5 then
                            root.AssemblyLinearVelocity = Vector3.new(
                                root.AssemblyLinearVelocity.X * 0.1,
                                0,
                                root.AssemblyLinearVelocity.Z * 0.1)
                        end
                    end)
                    task.wait(0.05)
                end
            end)
            task.wait(0.1)
            local safetyAborted = false
            local _damageTaken = false
            local lastHealthScale = 1
            pcall(function()
                local iface = localPlayer.PlayerGui:FindFirstChild("interface")
                local fb = iface and iface:FindFirstChild("healthbar") and iface.healthbar:FindFirstChild("fillbar")
                if fb then lastHealthScale = fb.Size.X.Scale end
            end)

            task.spawn(function()
                while _isBusy and _autofarmEnabled and not safetyAborted do
                    task.wait(0.1)
                    local currentScale = 1
                    pcall(function()
                        local iface = localPlayer.PlayerGui:FindFirstChild("interface")
                        local fb = iface and iface:FindFirstChild("healthbar") and iface.healthbar:FindFirstChild("fillbar")
                        if fb then currentScale = fb.Size.X.Scale end
                    end)

                    if currentScale < lastHealthScale - 0.01 then
                        uiLog("Damage detected! Evacuating.", "error")
                        gameNotify("Emergency", "Taking damage! Evacuating.", 5, 10)
                        _damageTaken = true; safetyAborted = true; break
                    end
                    lastHealthScale = currentScale

                    if best and best.Parent then
                        local d = (Vector3.new(root.Position.X,0,root.Position.Z) - Vector3.new(scan.Position.X,0,scan.Position.Z)).Magnitude
                        -- Evacuate if storm gets within sfc + 50 studs (actual damage zone)
                        local dangerEdge = sfcRadius + 50
                        if d < dangerEdge then
                            uiLog("Storm too close! Evacuating.", "error")
                            gameNotify("Emergency", "Storm reached probe site! Evacuating.", 5, 15)
                            safetyAborted = true
                        end
                    else safetyAborted = true end
                end
            end)
            -- Per-probe placement with retry â€” confirms each probe was consumed before moving on.
            -- If the server rejects placement (high winds), steps forward and retries up to 3 times.
            local placedCount = 0
            local allProbes = getProbes()
            _clusterActive = true

            local function tryPlaceProbe(probe)
                if not (probe and probe.Parent) then return false end
                if probe.Parent ~= localPlayer.Backpack and probe.Parent ~= char then return false end

                local VirtualUser = game:GetService("VirtualUser")

                for attempt = 1, 3 do
                    if not _autofarmEnabled or safetyAborted or not _clusterActive then return false end
                    _lastPlacementFailed = false
                    _needsMoreBuffer = false

                    -- Equip the probe (direct, no backpack round-trip)
                    local successEquip, equipErr = pcall(function()
                        probe.Parent = char
                    end)
                    if not successEquip then
                        uiLog("Equip failed: " .. tostring(equipErr), "warning")
                        return false
                    end
                    -- 0.3s settle: server needs to register the equip before Activate() fires
                    task.wait(0.3)

                    if probe.Parent ~= char then continue end

                    -- Force standing state so server ground raycast succeeds
                    local hum2 = char:FindFirstChild("Humanoid")
                    if hum2 then
                        hum2.PlatformStand = false
                        hum2:ChangeState(Enum.HumanoidStateType.Landed)
                    end

                    -- Activate twice (sourcecode.lua pattern)
                    pcall(function() probe:Activate() end)
                    task.wait(0.05)
                    if probe.Parent == char then
                        pcall(function()
                            VirtualUser:Button1Down(Vector2.new(0,0))
                            task.wait(0.05)
                            VirtualUser:Button1Up(Vector2.new(0, 0))
                        end)
                    end

                    -- Poll for server confirmation (max 3.0s)
                    task.wait(0.2)
                    for w = 1, 28 do
                        if probe.Parent ~= char and probe.Parent ~= localPlayer.Backpack then break end
                        if not _clusterActive or safetyAborted then return false end
                        if _needsMoreBuffer or _lastPlacementFailed then break end
                        task.wait(0.1)
                    end

                    -- Success: server consumed the tool
                    if probe.Parent ~= char and probe.Parent ~= localPlayer.Backpack then
                        return true
                    end

                    -- Rejected by server.
                    pcall(function() probe.Parent = localPlayer.Backpack end)
                    local currentOuter = getOuterWinds(best)
                    if currentOuter >= MAX_OUTER_WINDS then
                        -- Outer winds too high: step further away from the storm and retry immediately
                        uiLog("High outer winds. Stepping back.", "warning")
                        local stepDist = attempt * 350  -- step 350/700/1050 studs further per attempt
                        local stepPos = root.Position + heading * stepDist
                        local stepRay = workspace:Raycast(
                            Vector3.new(stepPos.X, 3000, stepPos.Z),
                            Vector3.new(0, -5000, 0),
                            rayParams
                        )
                        if stepRay and stepRay.Position.Y <= 500 then
                            local newCF = CFrame.new(stepRay.Position + Vector3.new(0, getCharHeightOffset(char), 0))
                                * CFrame.Angles(0, math.atan2(heading.X, heading.Z), 0)
                            holdCF = newCF
                            root.CFrame = newCF
                            root.Velocity = Vector3.new(0, 0, 0)
                        end
                        task.wait(0.5)
                    else
                        -- Rejected for other reason: step further AHEAD (away from storm) and retry
                        uiLog("Rejected. Stepping forward.", "warning")
                        local stepPos = root.Position + heading * (attempt * 200)
                        local stepRay = workspace:Raycast(
                            Vector3.new(stepPos.X, 3000, stepPos.Z),
                            Vector3.new(0, -5000, 0),
                            rayParams
                        )
                        if stepRay and stepRay.Position.Y <= 500 then
                            local newCF = CFrame.new(stepRay.Position + Vector3.new(0, getCharHeightOffset(char), 0))
                                * CFrame.Angles(0, math.atan2(heading.X, heading.Z), 0)
                            holdCF = newCF
                            root.CFrame = newCF
                            root.Velocity = Vector3.new(0, 0, 0)
                        end
                    end
                    _needsMoreBuffer = false
                    _lastPlacementFailed = false
                    task.wait(0.3)
                end

                pcall(function() probe.Parent = localPlayer.Backpack end)
                return false
            end

            local totalToPlace = #allProbes
            if totalToPlace > 0 then
                uiLog(("Deploying %d probe(s)..."):format(totalToPlace), "action")

                local i = 1
                while i <= totalToPlace and not safetyAborted and _autofarmEnabled and not _needsMoreBuffer do
                    local probeA = allProbes[i]
                    local probeB = allProbes[i + 1]  -- nil if only 1 probe left

                    -- Re-center at placement spot before each pair.
                    -- Recompute targetDist from LIVE winds so a mid-cycle spike is handled immediately.
                    do
                        local liveWinds    = getTornadoWinds(best)
                        local liveOuter    = getOuterWinds(best)
                        local liveSfcRad   = getTornadoRadius(best)
                        local liveSpeed    = getSmoothed(best).speed

                        -- Rebuild targetDist the same way as initial, but from live values
                        local liveSpeedF  = math.max(liveSpeed, 15)
                        local liveWindF   = math.clamp(liveWinds / 75, 1, 8)
                        local liveBuf
                        if liveSfcRad < 150 then liveBuf = 200
                        elseif liveSfcRad < 250 then liveBuf = 300
                        elseif liveSfcRad < 400 then liveBuf = 450
                        elseif liveSfcRad < 600 then liveBuf = 750
                        else liveBuf = math.max(1000, math.floor(liveSfcRad * 1.5)) end

                        local liveTimeLead = liveSpeed * 3
                        local liveDist = math.max(liveSpeedF * 12 * liveWindF, liveSfcRad + liveBuf) + liveTimeLead + 150

                        if liveWinds >= 200 then
                            liveDist = liveDist + (liveWinds >= 300 and 2000 or 950)
                        end
                        if liveOuter > 50 then
                            liveDist = liveDist + math.min(math.floor((liveOuter - 50) * 15), 800)
                        end

                        -- Only move further away â€” never closer than the original targetDist
                        targetDist = math.max(targetDist, liveDist)

                        local liveScanPos = scan and scan.Parent and scan.Position or Vector3.new(groundPos.X, groundPos.Y, groundPos.Z)
                        local liveHeading = (getSmoothed(best).speed > 0.5) and getSmoothed(best).heading or heading
                        local livePredicted = Vector3.new(liveScanPos.X, liveScanPos.Y, liveScanPos.Z) + liveHeading * targetDist
                        local liveRay = solidGroundRay(livePredicted.X, livePredicted.Z)
                        if liveRay then
                            local dToStorm = (Vector3.new(livePredicted.X, 0, livePredicted.Z) - Vector3.new(liveScanPos.X, 0, liveScanPos.Z)).Magnitude
                            if dToStorm >= liveSfcRad + 350 then
                                groundPos = liveRay.Position
                            end
                        end
                        heading = liveHeading
                    end
                    holdCF = CFrame.new(groundPos + Vector3.new(0, getCharHeightOffset(char), 0))
                        * CFrame.Angles(0, math.atan2(heading.X, heading.Z), 0)
                    root.CFrame = holdCF
                    root.Velocity = Vector3.new(0, 0, 0)
                    game:GetService("RunService").RenderStepped:Wait()

                    -- SIMULTANEOUS PAIR PLACEMENT:
                    -- Equip BOTH probes into the character at the same time, then click each one.

                    local VirtualUser = game:GetService("VirtualUser")
                    local hum2 = char:FindFirstChild("Humanoid")

                    -- Step 1: HARD PRE-PLACEMENT SAFETY CHECK (before equipping)
                    -- If inside the danger zone, push further away FIRST, then equip.
                    do
                        local liveScan = scan and scan.Parent and scan.Position
                        if liveScan then
                            local liveSfcRadius = getTornadoRadius(best)
                            local distToStorm = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(liveScan.X, 0, liveScan.Z)).Magnitude
                            local safeMin = liveSfcRadius + 350
                            if distToStorm < safeMin then
                                uiLog("Too close to storm! Stepping back.", "warning")
                                local pushDist = safeMin - distToStorm + 200
                                local pushPos = root.Position + heading * pushDist
                                local pushRay = workspace:Raycast(Vector3.new(pushPos.X, 3000, pushPos.Z), Vector3.new(0, -5000, 0), rayParams)
                                if pushRay and pushRay.Position.Y <= 500 then
                                    groundPos = pushRay.Position
                                    holdCF = CFrame.new(groundPos + Vector3.new(0, getCharHeightOffset(char), 0))
                                        * CFrame.Angles(0, math.atan2(heading.X, heading.Z), 0)
                                    root.CFrame = holdCF
                                    root.Velocity = Vector3.new(0, 0, 0)
                    game:GetService("RunService").RenderStepped:Wait()
                                end
                            end
                        end
                    end

                    -- Step 2: Equip both probes at final position
                    if probeA and (probeA.Parent == localPlayer.Backpack or probeA.Parent == char) then
                        pcall(function() probeA.Parent = char end)
                    end
                    if probeB and (probeB.Parent == localPlayer.Backpack or probeB.Parent == char) then
                        pcall(function() probeB.Parent = char end)
                    end

                    -- Force standing so server ground raycasts succeed
                    if hum2 then
                        hum2.PlatformStand = false
                        hum2:ChangeState(Enum.HumanoidStateType.Landed)
                    end
                    task.wait(0.3)  -- settle: server registers both equips

                    -- Step 3: Activate + click probe A (fire unconditionally â€” server registered equip already)
                    if probeA then
                        pcall(function() probeA:Activate() end)
                        task.wait(0.05)
                        pcall(function()
                            VirtualUser:Button1Down(Vector2.new(0,0))
                            task.wait(0.05)
                            VirtualUser:Button1Up(Vector2.new(0, 0))
                        end)
                    end
                    task.wait(0.15)

                    -- Step 4: Activate + click probe B (fire unconditionally)
                    if probeB and not safetyAborted and _autofarmEnabled then
                        pcall(function() probeB:Activate() end)
                        task.wait(0.05)
                        pcall(function()
                            VirtualUser:Button1Down(Vector2.new(0,0))
                            task.wait(0.05)
                            VirtualUser:Button1Up(Vector2.new(0, 0))
                        end)
                    end


                    -- Step 4: Wait for server to consume both tools (up to 3s)
                    local waitFor = tick()
                    repeat task.wait(0.1) until tick() - waitFor > 3
                        or (
                            (not probeA or (probeA.Parent ~= char and probeA.Parent ~= localPlayer.Backpack))
                            and
                            (not probeB or (probeB.Parent ~= char and probeB.Parent ~= localPlayer.Backpack))
                        )
                        or safetyAborted

                    -- Step 5: Count how many were actually placed
                    if probeA and probeA.Parent ~= char and probeA.Parent ~= localPlayer.Backpack then
                        placedCount += 1; probesPlaced += 1
                    else
                        pcall(function() probeA.Parent = localPlayer.Backpack end)
                    end
                    if probeB and probeB.Parent ~= char and probeB.Parent ~= localPlayer.Backpack then
                        placedCount += 1; probesPlaced += 1
                    else
                        pcall(function() probeB.Parent = localPlayer.Backpack end)
                    end

                    uiLog(("Placed %d/%d"):format(placedCount, totalToPlace), "action")

                    i += 2

                    -- If placing probes 3+4, step forward so they don't stack on 1+2
                    if i <= totalToPlace and not safetyAborted then
                        groundPos = groundPos + heading * 80
                        holdCF = CFrame.new(groundPos + Vector3.new(0, getCharHeightOffset(char), 0))
                            * CFrame.Angles(0, math.atan2(heading.X, heading.Z), 0)
                        root.CFrame = holdCF
                        root.Velocity = Vector3.new(0, 0, 0)
                    game:GetService("RunService").RenderStepped:Wait()
                    end
                end

                task.wait(0.5)
                _clusterActive = false
                holdConn:Disconnect()
                _holding1 = false

                if placedCount == 0 then
                    uiLog("Deployment failed. Retrying.", "warning")
                    _isBusy = false
                    task.wait(1)
                    continue
                end

                -- If we still have probes in inventory but already have some in the world
                -- (e.g. safety abort after partial placement), place remaining near same spot
                local remainingInv = getProbes()
                local worldAfterPlace = countWorldProbes()
                if #remainingInv > 0 and worldAfterPlace > 0 then
                    uiLog("Partial placement. Deploying remaining.", "action")
                    _clusterActive = true
                    _holding1 = true
                    root.CFrame = CFrame.new(groundPos + Vector3.new(0, getCharHeightOffset(char), 0))
                        * CFrame.Angles(0, math.atan2(heading.X, heading.Z), 0)
                    root.Velocity = Vector3.new(0, 0, 0)
                    game:GetService("RunService").RenderStepped:Wait()

                    -- Deploy remaining in pairs (same dual-equip approach as main loop)
                    local ri = 1
                    while ri <= #remainingInv and _autofarmEnabled and not safetyAborted do
                        local pA = remainingInv[ri]
                        local pB = remainingInv[ri + 1]
                        local VU = game:GetService("VirtualUser")
                        local rHum = char:FindFirstChild("Humanoid")

                        -- Equip both at final position
                        if pA and (pA.Parent == localPlayer.Backpack or pA.Parent == char) then
                            pcall(function() pA.Parent = char end)
                        end
                        if pB and (pB.Parent == localPlayer.Backpack or pB.Parent == char) then
                            pcall(function() pB.Parent = char end)
                        end
                        if rHum then
                            rHum.PlatformStand = false
                            rHum:ChangeState(Enum.HumanoidStateType.Landed)
                        end
                        task.wait(0.3)

                        -- Click both unconditionally
                        if pA then
                            pcall(function() pA:Activate() end)
                            task.wait(0.05)
                            pcall(function()
                                VU:Button1Down(Vector2.new(0,0))
                                task.wait(0.05)
                                VU:Button1Up(Vector2.new(0, 0))
                            end)
                        end
                        task.wait(0.15)
                        if pB then
                            pcall(function() pB:Activate() end)
                            task.wait(0.05)
                            pcall(function()
                                VU:Button1Down(Vector2.new(0,0))
                                task.wait(0.05)
                                VU:Button1Up(Vector2.new(0, 0))
                            end)
                        end

                        -- Wait for server confirmation (up to 3s)
                        local wt = tick()
                        repeat task.wait(0.1) until tick() - wt > 3
                            or (
                                (not pA or (pA.Parent ~= char and pA.Parent ~= localPlayer.Backpack))
                                and
                                (not pB or (pB.Parent ~= char and pB.Parent ~= localPlayer.Backpack))
                            )
                            or safetyAborted

                        if pA and pA.Parent ~= char and pA.Parent ~= localPlayer.Backpack then
                            placedCount += 1; probesPlaced += 1
                        else
                            pcall(function() if pA then pA.Parent = localPlayer.Backpack end end)
                        end
                        if pB and pB.Parent ~= char and pB.Parent ~= localPlayer.Backpack then
                            placedCount += 1; probesPlaced += 1
                        else
                            pcall(function() if pB then pB.Parent = localPlayer.Backpack end end)
                        end

                        ri += 2
                    end

                    _clusterActive = false
                    _holding1 = false
                end

                for _, t in ipairs(char:GetChildren()) do
                    if t:IsA("Tool") and (t.Name:lower():match("probe") or t.Name:lower():match("twistex") or t.Name:lower():match("tower") or t.Name:lower():match("pod") or t.Name:lower():match("v2")) then
                        pcall(function() t.Parent = localPlayer.Backpack end)
                        task.wait(0.3)
                    end
                end
            end
            _clusterActive = false
            if holdConn then holdConn:Disconnect() end
            _isBusy = false


            -- On high-latency clients (mobile) placedCount may read 0 even though probes ARE in the
            -- world â€” the server folder just hasn't replicated yet. Fall back to countWorldProbes().
            local worldNow = countWorldProbes()
            if placedCount == 0 and worldNow > 0 then
                placedCount = worldNow
                uiLog("Detected " .. worldNow .. " world probe(s).", "action")
            end

            -- Snap back to start position after placement â€” server sees player safely away.
            local waitCF = CFrame.new(START_POS)
            root.Anchored = false
            root.CFrame = waitCF
            root.Velocity = Vector3.new(0, 0, 0)
            
            if placedCount > 0 then
                pcall(showTeleportPopup)
                _lastPlacementTime = tick()
                _isWaiting = true

                -- Baseline scan height at the moment probes went down
                local scanBaseY = scan.Position.Y

                -- Re-lock at start position for the duration of the watch
                _startHolding = true
                _holdId = _holdId + 1
                local myHoldId = _holdId
                task.spawn(function()
                    while _startHolding and myHoldId == _holdId and root and root.Parent do
                        root.CFrame = waitCF
                        root.Velocity = Vector3.new(0, 0, 0)
                    game:GetService("RunService").RenderStepped:Wait()
                    end
                end)

                uiLog("Deployed. Watching storm...", "action")
                _forceHealthCheck = true

                -- Helper: get the average position of our deployed probes for accurate distance tracking
                local function getProbeCenter()
                    local folder = workspace:FindFirstChild("player_related") and workspace.player_related:FindFirstChild("probes")
                    if not folder then return groundPos end
                    local myId = tostring(localPlayer.UserId)
                    local sum = Vector3.new(0,0,0); local cnt = 0
                    for _, p in pairs(folder:GetChildren()) do
                        local attr = p:GetAttribute("id") or p:GetAttribute("OwnerId") or p:GetAttribute("owner")
                        if tostring(attr) == myId or p.Name:match(myId) then
                            local part = p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart")
                            if part then sum = sum + part.Position; cnt += 1 end
                        end
                    end
                    return cnt > 0 and (sum / cnt) or groundPos
                end

                -- Adaptive timeout: scale based on distance and speed. Add generous buffer for fast/far storms.
                -- High-wind storms placed 2000+ studs away at 200 mph need at least 90+ seconds of travel time.
                local estimatedTime = (stormSpeed > 1.0) and (targetDist / stormSpeed) or 60
                local travelBuffer = math.max(45, estimatedTime * 0.5) -- extra 50% margin on top of ETA
                local adaptiveTimeout = math.clamp(estimatedTime + travelBuffer, 90, 360)

                local wt = 0; local minDist = math.huge; local hasApproached = false
                local missTicks = 0
                local lastRedeployTick = 0
                while _autofarmEnabled and wt < adaptiveTimeout do
                    task.wait(1); wt += 1
                    if not best.Parent then uiLog("Storm ended.", "warning"); break end

                    -- Fast-exit: if probes are already collected (storm sucked them up instantly), move on
                    if countWorldProbes() == 0 then
                        uiLog("Probes collected.", "success")
                        hasApproached = true  -- Mark so we skip the pickup step gracefully
                        break
                    end

                    local sPos = scan.Position
                    -- Dissipation: funnel height rose back up
                    if sPos.Y > scanBaseY + 400 then uiLog("Storm dissipated.", "warning"); break end

                    local trueWidth = getTornadoRadius(best)
                    local sData = getSmoothed(best)

                    -- â”€â”€ PER-PROBE STRAGGLER CHECK â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    -- If the storm has moved past some probes but others are still ahead,
                    -- retrieve the straggler probes and re-deploy them forward.
                    if sData.speed > 1.0 and tick() - lastRedeployTick > 8 then
                        local probeFolder = workspace:FindFirstChild("player_related") and workspace.player_related:FindFirstChild("probes")
                        local myId = tostring(localPlayer.UserId)
                        if probeFolder then
                            local stragglersExist = false
                            for _, p in pairs(probeFolder:GetChildren()) do
                                local attr = p:GetAttribute("id") or p:GetAttribute("OwnerId") or p:GetAttribute("owner")
                                if tostring(attr) == myId or p.Name:match(myId) then
                                    local part = p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart")
                                    if part then
                                        -- Vector from storm to this probe along storm heading
                                        local pv = Vector3.new(part.Position.X - sPos.X, 0, part.Position.Z - sPos.Z)
                                        local dot = pv.X * sData.heading.X + pv.Z * sData.heading.Z
                                        -- Probe is safely behind the storm's danger zone = straggler
                                        if dot < -(trueWidth + 400) then
                                            stragglersExist = true
                                            break
                                        end
                                    end
                                end
                            end
                            if stragglersExist then
                                uiLog("Repositioning.", "action")
                                lastRedeployTick = tick()
                                _startHolding = false
                                root.Anchored = false
                                -- Pick up stragglers
                                pickupMyProbes(true)
                                local pickupTO = tick()
                                repeat task.wait(0.5) until not _pickupInProgress or tick() - pickupTO > 20
                                -- Re-deploy near groundPos (same general area, ahead of storm)
                                local redeployProbes = getProbes()
                                if #redeployProbes > 0 and _autofarmEnabled then
                                    _clusterActive = true
                                    -- Recalculate placement position from live storm location so we
                                    -- redeploy AHEAD of the storm, not at the stale groundPos behind it.
                                    local liveS = getSmoothed(best)
                                    local liveH = (liveS.speed > 0.5) and liveS.heading or heading
                                    local liveScanPos = scan and scan.Parent and scan.Position or Vector3.new(groundPos.X, groundPos.Y, groundPos.Z)
                                    local liveTarget = Vector3.new(liveScanPos.X, liveScanPos.Y, liveScanPos.Z) + liveH * targetDist
                                    local liveGround = solidGroundRay(liveTarget.X, liveTarget.Z)
                                    local deployPos = (liveGround and (Vector3.new(liveTarget.X,0,liveTarget.Z) - Vector3.new(liveScanPos.X,0,liveScanPos.Z)).Magnitude >= sfcRadius + 80)
                                        and liveGround.Position or groundPos
                                    heading = liveH
                                    groundPos = deployPos
                                    root.CFrame = CFrame.new(deployPos + Vector3.new(0, getCharHeightOffset(char), 0))
                                        * CFrame.Angles(0, math.atan2(liveH.X, liveH.Z), 0)
                                    root.Velocity = Vector3.new(0, 0, 0)
                    game:GetService("RunService").RenderStepped:Wait()
                                    -- Redeploy in pairs
                                    local ri2 = 1
                                    local VU2 = game:GetService("VirtualUser")
                                    while ri2 <= #redeployProbes and _autofarmEnabled do
                                        local pA2 = redeployProbes[ri2]
                                        local pB2 = redeployProbes[ri2 + 1]
                                        local rH2 = char:FindFirstChild("Humanoid")
                                        if pA2 and (pA2.Parent == localPlayer.Backpack or pA2.Parent == char) then pcall(function() pA2.Parent = char end) end
                                        if pB2 and (pB2.Parent == localPlayer.Backpack or pB2.Parent == char) then pcall(function() pB2.Parent = char end) end
                                        if rH2 then rH2.PlatformStand = false; rH2:ChangeState(Enum.HumanoidStateType.Landed) end
                                        task.wait(0.3)
                                        if pA2 then
                                            pcall(function() pA2:Activate() end); task.wait(0.05)
                                            pcall(function() VU2:Button1Down(Vector2.new(0,0)); task.wait(0.05); VU2:Button1Up(Vector2.new(0,0)) end)
                                        end
                                        task.wait(0.15)
                                        if pB2 then
                                            pcall(function() pB2:Activate() end); task.wait(0.05)
                                            pcall(function() VU2:Button1Down(Vector2.new(0,0)); task.wait(0.05); VU2:Button1Up(Vector2.new(0,0)) end)
                                        end
                                        local wt2 = tick()
                                        repeat task.wait(0.1) until tick()-wt2 > 3
                                            or ((not pA2 or (pA2.Parent~=char and pA2.Parent~=localPlayer.Backpack)) and (not pB2 or (pB2.Parent~=char and pB2.Parent~=localPlayer.Backpack)))
                                        if pA2 and pA2.Parent~=char and pA2.Parent~=localPlayer.Backpack then placedCount+=1; probesPlaced+=1
                                        else pcall(function() if pA2 then pA2.Parent=localPlayer.Backpack end end) end
                                        if pB2 and pB2.Parent~=char and pB2.Parent~=localPlayer.Backpack then placedCount+=1; probesPlaced+=1
                                        else pcall(function() if pB2 then pB2.Parent=localPlayer.Backpack end end) end
                                        ri2 += 2
                                    end
                                    _clusterActive = false
                                    pcall(showTeleportPopup)
                                end
                                -- Return to staging and re-lock
                                root.CFrame = CFrame.new(START_POS)
                                _startHolding = true
                                _holdId = _holdId + 1
                                local myHoldId2 = _holdId
                                task.spawn(function()
                                    while _startHolding and myHoldId2 == _holdId and root and root.Parent do
                                        root.CFrame = waitCF
                                        root.Velocity = Vector3.new(0, 0, 0)
                    game:GetService("RunService").RenderStepped:Wait()
                                    end
                                end)
                            end
                        end
                    end
                    -- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

                    -- Measure distance from storm to actual probe center, not groundPos
                    local probeCenter = getProbeCenter()
                    local d2 = (Vector3.new(sPos.X,0,sPos.Z) - Vector3.new(probeCenter.X,0,probeCenter.Z)).Magnitude

                    if d2 < minDist then minDist = d2 end
                    if d2 <= trueWidth + 150 and not hasApproached then uiLog("Storm reached probes.", "success"); hasApproached = true end
                    
                    -- Buy and deploy replacements if probes are destroyed during wait
                    local totalProbes = countProbesInv() + countWorldProbes()
                    if totalProbes < PROBE_TARGET and _autofarmEnabled and not _isBusy then
                        local missing = PROBE_TARGET - totalProbes
                        uiLog("Probe lost. Replacing.", "warning")
                        _startHolding = false
                        root.Anchored = false
                        
                        buyProbe(missing)
                        
                        local newProbes = getProbes()
                        if #newProbes > 0 and _autofarmEnabled then
                            _clusterActive = true
                            local liveS = getSmoothed(best)
                            local liveH = (liveS.speed > 0.5) and liveS.heading or heading
                            local liveScanPos = scan and scan.Parent and scan.Position or Vector3.new(groundPos.X, groundPos.Y, groundPos.Z)
                            local liveTarget = Vector3.new(liveScanPos.X, liveScanPos.Y, liveScanPos.Z) + liveH * targetDist
                            local liveGround = solidGroundRay(liveTarget.X, liveTarget.Z)
                            local deployPos = (liveGround and (Vector3.new(liveTarget.X,0,liveTarget.Z) - Vector3.new(liveScanPos.X,0,liveScanPos.Z)).Magnitude >= sfcRadius + 80)
                                and liveGround.Position or groundPos
                            
                            root.CFrame = CFrame.new(deployPos + Vector3.new(0, getCharHeightOffset(char), 0))
                                * CFrame.Angles(0, math.atan2(liveH.X, liveH.Z), 0)
                            root.Velocity = Vector3.new(0, 0, 0)
                    game:GetService("RunService").RenderStepped:Wait()
                            
                            -- Deploy replacements in pairs
                            local ri3 = 1
                            local VU3 = game:GetService("VirtualUser")
                            while ri3 <= #newProbes and _autofarmEnabled do
                                local pA3 = newProbes[ri3]
                                local pB3 = newProbes[ri3 + 1]
                                local rH3 = char:FindFirstChild("Humanoid")
                                if pA3 and (pA3.Parent == localPlayer.Backpack or pA3.Parent == char) then pcall(function() pA3.Parent = char end) end
                                if pB3 and (pB3.Parent == localPlayer.Backpack or pB3.Parent == char) then pcall(function() pB3.Parent = char end) end
                                if rH3 then rH3.PlatformStand = false; rH3:ChangeState(Enum.HumanoidStateType.Landed) end
                                task.wait(0.3)
                                if pA3 then
                                    pcall(function() pA3:Activate() end); task.wait(0.05)
                                    pcall(function() VU3:Button1Down(Vector2.new(0,0)); task.wait(0.05); VU3:Button1Up(Vector2.new(0,0)) end)
                                end
                                task.wait(0.15)
                                if pB3 then
                                    pcall(function() pB3:Activate() end); task.wait(0.05)
                                    pcall(function() VU3:Button1Down(Vector2.new(0,0)); task.wait(0.05); VU3:Button1Up(Vector2.new(0,0)) end)
                                end
                                local wt3 = tick()
                                repeat task.wait(0.1) until tick()-wt3 > 3
                                    or ((not pA3 or (pA3.Parent~=char and pA3.Parent~=localPlayer.Backpack)) and (not pB3 or (pB3.Parent~=char and pB3.Parent~=localPlayer.Backpack)))
                                if pA3 and pA3.Parent~=char and pA3.Parent~=localPlayer.Backpack then placedCount=placedCount+1; probesPlaced=probesPlaced+1
                                else pcall(function() if pA3 then pA3.Parent=localPlayer.Backpack end end) end
                                if pB3 and pB3.Parent~=char and pB3.Parent~=localPlayer.Backpack then placedCount=placedCount+1; probesPlaced=probesPlaced+1
                                else pcall(function() if pB3 then pB3.Parent=localPlayer.Backpack end end) end
                                ri3 += 2
                            end
                            _clusterActive = false
                            pcall(showTeleportPopup)
                        end
                        
                        root.CFrame = CFrame.new(START_POS)
                        _startHolding = true
                        _holdId = _holdId + 1
                        local myHoldId3 = _holdId
                        task.spawn(function()
                            while _startHolding and myHoldId3 == _holdId and root and root.Parent do
                                root.CFrame = waitCF
                                root.Velocity = Vector3.new(0, 0, 0)
                    game:GetService("RunService").RenderStepped:Wait()
                            end
                        end)
                    end

                    -- Dynamic Trajectory Check: Detect path changes and passes instantly
                    if sData.speed > 1.0 then
                        local v = Vector3.new(probeCenter.X - sPos.X, 0, probeCenter.Z - sPos.Z)
                        local t = v.X * sData.heading.X + v.Z * sData.heading.Z
                        
                        -- If probes are safely behind the storm, collect them immediately
                        -- We ensure d2 > trueWidth + 300 so it NEVER picks up probes while they are physically inside the funnel
                        if (hasApproached and d2 > trueWidth + 300) or (t < -(trueWidth + 400) and d2 > trueWidth + 300) then
                            uiLog("Storm passed. Retrieving.", "action")
                            break
                        elseif t > 0 and not hasApproached then
                            -- Probes are ahead, but check if the storm is actually heading towards them
                            local closestPoint = Vector3.new(sPos.X + sData.heading.X * t, 0, sPos.Z + sData.heading.Z * t)
                            local missDist = (Vector3.new(probeCenter.X, 0, probeCenter.Z) - closestPoint).Magnitude
                            
                            -- If the storm's trajectory will miss the probes by a margin that scales with distance
                            -- We use a smaller multiplier (0.25) so it doesn't wait too long for long-distance high-wind storms
                            local allowedMiss = trueWidth + 400 + math.max(0, t * 0.25)
                            
                            if missDist > allowedMiss and d2 > trueWidth + 200 then
                                missTicks += 1
                                -- React faster (3 ticks = ~0.9s) especially for fast storms
                                local tickThreshold = (sData.speed > 100) and 2 or 3
                                if missTicks >= tickThreshold then
                                    uiLog("Storm turned. Repositioning.", "warning")
                                    break
                                end
                            else
                                missTicks = 0
                            end
                        end
                    else
                        -- Fallback for extremely slow/stationary storms
                        if hasApproached and d2 > trueWidth + 400 then
                            uiLog("Storm drifted. Retrieving.","action"); break
                        end
                    end
                end
                if wt >= adaptiveTimeout then uiLog("Watch timeout.", "warning") end
                _startHolding = false
                _isWaiting = false
                root.Anchored = false
                -- Only pick up if probes are actually still in the world
                if countWorldProbes() > 0 then
                    task.spawn(function() pickupMyProbes(true) end)
                    -- Block until pickup finishes so next cycle has a full inventory
                    local pickupTimeout = tick()
                    repeat task.wait(0.5) until not _pickupInProgress or tick() - pickupTimeout > 30
                else
                    uiLog("No probes to collect.", "action")
                end
            else
                uiLog("No probes placed. Retrying.", "warning")
                _isWaiting = false
                root.Anchored = false
            end
            task.wait(0.5); break
        end
        if not targetFound then
            if stormForming then
                if not loggedWaiting then uiLog("Waiting for touchdown...", "action"); loggedWaiting = true end
                _noStormTimer = nil  -- Pause the hop timer because a storm is coming down
            elseif stormOverWater then
                if not loggedWaiting then uiLog("Waiting for storm to reach ground...", "action"); loggedWaiting = true end
                _noStormTimer = nil  -- Pause the hop timer because we are waiting for this storm
            else
                if not loggedWaiting then uiLog("Waiting for storm...", "action"); loggedWaiting = true end
                if _autoHopEnabled then
                    if not _noStormTimer then _noStormTimer = tick() end
                    local waitTime = tick() - _noStormTimer
                    if waitTime >= 45 then
                        uiLog("No storms. Hopping.", "warning")
                        serverHop()
                        break
                    end
                    if math.floor(waitTime) % 15 == 0 and math.floor(waitTime) > 0 then
                        uiLog(("No storms. Hopping in %ds."):format(math.floor(45 - waitTime)), "warning", 10)
                    end
                end
            end
            task.wait(2)
        else 
            loggedWaiting = false 
            _noStormTimer = nil
        end
    end
end)

-- ============================================================
--  DISCORD WEBHOOK SESSION TRACKER
-- ============================================================
-- WEBHOOK_URL and SEND_INTERVAL already declared at top of eclipse_main

if not sessionMoneyStart then
    sessionMoneyStart = getgenv().eclipse2_session_money
end
local moneyHistory = getgenv().eclipse2_money_history or {}

local function formatTime(s)
    local h = math.floor(s/3600); local m = math.floor((s%3600)/60); local sc = math.floor(s%60)
    if h > 0 then return ("%dh %dm %ds"):format(h,m,sc)
    elseif m > 0 then return ("%dm %ds"):format(m,sc)
    else return ("%ds"):format(sc) end
end

local function formatMoney(n)
    if not n then return "N/A" end
    if n >= 1e6 then return ("$%.2fM"):format(n/1e6)
    elseif n >= 1000 then return ("$%.1fK"):format(n/1000)
    else return ("$%d"):format(n) end
end

-- Direct money source: dynamically check common paths
local function getPlayerMoney()
    local paths = {
        function() return localPlayer.leaderstats.Money.Value end,
        function() return localPlayer.leaderstats.Cash.Value end,
        function() return localPlayer.leaderstats.Credits.Value end,
        function() return localPlayer.player_stats.money.Value end,
        function() return localPlayer:FindFirstChild("leaderstats") and localPlayer.leaderstats:FindFirstChildOfClass("IntValue") and localPlayer.leaderstats:FindFirstChildOfClass("IntValue").Value end
    }
    for _, getFunc in ipairs(paths) do
        local ok, val = pcall(getFunc)
        if ok and type(val) == "number" then return val end
    end
    return nil
end

-- Stats bar updater â€” now placed after formatTime/formatMoney/getPlayerMoney are in scope
task.spawn(function()
    while _autofarmRunning do
        task.wait(2)
        local elapsed = getActiveSessionTime()
        local cur = getPlayerMoney()
        local earned = (cur and sessionMoneyStart) and math.max(0, cur - sessionMoneyStart) or 0
        local perHour = elapsed > 30 and math.floor(earned / (elapsed / 3600)) or 0
        statTimeVal.Text   = formatTime(elapsed)
        statEarnedVal.Text = formatMoney(earned)
        statHourlyVal.Text = formatMoney(perHour) .. "/hr"
    end
end)

local function buildChartUrl()
    if #moneyHistory < 2 then return nil end
    local labels, data = {}, {}
    local startIdx = math.max(1, #moneyHistory - 20)
    for i = startIdx, #moneyHistory do
        local pt = moneyHistory[i]
        table.insert(labels, "'"..formatTime(pt.elapsed).."'")
        table.insert(data, tostring(math.floor(pt.earned)))
    end
    
    -- Pad data so short sessions don't flood the fill area
    local paddedData = {}
    local minVal = math.huge; local maxVal = -math.huge
    for _, v in ipairs(data) do
        local n = tonumber(v) or 0
        if n < minVal then minVal = n end
        if n > maxVal then maxVal = n end
        table.insert(paddedData, n)
    end
    -- Ensure y-axis has meaningful range so fill doesn't flood on flat data
    local yMin = 0
    local yMax = math.max(maxVal * 1.25, 100)

    local cfg = {
        type = "line",
        data = {
            labels = labels,
            datasets = {
                {
                    label = "Earnings",
                    data = paddedData,
                    fill = true,
                    backgroundColor = "rgba(46, 213, 115, 0.15)",
                    borderColor = "#2ed573",
                    borderWidth = 2,
                    pointRadius = 0,
                    pointHoverRadius = 0,
                    tension = 0.4
                }
            }
        },
        options = {
            animation = { duration = 0 },
            plugins = {
                legend = { display = false },
                title = {
                    display = true,
                    text = "EARNING GRAPH",
                    color = "#ffffff",
                    font = { size = 14, family = "monospace", weight = "bold" },
                    padding = { top = 8, bottom = 4 }
                }
            },
            scales = {
                x = {
                    ticks = { color = "#444", font = { size = 7 }, maxRotation = 0 },
                    grid = { color = "rgba(255,255,255,0.04)" }
                },
                y = {
                    min = yMin,
                    max = yMax,
                    ticks = { color = "#444", font = { size = 7 } },
                    grid = { color = "rgba(255,255,255,0.04)" }
                }
            },
            layout = { padding = { left = 6, right = 14, top = 2, bottom = 4 } }
        }
    }

    local ok, json = pcall(function() return HttpService:JSONEncode(cfg) end)
    if not ok then return nil end
    return "https://quickchart.io/chart?w=820&h=370&bkg=%230a0a0a&v=3&c="..HttpService:UrlEncode(json)
end

-- Robust Request Handler
local function safeRequest(options, retryCount)
    local retryCount = retryCount or 0
    local requestFunc = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if not requestFunc then
        uiLog("Webhook error: No request function.", "error")
        return false
    end
    
    local success, response = pcall(function()
        return requestFunc(options)
    end)
    
    if success and response then
        local code = response.StatusCode or response.status or 0
        if code >= 200 and code < 300 then
            return true
        elseif code == 429 and retryCount < 1 then
            uiLog("Webhook rate limited. Retrying.", "warning")
            task.wait(5)
            return safeRequest(options, retryCount + 1)
        else
            uiLog("Webhook HTTP error: " .. tostring(code), "error")
        end
    else
        uiLog("Webhook network error.", "error")
    end
    return false
end

buildAndSend = function(extraFields, titleOverride, colorOverride, isRetry) -- Assigned to outer scope
    local elapsed = getActiveSessionTime()
    local currentMoney = getPlayerMoney()
    if sessionMoneyStart == nil and currentMoney then sessionMoneyStart = currentMoney end
    local earned = (currentMoney and sessionMoneyStart) and math.max(0, currentMoney - sessionMoneyStart) or 0
    local perHour = elapsed > 120 and math.floor(earned / (elapsed / 3600)) or 0

    local chartUrl = buildChartUrl()
    
    -- Layout matching 'remake it look like this'
    local fields = {
        {
            name = "**SESSION**",
            value = ("Time: %s\nStatus: %s\nSnapshots: %d"):format(formatTime(elapsed), _autofarmEnabled and "Running" or "Paused", #moneyHistory),
            inline = true
        },
        {
            name = "**EARNINGS**",
            value = ("Total: %s\nHourly: %s"):format(formatMoney(earned), formatMoney(perHour)),
            inline = true
        },
        {
            name = "**ACTIVITY**",
            value = ("Placed: %d\nRecovered: %d"):format(probesPlaced, probesRecovered),
            inline = true
        },
        {
            name = "**ENVIRONMENT**",
            value = ("Storms: %d\nLocation: %s"):format(#getTornadoes(), tostring(game.PlaceId)),
            inline = true
        },
        {
            name = "**PLAYER**",
            value = localPlayer.Name,
            inline = true
        }
    }
    
    if extraFields and type(extraFields) == "table" then
        for _, f in ipairs(extraFields) do
            if type(f) == "table" then 
                -- Map custom fields to the same bold style
                if f.name then f.name = "**" .. f.name:upper() .. "**" end
                table.insert(fields, f) 
            end
        end
    end

    local embed = {
        title = tostring(titleOverride or "Eclipse Autofarm Dashboard"),
        description = "Session Activity Report",
        color = tonumber(colorOverride) or 0,
        fields = fields,
        footer = {
            text = "Eclipse | " .. os.date("%X") .. " â€¢ Today at " .. os.date("%H:%M %p"),
        },
    }
    
    local ok_ts, ts = pcall(function() return os.date("!%Y-%m-%dT%H:%M:%SZ") end)
    if ok_ts then embed.timestamp = ts end
    if chartUrl then embed.image = {url = tostring(chartUrl)} end

    local payload = HttpService:JSONEncode({
        username = "Eclipse Autofarm",
        avatar_url = "https://i.postimg.cc/SxtVbHhh/8429be3ee09690842c1563546762df75.png",
        embeds = {embed}
    })

    return safeRequest({
        Url = WEBHOOK_URL, 
        Method = "POST", 
        Headers = {["Content-Type"] = "application/json"}, 
        Body = payload
    })
end

local function sendWebhook()
    local success = buildAndSend(nil, nil, nil, false)
    if success then
        local currentMoney = getPlayerMoney()
        local earned = (currentMoney and sessionMoneyStart) and math.max(0, currentMoney - sessionMoneyStart) or 0
        uiLog("Webhook sent.", "success")
    end
end

-- Disconnect webhook
game:GetService("Players").PlayerRemoving:Connect(function(plr)
    if plr ~= localPlayer then return end
    local reason = "Left game"
    pcall(function()
        local state = game:GetService("TeleportService"):GetLocalPlayerTeleportData()
        if state then reason = "Teleport / Server Hop" end
    end)
    pcall(function()
        local kr = localPlayer:FindFirstChild("kick_reason")
        if kr then reason = "Kicked: "..(kr.Value or "no reason") end
    end)
    buildAndSend(
        {{name = "DISCONNECT REASON", value = "**" .. reason .. "**", inline = false}},
        "ECLIPSE DASHBOARD",
        15158332
    )
end)

-- Retry until money is readable, but DO NOT overwrite if we already have a session baseline from a server hop
task.spawn(function()
    if sessionMoneyStart then
        uiLog("Tracking resumed: " .. formatMoney(sessionMoneyStart), "action")
        return
    end

    local attempts = 0
    repeat
        task.wait(2)
        attempts = attempts + 1
        sessionMoneyStart = getPlayerMoney()
    until sessionMoneyStart ~= nil or attempts >= 15

    if sessionMoneyStart then
        uiLog("Tracking started: " .. formatMoney(sessionMoneyStart), "action")
    else
        uiLog("Could not read balance. Using relative tracking.", "warning")
    end
end)

-- History sampler: runs every 15s so the graph always has fresh data points
-- independent of how often the webhook fires
task.spawn(function()
    task.wait(10)
    while _autofarmRunning do
        local currentMoney = getPlayerMoney()
        if sessionMoneyStart == nil and currentMoney then
            sessionMoneyStart = currentMoney
        end
        if currentMoney and sessionMoneyStart then
            local elapsed = getActiveSessionTime()
            local earned = math.max(0, currentMoney - sessionMoneyStart)
            table.insert(moneyHistory, {elapsed = elapsed, earned = earned})
            if #moneyHistory > 60 then table.remove(moneyHistory, 1) end
            getgenv().eclipse2_money_history = moneyHistory
            getgenv().eclipse2_session_money = sessionMoneyStart
            -- saveSettings() removed: now only saves during server hops as requested
        end
        task.wait(15)
    end
end)

-- Periodic webhook sends
task.spawn(function()
    task.wait(SEND_INTERVAL)
    while _autofarmRunning do
        if _autofarmEnabled and WEBHOOK_ENABLED and WEBHOOK_URL ~= "" then 
            task.spawn(sendWebhook) 
        end
        task.wait(SEND_INTERVAL)
    end
end)


end -- close eclipse_main

-- Final startup call (with error reporting)
local _ok, _err = pcall(eclipse_main)
if not _ok then
    warn('ECLIPSE ERROR: ' .. tostring(_err))
    print('ECLIPSE ERROR: ' .. tostring(_err))
end
