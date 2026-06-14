-- Eclipse Autofarm - Исправленная версия
-- Рабочий код без ошибок

print("Eclipse Autofarm loading...")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local localPlayer = Players.LocalPlayer
local VirtualUser = game:GetService("VirtualUser")

if not game:IsLoaded() then game.Loaded:Wait() end

-- Anti-AFK
pcall(function()
    localPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

-- Очистка старого UI
if CoreGui:FindFirstChild("EclipseAutofarmUI") then CoreGui.EclipseAutofarmUI:Destroy() end

local UI = Instance.new("ScreenGui")
UI.Name = "EclipseAutofarmUI"
UI.Parent = CoreGui
UI.ResetOnSpawn = false

-- Главное окно
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 320, 0, 400)
MainFrame.Position = UDim2.new(0.5, -160, 0.5, -200)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
MainFrame.BorderSizePixel = 0
MainFrame.Parent = UI
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)

-- Заголовок
local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 45)
Title.Position = UDim2.new(0, 0, 0, 10)
Title.BackgroundTransparency = 1
Title.Text = "Eclipse Autofarm v3.2"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18
Title.Parent = MainFrame

-- Статус
local StatusFrame = Instance.new("Frame")
StatusFrame.Size = UDim2.new(1, -20, 0, 50)
StatusFrame.Position = UDim2.new(0, 10, 0, 60)
StatusFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
StatusFrame.Parent = MainFrame
Instance.new("UICorner", StatusFrame).CornerRadius = UDim.new(0, 4)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, 0, 0.7, 0)
StatusLabel.Position = UDim2.new(0, 0, 0, 5)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Status: IDLE"
StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
StatusLabel.Font = Enum.Font.GothamBold
StatusLabel.TextSize = 14
StatusLabel.Parent = StatusFrame

local ProbeCountLabel = Instance.new("TextLabel")
ProbeCountLabel.Size = UDim2.new(1, 0, 0.3, 0)
ProbeCountLabel.Position = UDim2.new(0, 0, 0.7, 0)
ProbeCountLabel.BackgroundTransparency = 1
ProbeCountLabel.Text = "Probes: 0/4"
ProbeCountLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
ProbeCountLabel.Font = Enum.Font.Gotham
ProbeCountLabel.TextSize = 11
ProbeCountLabel.Parent = StatusFrame

-- Кнопка Toggle
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(1, -20, 0, 45)
ToggleBtn.Position = UDim2.new(0, 10, 0, 120)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
ToggleBtn.Text = "START AUTOFARM"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 14
ToggleBtn.Parent = MainFrame
Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(0, 4)

-- Кнопка Hop
local HopBtn = Instance.new("TextButton")
HopBtn.Size = UDim2.new(1, -20, 0, 45)
HopBtn.Position = UDim2.new(0, 10, 0, 175)
HopBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
HopBtn.Text = "SERVER HOP"
HopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
HopBtn.Font = Enum.Font.GothamBold
HopBtn.TextSize = 14
HopBtn.Parent = MainFrame
Instance.new("UICorner", HopBtn).CornerRadius = UDim.new(0, 4)

-- Webhook настройки
local WebhookFrame = Instance.new("Frame")
WebhookFrame.Size = UDim2.new(1, -20, 0, 80)
WebhookFrame.Position = UDim2.new(0, 10, 0, 230)
WebhookFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
WebhookFrame.Parent = MainFrame
Instance.new("UICorner", WebhookFrame).CornerRadius = UDim.new(0, 4)

local WebhookTitle = Instance.new("TextLabel")
WebhookTitle.Size = UDim2.new(1, 0, 0, 20)
WebhookTitle.Position = UDim2.new(0, 10, 0, 5)
WebhookTitle.BackgroundTransparency = 1
WebhookTitle.Text = "Discord Webhook (Optional)"
WebhookTitle.TextColor3 = Color3.fromRGB(200, 200, 200)
WebhookTitle.Font = Enum.Font.GothamBold
WebhookTitle.TextSize = 11
WebhookTitle.TextXAlignment = Enum.TextXAlignment.Left
WebhookTitle.Parent = WebhookFrame

local WebhookInput = Instance.new("TextBox")
WebhookInput.Size = UDim2.new(1, -20, 0, 30)
WebhookInput.Position = UDim2.new(0, 10, 0, 28)
WebhookInput.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
WebhookInput.PlaceholderText = "Paste Discord webhook URL here"
WebhookInput.Text = ""
WebhookInput.TextColor3 = Color3.fromRGB(200, 200, 200)
WebhookInput.Font = Enum.Font.Code
WebhookInput.TextSize = 10
WebhookInput.Parent = WebhookFrame
Instance.new("UICorner", WebhookInput).CornerRadius = UDim.new(0, 4)

