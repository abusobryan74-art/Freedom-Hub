-- Place in: StarterPlayer > StarterPlayerScripts (LocalScript)
 
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local UIS                = game:GetService("UserInputService")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")
local Stats              = game:GetService("Stats")
local VirtualUser        = game:GetService("VirtualUser")
 
local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local RollEvent = ReplicatedStorage:WaitForChild("RollEvent", 10)
 
-- ===== CONFIG & STATE =====
local TARGET_POSITION     = Vector3.new(82, 5, 20)  -- destination
local WALK_SPEED_WORLD_1 = 500  -- World 1 speed
local WALK_SPEED_WORLD_2 = 1000 -- World 2 speed
local WALK_SPEED_DEFAULT = 500  -- safe fallback if the world identifier cannot be detected

-- Supported worlds only: World 1 = 500, World 2 = 1000. No other world speed rules are included.
-- Detect the current world from common player attributes, leaderstats, or workspace names.
local function normalizeWorld(value)
    if value == nil then return nil end
    local text = string.lower(tostring(value)):gsub("[%s_%-]", "")
    if text == "1" or text == "world1" or text == "world01" or text == "worldone" then
        return 1
    elseif text == "2" or text == "world2" or text == "world02" or text == "worldtwo" then
        return 2
    end
    return nil
end

local function getCurrentWorld()
    for _, key in ipairs({"World", "CurrentWorld", "WorldName", "WorldId", "WorldID", "world"}) do
        local ok, value = pcall(function() return player:GetAttribute(key) end)
        if ok then
            local worldNumber = normalizeWorld(value)
            if worldNumber then return worldNumber end
        end
    end

    local leaderstats = player:FindFirstChild("leaderstats")
    if leaderstats then
        for _, key in ipairs({"World", "CurrentWorld", "WorldName", "WorldId", "WorldID"}) do
            local value = leaderstats:FindFirstChild(key)
            if value then
                local worldNumber = normalizeWorld(value.Value)
                if worldNumber then return worldNumber end
            end
        end
    end

    for _, name in ipairs({"World1", "World 1", "World_1", "World-1"}) do
        if workspace:FindFirstChild(name) then return 1 end
    end
    for _, name in ipairs({"World2", "World 2", "World_2", "World-2"}) do
        if workspace:FindFirstChild(name) then return 2 end
    end

    return nil
end

local function getCurrentWalkSpeed()
    local worldNumber = getCurrentWorld()
    if worldNumber == 1 then return WALK_SPEED_WORLD_1 end
    if worldNumber == 2 then return WALK_SPEED_WORLD_2 end
    -- If the current world cannot be identified, default to World 1 speed (500).
    return WALK_SPEED_DEFAULT
end
-- Balanced movement update rates reduce command spam and help avoid jitter at high speeds.
local DIRECT_UPDATE_RATE   = 0.12
local STUCK_JUMP_AFTER     = 1.0
local STUCK_FALLBACK_AFTER = 3.0
 
local ROLL_CHARGE_DELAY   = 0.5       -- timing window; tune only to the game's documented mechanic
local DELAY_BETWEEN_ROLLS = 0        -- no extra pause after each roll cycle
local ROLL_VALUE          = 0.9802019699760107 -- existing value; verify against your game's roll logic
 
local autoRollActive      = false
local autoWalkActive      = false
local autoTrainActive     = false
local autoAFKActive       = false
local fpsBoostActive      = false
local fpsSavedProperties = {}
local fpsHiddenWorldParts = {}
local autoBuyBarbellActive = false
local autoBuySpeedActive = false
local selectedSpeedMultiplier = 1
local rollToken           = 0
local masterToken          = 0
local trainToken           = 0
local TRAIN_INTERVAL       = 0.2
 
-- ===== PRO iOS DARK GREY LIQUID THEME =====
local C = {
	glass     = Color3.fromRGB(22, 22, 26),
	glass2    = Color3.fromRGB(29, 29, 34),
	side      = Color3.fromRGB(15, 15, 19),
	stroke    = Color3.fromRGB(72, 72, 82),
	text      = Color3.fromRGB(245, 245, 247),
	sub       = Color3.fromRGB(150, 150, 160),
	accent    = Color3.fromRGB(210, 210, 220),
	select    = Color3.fromRGB(42, 42, 49),
	on        = Color3.fromRGB(48, 209, 88), -- iOS Green
}
local FONT, FONT_B, MONO = Enum.Font.GothamMedium, Enum.Font.GothamBold, Enum.Font.Code
local SIDE_W = 120
 
-- ===== HELPERS =====
local function new(class, props, par)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = par
	return o
end
local function corner(o, r) return new("UICorner", { CornerRadius = UDim.new(0, r) }, o) end
local function stroke(o, tr)
	return new("UIStroke", { Color = C.stroke, Thickness = 1, Transparency = tr or 0.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end
local function tw(o, t, props, style, dir)
	local tween = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint,
		dir or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end
local function glass(o, tr)
	o.BackgroundColor3 = C.glass
	o.BackgroundTransparency = tr or 0.2
	return new("UIGradient", {
		Rotation = 135,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.12), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 170, 178)),
	}, o)
end
 
local function animateButton(btn, hoverTr, baseTr)
	local sc = new("UIScale", { Scale = 1 }, btn)
	btn.MouseEnter:Connect(function() tw(btn, 0.15, { BackgroundTransparency = hoverTr }) end)
	btn.MouseLeave:Connect(function() tw(btn, 0.2, { BackgroundTransparency = baseTr }); tw(sc, 0.15, { Scale = 1 }) end)
	btn.MouseButton1Down:Connect(function() tw(sc, 0.1, { Scale = 0.94 }) end)
	btn.MouseButton1Up:Connect(function() tw(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back) end)
end
 
local function getGuiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	local ok2, core = pcall(function() return game:GetService("CoreGui") end)
	if ok2 and core then
		local t = Instance.new("ScreenGui")
		local ok3 = pcall(function() t.Parent = core end)
		t:Destroy()
		if ok3 then return core end
	end
	return playerGui
end
 
local guiParent = getGuiParent()
for _, p in ipairs({ guiParent, playerGui }) do
	local old = p:FindFirstChild("FreedomHubPro")
	if old then old:Destroy() end
end
local gui = new("ScreenGui", { Name = "FreedomHubPro", ResetOnSpawn = false, DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true }, guiParent)
 
-- ===== WINDOW =====
local window = new("CanvasGroup", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.38, 0.58), BorderSizePixel = 0, GroupTransparency = 1,
}, gui)
local windowGrad = glass(window, 0.15)
corner(window, 20); stroke(window, 0.4)
new("UISizeConstraint", { MinSize = Vector2.new(380, 230), MaxSize = Vector2.new(540, 340) }, window)
local winScale = new("UIScale", { Scale = 0.85 }, window)
 
-- ===== SIDEBAR =====
local sidebar = new("Frame", { Size = UDim2.new(0, SIDE_W, 1, 0), BackgroundColor3 = C.side,
	BackgroundTransparency = 0.3, BorderSizePixel = 0 }, window)
new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 1, 1, 0),
	BackgroundColor3 = C.stroke, BackgroundTransparency = 0.6, BorderSizePixel = 0 }, sidebar)
 
local logo = new("Frame", { Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1 }, sidebar)
 
local title = new("TextLabel", { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -22, 0, 16),
	BackgroundTransparency = 1, Text = "FREEDOM PRO", Font = FONT_B, TextScaled = true, TextColor3 = C.text,
	TextXAlignment = Enum.TextXAlignment.Left }, logo)
new("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 6 }, title)
local subtitle = new("TextLabel", { Position = UDim2.fromOffset(14, 28), Size = UDim2.new(1, -22, 0, 11),
	BackgroundTransparency = 1, Text = "iOS Liquid Dark", Font = MONO, TextScaled = true, TextColor3 = C.sub,
	TextXAlignment = Enum.TextXAlignment.Left }, logo)
new("UITextSizeConstraint", { MaxTextSize = 9, MinTextSize = 5 }, subtitle)
 
new("TextLabel", { Position = UDim2.fromOffset(14, 52), Size = UDim2.new(1, -20, 0, 14), BackgroundTransparency = 1,
	Text = "Modules", Font = MONO, TextSize = 8, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Left }, sidebar)
 
-- Main tab (above Auto Farm)
local mainTab = new("TextButton", {
    Position = UDim2.fromOffset(8, 68), Size = UDim2.new(1, -16, 0, 32),
    BackgroundColor3 = C.select, BackgroundTransparency = 0.3, Text = "",
    Font = FONT_B, TextSize = 11, TextColor3 = Color3.fromRGB(255, 255, 255),
    TextStrokeColor3 = Color3.fromRGB(235, 245, 255), TextStrokeTransparency = 0.35, AutoButtonColor = false,
    BorderSizePixel = 0,
}, sidebar)
corner(mainTab, 10)
animateButton(mainTab, 0.2, 0.3)
local mainTabLabel = new("TextLabel", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -20, 1, 0),
    BackgroundTransparency = 1, Text = "Main", Font = FONT_B, TextSize = 11,
    TextColor3 = Color3.fromRGB(255, 255, 255), TextStrokeColor3 = Color3.fromRGB(235, 245, 255),
    TextStrokeTransparency = 0.35, TextXAlignment = Enum.TextXAlignment.Left }, mainTab)

-- Auto Farm tab
local tab = new("TextButton", { Position = UDim2.fromOffset(8, 106), Size = UDim2.new(1, -16, 0, 32),
	BackgroundColor3 = C.select, BackgroundTransparency = 0.3, Text = "", AutoButtonColor = false,
	BorderSizePixel = 0, ClipsDescendants = true }, sidebar)
corner(tab, 10)
animateButton(tab, 0.2, 0.3)
local indicator = new("Frame", { Position = UDim2.fromOffset(0, 8), Size = UDim2.fromOffset(3, 0),
	BackgroundColor3 = C.text, BorderSizePixel = 0 }, tab)
corner(indicator, 2)
local autoFarmIcon = new("ImageLabel", { Position = UDim2.fromOffset(9, 8), Size = UDim2.fromOffset(16, 16),
    BackgroundTransparency = 1, Image = "rbxassetid://6034818485", ImageColor3 = Color3.fromRGB(255, 255, 255),
    ScaleType = Enum.ScaleType.Fit }, tab)
local tabLabel = new("TextLabel", { Position = UDim2.fromOffset(31, 0), Size = UDim2.new(1, -36, 1, 0),
	BackgroundTransparency = 1, Text = "Auto Farm", Font = FONT_B, TextScaled = true,
    TextColor3 = Color3.fromRGB(255, 255, 255), TextStrokeColor3 = Color3.fromRGB(235, 245, 255),
    TextStrokeTransparency = 0.35, TextXAlignment = Enum.TextXAlignment.Left }, tab)
new("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 7 }, tabLabel)

local settingsTab = new("TextButton", {
    Position = UDim2.fromOffset(8, 182), Size = UDim2.new(1, -16, 0, 32),
    BackgroundColor3 = C.select, BackgroundTransparency = 1, Text = "",
    Font = FONT_B, TextSize = 11, TextColor3 = Color3.fromRGB(255, 255, 255),
    TextStrokeColor3 = Color3.fromRGB(235, 245, 255), TextStrokeTransparency = 0.35, AutoButtonColor = false,
    BorderSizePixel = 0,
}, sidebar)
corner(settingsTab, 10)
animateButton(settingsTab, 0.2, 1)
local settingsIcon = new("ImageLabel", { Position = UDim2.fromOffset(9, 8), Size = UDim2.fromOffset(16, 16),
    BackgroundTransparency = 1, Image = "rbxassetid://6031280882", ImageColor3 = Color3.fromRGB(255, 255, 255),
    ScaleType = Enum.ScaleType.Fit }, settingsTab)
local settingsTabLabel = new("TextLabel", { Position = UDim2.fromOffset(31, 0), Size = UDim2.new(1, -36, 1, 0),
    BackgroundTransparency = 1, Text = "Settings", Font = FONT_B, TextSize = 11,
    TextColor3 = Color3.fromRGB(255, 255, 255), TextStrokeColor3 = Color3.fromRGB(235, 245, 255),
    TextStrokeTransparency = 0.35, TextXAlignment = Enum.TextXAlignment.Left }, settingsTab)

local shopTab = new("TextButton", {
    Position = UDim2.fromOffset(8, 144), Size = UDim2.new(1, -16, 0, 32),
    BackgroundColor3 = C.select, BackgroundTransparency = 1, Text = "",
    Font = FONT_B, TextSize = 11, TextColor3 = Color3.fromRGB(255, 255, 255),
    TextStrokeColor3 = Color3.fromRGB(235, 245, 255), TextStrokeTransparency = 0.35, AutoButtonColor = false,
    BorderSizePixel = 0,
}, sidebar)
corner(shopTab, 10)
animateButton(shopTab, 0.2, 1)
local shopIcon = new("ImageLabel", { Position = UDim2.fromOffset(9, 8), Size = UDim2.fromOffset(16, 16),
    BackgroundTransparency = 1, Image = "rbxassetid://6034818485", ImageColor3 = Color3.fromRGB(255, 255, 255),
    ScaleType = Enum.ScaleType.Fit }, shopTab)
local shopTabLabel = new("TextLabel", { Position = UDim2.fromOffset(31, 0), Size = UDim2.new(1, -36, 1, 0),
    BackgroundTransparency = 1, Text = "Shop", Font = FONT_B, TextSize = 11,
    TextColor3 = Color3.fromRGB(255, 255, 255), TextStrokeColor3 = Color3.fromRGB(235, 245, 255),
    TextStrokeTransparency = 0.35, TextXAlignment = Enum.TextXAlignment.Left }, shopTab)

-- ===== MAIN CONTENT AREA =====
local main = new("Frame", { Position = UDim2.new(0, SIDE_W, 0, 0), Size = UDim2.new(1, -SIDE_W, 1, 0),
	BackgroundTransparency = 1 }, window)
local topbar = new("Frame", { Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1 }, main)
 
local pageTitle = new("TextLabel", { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -160, 0, 18),
	BackgroundTransparency = 1, Text = "Auto Farm Hub", Font = FONT_B, TextSize = 14, TextColor3 = C.text,
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, topbar)
local pageSub = new("TextLabel", { Position = UDim2.fromOffset(14, 27), Size = UDim2.new(1, -160, 0, 14), BackgroundTransparency = 1,
	Text = "Continuous Walk & Roll System", Font = FONT, TextSize = 9, TextColor3 = C.sub,
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, topbar)
 
local function pill(w, x, text)
	local f = new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, x, 0, 9),
		Size = UDim2.fromOffset(w, 22), BackgroundColor3 = C.glass2, BackgroundTransparency = 0.4,
		Text = text, Font = MONO, TextSize = 9, TextColor3 = C.text, BorderSizePixel = 0 }, topbar)
	corner(f, 7); stroke(f, 0.5)
	return f