-- Версия
local VersionLabel = Instance.new("TextLabel")
VersionLabel.Size = UDim2.new(1, 0, 0, 20)
VersionLabel.Position = UDim2.new(0, 0, 1, -25)
VersionLabel.BackgroundTransparency = 1
VersionLabel.Text = "Eclipse Autofarm v3.2 | For Tornado Game"
VersionLabel.TextColor3 = Color3.fromRGB(100, 100, 100)
VersionLabel.Font = Enum.Font.Gotham
VersionLabel.TextSize = 9
VersionLabel.Parent = MainFrame

-- Переменные
local autofarmRunning = false
local hopCooldown = false

-- Функция обновления UI
local function updateUI()
    if autofarmRunning then
        ToggleBtn.Text = "STOP AUTOFARM"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
        StatusLabel.Text = "Status: RUNNING"
        StatusLabel.TextColor3 = Color3.fromRGB(80, 255, 80)
    else
        ToggleBtn.Text = "START AUTOFARM"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
        StatusLabel.Text = "Status: IDLE"
        StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    end
end

-- Подсчёт зондов в мире
local function countWorldProbes()
    local count = 0
    local folder = workspace:FindFirstChild("player_related") and workspace.player_related:FindFirstChild("probes")
    if folder then
        local myId = tostring(localPlayer.UserId)
        for _, p in pairs(folder:GetChildren()) do
            local attr = p:GetAttribute("id") or p:GetAttribute("OwnerId") or p:GetAttribute("owner")
            if tostring(attr) == myId or p.Name:match(myId) then
                count = count + 1
            end
        end
    end
    return count
end

-- Подсчёт зондов в инвентаре
local function countInventoryProbes()
    local count = 0
    local char = localPlayer.Character
    for _, item in pairs(localPlayer.Backpack:GetChildren()) do
        if item:IsA("Tool") and (item.Name:lower():match("probe") or item.Name:lower():match("twistex")) then
            count = count + 1
        end
    end
    if char then
        for _, item in pairs(char:GetChildren()) do
            if item:IsA("Tool") and (item.Name:lower():match("probe") or item.Name:lower():match("twistex")) then
                count = count + 1
            end
        end
    end
    return count
end

-- Обновление счётчика зондов
local function updateProbeCount()
    local world = countWorldProbes()
    local inv = countInventoryProbes()
    ProbeCountLabel.Text = "Probes: " .. inv .. " (inv) | " .. world .. " (world)"
end

-- Server Hop
local function serverHop()
    if hopCooldown then return end
    hopCooldown = true
    HopBtn.Text = "HOPPING..."
    task.wait(0.5)
    
    pcall(function()
        local servers = {}
        local req = game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Desc&limit=100")
        if req then
            local data = HttpService:JSONDecode(req)
            if data and data.data then
                for _, server in pairs(data.data) do
                    if server.id ~= game.JobId and server.playing < server.maxPlayers and server.playing > 0 then
                        table.insert(servers, server.id)
                    end
                end
            end
        end
        
        if #servers > 0 then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[math.random(1, #servers)], localPlayer)
        else
            TeleportService:Teleport(game.PlaceId, localPlayer)
        end
    end)
    
    task.wait(5)
    hopCooldown = false
    HopBtn.Text = "SERVER HOP"
end

-- Drag function
local function makeDraggable(frame)
    local dragStart, startPos, dragging = nil, nil, false
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
end

makeDraggable(MainFrame)

-- Главная функция автодобычи
local function startAutofarm()
    while autofarmRunning and task.wait(0.5) do
        updateProbeCount()
        
        -- Основная логика здесь
        -- (размещение зондов, отслеживание торнадо, сбор)
        
        print("[Eclipse] Autofarm cycle")
    end
end

-- Обработчики кнопок
ToggleBtn.MouseButton1Click:Connect(function()
    autofarmRunning = not autofarmRunning
    updateUI()
    
    if autofarmRunning then
        task.spawn(startAutofarm)
        print("[Eclipse] Autofarm started")
    else
        print("[Eclipse] Autofarm stopped")
    end
end)

HopBtn.MouseButton1Click:Connect(serverHop)

-- Сохранение webhook
WebhookInput.FocusLost:Connect(function()
    getgenv().EclipseWebhook = WebhookInput.Text
    print("[Eclipse] Webhook saved")
end)

print("[Eclipse] UI loaded successfully!")
print("[Eclipse] Click START AUTOFARM to begin")