end
local minBtn = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 9),
	Size = UDim2.fromOffset(28, 22), BackgroundColor3 = C.glass2, BackgroundTransparency = 0.4, Text = "-",
	Font = FONT_B, TextSize = 14, TextColor3 = C.text, AutoButtonColor = false, BorderSizePixel = 0 }, topbar)
corner(minBtn, 7); stroke(minBtn, 0.4)
animateButton(minBtn, 0.2, 0.4)
local pingPill = pill(46, -44, "0 ms")
local fpsPill = pill(46, -94, "0 fps")
 
-- Page Scroll Containers
local mainPage = new("ScrollingFrame", {
    Name = "MainPage", Position = UDim2.fromOffset(12, 58), Size = UDim2.new(1, -24, 1, -68),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2,
    ScrollBarImageColor3 = C.accent, CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = true,
}, main)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, mainPage)

local noticeCard = new("Frame", {
    Name = "OfficialNotice", Size = UDim2.new(1, 0, 0, 194),
    BackgroundColor3 = C.glass2, BackgroundTransparency = 0.08, BorderSizePixel = 0,
    LayoutOrder = 1,
}, mainPage)
corner(noticeCard, 12); stroke(noticeCard, 0.2)
local noticeGlow = new("UIStroke", {
    Color = Color3.fromRGB(0, 255, 220), Thickness = 1.5, Transparency = 0.25,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, noticeCard)
new("TextLabel", {
    Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 0, 22),
    BackgroundTransparency = 1, Text = "OFFICIAL SCRIPT NOTICE", Font = FONT_B,
    TextSize = 12, TextColor3 = Color3.fromRGB(0, 255, 220),
    TextStrokeColor3 = Color3.fromRGB(0, 120, 255), TextStrokeTransparency = 0.45,
    TextXAlignment = Enum.TextXAlignment.Left,
}, noticeCard)
new("TextLabel", {
    Position = UDim2.fromOffset(12, 38), Size = UDim2.new(1, -24, 0, 72),
    BackgroundTransparency = 1,
    Text = "If you obtained this script from an unauthorized third party, you may have been scammed. To ensure you receive authentic scripts and future updates, please join our official Discord server linked below.",
    Font = FONT, TextSize = 10, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
    TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(110, 255, 235),
    TextStrokeColor3 = Color3.fromRGB(0, 100, 120), TextStrokeTransparency = 0.7,
}, noticeCard)
local discordButton = new("TextButton", {
    Name = "OfficialDiscordButton", Position = UDim2.fromOffset(12, 116),
    Size = UDim2.new(1, -24, 0, 42), BackgroundColor3 = Color3.fromRGB(88, 101, 242),
    BackgroundTransparency = 0.02, BorderSizePixel = 0, AutoButtonColor = true,
    Text = "", Font = FONT_B, TextSize = 13, TextColor3 = Color3.new(1, 1, 1),
}, noticeCard)
corner(discordButton, 9)
new("UIStroke", { Color = Color3.fromRGB(150, 160, 255), Thickness = 1.25, Transparency = 0.15 }, discordButton)
-- Discord-style emblem placed before FREEDOM HUB. Roblox UI images must use Roblox asset IDs,
-- so this is drawn with a text glyph instead of loading the external website image URL directly.
local discordLogo = new("TextLabel", {
    Name = "DiscordLogo", Position = UDim2.new(0, 10, 0, 0), Size = UDim2.fromOffset(30, 42),
    BackgroundTransparency = 1, Text = "☻", Font = Enum.Font.GothamBold, TextSize = 24,
    TextColor3 = Color3.fromRGB(255, 255, 255), TextXAlignment = Enum.TextXAlignment.Center,
}, discordButton)
local discordButtonLabel = new("TextLabel", {
    Name = "DiscordButtonLabel", Position = UDim2.new(0, 42, 0, 0),
    Size = UDim2.new(1, -50, 1, 0), BackgroundTransparency = 1,
    Text = "FREEDOM HUB", Font = FONT_B, TextSize = 13,
    TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left,
}, discordButton)
local discordHint = new("TextLabel", {
    Position = UDim2.fromOffset(12, 162), Size = UDim2.new(1, -24, 0, 20),
    BackgroundTransparency = 1, Text = "Click to copy invite: discord.gg/2ASthK7HFE",
    Font = MONO, TextSize = 8, TextColor3 = Color3.fromRGB(170, 180, 255),
    TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
}, noticeCard)

local inviteLink = "https://discord.gg/2ASthK7HFE"
local function copyDiscordInvite()
    local clipboardCopied = false
    -- Clipboard functions are available in some supported script environments, not standard Roblox LocalScripts.
    for _, clipboardFunction in ipairs({
        (type(setclipboard) == "function" and setclipboard or nil),
        (type(toclipboard) == "function" and toclipboard or nil),
    }) do
        if clipboardFunction then
            local ok = pcall(clipboardFunction, inviteLink)
            if ok then clipboardCopied = true; break end
        end
    end
    if clipboardCopied then
        discordButtonLabel.Text = "✓  INVITE COPIED!"
        discordHint.Text = inviteLink
    else
        discordButtonLabel.Text = "FREEDOM HUB"
        discordHint.Text = "Clipboard unavailable here: " .. inviteLink
        -- Still try to open the invite as a fallback.
        pcall(function()
            game:GetService("GuiService"):OpenBrowserWindow(inviteLink)
        end)
    end
    task.delay(2.5, function()
        if discordButton and discordButton.Parent then
            discordButtonLabel.Text = "FREEDOM HUB"
        end
    end)
end
discordButton.MouseButton1Click:Connect(copyDiscordInvite)

local profileCard = new("Frame", {
    Name = "UserProfileCard", Size = UDim2.new(1, 0, 0, 154),
    BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0,
    BorderSizePixel = 0, LayoutOrder = 2,
}, mainPage)
corner(profileCard, 12); stroke(profileCard, 0.2)
new("UIStroke", { Color = Color3.fromRGB(205, 205, 215), Thickness = 1.25, Transparency = 0.05 }, profileCard)
new("TextLabel", {
    Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 18),
    BackgroundTransparency = 1, Text = "PLAYER PROFILE", Font = FONT_B, TextSize = 12,
    TextColor3 = Color3.fromRGB(48, 48, 58),
    TextStrokeColor3 = Color3.fromRGB(255, 255, 255), TextStrokeTransparency = 1,
    TextXAlignment = Enum.TextXAlignment.Left,
}, profileCard)
local profileFace = new("ImageLabel", {
    Name = "ProfileFace", Position = UDim2.fromOffset(12, 32), Size = UDim2.fromOffset(58, 58),
    BackgroundColor3 = Color3.fromRGB(238, 238, 242), BackgroundTransparency = 0, BorderSizePixel = 0,
    Image = "", ScaleType = Enum.ScaleType.Crop,
}, profileCard)
corner(profileFace, 10); stroke(profileFace, 0.25)
local profileName = new("TextLabel", {
    Name = "ProfileName", Position = UDim2.fromOffset(80, 34), Size = UDim2.new(1, -92, 0, 24),
    BackgroundTransparency = 1, Text = "Name: " .. player.Name,
    Font = FONT_B, TextSize = 11, TextColor3 = Color3.fromRGB(28, 28, 34),
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
}, profileCard)
local profileDisplayName = new("TextLabel", {
    Name = "ProfileDisplayName", Position = UDim2.fromOffset(80, 58), Size = UDim2.new(1, -92, 0, 18),
    BackgroundTransparency = 1, Text = "Display: " .. player.DisplayName,
    Font = FONT, TextSize = 9, TextColor3 = Color3.fromRGB(78, 78, 88),
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
}, profileCard)
local profileGame = new("TextLabel", {
    Name = "ProfileGame", Position = UDim2.fromOffset(12, 101), Size = UDim2.new(1, -24, 0, 42),
    BackgroundTransparency = 1, Text = "Game: " .. game.Name .. "\nPlace ID: " .. tostring(game.PlaceId),
    Font = MONO, TextSize = 9, TextColor3 = Color3.fromRGB(78, 78, 88),
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true,
}, profileCard)
-- Load the local player's Roblox headshot asynchronously so the Main page stays responsive.
task.spawn(function()
    local ok, thumbnail = pcall(function()
        return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
    end)
    if ok and profileFace and profileFace.Parent then
        profileFace.Image = thumbnail
    end
end)
task.spawn(function()
    local ok, productInfo = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
    end)
    if ok and productInfo and productInfo.Name and profileGame and profileGame.Parent then
        profileGame.Text = "Game: " .. productInfo.Name .. "\nPlace ID: " .. tostring(game.PlaceId)
    end
end)

local page = new("ScrollingFrame", { Position = UDim2.fromOffset(12, 58), Size = UDim2.new(1, -24, 1, -68),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2, ScrollBarImageColor3 = C.accent,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false }, main)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, page)

local settingsPage = new("ScrollingFrame", {
    Name = "SettingsPage", Position = page.Position, Size = page.Size,
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2,
    ScrollBarImageColor3 = C.accent, CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
}, main)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, settingsPage)
new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1,
    Text = "Settings & behavior", Font = FONT_B, TextSize = 12,
    TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left,
}, settingsPage)

local shopPage = new("ScrollingFrame", {
    Name = "ShopPage", Position = page.Position, Size = page.Size,
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2,
    ScrollBarImageColor3 = C.accent, CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
}, main)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, shopPage)
new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1,
    Text = "Shop automation", Font = FONT_B, TextSize = 12,
    TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left,
}, shopPage)

local function showPage(which)
    local isMain = which == "main"
    local isFarm = which == "farm"
    local isSettings = which == "settings"
    local isShop = which == "shop"
    mainPage.Visible = isMain
    page.Visible = isFarm
    settingsPage.Visible = isSettings
    shopPage.Visible = isShop
    pageTitle.Text = isMain and "Main" or (isSettings and "Settings" or (isShop and "Shop" or "Auto Farm Hub"))
    pageSub.Text = isMain and "Official information & community" or (isSettings and "Preferences & idle options" or (isShop and "Auto purchase options" or "Continuous Walk & Roll System"))
    mainTab.BackgroundTransparency = isMain and 0.3 or 1
    mainTab.TextColor3 = Color3.fromRGB(255, 255, 255)
    tab.BackgroundTransparency = isFarm and 0.3 or 1
    tabLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    settingsTab.BackgroundTransparency = isSettings and 0.3 or 1
    settingsTab.TextColor3 = Color3.fromRGB(255, 255, 255)
    shopTab.BackgroundTransparency = isShop and 0.3 or 1
    shopTab.TextColor3 = Color3.fromRGB(255, 255, 255)
end

mainTab.MouseButton1Click:Connect(function() showPage("main") end)
tab.MouseButton1Click:Connect(function() showPage("farm") end)
settingsTab.MouseButton1Click:Connect(function() showPage("settings") end)
shopTab.MouseButton1Click:Connect(function() showPage("shop") end)
showPage("main")

local statusLabel = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 24),
	BackgroundTransparency = 1,
	Text = "Status: Idle",
	Font = MONO,
	TextSize = 10,
	TextColor3 = C.sub,
	TextXAlignment = Enum.TextXAlignment.Left,
}, page)
 
-- ===== UI BUILDERS =====
local function createToggle(name, text, defaultState, callback, parent)
    parent = parent or page
	local container = new("Frame", { Name = name, Size = UDim2.new(1, 0, 0, 42),
		BackgroundColor3 = C.glass2, BackgroundTransparency = 0.4, BorderSizePixel = 0 }, parent)
	corner(container, 10); stroke(container, 0.5)
 
	local lbl = new("TextLabel", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -70, 1, 0),
		BackgroundTransparency = 1, Text = text, Font = FONT_B, TextSize = 11, TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left }, container)
 
	local switch = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 42, 0, 22), BackgroundColor3 = defaultState and C.on or C.glass,
		BackgroundTransparency = 0.15, Text = "", AutoButtonColor = false, BorderSizePixel = 0 }, container)
	corner(switch, 11); stroke(switch, 0.4)
 
	local knob = new("Frame", { AnchorPoint = Vector2.new(0, 0.5),
		Position = defaultState and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(18, 18), BackgroundColor3 = C.text, BorderSizePixel = 0 }, switch)
	corner(knob, 9)
 
	local state = defaultState
	switch.MouseButton1Click:Connect(function()
		state = not state
		tw(switch, 0.2, { BackgroundColor3 = state and C.on or C.glass })
		tw(knob, 0.2, { Position = state and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0) })
		callback(state)
	end)
 
	return container
end
 
local function getHumanoidAndRoot()
	local char = player.Character
	if not char then return nil, nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then return nil, nil end
	return hum, root
end
 
local function setStatus(text, color)
	statusLabel.Text = text or ""
	statusLabel.TextColor3 = color or C.sub
end
 
-- ===== STABLE FAST RETURN TO TARGET =====
local function runDirect(token)
    local hum, root = getHumanoidAndRoot()
    if not hum then return false end

    local originalSpeed = hum.WalkSpeed
    hum.WalkSpeed = getCurrentWalkSpeed()
    setStatus("Returning to target...", Color3.fromRGB(150, 255, 150))

    local lastPos = root.Position
    local lastMoveTime = os.clock()
    local lastCommandTime = 0
    local jumpAttempted = false

    while autoWalkActive and token == masterToken do
        local h, r = getHumanoidAndRoot()
        if not h or not r then break end
        h.WalkSpeed = getCurrentWalkSpeed()

        local distance = (r.Position - TARGET_POSITION).Magnitude
        if distance <= 3 then
            setStatus("At target position", Color3.fromRGB(150, 255, 150))
            -- Check again on the next scheduler step so displacement is detected quickly.
            task.wait()
            lastPos = r.Position
            lastMoveTime = os.clock()
            lastCommandTime = 0
            jumpAttempted = false
        else
            -- Refresh the destination at a steady interval to reduce movement jitter.
            if os.clock() - lastCommandTime >= DIRECT_UPDATE_RATE then
                h:MoveTo(TARGET_POSITION)
                lastCommandTime = os.clock()
            end

            if (r.Position - lastPos).Magnitude >= 1 then
                lastPos = r.Position
                lastMoveTime = os.clock()
                jumpAttempted = false
            elseif os.clock() - lastMoveTime >= STUCK_JUMP_AFTER and not jumpAttempted then
                h.Jump = true
                jumpAttempted = true
            elseif os.clock() - lastMoveTime >= STUCK_FALLBACK_AFTER then
                if h.Parent then h.WalkSpeed = originalSpeed end
                return false -- blocked: try pathfinding
            end
        end
        task.wait(0.03) -- responsive polling without a busy loop
    end

    if hum and hum.Parent then hum.WalkSpeed = originalSpeed end
    return false
end

local function runPathfinding(token)
    local hum, root = getHumanoidAndRoot()
    if not hum then return false end

    local originalSpeed = hum.WalkSpeed
    hum.WalkSpeed = getCurrentWalkSpeed()
    setStatus("Finding route to target...", Color3.fromRGB(150, 200, 255))

    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
    })

    local ok = pcall(function()
        path:ComputeAsync(root.Position, TARGET_POSITION)
    end)
    if not ok or path.Status ~= Enum.PathStatus.Success then
        if hum and hum.Parent then hum.WalkSpeed = originalSpeed end
        return false
    end

    for i, wp in ipairs(path:GetWaypoints()) do
        if not (autoWalkActive and token == masterToken) then break end
        local h, r = getHumanoidAndRoot()
        if not h or not r then break end
        h.WalkSpeed = getCurrentWalkSpeed()
        if wp.Action == Enum.PathWaypointAction.Jump then h.Jump = true end
        h:MoveTo(wp.Position)
        setStatus(("Pathfinding waypoint %d/%d"):format(i, #path:GetWaypoints()), Color3.fromRGB(150, 200, 255))

        local reached = false
        local conn = h.MoveToFinished:Connect(function(success)
            if success then reached = true end
        end)
        local started = os.clock()
        while not reached and os.clock() - started < 3 do
            if not (autoWalkActive and token == masterToken) then break end
            local _, currentRoot = getHumanoidAndRoot()
            if not currentRoot or (currentRoot.Position - wp.Position).Magnitude <= 3 then
                reached = true
                break
            end
            task.wait(0.05)
        end
        conn:Disconnect()
        if not reached then
            if hum and hum.Parent then hum.WalkSpeed = originalSpeed end
            return false
        end
    end

    if hum and hum.Parent then hum.WalkSpeed = originalSpeed end
    local _, finalRoot = getHumanoidAndRoot()
    return finalRoot ~= nil and (finalRoot.Position - TARGET_POSITION).Magnitude <= 3
end

local function goToTarget(token)
    if not (autoWalkActive and token == masterToken) then return false end
    local ok, result = pcall(runDirect, token)
    if ok and result then return true end
    if not (autoWalkActive and token == masterToken) then return false end
    local pathOk, pathResult = pcall(runPathfinding, token)
    return pathOk and pathResult or false
end

local function walkMainLoop(token)
    while autoWalkActive and token == masterToken do
        local hum, root = getHumanoidAndRoot()
        if not hum or not root then
            task.wait(0.25)
        elseif (root.Position - TARGET_POSITION).Magnitude <= 3 then
            setStatus("At target position", Color3.fromRGB(150, 255, 150))
            task.wait(0.03) -- frequent checks while keeping the loop lightweight
        else
            local success = goToTarget(token)
            if not success and autoWalkActive and token == masterToken then
                setStatus("Route blocked; retrying...", Color3.fromRGB(255, 190, 100))
                task.wait() -- immediately retry on the next scheduler step
            end
        end
    end
end

-- ===== CONTINUOUS AUTO ROLL LOGIC =====
-- Repeats charge/roll for as long as the toggle is ON. The server/game decides
-- whether a roll is Perfect; client timing alone cannot guarantee that result.
local function startSafeAutoRoll(token)
    if not RollEvent or not RollEvent:IsA("RemoteEvent") then
        setStatus("AUTO PERFECT ROLL unavailable: RollEvent RemoteEvent not found", Color3.fromRGB(255, 120, 120))
        return
    end

    setStatus("AUTO PERFECT ROLL ON — continuous cycle active", Color3.fromRGB(150, 255, 150))

    -- Keep the character settled at the configured farm target while rolling.
    -- Do not anchor the root part; anchoring can break normal character physics.
    task.spawn(function()
        local savedAutoRotate = nil
        local savedHumanoid = nil
        while autoRollActive and token == rollToken do
            local hum, root = getHumanoidAndRoot()
            if hum and root and (root.Position - TARGET_POSITION).Magnitude <= 3 then
                if savedHumanoid ~= hum then
                    savedHumanoid = hum
                    savedAutoRotate = hum.AutoRotate
                end
                hum.AutoRotate = false
                hum:Move(Vector3.zero, true)
                local velocity = root.AssemblyLinearVelocity
                root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
            end
            task.wait()
        end
        if savedHumanoid and savedHumanoid.Parent and savedAutoRotate ~= nil then
            savedHumanoid.AutoRotate = savedAutoRotate
        end
    end)

    task.spawn(function()
        local failures = 0
        while autoRollActive and token == rollToken do
            local chargeOK, chargeErr = pcall(function()
                RollEvent:FireServer("Charge")
            end)

            if not chargeOK then
                failures += 1
                warn("[Freedom Pro] Charge request failed:", chargeErr)
                setStatus("Auto Perfect Roll retrying after error...", Color3.fromRGB(255, 190, 100))
                task.wait(math.min(0.25 * failures, 2))
                continue
            end

            -- This is the configured charge interval, not a guarantee of perfect timing.
            task.wait(ROLL_CHARGE_DELAY)
            if not (autoRollActive and token == rollToken) then break end

            local rollOK, rollErr = pcall(function()
                RollEvent:FireServer("Roll", ROLL_VALUE)
            end)

            if rollOK then
                failures = 0
                -- Yield one scheduler step to keep the client responsive, then restart immediately.
                if DELAY_BETWEEN_ROLLS > 0 then
                    task.wait(DELAY_BETWEEN_ROLLS)
                else
                    task.wait()
                end
            else
                failures += 1
                warn("[Freedom Pro] Roll request failed:", rollErr)
                setStatus("Auto Perfect Roll retrying after error...", Color3.fromRGB(255, 190, 100))
                task.wait(math.min(0.25 * failures, 2))
            end
        end
        if token == rollToken and not autoRollActive then
            setStatus("Auto Perfect Roll OFF", C.sub)
        end
    end)
end

-- ===== AUTO TRAIN =====
-- Only equips/activates a Tool whose name contains "barbell" while Auto Train is ON.
local function findBarbell()
    local character = player.Character
    local backpack = player:FindFirstChildOfClass("Backpack")
    for _, container in ipairs({character, backpack}) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if item:IsA("Tool") and string.find(string.lower(item.Name), "barbell", 1, true) then
                    return item
                end
            end
        end
    end
    return nil
end

local function startAutoTrain(token)
    task.spawn(function()
        while autoTrainActive and token == trainToken do
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local backpack = player:FindFirstChildOfClass("Backpack")
            local tool = findBarbell()
            if humanoid and tool and autoTrainActive and token == trainToken then
                if tool.Parent == backpack then
                    pcall(function() humanoid:EquipTool(tool) end)
                end
                if tool.Parent == character and autoTrainActive and token == trainToken then
                    pcall(function() tool:Activate() end)
                end
            end
            task.wait(TRAIN_INTERVAL)
        end
    end)
end

local function stopAutoTrain()
    -- If the barbell was equipped by Auto Train, return it to Backpack when toggled OFF.
    local character = player.Character
    local backpack = player:FindFirstChildOfClass("Backpack")
    if character and backpack then
        for _, item in ipairs(character:GetChildren()) do
            if item:IsA("Tool") and string.find(string.lower(item.Name), "barbell", 1, true) then
                item.Parent = backpack
            end
        end
    end
end

-- ===== LOW-END DEVICE FPS / ANTI-LAG BOOST =====
-- Applies an aggressive client-side low-end graphics preset when enabled.
-- “100x” describes the requested preset name/target, not a guaranteed FPS multiplier.
local fpsDescendantConnection = nil
local fpsOriginalQuality = nil
local fpsOriginalGlobalShadows = nil
local fpsOriginalWaterWaveSize = nil
local fpsOriginalWaterWaveSpeed = nil
local fpsOriginalWaterReflectance = nil
local fpsOriginalWaterTransparency = nil
local fpsBoostToken = 0

local function setFPSBoost(enabled)
    fpsBoostToken += 1
    local myToken = fpsBoostToken
    fpsBoostActive = enabled

    if fpsDescendantConnection then
        fpsDescendantConnection:Disconnect()
        fpsDescendantConnection = nil
    end

    local lighting = game:GetService("Lighting")
    local terrain = workspace:FindFirstChildOfClass("Terrain")

    local function reduceVisualCost(obj)
        if not fpsBoostActive or myToken ~= fpsBoostToken then return end
        -- Hide fence pieces and plots that appear to belong to other players on this client only.
        -- Original LocalTransparencyModifier values are saved and restored when FPS Boost is turned off.
        if obj:IsA("BasePart") then
            local lowerName = string.lower(obj.Name)
            local fenceLike = string.find(lowerName, "fence", 1, true) ~= nil
            local plotAncestor = nil
            local ancestor = obj.Parent
            while ancestor and ancestor ~= workspace do
                local ancestorName = string.lower(ancestor.Name)
                if string.find(ancestorName, "fence", 1, true) then
                    fenceLike = true
                end
                if not plotAncestor and string.find(ancestorName, "plot", 1, true) then
                    plotAncestor = ancestor
                end
                ancestor = ancestor.Parent
            end
            -- Only hide a plot when its owner can be positively identified as another player.
            -- Unknown/unlabelled plots are left visible to avoid accidentally hiding the local player's plot.
            local function resolvePlotOwner(plot)
                if not plot then return nil end
                local function matchPlayerText(value)
                    if value == nil then return nil end
                    local textValue = string.lower(tostring(value))
                    if textValue == "" then return nil end
                    if textValue == string.lower(player.Name)
                        or textValue == string.lower(player.DisplayName)
                        or textValue == tostring(player.UserId) then
                        return player
                    end
                    for _, otherPlayer in ipairs(Players:GetPlayers()) do
                        if textValue == string.lower(otherPlayer.Name)
                            or textValue == string.lower(otherPlayer.DisplayName)
                            or textValue == tostring(otherPlayer.UserId) then
                            return otherPlayer
                        end
                    end
                    -- Allow common owner labels like "Plot_PlayerName" or "PlayerName_Plot".
                    for _, otherPlayer in ipairs(Players:GetPlayers()) do
                        local n = string.lower(otherPlayer.Name)
                        local d = string.lower(otherPlayer.DisplayName)
                        if string.find(textValue, n, 1, true) or string.find(textValue, d, 1, true)
                            or string.find(textValue, tostring(otherPlayer.UserId), 1, true) then
                            return otherPlayer
                        end
                    end
                    return nil
                end
                local nameOwner = matchPlayerText(plot.Name)
                if nameOwner then return nameOwner end
                for _, key in ipairs({"Owner", "OwnerName", "PlayerName", "UserName", "UserId", "OwnerUserId"}) do
                    local ok, value = pcall(function() return plot:GetAttribute(key) end)
                    if ok and value ~= nil then
                        local owner = matchPlayerText(value)
                        if owner then return owner end
                    end
                    local child = plot:FindFirstChild(key, true)
                    if child and (child:IsA("StringValue") or child:IsA("IntValue") or child:IsA("NumberValue")) then
                        local owner = matchPlayerText(child.Value)
                        if owner then return owner end
                    elseif child and child:IsA("ObjectValue") and child.Value then
                        local valueObj = child.Value
                        if valueObj:IsA("Player") then return valueObj end
                        local owner = matchPlayerText(valueObj.Name)
                        if owner then return owner end
                    end
                end
                return nil
            end
            local plotOwner = resolvePlotOwner(plotAncestor)
            local belongsToOtherPlayer = plotOwner ~= nil and plotOwner ~= player
            -- Keep the local player's plot and pets intact. Parts/pets under a confirmed
            -- other player's plot are hidden locally through LocalTransparencyModifier.
            local shouldHide = (plotAncestor and belongsToOtherPlayer)
                or (fenceLike and not plotAncestor)
            if shouldHide then
                if fpsHiddenWorldParts[obj] == nil then
                    fpsHiddenWorldParts[obj] = obj.LocalTransparencyModifier
                end
                obj.LocalTransparencyModifier = 1
            end
        end
        if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
            or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
            if fpsSavedProperties[obj] == nil then
                fpsSavedProperties[obj] = { Enabled = obj.Enabled }
                obj.Enabled = false
            end
        elseif obj:IsA("PostEffect") then
            if fpsSavedProperties[obj] == nil then
                fpsSavedProperties[obj] = { Enabled = obj.Enabled }
                obj.Enabled = false
            end
        elseif obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
            if fpsSavedProperties[obj] == nil then
                fpsSavedProperties[obj] = { Shadows = obj.Shadows }
                obj.Shadows = false
            end
        elseif obj:IsA("BasePart") and obj.Material ~= Enum.Material.Plastic
            and obj.Material ~= Enum.Material.SmoothPlastic then
            if fpsSavedProperties[obj] == nil then
                fpsSavedProperties[obj] = { Material = obj.Material, Reflectance = obj.Reflectance }
                obj.Material = Enum.Material.Plastic
                obj.Reflectance = 0
            end
        end
    end

    if enabled then
        fpsSavedProperties = {}
        fpsHiddenWorldParts = {}

        -- Low rendering quality and fewer expensive lighting effects are applied first.
        pcall(function()
            fpsOriginalQuality = UserSettings():GetService("UserGameSettings").SavedQualityLevel
            UserSettings():GetService("UserGameSettings").SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
        end)
        pcall(function()
            fpsOriginalGlobalShadows = lighting.GlobalShadows
            lighting.GlobalShadows = false
        end)
        if terrain then
            pcall(function()
                fpsSavedProperties[terrain] = {
                    Decoration = terrain.Decoration,
                    WaterWaveSize = terrain.WaterWaveSize,
                    WaterWaveSpeed = terrain.WaterWaveSpeed,
                    WaterReflectance = terrain.WaterReflectance,
                    WaterTransparency = terrain.WaterTransparency,
                }
                terrain.Decoration = false
                terrain.WaterWaveSize = 0
                terrain.WaterWaveSpeed = 0
                terrain.WaterReflectance = 0
                terrain.WaterTransparency = 1
            end)
        end

        -- Watch newly streamed/spawned effects immediately.
        fpsDescendantConnection = game.DescendantAdded:Connect(reduceVisualCost)
        setStatus("FPS BOOST ON — applying ultra low-end performance preset…", Color3.fromRGB(150, 255, 150))

        -- Batch the existing world scan so enabling the toggle doesn't stall the UI.
        task.spawn(function()
            local descendants = game:GetDescendants()
            for index, obj in ipairs(descendants) do
                if not fpsBoostActive or myToken ~= fpsBoostToken then return end
                pcall(reduceVisualCost, obj)
                if index % 200 == 0 then task.wait() end
            end
            if fpsBoostActive and myToken == fpsBoostToken then
                setStatus("FPS BOOST ACTIVE — ultra low-end preset applied", Color3.fromRGB(150, 255, 150))
            end
        end)
    else
        -- Stop background work and restore properties captured before the boost.
        for obj, properties in pairs(fpsSavedProperties) do
            if obj and obj.Parent then
                for property, value in pairs(properties) do
                    pcall(function() obj[property] = value end)
                end
            end
        end
        fpsSavedProperties = {}
        for part, originalModifier in pairs(fpsHiddenWorldParts) do
            if part and part.Parent then
                pcall(function() part.LocalTransparencyModifier = originalModifier end)
            end
        end
        fpsHiddenWorldParts = {}
        if fpsOriginalQuality ~= nil then
            pcall(function()
                UserSettings():GetService("UserGameSettings").SavedQualityLevel = fpsOriginalQuality
            end)
            fpsOriginalQuality = nil
        end
        if fpsOriginalGlobalShadows ~= nil then
            pcall(function() lighting.GlobalShadows = fpsOriginalGlobalShadows end)
            fpsOriginalGlobalShadows = nil
        end
        setStatus("FPS BOOST OFF — saved visual settings restored", C.sub)
    end
end

-- ===== AUTO AFK =====
-- Attempts to prevent the client from being marked idle while this toggle is on.
player.Idled:Connect(function()
    if not autoAFKActive then return end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end)

-- ===== REGISTER TOGGLES =====
-- Professional Auto Perfect Roll toggle: continuously repeats the existing Charge -> Roll sequence while enabled.
-- Actual Perfect results depend on the game server's timing/validation logic.
createToggle("AutoRollFeature", "Auto Perfect Roll", false, function(state)
	autoRollActive = state
	rollToken += 1
	if autoRollActive then
        startSafeAutoRoll(rollToken)
    else
        setStatus("Auto Perfect Roll OFF", C.sub)
    end
end)
 
createToggle("AutoTrainFeature", "Enable Auto Train", false, function(state)
    autoTrainActive = state
    trainToken += 1
    if autoTrainActive then
        startAutoTrain(trainToken)
        setStatus("Auto Train enabled", Color3.fromRGB(150, 255, 150))
    else
        stopAutoTrain()
        setStatus("Auto Train stopped — barbell returned", C.sub)
    end
end)

createToggle("AutoAFKFeature", "Auto AFK", false, function(state)
    autoAFKActive = state
    if state then
        setStatus("AUTO AFK ON — idle prevention active", Color3.fromRGB(150, 255, 150))
    else
        setStatus("AUTO AFK OFF", C.sub)
    end
end, settingsPage)

createToggle("FPSBoostSetting", "FPS Boost", false, function(state)
    setFPSBoost(state)
end, settingsPage)

-- Shop controls are shown here, but purchasing needs the game's real shop RemoteEvents/API.
-- These toggles deliberately do not fire guessed remotes or fake purchases.
createToggle("AutoBuySpeedFeature", "Auto Buy Speed", false, function(state)
    autoBuySpeedActive = state
    setStatus("Auto Buy toggled; real shop purchase hookup is still required", Color3.fromRGB(255, 190, 90))
end, shopPage)

local speedOptions = new("Frame", {
    Name = "SpeedMultiplierOptions", Size = UDim2.new(1, 0, 0, 58),
    BackgroundColor3 = C.glass2, BackgroundTransparency = 0.4, BorderSizePixel = 0,
}, shopPage)
corner(speedOptions, 10); stroke(speedOptions, 0.5)
new("TextLabel", {
    Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 18),
    BackgroundTransparency = 1, Text = "Purchase amount",
    Font = FONT_B, TextSize = 10, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left,
}, speedOptions)

local function makeSpeedOption(label, multiplier, x, width)
    local button = new("TextButton", {
        Position = UDim2.new(x, 0, 0, 27), Size = UDim2.new(width, -4, 0, 24),
        BackgroundColor3 = selectedSpeedMultiplier == multiplier and C.on or C.glass,
        BackgroundTransparency = 0.15, BorderSizePixel = 0, AutoButtonColor = false,
        Text = label, Font = FONT_B, TextSize = 10, TextColor3 = C.text,
    }, speedOptions)
    corner(button, 7)
    button.MouseButton1Click:Connect(function()
        selectedSpeedMultiplier = multiplier
        for _, child in ipairs(speedOptions:GetChildren()) do
            if child:IsA("TextButton") then
                child.BackgroundColor3 = child == button and C.on or C.glass
            end
        end
        setStatus("Speed multiplier selected: " .. multiplier .. "x (shop hookup required)", Color3.fromRGB(255, 190, 90))
    end)
end
makeSpeedOption("1x", 1, 0, 1/3)
makeSpeedOption("5x", 5, 1/3, 1/3)
makeSpeedOption("10x", 10, 2/3, 1/3)

createToggle("AutoWalkFeature", "Enable Auto Walk", false, function(state)
	autoWalkActive = state
	masterToken += 1
	if autoWalkActive then
		local myToken = masterToken
		setStatus(("🚀 Auto walking to (%d, %d, %d)"):format(
			TARGET_POSITION.X, TARGET_POSITION.Y, TARGET_POSITION.Z),
			Color3.fromRGB(150, 255, 150))
		task.spawn(function() walkMainLoop(myToken) end)
	else
		setStatus("⏹ Walk Stopped", C.sub)
	end
end)
 
-- ===== LIVE METRICS =====
local frames, last = 0, os.clock()
RunService.RenderStepped:Connect(function()
	frames += 1
	if os.clock() - last >= 0.5 then
		fpsPill.Text = math.floor(frames / (os.clock() - last)) .. " fps"
		frames, last = 0, os.clock()
		local ok, ping = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
		pingPill.Text = (ok and math.floor(ping) or 0) .. " ms"
	end
end)
 
RunService.Heartbeat:Connect(function()
	windowGrad.Rotation = 135 + math.sin(os.clock() * 0.6) * 20
end)
 
-- ===== MINIMIZE FUNCTIONALITY =====
local mini = new("TextButton", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.08),
	Size = UDim2.fromOffset(130, 32), Text = "FREEDOM PRO", Font = FONT_B, TextSize = 10, TextColor3 = C.text,
	AutoButtonColor = false, BorderSizePixel = 0, Visible = false }, gui)
glass(mini, 0.15); corner(mini, 16); stroke(mini, 0.4)
local miniScale = new("UIScale", { Scale = 0.7 }, mini)
mini.MouseEnter:Connect(function() tw(miniScale, 0.15, { Scale = 1.05 }) end)
mini.MouseLeave:Connect(function() tw(miniScale, 0.2, { Scale = 1 }) end)
 
local minimized, busy = false, false
local function setMinimized(state)
	if busy or state == minimized then return end
	busy = true
	minimized = state
	if state then
		tw(winScale, 0.2, { Scale = 0.8 })
		tw(window, 0.2, { GroupTransparency = 1 })
		task.delay(0.2, function()
			window.Visible = false
			mini.Visible = true
			miniScale.Scale = 0.7
			tw(miniScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			busy = false
		end)
	else
		tw(miniScale, 0.15, { Scale = 0.7 })
		task.delay(0.15, function()
			mini.Visible = false
			window.Visible = true
			winScale.Scale = 0.85
			tw(winScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			tw(window, 0.2, { GroupTransparency = 0 })
			busy = false
		end)
	end
end
minBtn.MouseButton1Click:Connect(function() setMinimized(true) end)
mini.MouseButton1Click:Connect(function() setMinimized(false) end)
UIS.InputBegan:Connect(function(i, gp)
	if not gp and i.KeyCode == Enum.KeyCode.RightShift then setMinimized(not minimized) end
end)
 
-- ===== DRAGGABLE WINDOW =====
local function makeDraggable(handle, target)
	local dragging, start, origin
	handle.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, start, origin = true, i.Position, target.Position
			i.Changed:Connect(function()
				if i.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - start
			target.Position = UDim2.new(origin.X.Scale, origin.X.Offset + d.X, origin.Y.Scale, origin.Y.Offset + d.Y)
		end
	end)
end
makeDraggable(topbar, window)
makeDraggable(logo, window)
makeDraggable(mini, mini)
 
-- ===== INTRO ENTRANCE =====
task.defer(function()
	tw(window, 0.35, { GroupTransparency = 0 })
	tw(winScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	task.wait(0.15)
	tw(indicator, 0.3, { Size = UDim2.fromOffset(3, 16) }, Enum.EasingStyle.Back)
end)