--[[
    Banana Hub UI.

    Shared interface library for the Banana Hub Soreya scripts. Load it once:

        local BananaHubUI = loadstring(readfile("BananaHubUI.luau"))()
        local Window = BananaHubUI:CreateWindow({ Title = "Banana Hub" })

    The public surface deliberately mirrors WindUI (CreateWindow / Notify /
    SetTheme, Window:Tab, Section:Toggle ... Space) so the Soreya feature code
    runs unchanged, while the window itself is the Banana Hub interface.

    No key system, no roles, no tiers. Everything is local.
]]

-- BANANAHUB_BUILD_BLACK_8
-- Build marker. The Soreya scripts look for this exact string before they
-- accept a copy of this library, so a stale workspace cache (the old blue /
-- see-through build) can never be loaded again.
local BUILD = "black-8"

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local GuiService = game:GetService("GuiService")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local viewport = workspace.CurrentCamera.ViewportSize

local CONFIG_FOLDER = "BananaHub/Config/"

-- Config state. Elements is keyed by "Type_Title" and holds every widget that
-- can be written back to, which is what the Config tab saves and restores.
local ConfigData = {}
local Elements = {}
local CURRENT_VERSION = nil

local function CheckFolders()
	local mainFolder = CONFIG_FOLDER:split("/")[1]
	if not isfolder(mainFolder) then makefolder(mainFolder) end
	if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
end

local function SaveConfig(name)
	if not writefile then return false end
	CheckFolders()
	local fileName = CONFIG_FOLDER .. (name or "Default") .. ".json"
	ConfigData._version = CURRENT_VERSION
	writefile(fileName, HttpService:JSONEncode(ConfigData))
	return true
end

local function LoadConfigFromFile(name)
	if not (isfile and readfile) then return false end
	CheckFolders()
	local fileName = CONFIG_FOLDER .. (name or "Default") .. ".json"
	if not isfile(fileName) then return false end

	local success, result = pcall(function()
		return HttpService:JSONDecode(readfile(fileName))
	end)
	if not (success and type(result) == "table") then return false end

	ConfigData = result
	return true
end

-- Loading a config is a user action: the widgets must fire their callbacks or
-- the interface would flip without the feature state following it. Only the
-- initial build is silent.
local function LoadConfigElements()
	for key, element in pairs(Elements) do
		local targetValue = ConfigData[key]
		if element.Set then
			if targetValue ~= nil then
				element:Set(targetValue)
			elseif element.Type == "Toggle" then
				element:Set(false)
			elseif element.Type == "Slider" then
				element:Set(element.Default or 0)
			elseif element.Type == "Dropdown" then
				element:Set(element.Default or "")
			elseif element.Type == "Input" then
				element:Set("")
			end
		end
	end
end

-- Panel surfaces. The window is a black card; rows sit a shade above it so
-- the background picture only shows faintly through them.
local SURFACE = Color3.fromRGB(18, 18, 18)
local SURFACE_SOFT = Color3.fromRGB(30, 30, 30)

-- Tab icons. Only the ones Banana Hub's tabs ask for are kept.
local Icons = {
	fish      = "rbxassetid://97167558235554",
	gem       = "rbxassetid://107005941750079",
	mountain  = "rbxassetid://13132186360",
	mapPin    = "rbxassetid://17824309485",
	sparkles  = "rbxassetid://16833255748",
	webhook   = "rbxassetid://137601480983962",
	settings  = "rbxassetid://70386228443175",
	fileCog   = "rbxassetid://6340513838",
	info      = "rbxassetid://17510196486",
	home      = "rbxassetid://6340513838",
	player    = "rbxassetid://12120698352",
	bag       = "rbxassetid://8601111810",
	shop      = "rbxassetid://4985385964",
	loop      = "rbxassetid://122032243989747",
	compas    = "rbxassetid://125300760963399",
	menu      = "rbxassetid://6340513838",
	crosshair = "rbxassetid://12614416478",
	user      = "rbxassetid://108483430622128",
	stat      = "rbxassetid://12094445329",
	eyes      = "rbxassetid://14321059114",
	sword     = "rbxassetid://82472368671405",
	discord   = "rbxassetid://94434236999817",
	star      = "rbxassetid://107005941750079",
	payment   = "rbxassetid://18747025078",
	alert     = "rbxassetid://73186275216515",
	question  = "rbxassetid://17510196486",
	idea      = "rbxassetid://16833255748",
	water     = "rbxassetid://100076212630732",
	start     = "rbxassetid://108886429866687",
	next      = "rbxassetid://12662718374",
	rod       = "rbxassetid://103247953194129",
}

local function isMobileDevice()
	return UserInputService.TouchEnabled
		and not UserInputService.KeyboardEnabled
		and not UserInputService.MouseEnabled
end

local isMobile = isMobileDevice()

local function safeSize(pxWidth, pxHeight)
	local scaleX = pxWidth / viewport.X
	local scaleY = pxHeight / viewport.Y
	if isMobile then
		if scaleX > 0.5 then scaleX = 0.5 end
		if scaleY > 0.3 then scaleY = 0.3 end
	end
	return UDim2.new(scaleX, 0, scaleY, 0)
end

local function MakeDraggable(topbarobject, object)
	local function CustomPos(bar, frame)
		local Dragging, DragInput, DragStart, StartPosition

		local function UpdatePos(input)
			local Delta = input.Position - DragStart
			local pos = UDim2.new(
				StartPosition.X.Scale,
				StartPosition.X.Offset + Delta.X,
				StartPosition.Y.Scale,
				StartPosition.Y.Offset + Delta.Y
			)
			-- remember where the user parked the window so the open/close
			-- animation reopens it in the same spot
			frame:SetAttribute("BH_RestingX", pos.X.Offset)
			frame:SetAttribute("BH_RestingY", pos.Y.Offset)
			TweenService:Create(frame, TweenInfo.new(0.2), { Position = pos }):Play()
		end

		bar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				Dragging = true
				DragStart = input.Position
				StartPosition = frame.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						Dragging = false
					end
				end)
			end
		end)

		bar.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				DragInput = input
			end
		end)

		UserInputService.InputChanged:Connect(function(input)
			if input == DragInput and Dragging then
				UpdatePos(input)
			end
		end)
	end

	local function CustomSize(frame)
		local Dragging, DragInput, DragStart, StartSize
		local minSizeX, minSizeY = 100, 100
		local defSizeX, defSizeY = 640, 400
		if isMobile then
			defSizeX, defSizeY = 470, 270
		end

		frame.Size = UDim2.new(0, defSizeX, 0, defSizeY)

		-- Grab area: sits over the bottom-right corner of the shadow ring and the
		-- very corner of the panel. The visible lines are drawn inside this box
		-- but outside the panel itself.
		local changesizeobject = Instance.new("Frame")
		changesizeobject.AnchorPoint = Vector2.new(1, 1)
		changesizeobject.BackgroundTransparency = 1
		changesizeobject.Size = UDim2.new(0, 34, 0, 34)
		changesizeobject.Position = UDim2.new(1, 0, 1, 0)
		changesizeobject.ZIndex = 10
		changesizeobject.Name = "changesizeobject"
		changesizeobject.Parent = frame

		-- Resize grip: two short 45-degree lines just OUTSIDE the panel's
		-- bottom-right corner, in the transparent shadow margin around it, so it
		-- reads as "drag me bigger" without stealing space inside the UI.
		-- The panel is inset 23.5px inside the holder, so offsets around 14-21px
		-- from the holder corner hug the panel's corner from just outside it.
		local function GripLine(inset, length)
			local line = Instance.new("Frame")
			line.Name = "ResizeGripLine"
			line.AnchorPoint = Vector2.new(0.5, 0.5)
			line.BackgroundColor3 = Color3.fromRGB(215, 215, 215)
			line.BackgroundTransparency = 0.1
			line.BorderSizePixel = 0
			line.Position = UDim2.new(1, -inset, 1, -inset)
			line.Size = UDim2.new(0, 2, 0, length)
			line.Rotation = 45
			line.ZIndex = 11
			line.Parent = changesizeobject

			local lineCorner = Instance.new("UICorner")
			lineCorner.CornerRadius = UDim.new(1, 0)
			lineCorner.Parent = line
			return line
		end

		GripLine(14, 11)
		GripLine(21, 11)

		local function UpdateSize(input)
			local Delta = input.Position - DragStart
			local newWidth = math.max(StartSize.X.Offset + Delta.X, minSizeX)
			local newHeight = math.max(StartSize.Y.Offset + Delta.Y, minSizeY)
			-- remember the user's size so the open/close animation zooms back
			-- to it instead of the size the script originally requested
			frame:SetAttribute("BH_RestingW", newWidth)
			frame:SetAttribute("BH_RestingH", newHeight)
			TweenService:Create(frame, TweenInfo.new(0.2), { Size = UDim2.new(0, newWidth, 0, newHeight) }):Play()
		end

		changesizeobject.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				Dragging = true
				DragStart = input.Position
				StartSize = frame.Size
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						Dragging = false
					end
				end)
			end
		end)

		changesizeobject.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				DragInput = input
			end
		end)

		UserInputService.InputChanged:Connect(function(input)
			if input == DragInput and Dragging then
				UpdateSize(input)
			end
		end)
	end

	CustomSize(object)
	CustomPos(topbarobject, object)
end

local function CircleClick(Button, X, Y)
	task.spawn(function()
		Button.ClipsDescendants = true
		local Circle = Instance.new("ImageLabel")
		Circle.Image = "rbxassetid://266543268"
		Circle.ImageColor3 = Color3.fromRGB(80, 80, 80)
		Circle.ImageTransparency = 0.9
		Circle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		Circle.BackgroundTransparency = 1
		Circle.ZIndex = 10
		Circle.Name = "Circle"
		Circle.Parent = Button

		local NewX = X - Circle.AbsolutePosition.X
		local NewY = Y - Circle.AbsolutePosition.Y
		Circle.Position = UDim2.new(0, NewX, 0, NewY)

		local Size = math.max(Button.AbsoluteSize.X, Button.AbsoluteSize.Y) * 1.5
		local Time = 0.5
		Circle:TweenSizeAndPosition(
			UDim2.new(0, Size, 0, Size),
			UDim2.new(0.5, -Size / 2, 0.5, -Size / 2),
			"Out", "Quad", Time, false, nil
		)
		for _ = 1, 10 do
			Circle.ImageTransparency = Circle.ImageTransparency + 0.01
			task.wait(Time / 10)
		end
		Circle:Destroy()
	end)
end

local BananaHub = {}
BananaHub.Icons = Icons
BananaHub.ConfigFolder = CONFIG_FOLDER

-- =====================================================================
-- Notifications
-- =====================================================================
function BananaHub:MakeNotify(NotifyConfig)
	NotifyConfig = NotifyConfig or {}
	NotifyConfig.Title = NotifyConfig.Title or "Banana Hub"
	NotifyConfig.Description = NotifyConfig.Description or "Notification"
	NotifyConfig.Content = NotifyConfig.Content or "Content"
	NotifyConfig.Color = NotifyConfig.Color or Color3.fromRGB(255, 255, 255)
	NotifyConfig.Time = NotifyConfig.Time or 0.5
	NotifyConfig.Delay = NotifyConfig.Delay or 5

	local NotifyFunction = {}

	task.spawn(function()
		if not CoreGui:FindFirstChild("NotifyGui") then
			local NotifyGui = Instance.new("ScreenGui")
			NotifyGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			NotifyGui.Name = "NotifyGui"
			NotifyGui.ResetOnSpawn = false
			NotifyGui.Parent = CoreGui
		end

		if not CoreGui.NotifyGui:FindFirstChild("NotifyLayout") then
			local NotifyLayout = Instance.new("Frame")
			NotifyLayout.AnchorPoint = Vector2.new(1, 1)
			NotifyLayout.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			NotifyLayout.BackgroundTransparency = 0.999
			NotifyLayout.BorderSizePixel = 0
			NotifyLayout.Position = UDim2.new(1, -30, 1, -30)
			NotifyLayout.Size = UDim2.new(0, 320, 1, 0)
			NotifyLayout.Name = "NotifyLayout"
			NotifyLayout.Parent = CoreGui.NotifyGui

			CoreGui.NotifyGui.NotifyLayout.ChildRemoved:Connect(function()
				local Count = 0
				for _, v in ipairs(CoreGui.NotifyGui.NotifyLayout:GetChildren()) do
					TweenService:Create(
						v,
						TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
						{ Position = UDim2.new(0, 0, 1, -((v.Size.Y.Offset + 12) * Count)) }
					):Play()
					Count = Count + 1
				end
			end)
		end

		local NotifyPosHeigh = 0
		for _, v in ipairs(CoreGui.NotifyGui.NotifyLayout:GetChildren()) do
			NotifyPosHeigh = -(v.Position.Y.Offset) + v.Size.Y.Offset + 12
		end

		local NotifyFrame = Instance.new("Frame")
		local NotifyFrameReal = Instance.new("Frame")
		local UICorner = Instance.new("UICorner")
		local UIStroke = Instance.new("UIStroke")
		local LeftIcon = Instance.new("ImageLabel")
		local LeftIconCorner = Instance.new("UICorner")
		local ContentFrame = Instance.new("Frame")
		local Top = Instance.new("Frame")
		local TextLabel = Instance.new("TextLabel")
		local TextLabel1 = Instance.new("TextLabel")
		local Close = Instance.new("TextButton")
		local ImageLabel = Instance.new("ImageLabel")
		local TextLabel2 = Instance.new("TextLabel")

		NotifyFrame.BackgroundTransparency = 1
		NotifyFrame.Size = UDim2.new(1, 0, 0, 150)
		NotifyFrame.Name = "NotifyFrame"
		NotifyFrame.Parent = CoreGui.NotifyGui.NotifyLayout
		NotifyFrame.AnchorPoint = Vector2.new(0, 1)
		NotifyFrame.Position = UDim2.new(0, 0, 1, -NotifyPosHeigh)

		NotifyFrameReal.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
		NotifyFrameReal.BorderSizePixel = 0
		NotifyFrameReal.Position = UDim2.new(0, 400, 0, 0)
		NotifyFrameReal.Size = UDim2.new(1, 0, 1, 0)
		NotifyFrameReal.Name = "NotifyFrameReal"
		NotifyFrameReal.Parent = NotifyFrame

		UICorner.Parent = NotifyFrameReal
		UICorner.CornerRadius = UDim.new(0, 10)

		UIStroke.Parent = NotifyFrameReal
		UIStroke.Color = Color3.fromRGB(40, 40, 45)
		UIStroke.Thickness = 1
		UIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

		LeftIcon.Image = NotifyConfig.Image or "rbxassetid://125326185088678"
		LeftIcon.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
		LeftIcon.BackgroundTransparency = 0
		LeftIcon.BorderSizePixel = 0
		LeftIcon.Size = UDim2.new(0, 55, 1, 0)
		LeftIcon.ScaleType = Enum.ScaleType.Fit
		LeftIcon.Parent = NotifyFrameReal

		LeftIconCorner.Parent = LeftIcon
		LeftIconCorner.CornerRadius = UDim.new(0, 10)

		ContentFrame.BackgroundTransparency = 1
		ContentFrame.Position = UDim2.new(0, 55, 0, 0)
		ContentFrame.Size = UDim2.new(1, -55, 1, 0)
		ContentFrame.Name = "ContentFrame"
		ContentFrame.Parent = NotifyFrameReal

		Top.BackgroundTransparency = 1
		Top.Size = UDim2.new(1, 0, 0, 36)
		Top.Name = "Top"
		Top.Parent = ContentFrame

		TextLabel.Font = Enum.Font.GothamBold
		TextLabel.Text = NotifyConfig.Title
		TextLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
		TextLabel.TextSize = 14
		TextLabel.TextXAlignment = Enum.TextXAlignment.Left
		TextLabel.BackgroundTransparency = 1
		TextLabel.Size = UDim2.new(1, -50, 1, 0)
		TextLabel.Position = UDim2.new(0, 10, 0, 0)
		TextLabel.Parent = Top

		TextLabel1.Font = Enum.Font.GothamMedium
		TextLabel1.Text = NotifyConfig.Description
		TextLabel1.TextColor3 = NotifyConfig.Color
		TextLabel1.TextSize = 13
		TextLabel1.TextXAlignment = Enum.TextXAlignment.Left
		TextLabel1.BackgroundTransparency = 1
		TextLabel1.Size = UDim2.new(1, 0, 1, 0)
		TextLabel1.Position = UDim2.new(0, TextLabel.TextBounds.X + 15, 0, 0)
		TextLabel1.Parent = Top

		Close.Text = ""
		Close.AnchorPoint = Vector2.new(1, 0.5)
		Close.BackgroundTransparency = 1
		Close.Position = UDim2.new(1, -8, 0.5, 0)
		Close.Size = UDim2.new(0, 24, 0, 24)
		Close.Name = "Close"
		Close.Parent = Top

		ImageLabel.Image = "rbxassetid://9886659671"
		ImageLabel.ImageColor3 = Color3.fromRGB(160, 160, 165)
		ImageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		ImageLabel.BackgroundTransparency = 1
		ImageLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
		ImageLabel.Size = UDim2.new(0.7, 0, 0.7, 0)
		ImageLabel.Parent = Close

		TextLabel2.Font = Enum.Font.Gotham
		TextLabel2.TextColor3 = Color3.fromRGB(160, 160, 165)
		TextLabel2.TextSize = 13
		TextLabel2.Text = NotifyConfig.Content
		TextLabel2.TextXAlignment = Enum.TextXAlignment.Left
		TextLabel2.TextYAlignment = Enum.TextYAlignment.Top
		TextLabel2.BackgroundTransparency = 1
		TextLabel2.Position = UDim2.new(0, 10, 0, 30)
		TextLabel2.Parent = ContentFrame
		TextLabel2.Size = UDim2.new(1, -20, 0, 13)
		TextLabel2.TextWrapped = true
		TextLabel2.Size = UDim2.new(1, -20, 0, 13 + (13 * (TextLabel2.TextBounds.X // math.max(TextLabel2.AbsoluteSize.X, 1))))

		if TextLabel2.AbsoluteSize.Y < 27 then
			NotifyFrame.Size = UDim2.new(1, 0, 0, 70)
		else
			NotifyFrame.Size = UDim2.new(1, 0, 0, TextLabel2.AbsoluteSize.Y + 43)
		end

		local closed = false
		function NotifyFunction:Close()
			if closed then return false end
			closed = true
			TweenService:Create(
				NotifyFrameReal,
				TweenInfo.new(tonumber(NotifyConfig.Time), Enum.EasingStyle.Quint, Enum.EasingDirection.In),
				{ Position = UDim2.new(0, 400, 0, 0) }
			):Play()
			task.wait(tonumber(NotifyConfig.Time) / 1.2)
			NotifyFrame:Destroy()
		end

		Close.Activated:Connect(function()
			NotifyFunction:Close()
		end)

		TweenService:Create(
			NotifyFrameReal,
			TweenInfo.new(tonumber(NotifyConfig.Time), Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0, 0, 0, 0) }
		):Play()

		task.wait(tonumber(NotifyConfig.Delay))
		NotifyFunction:Close()
	end)

	return NotifyFunction
end

local function BananaNotify(msg, delay, color, title, desc)
	return BananaHub:MakeNotify({
		Title = title or "Banana Hub",
		Description = desc or "Notification",
		Content = msg or "Content",
		Color = color or Color3.fromRGB(255, 255, 255),
		Delay = delay or 4,
	})
end
BananaHub.NotifyRaw = BananaNotify

-- =====================================================================
-- Window
-- =====================================================================
function BananaHub:Window(GuiConfig)
	GuiConfig = GuiConfig or {}
	GuiConfig.Title = GuiConfig.Title or "Banana Hub"
	GuiConfig.Footer = GuiConfig.Footer or GuiConfig.Author or "Banana Hub"
	GuiConfig.Color = GuiConfig.Color or Color3.fromRGB(255, 255, 255)
	GuiConfig["Tab Width"] = GuiConfig["Tab Width"] or 120
	GuiConfig.Version = GuiConfig.Version or 1
	GuiConfig.Icon = GuiConfig.Icon or "rbxassetid://125326185088678"
	GuiConfig.Image = GuiConfig.Image or GuiConfig.Icon

	CURRENT_VERSION = GuiConfig.Version

	-- Locked-feature panel. A free-script widget keeps its normal row on top and
	-- gets a card underneath with a padlock and "Buy Premium to unlock this
	-- feature". Everything is drawn from frames + gradients, so it needs no
	-- asset ids and scales cleanly at any size.
	local LOCK_TEXT = "Buy Premium to unlock this feature"

	-- Premium accent used by the lock art (warm gold reads as "paid" against
	-- the black panel and cannot be confused with the white UI accent).
	local GOLD = Color3.fromRGB(255, 196, 61)
	local GOLD_DIM = Color3.fromRGB(196, 142, 30)
	local LOCK_BG = Color3.fromRGB(14, 13, 11)

	-- Draws a padlock: a gold shackle behind a gradient body, with a keyhole
	-- punched into it and a soft glow. `size` is the body width in px.
	-- `hole` is the colour the shackle opening and keyhole are cut to (the
	-- surface the lock sits on), so it reads as a real cut-out.
	local function MakePadlock(parent, size, zIndex, hole)
		hole = hole or LOCK_BG

		local Icon = Instance.new("Frame")
		Icon.Name = "LockIcon"
		Icon.AnchorPoint = Vector2.new(0.5, 0)
		Icon.BackgroundTransparency = 1
		Icon.Size = UDim2.new(0, size, 0, math.floor(size * 1.3))
		Icon.ZIndex = zIndex
		Icon.Parent = parent

		-- Soft halo behind the lock so it lifts off the black card.
		local Glow = Instance.new("ImageLabel")
		Glow.Name = "Glow"
		Glow.AnchorPoint = Vector2.new(0.5, 0.5)
		Glow.BackgroundTransparency = 1
		Glow.Image = "rbxassetid://5028857084"
		Glow.ImageColor3 = GOLD
		Glow.ImageTransparency = 0.8
		Glow.Position = UDim2.new(0.5, 0, 0.55, 0)
		Glow.Size = UDim2.new(0, math.floor(size * 2.6), 0, math.floor(size * 2.6))
		Glow.ZIndex = zIndex - 1
		Glow.Parent = Icon

		-- Shackle: a solid gold arch with the middle cut out. Drawn from two
		-- frames rather than a UIStroke on a transparent frame, which renders
		-- inconsistently across devices.
		local shackleW = math.max(6, math.floor(size * 0.68))
		local shackleH = math.max(6, math.floor(size * 0.72))
		local thick = math.max(2, math.floor(size * 0.14))

		local Shackle = Instance.new("Frame")
		Shackle.Name = "Shackle"
		Shackle.AnchorPoint = Vector2.new(0.5, 0)
		Shackle.BackgroundColor3 = GOLD
		Shackle.BorderSizePixel = 0
		Shackle.Position = UDim2.new(0.5, 0, 0, 0)
		Shackle.Size = UDim2.new(0, shackleW, 0, shackleH)
		Shackle.ZIndex = zIndex
		Shackle.Parent = Icon

		local ShackleCorner = Instance.new("UICorner")
		ShackleCorner.CornerRadius = UDim.new(0, math.floor(shackleW / 2))
		ShackleCorner.Parent = Shackle

		local ShackleGradient = Instance.new("UIGradient")
		ShackleGradient.Rotation = 90
		ShackleGradient.Color = ColorSequence.new(GOLD, GOLD_DIM)
		ShackleGradient.Parent = Shackle

		local ShackleHole = Instance.new("Frame")
		ShackleHole.Name = "ShackleHole"
		ShackleHole.AnchorPoint = Vector2.new(0.5, 0)
		ShackleHole.BackgroundColor3 = hole
		ShackleHole.BorderSizePixel = 0
		ShackleHole.Position = UDim2.new(0.5, 0, 0, thick)
		ShackleHole.Size = UDim2.new(0, shackleW - thick * 2, 0, shackleH - thick)
		ShackleHole.ZIndex = zIndex + 1
		ShackleHole.Parent = Shackle

		local HoleCorner = Instance.new("UICorner")
		HoleCorner.CornerRadius = UDim.new(0, math.floor((shackleW - thick * 2) / 2))
		HoleCorner.Parent = ShackleHole

		-- Body
		local Body = Instance.new("Frame")
		Body.Name = "LockBody"
		Body.AnchorPoint = Vector2.new(0.5, 1)
		Body.BackgroundColor3 = GOLD
		Body.BorderSizePixel = 0
		Body.Position = UDim2.new(0.5, 0, 1, 0)
		Body.Size = UDim2.new(0, size, 0, math.floor(size * 0.7))
		Body.ZIndex = zIndex + 2
		Body.Parent = Icon

		local BodyCorner = Instance.new("UICorner")
		BodyCorner.CornerRadius = UDim.new(0, math.max(2, math.floor(size * 0.2)))
		BodyCorner.Parent = Body

		local BodyGradient = Instance.new("UIGradient")
		BodyGradient.Rotation = 90
		BodyGradient.Color = ColorSequence.new(GOLD, GOLD_DIM)
		BodyGradient.Parent = Body

		local BodyStroke = Instance.new("UIStroke")
		BodyStroke.Color = Color3.fromRGB(255, 232, 168)
		BodyStroke.Thickness = 1
		BodyStroke.Transparency = 0.55
		BodyStroke.Parent = Body

		-- Keyhole: circle + stem, punched through to the surface colour.
		local Keyhole = Instance.new("Frame")
		Keyhole.Name = "Keyhole"
		Keyhole.AnchorPoint = Vector2.new(0.5, 0)
		Keyhole.BackgroundColor3 = hole
		Keyhole.BorderSizePixel = 0
		Keyhole.Position = UDim2.new(0.5, 0, 0, math.floor(size * 0.16))
		Keyhole.Size = UDim2.new(0, math.max(2, math.floor(size * 0.2)), 0, math.max(2, math.floor(size * 0.2)))
		Keyhole.ZIndex = zIndex + 3
		Keyhole.Parent = Body

		local KeyholeCorner = Instance.new("UICorner")
		KeyholeCorner.CornerRadius = UDim.new(1, 0)
		KeyholeCorner.Parent = Keyhole

		local Stem = Instance.new("Frame")
		Stem.Name = "Stem"
		Stem.AnchorPoint = Vector2.new(0.5, 0)
		Stem.BackgroundColor3 = hole
		Stem.BorderSizePixel = 0
		Stem.Position = UDim2.new(0.5, 0, 0, math.floor(size * 0.3))
		Stem.Size = UDim2.new(0, math.max(1, math.floor(size * 0.09)), 0, math.floor(size * 0.24))
		Stem.ZIndex = zIndex + 3
		Stem.Parent = Body

		local StemCorner = Instance.new("UICorner")
		StemCorner.CornerRadius = UDim.new(1, 0)
		StemCorner.Parent = Stem

		return Icon
	end

	-- One small padlock in the section header, so a locked section is obvious
	-- from the tab list.
	local function AddSectionLockHeader(sectionAdd)
		if not sectionAdd then return end
		local section = sectionAdd.Parent
		if section and section.Name == "Section" and not section:GetAttribute("BH_Locked") then
			section:SetAttribute("BH_Locked", true)
			local real = section:FindFirstChild("SectionReal")
			if real then
				local head = MakePadlock(real, 9, 6, SURFACE)
				head.AnchorPoint = Vector2.new(1, 0.5)
				head.Position = UDim2.new(1, -32, 0.5, 0)
			end
		end
	end

	-- Every locked widget renders as this one row: padlock, feature name, and
	-- the "Buy Premium" line. The normal control (switch, slider, button, select
	-- box) is hidden rather than drawn dimmed, because a dead control invites
	-- clicks and reads as a bug.
	local function RenderLockedRow(row, titleLabel, titleText, sectionAdd)
		row.Size = UDim2.new(1, 0, 0, 46)

		-- Give the row the normal surface so every locked row looks the same,
		-- whatever widget it came from (a Button keeps its surface on an inner
		-- frame that is about to be hidden).
		row.BackgroundColor3 = SURFACE
		row.BackgroundTransparency = 0.2
		row.BorderSizePixel = 0
		if not row:FindFirstChildOfClass("UICorner") then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 4)
			corner.Parent = row
		end

		for _, child in ipairs(row:GetChildren()) do
			if child ~= titleLabel and child:IsA("GuiObject") then
				child.Visible = false
				child.Active = false
			end
		end

		-- Some widgets nest their title inside the control they draw (the Button
		-- puts its label inside the button frame), so pull it up to the row or it
		-- would be hidden along with its parent.
		if titleLabel.Parent ~= row then
			titleLabel.Parent = row
		end
		titleLabel.Visible = true
		titleLabel.Text = titleText
		titleLabel.Position = UDim2.new(0, 34, 0, 9)
		titleLabel.Size = UDim2.new(1, -44, 0, 13)
		titleLabel.TextColor3 = Color3.fromRGB(255, 226, 160)
		titleLabel.ZIndex = 2

		local lock = MakePadlock(row, 11, 6, SURFACE)
		lock.AnchorPoint = Vector2.new(0, 0.5)
		lock.Position = UDim2.new(0, 9, 0.5, 0)

		local Sub = Instance.new("TextLabel")
		Sub.Name = "LockSub"
		Sub.Font = Enum.Font.Gotham
		Sub.Text = LOCK_TEXT
		Sub.TextColor3 = Color3.fromRGB(150, 142, 126)
		Sub.TextSize = 10
		Sub.TextXAlignment = Enum.TextXAlignment.Left
		Sub.TextTruncate = Enum.TextTruncate.AtEnd
		Sub.BackgroundTransparency = 1
		Sub.Position = UDim2.new(0, 34, 0, 27)
		Sub.Size = UDim2.new(1, -44, 0, 12)
		Sub.ZIndex = 2
		Sub.Parent = row

		AddSectionLockHeader(sectionAdd)
	end

	local GuiFunc = {}

	local BananaHubGui = Instance.new("ScreenGui")
	local DropShadowHolder = Instance.new("Frame")
	local DropShadow = Instance.new("ImageLabel")
	local Main = Instance.new("Frame")
	local UICorner = Instance.new("UICorner")
	local Top = Instance.new("Frame")
	local TextLabel = Instance.new("TextLabel")
	local TextLabel1 = Instance.new("TextLabel")
	local TitleIcon = Instance.new("ImageLabel")
	local Close = Instance.new("TextButton")
	local ImageLabel1 = Instance.new("ImageLabel")
	local Min = Instance.new("TextButton")
	local ImageLabel2 = Instance.new("ImageLabel")
	local LayersTab = Instance.new("Frame")
	local UICorner2 = Instance.new("UICorner")
	local DecideFrame = Instance.new("Frame")
	local Layers = Instance.new("Frame")
	local UICorner6 = Instance.new("UICorner")
	local NameTab = Instance.new("TextLabel")
	local LayersReal = Instance.new("Frame")
	local LayersFolder = Instance.new("Folder")
	local LayersPageLayout = Instance.new("UIPageLayout")
	local MainStroke = Instance.new("UIStroke")

	BananaHubGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	BananaHubGui.Name = "BananaHub"
	BananaHubGui.ResetOnSpawn = false
	local okParent = pcall(function() BananaHubGui.Parent = CoreGui end)
	if not okParent then
		pcall(function() BananaHubGui.Parent = LocalPlayer:WaitForChild("PlayerGui", 10) end)
	end

	DropShadowHolder.BackgroundTransparency = 1
	DropShadowHolder.BorderSizePixel = 0
	DropShadowHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	DropShadowHolder.Position = UDim2.new(0.5, 0, 0.5, 0)
	DropShadowHolder.Size = isMobile and safeSize(470, 270) or safeSize(640, 400)
	DropShadowHolder.ZIndex = 0
	DropShadowHolder.Name = "DropShadowHolder"
	DropShadowHolder.Parent = BananaHubGui

	DropShadow.Image = "rbxassetid://6015897843"
	DropShadow.ImageColor3 = Color3.fromRGB(15, 15, 15)
	DropShadow.ImageTransparency = 1
	DropShadow.ScaleType = Enum.ScaleType.Slice
	DropShadow.SliceCenter = Rect.new(49, 49, 450, 450)
	DropShadow.AnchorPoint = Vector2.new(0.5, 0.5)
	DropShadow.BackgroundTransparency = 1
	DropShadow.BorderSizePixel = 0
	DropShadow.Position = UDim2.new(0.5, 0, 0.5, 0)
	DropShadow.Size = UDim2.new(1, 47, 1, 47)
	DropShadow.ZIndex = 0
	DropShadow.Name = "DropShadow"
	DropShadow.Parent = DropShadowHolder

	-- A numeric Theme is an image asset id (the original convention). Soreya
	-- passes a palette name ("Dark"), which is not an asset, so fall through to
	-- the solid dark panel instead of loading a broken image.
	--
	-- Background = picture for the panel. Roblox only draws rbxassetid images,
	-- so an http(s) URL is fetched and turned into a custom asset first.
	local themeAsset = GuiConfig.Theme
	if type(themeAsset) == "number" then themeAsset = tostring(themeAsset) end

	local panelImage
	local background = GuiConfig.Background
	if type(background) == "string" and background ~= "" then
		if background:match("^https?://") then
			-- Executors that expose getcustomasset can turn the downloaded file
			-- into something Roblox will actually draw. Without it, hand the URL
			-- to the ImageLabel anyway: patched executors render it, stock ones
			-- just show the black panel.
			panelImage = background
			if writefile and getcustomasset then
				local ext = background:match("%.(%a+)%s*$") or "png"
				local path = "BananaHubBg." .. ext
				local fetched, data = pcall(function() return game:HttpGet(background, true) end)
				if fetched and type(data) == "string" and #data > 0 then
					if pcall(writefile, path, data) then
						local okAsset, asset = pcall(getcustomasset, path)
						if okAsset and type(asset) == "string" then panelImage = asset end
					end
				end
			end
		else
			panelImage = background
		end
	end

	if panelImage then
		Main:Destroy()
		Main = Instance.new("ImageLabel")
		Main.Image = panelImage
		Main.ScaleType = Enum.ScaleType.Crop
		Main.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		Main.BackgroundTransparency = 0
		Main.ImageTransparency = tonumber(GuiConfig.BackgroundTransparency) or 0.25
	elseif type(themeAsset) == "string" and themeAsset:match("^%d+$") then
		Main:Destroy()
		Main = Instance.new("ImageLabel")
		Main.Image = "rbxassetid://" .. themeAsset
		Main.ScaleType = Enum.ScaleType.Crop
		Main.BackgroundTransparency = 1
		Main.ImageTransparency = GuiConfig.ThemeTransparency or 0.15
	else
		Main.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		Main.BackgroundTransparency = 0
	end

	Main.AnchorPoint = Vector2.new(0.5, 0.5)
	Main.BorderSizePixel = 0
	Main.Position = UDim2.new(0.5, 0, 0.5, 0)
	Main.Size = UDim2.new(1, -47, 1, -47)
	Main.Name = "Main"
	Main.Parent = DropShadow

	MainStroke.Thickness = 1.2
	MainStroke.Color = GuiConfig.Color
	MainStroke.Transparency = 0.6
	MainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	MainStroke.Parent = Main

	UICorner.Parent = Main

	Top.BackgroundTransparency = 0.999
	Top.Size = UDim2.new(1, 0, 0, 38)
	Top.Name = "Top"
	Top.Parent = Main

	TitleIcon.Name = "TitleIcon"
	TitleIcon.Parent = Top
	TitleIcon.BackgroundTransparency = 1
	TitleIcon.BorderSizePixel = 0
	TitleIcon.AnchorPoint = Vector2.new(0, 0.5)
	TitleIcon.Position = UDim2.new(0, 10, 0.5, 0)
	TitleIcon.Size = UDim2.new(0, 20, 0, 20)
	TitleIcon.Image = GuiConfig.Icon

	TextLabel.Font = Enum.Font.GothamBold
	TextLabel.Text = GuiConfig.Title
	TextLabel.TextColor3 = GuiConfig.Color
	TextLabel.TextSize = 14
	TextLabel.TextXAlignment = Enum.TextXAlignment.Left
	TextLabel.BackgroundTransparency = 0.999
	TextLabel.Size = UDim2.new(1, -135, 1, 0)
	TextLabel.Position = UDim2.new(0, 35, 0, 0)
	TextLabel.Parent = Top

	TextLabel1.Font = Enum.Font.GothamBold
	TextLabel1.Text = GuiConfig.Footer
	TextLabel1.TextColor3 = GuiConfig.Color
	TextLabel1.TextSize = 14
	TextLabel1.BackgroundTransparency = 0.999
	TextLabel1.TextXAlignment = Enum.TextXAlignment.Right
	TextLabel1.Size = UDim2.new(0, 240, 1, 0)
	TextLabel1.Position = UDim2.new(1, -310, 0, 0)
	TextLabel1.Parent = Top

	Close.Font = Enum.Font.SourceSans
	Close.Text = ""
	Close.AnchorPoint = Vector2.new(1, 0.5)
	Close.BackgroundTransparency = 0.999
	Close.Position = UDim2.new(1, -8, 0.5, 0)
	Close.Size = UDim2.new(0, 25, 0, 25)
	Close.Name = "Close"
	Close.Parent = Top

	ImageLabel1.Image = "rbxassetid://9886659671"
	ImageLabel1.AnchorPoint = Vector2.new(0.5, 0.5)
	ImageLabel1.BackgroundTransparency = 0.999
	ImageLabel1.Position = UDim2.new(0.49, 0, 0.5, 0)
	ImageLabel1.Size = UDim2.new(1, -8, 1, -8)
	ImageLabel1.Parent = Close

	Min.Font = Enum.Font.SourceSans
	Min.Text = ""
	Min.AnchorPoint = Vector2.new(1, 0.5)
	Min.BackgroundTransparency = 0.999
	Min.Position = UDim2.new(1, -38, 0.5, 0)
	Min.Size = UDim2.new(0, 25, 0, 25)
	Min.Name = "Min"
	Min.Parent = Top

	ImageLabel2.Image = "rbxassetid://9886659276"
	ImageLabel2.AnchorPoint = Vector2.new(0.5, 0.5)
	ImageLabel2.BackgroundTransparency = 0.999
	ImageLabel2.ImageTransparency = 0.2
	ImageLabel2.Position = UDim2.new(0.5, 0, 0.5, 0)
	ImageLabel2.Size = UDim2.new(1, -9, 1, -9)
	ImageLabel2.Parent = Min

	LayersTab.BackgroundTransparency = 0.999
	LayersTab.Position = UDim2.new(0, 9, 0, 50)
	LayersTab.Size = UDim2.new(0, GuiConfig["Tab Width"], 1, -59)
	LayersTab.Name = "LayersTab"
	LayersTab.Parent = Main

	UICorner2.CornerRadius = UDim.new(0, 2)
	UICorner2.Parent = LayersTab

	DecideFrame.AnchorPoint = Vector2.new(0.5, 0)
	DecideFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	DecideFrame.BackgroundTransparency = 0.85
	DecideFrame.BorderSizePixel = 0
	DecideFrame.Position = UDim2.new(0.5, 0, 0, 38)
	DecideFrame.Size = UDim2.new(1, 0, 0, 1)
	DecideFrame.Name = "DecideFrame"
	DecideFrame.Parent = Main

	Layers.BackgroundTransparency = 0.999
	Layers.Position = UDim2.new(0, GuiConfig["Tab Width"] + 18, 0, 50)
	Layers.Size = UDim2.new(1, -(GuiConfig["Tab Width"] + 9 + 18), 1, -59)
	Layers.Name = "Layers"
	Layers.Parent = Main

	UICorner6.CornerRadius = UDim.new(0, 2)
	UICorner6.Parent = Layers

	NameTab.Font = Enum.Font.GothamBold
	NameTab.Text = ""
	NameTab.TextColor3 = Color3.fromRGB(255, 255, 255)
	NameTab.TextSize = 24
	NameTab.TextWrapped = true
	NameTab.TextXAlignment = Enum.TextXAlignment.Left
	NameTab.BackgroundTransparency = 0.999
	NameTab.Size = UDim2.new(1, 0, 0, 30)
	NameTab.Name = "NameTab"
	NameTab.Parent = Layers

	LayersReal.AnchorPoint = Vector2.new(0, 1)
	LayersReal.BackgroundTransparency = 0.999
	LayersReal.ClipsDescendants = true
	LayersReal.Position = UDim2.new(0, 0, 1, 0)
	LayersReal.Size = UDim2.new(1, 0, 1, -33)
	LayersReal.Name = "LayersReal"
	LayersReal.Parent = Layers

	LayersFolder.Name = "LayersFolder"
	LayersFolder.Parent = LayersReal

	LayersPageLayout.SortOrder = Enum.SortOrder.LayoutOrder
	LayersPageLayout.Name = "LayersPageLayout"
	LayersPageLayout.Parent = LayersFolder
	LayersPageLayout.TweenTime = 0.5
	LayersPageLayout.EasingDirection = Enum.EasingDirection.InOut
	LayersPageLayout.EasingStyle = Enum.EasingStyle.Quad

	local PlayerFooter = Instance.new("Frame")
	PlayerFooter.Name = "PlayerFooter"
	PlayerFooter.AnchorPoint = Vector2.new(0, 1)
	PlayerFooter.BackgroundTransparency = 1
	PlayerFooter.Position = UDim2.new(0, 3, 1, -3)
	PlayerFooter.Size = UDim2.new(1, -18, 0, 40)
	PlayerFooter.Parent = LayersTab
	PlayerFooter.ZIndex = 100

	local PlayerAvatar = Instance.new("ImageLabel")
	PlayerAvatar.Name = "PlayerAvatar"
	PlayerAvatar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	PlayerAvatar.BackgroundTransparency = 0.2
	PlayerAvatar.BorderSizePixel = 0
	PlayerAvatar.AnchorPoint = Vector2.new(0, 0.5)
	PlayerAvatar.Position = UDim2.new(0, 0, 0.5, 2)
	PlayerAvatar.Size = UDim2.new(0, 26, 0, 26)
	PlayerAvatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. LocalPlayer.UserId .. "&w=150&h=150"
	PlayerAvatar.Parent = PlayerFooter

	local AvatarCorner = Instance.new("UICorner")
	AvatarCorner.CornerRadius = UDim.new(1, 0)
	AvatarCorner.Parent = PlayerAvatar

	local AvatarStroke = Instance.new("UIStroke")
	AvatarStroke.Color = GuiConfig.Color
	AvatarStroke.Thickness = 1.2
	AvatarStroke.Transparency = 0.5
	AvatarStroke.Parent = PlayerAvatar

	local PlayerName = Instance.new("TextLabel")
	PlayerName.Name = "PlayerName"
	PlayerName.Font = Enum.Font.GothamBold
	PlayerName.Text = LocalPlayer.DisplayName
	PlayerName.TextColor3 = Color3.fromRGB(180, 180, 180)
	PlayerName.TextSize = 11
	PlayerName.TextXAlignment = Enum.TextXAlignment.Left
	PlayerName.BackgroundTransparency = 1
	PlayerName.Position = UDim2.new(0, 38, 0, 0)
	PlayerName.Size = UDim2.new(1, -38, 1, 0)
	PlayerName.TextTruncate = Enum.TextTruncate.AtEnd
	PlayerName.Parent = PlayerFooter

	local ScrollTab = Instance.new("ScrollingFrame")
	local UIListLayout = Instance.new("UIListLayout")

	ScrollTab.CanvasSize = UDim2.new(0, 0, 1.1, 0)
	ScrollTab.ScrollBarImageColor3 = Color3.fromRGB(0, 0, 0)
	ScrollTab.ScrollBarThickness = 0
	ScrollTab.Active = true
	ScrollTab.BackgroundTransparency = 0.999
	ScrollTab.Size = UDim2.new(1, 0, 1, -50)
	ScrollTab.Name = "ScrollTab"
	ScrollTab.Parent = LayersTab

	UIListLayout.Padding = UDim.new(0, 2)
	UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	UIListLayout.Parent = ScrollTab

	local function UpdateSize1()
		local OffsetY = 0
		for _, child in ipairs(ScrollTab:GetChildren()) do
			if child.Name ~= "UIListLayout" then
				OffsetY = OffsetY + 3 + child.Size.Y.Offset
			end
		end
		ScrollTab.CanvasSize = UDim2.new(0, 0, 0, OffsetY)
	end
	ScrollTab.ChildAdded:Connect(UpdateSize1)
	ScrollTab.ChildRemoved:Connect(UpdateSize1)

	function GuiFunc:DestroyGui()
		pcall(function() GuiFunc.CloseDropdowns() end)
		pcall(function() BananaHubGui:Destroy() end)
		local toggle = CoreGui:FindFirstChild("ToggleUIButton")
		if toggle then pcall(function() toggle:Destroy() end) end
	end

	-- Smooth open/close. The window zooms in/out with a Quart ease instead of
	-- popping in and out; it stays interactable the whole time and a close can
	-- interrupt an in-progress open (and vice versa).
	local BASE_POS = UDim2.new(0.5, 0, 0.5, 0)
	local BASE_SIZE = nil   -- captured after the requested size is applied
	local SizeTween = nil

	local function CancelSizeTween()
		if SizeTween then
			pcall(function() SizeTween:Cancel() end)
			SizeTween = nil
		end
	end

	local function RestingSize()
		if not DropShadowHolder then return nil end
		local w = DropShadowHolder:GetAttribute("BH_RestingW")
		local h = DropShadowHolder:GetAttribute("BH_RestingH")
		if typeof(w) == "number" and typeof(h) == "number" and w > 0 and h > 0 then
			return UDim2.new(0, w, 0, h)
		end
		return BASE_SIZE or DropShadowHolder.Size
	end

	-- The spot the user dragged the window to (falls back to dead centre).
	local function RestingPos()
		if not DropShadowHolder then return BASE_POS end
		local x = DropShadowHolder:GetAttribute("BH_RestingX")
		local y = DropShadowHolder:GetAttribute("BH_RestingY")
		if typeof(x) == "number" and typeof(y) == "number" then
			return UDim2.new(0.5, x, 0.5, y)
		end
		return BASE_POS
	end

	local function PlayOpen()
		if not DropShadowHolder then return end
		CancelSizeTween()
		local target = RestingSize()
		DropShadowHolder.Visible = true
		DropShadowHolder.AnchorPoint = Vector2.new(0.5, 0.5)
		DropShadowHolder.Position = RestingPos()
		DropShadowHolder.Size = UDim2.new(
			0, math.floor(target.X.Offset * 0.9),
			0, math.floor(target.Y.Offset * 0.9))
		SizeTween = TweenService:Create(
			DropShadowHolder,
			TweenInfo.new(0.26, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Size = target })
		SizeTween:Play()
	end

	local function PlayClose()
		if not DropShadowHolder then return end
		-- A floating list belongs to a row inside the window; it must not be
		-- left hanging on screen while the window is shut.
		pcall(function() GuiFunc.CloseDropdowns() end)
		CancelSizeTween()
		local target = RestingSize()
		SizeTween = TweenService:Create(
			DropShadowHolder,
			TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{ Size = UDim2.new(
				0, math.floor(target.X.Offset * 0.9),
				0, math.floor(target.Y.Offset * 0.9)) })
		SizeTween:Play()
		local thisTween = SizeTween
		SizeTween.Completed:Connect(function()
			if SizeTween ~= thisTween then return end   -- superseded by a new tween
			if not DropShadowHolder then return end
			DropShadowHolder.Visible = false
			DropShadowHolder.Size = target
		end)
	end

	Min.Activated:Connect(function()
		CircleClick(Min, Mouse.X, Mouse.Y)
		PlayClose()
	end)

	Close.Activated:Connect(function()
		CircleClick(Close, Mouse.X, Mouse.Y)
		GuiFunc:DestroyGui()
	end)

	local ToggleKey = Enum.KeyCode.Insert
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == ToggleKey and DropShadowHolder then
			if DropShadowHolder.Visible then PlayClose() else PlayOpen() end
		end
	end)

	function GuiFunc:SetVisible(v)
		if v == false then PlayClose() else PlayOpen() end
	end

	function GuiFunc:Toggle()
		if DropShadowHolder.Visible then PlayClose() else PlayOpen() end
	end

	function GuiFunc:SetPanelBackground() end
	function GuiFunc:SetAccent(colour)
		if typeof(colour) ~= "Color3" then return end
		GuiConfig.Color = colour
		pcall(function() MainStroke.Color = colour end)
		pcall(function() AvatarStroke.Color = colour end)
		pcall(function() TextLabel.TextColor3 = colour end)
		pcall(function() TextLabel1.TextColor3 = colour end)
	end

	MakeDraggable(Top, DropShadowHolder)

	-- MakeDraggable installs the resize handle and a default 640x400. Honour
	-- the size the script asked for when it passed one.
	local requested = GuiConfig.Size
	if typeof(requested) == "UDim2" and (requested.X.Offset > 0 or requested.Y.Offset > 0) then
		DropShadowHolder.Size = UDim2.new(0, math.max(requested.X.Offset, 420), 0, math.max(requested.Y.Offset, 300))
	end
	BASE_SIZE = DropShadowHolder.Size
	-- Animate in on first launch too, so the window never pops into place.
	task.defer(PlayOpen)

	GuiFunc.__gui = BananaHubGui
	GuiFunc.__nameTab = NameTab
	GuiFunc.__pageLayout = LayersPageLayout
	GuiFunc.__window = GuiConfig
	GuiFunc.__main = Main

	-- Only one dropdown list stays open at a time. Each entry is
	-- { Header = row, List = floating list, Close = fn }.
	local OpenDropdowns = {}

	local function closeAllDropdowns()
		-- Snapshot first: a list's Close also unregisters itself.
		local open = OpenDropdowns
		OpenDropdowns = {}
		for _, entry in ipairs(open) do
			if type(entry) == "table" and entry.Close then pcall(entry.Close) end
		end
	end
	GuiFunc.CloseDropdowns = closeAllDropdowns

	-- Floating layer for open dropdown lists. With ZIndexBehavior.Sibling a
	-- child of Main is always drawn above Main's other children, so a list that
	-- lives here escapes its row, its section and the scrolling frame instead of
	-- being clipped or painted over by later widgets.
	local OverlayLayer = Instance.new("Frame")
	OverlayLayer.Name = "OverlayLayer"
	OverlayLayer.BackgroundTransparency = 1
	OverlayLayer.BorderSizePixel = 0
	OverlayLayer.Size = UDim2.new(1, 0, 1, 0)
	OverlayLayer.Active = false
	OverlayLayer.ZIndex = 500
	OverlayLayer.Parent = Main

	-- Close an open list when the player clicks anywhere that is not that
	-- list's own header or its options. This is done by hit-testing instead of
	-- with an invisible full-panel button: a catcher would swallow the click
	-- meant for another dropdown's header, and it could not be layered under the
	-- page anyway (ZIndexBehavior.Sibling always draws a child above its
	-- parent's siblings, so anything covering the page also covers every
	-- dropdown header).
	local function pointInside(gui, x, y)
		if not gui or not gui.Visible then return false end
		local p, s = gui.AbsolutePosition, gui.AbsoluteSize
		return x >= p.X and x <= p.X + s.X
			and y >= p.Y and y <= p.Y + s.Y
	end

	UserInputService.InputBegan:Connect(function(input)
		if #OpenDropdowns == 0 then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end

		-- GetMouseLocation is inset-adjusted, which is the same space
		-- GuiObject.AbsolutePosition uses. A touch reports raw screen pixels,
		-- so the top-bar inset is subtracted to match.
		local points = {}
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			points[1] = UserInputService:GetMouseLocation()
		else
			local inset = GuiService:GetGuiInset()
			points[1] = Vector2.new(input.Position.X, input.Position.Y - inset.Y)
			points[2] = Vector2.new(input.Position.X, input.Position.Y)
		end

		for _, entry in ipairs(OpenDropdowns) do
			if type(entry) == "table" then
				for _, p in ipairs(points) do
					if pointInside(entry.Header, p.X, p.Y) or pointInside(entry.List, p.X, p.Y) then
						return
					end
				end
			end
		end
		closeAllDropdowns()
	end)

	-- ---------------------------------------------------------------
	-- Icon lookup
	--
	-- Soreya asks for Lucide names ("map-pin", "file-cog"); those are mapped
	-- to the asset ids above. A raw "rbxassetid://" string passes through.
	-- ---------------------------------------------------------------
	local ICON_ALIAS = {
		["map-pin"] = "mapPin",
		["file-cog"] = "fileCog",
		["refresh-cw"] = "loop",
		["folder-open"] = "fileCog",
		["hand-coins"] = "payment",
		["triangle-alert"] = "alert",
		["power"] = "next",
		["save"] = "fileCog",
		["link"] = "web",
		["lock"] = "settings",
		["bell"] = "alert",
		["clock"] = "stat",
		["wifi"] = "stat",
	}

	local function resolveIcon(icon)
		if type(icon) ~= "string" or icon == "" then return nil end
		if icon:find("rbxassetid://") or icon:find("rbxthumb://") then return icon end
		local key = ICON_ALIAS[icon] or icon
		return Icons[key]
	end

	-- ---------------------------------------------------------------
	-- Elements
	--
	-- Each widget exposes the WindUI-shaped handles the Soreya code expects
	-- (SetValue / SetTitle / Refresh / Set) plus the Type and Default
	-- fields used by the Config tab.
	-- ---------------------------------------------------------------
	local function registerElement(configKey, element)
		if configKey then Elements[configKey] = element end
		return element
	end

	local function addSpacer(sectionAdd, listOrder)
		local Spacer = Instance.new("Frame")
		Spacer.Name = "Spacer"
		Spacer.BackgroundTransparency = 1
		Spacer.Size = UDim2.new(1, 0, 0, 6)
		Spacer.LayoutOrder = listOrder
		Spacer.Parent = sectionAdd
		return Spacer
	end

	-- ---------------------------------------------------------------
	-- Tabs
	--
	-- Each call returns its own handle table; the counters below only track
	-- ordering across the window.
	-- ---------------------------------------------------------------
	local CountTab = 0

	function GuiFunc:Tab(TabConfig)
		TabConfig = TabConfig or {}
		local tabName = tostring(TabConfig.Title or TabConfig.Name or "Tab")
		local Tabs = {}

		local ScrolLayers = Instance.new("ScrollingFrame")
		local UIListLayout1 = Instance.new("UIListLayout")

		ScrolLayers.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 80)
		ScrolLayers.ScrollBarThickness = 0
		ScrolLayers.Active = true
		ScrolLayers.LayoutOrder = CountTab
		ScrolLayers.BackgroundTransparency = 0.999
		ScrolLayers.BorderSizePixel = 0
		ScrolLayers.Size = UDim2.new(1, 0, 1, 0)
		ScrolLayers.Name = "ScrolLayers"
		ScrolLayers.Parent = LayersFolder

		UIListLayout1.Padding = UDim.new(0, 3)
		UIListLayout1.SortOrder = Enum.SortOrder.LayoutOrder
		UIListLayout1.Parent = ScrolLayers

		local Tab = Instance.new("Frame")
		local UICorner3 = Instance.new("UICorner")
		local TabButton = Instance.new("TextButton")
		local TabName = Instance.new("TextLabel")
		local FeatureImg = Instance.new("ImageLabel")
		local UIStroke2 = Instance.new("UIStroke")
		local UICorner4 = Instance.new("UICorner")

		local order = CountTab
		Tab.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		Tab.BackgroundTransparency = (order == 0) and 0.92 or 0.999
		Tab.BorderSizePixel = 0
		Tab.LayoutOrder = order
		Tab.Size = UDim2.new(1, 0, 0, 28)
		Tab.Name = "Tab"
		Tab.Parent = ScrollTab

		UICorner3.CornerRadius = UDim.new(0, 4)
		UICorner3.Parent = Tab

		TabButton.Font = Enum.Font.GothamBold
		TabButton.Text = ""
		TabButton.TextXAlignment = Enum.TextXAlignment.Left
		TabButton.BackgroundTransparency = 0.999
		TabButton.BorderSizePixel = 0
		TabButton.Size = UDim2.new(1, 0, 1, 0)
		TabButton.Name = "TabButton"
		TabButton.Parent = Tab

		TabName.Font = Enum.Font.GothamBold
		TabName.Text = tabName
		TabName.TextColor3 = Color3.fromRGB(255, 255, 255)
		TabName.TextSize = 13
		TabName.TextXAlignment = Enum.TextXAlignment.Left
		TabName.BackgroundTransparency = 0.999
		TabName.Size = UDim2.new(1, 0, 1, 0)
		TabName.Position = UDim2.new(0, 10, 0, 0)
		TabName.Name = "TabName"
		TabName.Parent = Tab

		FeatureImg.BackgroundTransparency = 0.999
		FeatureImg.BorderSizePixel = 0
		FeatureImg.Position = UDim2.new(0, 9, 0, 7)
		FeatureImg.Size = UDim2.new(0, 16, 0, 16)
		FeatureImg.Name = "FeatureImg"
		FeatureImg.Parent = Tab
		FeatureImg.Visible = false

		local icon = resolveIcon(TabConfig.Icon)
		if icon then
			FeatureImg.Image = icon
			FeatureImg.Visible = true
			TabName.Position = UDim2.new(0, 32, 0, 0)
			TabName.Size = UDim2.new(1, -38, 1, 0)
		end

		if order == 0 then
			pcall(function() LayersPageLayout:JumpToIndex(0) end)
			NameTab.Text = tabName

			local ChooseFrame = Instance.new("Frame")
			ChooseFrame.BackgroundColor3 = GuiConfig.Color
			ChooseFrame.BorderSizePixel = 0
			ChooseFrame.Position = UDim2.new(0, 0, 0, 5)
			ChooseFrame.Size = UDim2.new(0, 3, 0, 20)
			ChooseFrame.Name = "ChooseFrame"
			ChooseFrame.Parent = Tab

			UIStroke2.Color = GuiConfig.Color
			UIStroke2.Thickness = 1.6
			UIStroke2.Parent = ChooseFrame

			UICorner4.Parent = ChooseFrame
		end

		TabButton.Activated:Connect(function()
			CircleClick(TabButton, Mouse.X, Mouse.Y)
			-- A floating dropdown list is anchored to a row on the old page, so
			-- it must not survive a tab change.
			pcall(function() GuiFunc.CloseDropdowns() end)
			local FrameChoose
			for _, s in ipairs(ScrollTab:GetChildren()) do
				for _, v in ipairs(s:GetChildren()) do
					if v.Name == "ChooseFrame" then
						FrameChoose = v
						break
					end
				end
			end

			local current = LayersPageLayout.CurrentPage
			if FrameChoose ~= nil and current ~= nil and Tab.LayoutOrder ~= current.LayoutOrder then
				for _, TabFrame in ipairs(ScrollTab:GetChildren()) do
					if TabFrame.Name == "Tab" then
						TweenService:Create(
							TabFrame,
							TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.InOut),
							{ BackgroundTransparency = 0.999 }
						):Play()
					end
				end
				TweenService:Create(
					Tab,
					TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.InOut),
					{ BackgroundTransparency = 0.92 }
				):Play()

				FrameChoose.Parent = Tab
				FrameChoose.Position = UDim2.new(0, 0, 0, 5)
				FrameChoose.Size = UDim2.new(0, 3, 0, 20)

				pcall(function() LayersPageLayout:JumpToIndex(Tab.LayoutOrder) end)
				task.wait(0.05)
				NameTab.Text = tabName
			end
		end)

		-- -----------------------------------------------------------
		-- Section
		-- -----------------------------------------------------------
		local Sections = {}
		local CountSection = 0

		function Sections:Section(SectionConfig)
			local title = "Section"
			if type(SectionConfig) == "table" then
				title = tostring(SectionConfig.Title or SectionConfig.Name or "Section")
			elseif SectionConfig ~= nil then
				title = tostring(SectionConfig)
			end

			local Section = Instance.new("Frame")
			local SectionDecideFrame = Instance.new("Frame")
			local UICorner1 = Instance.new("UICorner")
			local UIGradient = Instance.new("UIGradient")
			local SectionReal = Instance.new("Frame")
			local UICorner = Instance.new("UICorner")
			local SectionButton = Instance.new("TextButton")
			local FeatureFrame = Instance.new("Frame")
			local FeatureImg2 = Instance.new("ImageLabel")
			local SectionTitle = Instance.new("TextLabel")
			local SectionAdd = Instance.new("Frame")
			local UICorner8 = Instance.new("UICorner")
			local UIListLayout2 = Instance.new("UIListLayout")

			Section.BackgroundTransparency = 0.999
			Section.BorderSizePixel = 0
			Section.LayoutOrder = CountSection
			Section.ClipsDescendants = true
			Section.Size = UDim2.new(1, 0, 0, 30)
			Section.Name = "Section"
			Section.Parent = ScrolLayers

			SectionReal.AnchorPoint = Vector2.new(0.5, 0)
			SectionReal.BackgroundColor3 = SURFACE
			SectionReal.BackgroundTransparency = 0.2
			SectionReal.BorderSizePixel = 0
			SectionReal.Position = UDim2.new(0.5, 0, 0, 0)
			SectionReal.Size = UDim2.new(1, -2, 0, 30)
			SectionReal.Name = "SectionReal"
			SectionReal.Parent = Section

			UICorner.CornerRadius = UDim.new(0, 4)
			UICorner.Parent = SectionReal

			SectionButton.Font = Enum.Font.SourceSans
			SectionButton.Text = ""
			SectionButton.BackgroundTransparency = 0.999
			SectionButton.BorderSizePixel = 0
			SectionButton.Size = UDim2.new(1, 0, 1, 0)
			SectionButton.Name = "SectionButton"
			SectionButton.Parent = SectionReal

			FeatureFrame.AnchorPoint = Vector2.new(1, 0.5)
			FeatureFrame.BackgroundTransparency = 0.999
			FeatureFrame.Position = UDim2.new(1, -5, 0.5, 0)
			FeatureFrame.Size = UDim2.new(0, 20, 0, 20)
			FeatureFrame.Name = "FeatureFrame"
			FeatureFrame.Parent = SectionReal

			FeatureImg2.Image = "rbxassetid://16851841101"
			FeatureImg2.AnchorPoint = Vector2.new(0.5, 0.5)
			FeatureImg2.BackgroundTransparency = 0.999
			FeatureImg2.Position = UDim2.new(0.5, 0, 0.5, 0)
			FeatureImg2.Rotation = -90
			FeatureImg2.Size = UDim2.new(1, 6, 1, 6)
			FeatureImg2.Name = "FeatureImg"
			FeatureImg2.Parent = FeatureFrame

			SectionTitle.Font = Enum.Font.GothamBold
			SectionTitle.Text = title
			SectionTitle.TextColor3 = Color3.fromRGB(231, 231, 231)
			SectionTitle.TextSize = 13
			SectionTitle.TextXAlignment = Enum.TextXAlignment.Left
			SectionTitle.AnchorPoint = Vector2.new(0, 0.5)
			SectionTitle.BackgroundTransparency = 0.999
			SectionTitle.Position = UDim2.new(0, 10, 0.5, 0)
			SectionTitle.Size = UDim2.new(1, -50, 0, 13)
			SectionTitle.Name = "SectionTitle"
			SectionTitle.Parent = SectionReal

			SectionDecideFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			SectionDecideFrame.AnchorPoint = Vector2.new(0.5, 0)
			SectionDecideFrame.BorderSizePixel = 0
			SectionDecideFrame.Position = UDim2.new(0.5, 0, 0, 33)
			SectionDecideFrame.Size = UDim2.new(0, 0, 0, 2)
			SectionDecideFrame.Name = "SectionDecideFrame"
			SectionDecideFrame.Parent = Section

			UICorner1.Parent = SectionDecideFrame

			UIGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 20, 20)),
				ColorSequenceKeypoint.new(0.5, GuiConfig.Color),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 20)),
			})
			UIGradient.Parent = SectionDecideFrame

			SectionAdd.AnchorPoint = Vector2.new(0.5, 0)
			SectionAdd.BackgroundTransparency = 0.999
			SectionAdd.BorderSizePixel = 0
			SectionAdd.ClipsDescendants = true
			SectionAdd.LayoutOrder = 1
			SectionAdd.Position = UDim2.new(0.5, 0, 0, 38)
			SectionAdd.Size = UDim2.new(1, 0, 0, 0)
			SectionAdd.Name = "SectionAdd"
			SectionAdd.Parent = Section

			UICorner8.CornerRadius = UDim.new(0, 2)
			UICorner8.Parent = SectionAdd

			UIListLayout2.Padding = UDim.new(0, 3)
			UIListLayout2.SortOrder = Enum.SortOrder.LayoutOrder
			UIListLayout2.Parent = SectionAdd

			local OpenSection = true
			local isAnimating = false
			local ANIM_TIME = 0.25
			local ANIM_STYLE = Enum.EasingStyle.Quart
			local ANIM_DIR = Enum.EasingDirection.Out

			local function UpdateSizeScroll()
				local OffsetY = 0
				for _, child in ipairs(ScrolLayers:GetChildren()) do
					if child.Name ~= "UIListLayout" then
						OffsetY = OffsetY + 3 + child.Size.Y.Offset
					end
				end
				ScrolLayers.CanvasSize = UDim2.new(0, 0, 0, OffsetY)
			end

			local function UpdateSizeSection()
				if not OpenSection then return end
				local total = 38
				for _, v in ipairs(SectionAdd:GetChildren()) do
					if v.Name ~= "UIListLayout" and v.Name ~= "UICorner" then
						total = total + v.Size.Y.Offset + 3
					end
				end
				local tweenInfo = TweenInfo.new(ANIM_TIME, ANIM_STYLE, ANIM_DIR)
				TweenService:Create(Section, tweenInfo, { Size = UDim2.new(1, 1, 0, total) }):Play()
				TweenService:Create(SectionAdd, tweenInfo, { Size = UDim2.new(1, 0, 0, total - 38) }):Play()
				TweenService:Create(SectionDecideFrame, tweenInfo, { Size = UDim2.new(1, 0, 0, 2) }):Play()
				task.delay(ANIM_TIME, UpdateSizeScroll)
			end

			SectionButton.Activated:Connect(function()
				if isAnimating then return end
				isAnimating = true
				CircleClick(SectionButton, Mouse.X, Mouse.Y)
				-- Collapsing a section moves every row below it, so an open list
				-- would be left pointing at the wrong place.
				pcall(function() GuiFunc.CloseDropdowns() end)
				local tweenInfo = TweenInfo.new(ANIM_TIME, ANIM_STYLE, ANIM_DIR)
				OpenSection = not OpenSection

				if OpenSection then
					TweenService:Create(SectionTitle, TweenInfo.new(0.2), { TextColor3 = GuiConfig.Color }):Play()
					TweenService:Create(FeatureImg2, tweenInfo, { Rotation = 0 }):Play()
					UpdateSizeSection()
				else
					TweenService:Create(SectionTitle, TweenInfo.new(0.2), { TextColor3 = Color3.fromRGB(231, 231, 231) }):Play()
					TweenService:Create(FeatureImg2, tweenInfo, { Rotation = -90 }):Play()
					TweenService:Create(Section, tweenInfo, { Size = UDim2.new(1, 1, 0, 30) }):Play()
					TweenService:Create(SectionDecideFrame, tweenInfo, { Size = UDim2.new(0, 0, 0, 2) }):Play()
				end

				task.delay(ANIM_TIME, function()
					UpdateSizeScroll()
					isAnimating = false
				end)
			end)

			FeatureImg2.Rotation = 0
			SectionDecideFrame.Size = UDim2.new(1, 0, 0, 2)
			SectionAdd.ChildAdded:Connect(function()
				task.wait(0.05)
				UpdateSizeSection()
			end)
			SectionAdd.ChildRemoved:Connect(function()
				task.wait(0.05)
				UpdateSizeSection()
			end)

			local CountItem = 0

			local function nextOrder()
				CountItem = CountItem + 1
				return CountItem - 1
			end

			local Items = {}

			function Items:Space()
				addSpacer(SectionAdd, nextOrder())
				return Items
			end

			function Items:Toggle(cfg)
				cfg = cfg or {}
				local widgetTitle = tostring(cfg.Title or "Toggle")
				local locked = cfg.Locked == true
				local configKey = "Toggle_" .. widgetTitle
				local value = cfg.Value == true
				if ConfigData[configKey] ~= nil then value = ConfigData[configKey] == true end

				local ToggleFunc = {Value = value, Type = "Toggle", Default = cfg.Value == true}

				local Toggle = Instance.new("Frame")
				local UICorner20 = Instance.new("UICorner")
				local ToggleTitle = Instance.new("TextLabel")
				local ToggleButton = Instance.new("TextButton")
				local FeatureFrame2 = Instance.new("Frame")
				local UICorner22 = Instance.new("UICorner")
				local UIStroke8 = Instance.new("UIStroke")
				local ToggleCircle = Instance.new("Frame")
				local UICorner23 = Instance.new("UICorner")

				Toggle.BackgroundColor3 = SURFACE
				Toggle.BackgroundTransparency = 0.2
				Toggle.BorderSizePixel = 0
				Toggle.LayoutOrder = nextOrder()
				Toggle.Size = UDim2.new(1, 0, 0, 46)
				Toggle.Name = "Toggle"
				Toggle.Parent = SectionAdd

				UICorner20.CornerRadius = UDim.new(0, 4)
				UICorner20.Parent = Toggle

				ToggleTitle.Font = Enum.Font.GothamBold
				ToggleTitle.Text = widgetTitle
				ToggleTitle.TextSize = 13
				ToggleTitle.TextColor3 = Color3.fromRGB(231, 231, 231)
				ToggleTitle.TextXAlignment = Enum.TextXAlignment.Left
				ToggleTitle.BackgroundTransparency = 1
				ToggleTitle.Position = UDim2.new(0, 10, 0, 10)
				ToggleTitle.Size = UDim2.new(1, -70, 0, 13)
				ToggleTitle.TextWrapped = true
				ToggleTitle.Name = "ToggleTitle"
				ToggleTitle.Parent = Toggle

				if cfg.Desc or cfg.Content then
					Toggle.Size = UDim2.new(1, 0, 0, 62)
				end

				local Desc = Instance.new("TextLabel")
				Desc.Font = Enum.Font.Gotham
				Desc.Text = tostring(cfg.Desc or cfg.Content or "")
				Desc.TextSize = 11
				Desc.TextColor3 = Color3.fromRGB(150, 150, 150)
				Desc.TextXAlignment = Enum.TextXAlignment.Left
				Desc.BackgroundTransparency = 1
				Desc.Position = UDim2.new(0, 10, 0, 27)
				Desc.Size = UDim2.new(1, -70, 0, 12)
				Desc.TextWrapped = true
				Desc.Name = "ToggleDesc"
				Desc.Parent = Toggle

				ToggleButton.Text = ""
				ToggleButton.BackgroundTransparency = 1
				ToggleButton.Size = UDim2.new(1, 0, 1, 0)
				ToggleButton.Name = "ToggleButton"
				ToggleButton.Parent = Toggle

				FeatureFrame2.AnchorPoint = Vector2.new(1, 0.5)
				FeatureFrame2.BackgroundColor3 = SURFACE_SOFT
				FeatureFrame2.BackgroundTransparency = 0.25
				FeatureFrame2.BorderSizePixel = 0
				FeatureFrame2.Position = UDim2.new(1, -15, 0.5, 0)
				FeatureFrame2.Size = UDim2.new(0, 30, 0, 15)
				FeatureFrame2.Name = "FeatureFrame"
				FeatureFrame2.Parent = Toggle

				UICorner22.Parent = FeatureFrame2

				UIStroke8.Color = Color3.fromRGB(255, 255, 255)
				UIStroke8.Thickness = 2
				UIStroke8.Transparency = 0.9
				UIStroke8.Parent = FeatureFrame2

				ToggleCircle.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
				ToggleCircle.BorderSizePixel = 0
				ToggleCircle.Size = UDim2.new(0, 14, 0, 14)
				ToggleCircle.Name = "ToggleCircle"
				ToggleCircle.Parent = FeatureFrame2

				UICorner23.CornerRadius = UDim.new(0, 15)
				UICorner23.Parent = ToggleCircle

				local applying = false

				function ToggleFunc:Set(v, silent)
					v = v == true
					ToggleFunc.Value = v
					ConfigData[configKey] = v

					if v then
						TweenService:Create(ToggleTitle, TweenInfo.new(0.2), { TextColor3 = GuiConfig.Color }):Play()
						TweenService:Create(ToggleCircle, TweenInfo.new(0.2), { Position = UDim2.new(0, 15, 0, 0) }):Play()
						TweenService:Create(UIStroke8, TweenInfo.new(0.2), { Color = GuiConfig.Color, Transparency = 0 }):Play()
						TweenService:Create(FeatureFrame2, TweenInfo.new(0.2), { BackgroundColor3 = GuiConfig.Color, BackgroundTransparency = 0 }):Play()
					else
						TweenService:Create(ToggleTitle, TweenInfo.new(0.2), { TextColor3 = Color3.fromRGB(231, 231, 231) }):Play()
						TweenService:Create(ToggleCircle, TweenInfo.new(0.2), { Position = UDim2.new(0, 0, 0, 0) }):Play()
						TweenService:Create(UIStroke8, TweenInfo.new(0.2), { Color = Color3.fromRGB(255, 255, 255), Transparency = 0.9 }):Play()
						TweenService:Create(FeatureFrame2, TweenInfo.new(0.2), { BackgroundColor3 = SURFACE_SOFT, BackgroundTransparency = 0.25 }):Play()
					end

					if not applying and not silent and type(cfg.Callback) == "function" then
						applying = true
						task.spawn(function()
							pcall(cfg.Callback, v)
							applying = false
						end)
					end
				end

				ToggleFunc.SetValue = function(self, v)
					ToggleFunc:Set(v)
				end

				if locked then
					RenderLockedRow(Toggle, ToggleTitle, widgetTitle, SectionAdd)
				else
					ToggleButton.Activated:Connect(function()
						-- Flipping a feature is an execution too; drop any open
						-- list so it cannot sit over the row that just changed.
						pcall(closeAllDropdowns)
						ToggleFunc:Set(not ToggleFunc.Value)
					end)
				end

				ToggleFunc:Set(ToggleFunc.Value, true)
				return registerElement(configKey, ToggleFunc)
			end

			function Items:Slider(cfg)
				cfg = cfg or {}
				local widgetTitle = tostring(cfg.Title or "Slider")
				local locked = cfg.Locked == true

				local range = type(cfg.Value) == "table" and cfg.Value or {}
				local min = tonumber(range.Min) or tonumber(cfg.Min) or 0
				local max = tonumber(range.Max) or tonumber(cfg.Max) or 100
				local default = tonumber(range.Default) or tonumber(cfg.Default) or min
				local step = tonumber(cfg.Step) or tonumber(cfg.Increment) or 1
				if max <= min then max = min + 1 end

				local configKey = "Slider_" .. widgetTitle
				if tonumber(ConfigData[configKey]) then default = tonumber(ConfigData[configKey]) end

				local SliderFunc = {Value = default, Type = "Slider", Default = default, Min = min, Max = max}

				local Slider = Instance.new("Frame")
				local UICorner15 = Instance.new("UICorner")
				local SliderTitle = Instance.new("TextLabel")
				local SliderInput = Instance.new("Frame")
				local UICorner16 = Instance.new("UICorner")
				local TextBox = Instance.new("TextBox")
				local SliderFrame = Instance.new("Frame")
				local UICorner17 = Instance.new("UICorner")
				local SliderDraggable = Instance.new("Frame")
				local UICorner18 = Instance.new("UICorner")
				local SliderCircle = Instance.new("Frame")
				local UICorner19 = Instance.new("UICorner")

				Slider.BackgroundColor3 = SURFACE
				Slider.BackgroundTransparency = 0.2
				Slider.BorderSizePixel = 0
				Slider.LayoutOrder = nextOrder()
				Slider.Size = UDim2.new(1, 0, 0, 46)
				Slider.Name = "Slider"
				Slider.Parent = SectionAdd

				UICorner15.CornerRadius = UDim.new(0, 4)
				UICorner15.Parent = Slider

				SliderTitle.Font = Enum.Font.GothamBold
				SliderTitle.Text = widgetTitle
				SliderTitle.TextColor3 = Color3.fromRGB(231, 231, 231)
				SliderTitle.TextSize = 13
				SliderTitle.TextXAlignment = Enum.TextXAlignment.Left
				SliderTitle.BackgroundTransparency = 1
				SliderTitle.Position = UDim2.new(0, 10, 0, 8)
				SliderTitle.Size = UDim2.new(1, -180, 0, 13)
				SliderTitle.Name = "SliderTitle"
				SliderTitle.Parent = Slider

				SliderInput.AnchorPoint = Vector2.new(0, 0.5)
				SliderInput.BackgroundTransparency = 1
				SliderInput.Position = UDim2.new(1, -158, 0.5, 0)
				SliderInput.Size = UDim2.new(0, 34, 0, 20)
				SliderInput.Name = "SliderInput"
				SliderInput.Parent = Slider

				UICorner16.CornerRadius = UDim.new(0, 2)
				UICorner16.Parent = SliderInput

				TextBox.Font = Enum.Font.GothamBold
				TextBox.Text = tostring(default)
				TextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
				TextBox.TextSize = 12
				TextBox.BackgroundTransparency = 1
				TextBox.BorderSizePixel = 0
				TextBox.Size = UDim2.new(1, 0, 1, 0)
				TextBox.Parent = SliderInput

				SliderFrame.AnchorPoint = Vector2.new(1, 0.5)
				SliderFrame.BackgroundColor3 = SURFACE_SOFT
				SliderFrame.BackgroundTransparency = 0.35
				SliderFrame.BorderSizePixel = 0
				SliderFrame.Position = UDim2.new(1, -20, 0.5, 0)
				SliderFrame.Size = UDim2.new(0, 100, 0, 3)
				SliderFrame.Name = "SliderFrame"
				SliderFrame.Parent = Slider

				UICorner17.Parent = SliderFrame

				SliderDraggable.AnchorPoint = Vector2.new(0, 0.5)
				SliderDraggable.BackgroundColor3 = GuiConfig.Color
				SliderDraggable.BorderSizePixel = 0
				SliderDraggable.Position = UDim2.new(0, 0, 0.5, 0)
				SliderDraggable.Size = UDim2.new(0, 0, 0, 1)
				SliderDraggable.Name = "SliderDraggable"
				SliderDraggable.Parent = SliderFrame

				UICorner18.Parent = SliderDraggable

				SliderCircle.AnchorPoint = Vector2.new(1, 0.5)
				SliderCircle.BackgroundColor3 = GuiConfig.Color
				SliderCircle.BorderSizePixel = 0
				SliderCircle.Position = UDim2.new(1, 4, 0.5, 0)
				SliderCircle.Size = UDim2.new(0, 8, 0, 8)
				SliderCircle.Name = "SliderCircle"
				SliderCircle.Parent = SliderDraggable

				UICorner19.Parent = SliderCircle

				local Dragging = false
				local applying = false

				local function Round(Number, Factor)
					if Factor <= 0 then return Number end
					local Result = math.floor(Number / Factor + (Number >= 0 and 0.5 or -0.5)) * Factor
					return Result
				end

				function SliderFunc:Set(v, silent)
					v = math.clamp(Round(tonumber(v) or min, step), min, max)
					SliderFunc.Value = v
					TextBox.Text = tostring(v)
					ConfigData[configKey] = v
					local scale = (v - min) / (max - min)
					TweenService:Create(
						SliderDraggable,
						TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Size = UDim2.fromScale(scale, 1) }
					):Play()

					if not applying and not silent and type(cfg.Callback) == "function" then
						applying = true
						task.spawn(function()
							pcall(cfg.Callback, v)
							applying = false
						end)
					end
				end

				local function setFromX(absX)
					local rel = math.clamp((absX - SliderFrame.AbsolutePosition.X) / math.max(SliderFrame.AbsoluteSize.X, 1), 0, 1)
					SliderFunc:Set(min + (max - min) * rel)
				end

				SliderFrame.InputBegan:Connect(function(input)
					if locked then return end
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						-- Dragging is an execution; no open list should hover over it.
						pcall(closeAllDropdowns)
						Dragging = true
						setFromX(input.Position.X)
					end
				end)

				SliderFrame.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						Dragging = false
					end
				end)

				UserInputService.InputChanged:Connect(function(input)
					if Dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
						setFromX(input.Position.X)
					end
				end)

				TextBox.FocusLost:Connect(function()
					if locked then
						TextBox.Text = tostring(SliderFunc.Value)
						return
					end
					SliderFunc:Set(TextBox.Text)
					TextBox.Text = tostring(SliderFunc.Value)
				end)

				if not locked then
					SliderFunc:Set(default, true)
				else
					SliderFunc.Value = default
					TextBox.Text = tostring(default)
					RenderLockedRow(Slider, SliderTitle, widgetTitle, SectionAdd)
				end

				return registerElement(configKey, SliderFunc)
			end

			function Items:Dropdown(cfg)
				cfg = cfg or {}
				local widgetTitle = tostring(cfg.Title or "Dropdown")
				local locked = cfg.Locked == true

				local options = cfg.Values or cfg.Options or {}
				local multi = cfg.Multi == true
				local configKey = "Dropdown_" .. widgetTitle

				local DropdownFunc = {Type = "Dropdown", Options = options, Multi = multi, Value = nil}

				local Dropdown = Instance.new("Frame")
				local UICorner10 = Instance.new("UICorner")
				local DropdownTitle = Instance.new("TextLabel")
				local DropdownButton = Instance.new("TextButton")
				local SelectOptionsFrame = Instance.new("Frame")
				local UICorner11 = Instance.new("UICorner")
				local OptionSelecting = Instance.new("TextLabel")
				local OptionImg = Instance.new("ImageLabel")
				local OptionList = Instance.new("ScrollingFrame")

				Dropdown.BackgroundColor3 = SURFACE
				Dropdown.BackgroundTransparency = 0.2
				Dropdown.BorderSizePixel = 0
				Dropdown.LayoutOrder = nextOrder()
				Dropdown.Size = UDim2.new(1, 0, 0, 46)
				Dropdown.Name = "Dropdown"
				Dropdown.Parent = SectionAdd

				UICorner10.CornerRadius = UDim.new(0, 4)
				UICorner10.Parent = Dropdown

				DropdownTitle.Font = Enum.Font.GothamBold
				DropdownTitle.Text = widgetTitle
				DropdownTitle.TextColor3 = Color3.fromRGB(231, 231, 231)
				DropdownTitle.TextSize = 13
				DropdownTitle.TextXAlignment = Enum.TextXAlignment.Left
				DropdownTitle.BackgroundTransparency = 1
				DropdownTitle.Position = UDim2.new(0, 10, 0, 8)
				DropdownTitle.Size = UDim2.new(1, -180, 0, 13)
				DropdownTitle.Name = "DropdownTitle"
				DropdownTitle.Parent = Dropdown

				SelectOptionsFrame.AnchorPoint = Vector2.new(1, 0.5)
				SelectOptionsFrame.BackgroundColor3 = SURFACE
				SelectOptionsFrame.BackgroundTransparency = 0.15
				SelectOptionsFrame.Position = UDim2.new(1, -7, 0.5, 0)
				SelectOptionsFrame.Size = UDim2.new(0, 148, 0, 26)
				SelectOptionsFrame.Name = "SelectOptionsFrame"
				SelectOptionsFrame.Parent = Dropdown

				UICorner11.CornerRadius = UDim.new(0, 4)
				UICorner11.Parent = SelectOptionsFrame

				OptionSelecting.Font = Enum.Font.GothamBold
				OptionSelecting.Text = multi and "Select Options" or "Select Option"
				OptionSelecting.TextColor3 = Color3.fromRGB(255, 255, 255)
				OptionSelecting.TextSize = 11
				OptionSelecting.TextTruncate = Enum.TextTruncate.AtEnd
				OptionSelecting.TextXAlignment = Enum.TextXAlignment.Left
				OptionSelecting.AnchorPoint = Vector2.new(0, 0.5)
				OptionSelecting.BackgroundTransparency = 1
				OptionSelecting.Position = UDim2.new(0, 8, 0.5, 0)
				OptionSelecting.Size = UDim2.new(1, -30, 1, 0)
				OptionSelecting.Name = "OptionSelecting"
				OptionSelecting.Parent = SelectOptionsFrame

				OptionImg.Image = "rbxassetid://16851841101"
				OptionImg.ImageColor3 = Color3.fromRGB(230, 230, 230)
				OptionImg.AnchorPoint = Vector2.new(1, 0.5)
				OptionImg.BackgroundTransparency = 1
				OptionImg.Position = UDim2.new(1, -4, 0.5, 0)
				OptionImg.Size = UDim2.new(0, 16, 0, 16)
				OptionImg.Name = "OptionImg"
				OptionImg.Parent = SelectOptionsFrame

				-- Drop list: an opaque floating panel in the window overlay, so the
				-- section never clips it and neighbouring widgets never paint over
				-- it. It is a ScrollingFrame so a long option list (rarities,
				-- servers, ...) stays reachable instead of being cut off.
				OptionList.BackgroundColor3 = Color3.fromRGB(16, 16, 16)
				OptionList.BackgroundTransparency = 0
				OptionList.BorderSizePixel = 0
				OptionList.Visible = false
				OptionList.Size = UDim2.new(0, 200, 0, 0)
				OptionList.ZIndex = 501
				OptionList.ClipsDescendants = true
				OptionList.ScrollBarThickness = 3
				OptionList.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 90)
				OptionList.ScrollingDirection = Enum.ScrollingDirection.Y
				OptionList.CanvasSize = UDim2.new(0, 0, 0, 0)
				OptionList.AutomaticCanvasSize = Enum.AutomaticSize.Y
				OptionList.Name = "OptionList"
				OptionList.Parent = OverlayLayer

				local OptionListCorner = Instance.new("UICorner")
				OptionListCorner.CornerRadius = UDim.new(0, 4)
				OptionListCorner.Parent = OptionList

				local OptionListStroke = Instance.new("UIStroke")
				OptionListStroke.Color = GuiConfig.Color
				OptionListStroke.Transparency = 0.75
				OptionListStroke.Thickness = 1
				OptionListStroke.Parent = OptionList

				local OptionListLayout = Instance.new("UIListLayout")
				OptionListLayout.Padding = UDim.new(0, 2)
				OptionListLayout.SortOrder = Enum.SortOrder.LayoutOrder
				OptionListLayout.Parent = OptionList

				local OptionListPad = Instance.new("UIPadding")
				OptionListPad.PaddingTop = UDim.new(0, 4)
				OptionListPad.PaddingBottom = UDim.new(0, 4)
				OptionListPad.PaddingLeft = UDim.new(0, 4)
				OptionListPad.PaddingRight = UDim.new(0, 4)
				OptionListPad.Parent = OptionList

				local rows = {}
				local expandedHeight = 0

				-- Close/open this one list. Declared before buildRows because the
				-- row click handlers close the list after a single pick.
				local closeList, openList

				local function summary()
					if multi then
						local picked = {}
						for _, v in ipairs(DropdownFunc.Value or {}) do
							picked[#picked + 1] = tostring(v)
						end
						if #picked == 0 then return "Select Options" end
						return table.concat(picked, ", ")
					end
					local v = DropdownFunc.Value
					if v == nil or v == "" then return "Select Option" end
					return tostring(v)
				end

				local function refreshVisuals()
					for _, row in ipairs(rows) do
						local selected
						if multi then
							selected = table.find(DropdownFunc.Value or {}, row.value) ~= nil
						else
							selected = DropdownFunc.Value == row.value
						end
						row.frame.BackgroundTransparency = selected and 0.9 or 0.999
						row.label.TextColor3 = selected and GuiConfig.Color or Color3.fromRGB(231, 231, 231)
					end
					OptionSelecting.Text = summary()
				end

				local function buildRows()
					for _, row in ipairs(rows) do
						row.frame:Destroy()
					end
					rows = {}

					for i, option in ipairs(DropdownFunc.Options) do
						local label = tostring(option)
						local value = option

						local rowFrame = Instance.new("Frame")
						local rowButton = Instance.new("TextButton")
						local rowLabel = Instance.new("TextLabel")

						rowFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
						rowFrame.BackgroundTransparency = 0.999
						rowFrame.BorderSizePixel = 0
						rowFrame.Size = UDim2.new(1, 0, 0, 26)
						rowFrame.LayoutOrder = i
						rowFrame.ZIndex = 502
						rowFrame.Name = "Option"
						rowFrame.Parent = OptionList

						local rowCorner = Instance.new("UICorner")
						rowCorner.CornerRadius = UDim.new(0, 3)
						rowCorner.Parent = rowFrame

						rowButton.Text = ""
						rowButton.BackgroundTransparency = 1
						rowButton.Size = UDim2.new(1, 0, 1, 0)
						rowButton.ZIndex = 503
						rowButton.Parent = rowFrame

						rowLabel.Font = Enum.Font.GothamBold
						rowLabel.Text = label
						rowLabel.TextSize = 12
						rowLabel.TextColor3 = Color3.fromRGB(231, 231, 231)
						rowLabel.TextXAlignment = Enum.TextXAlignment.Left
						rowLabel.BackgroundTransparency = 1
						rowLabel.Position = UDim2.new(0, 8, 0, 0)
						rowLabel.Size = UDim2.new(1, -16, 1, 0)
						rowLabel.ZIndex = 504
						rowLabel.Name = "OptionText"
						rowLabel.Parent = rowFrame

						rowButton.Activated:Connect(function()
							if multi then
								local list = DropdownFunc.Value or {}
								local at = table.find(list, value)
								if at then
									table.remove(list, at)
								else
									list[#list + 1] = value
								end
								DropdownFunc:Set(list)
								-- Multi stays open: picking several rarities in a
								-- row is the whole point of the mode.
							else
								DropdownFunc:Set(value)
								-- A single pick is a finished choice, so the list
								-- closes instead of hovering over the page.
								closeList()
							end
						end)

						rows[#rows + 1] = {frame = rowFrame, label = rowLabel, value = value}
					end

					expandedHeight = math.min(#DropdownFunc.Options, 9) * 28 + 8
					refreshVisuals()
				end

				DropdownButton.Text = ""
				DropdownButton.BackgroundTransparency = 1
				DropdownButton.Size = UDim2.new(1, 0, 1, 0)
				DropdownButton.Name = "DropdownButton"
				DropdownButton.Parent = Dropdown

				-- Close just this list (used by the header toggle and by row picks).
				-- Declared local (not global) so each dropdown keeps its own pair.
				closeList = function()
					OptionList.Visible = false
					for i = #OpenDropdowns, 1, -1 do
						if OpenDropdowns[i] and OpenDropdowns[i].List == OptionList then
							table.remove(OpenDropdowns, i)
						end
					end
				end

				openList = function()
					-- Anchor the floating panel directly under its row, in the
					-- window overlay's coordinate space, and flip it above the row
					-- when there is not enough room below.
					local row = Dropdown.AbsolutePosition
					local origin = OverlayLayer.AbsolutePosition
					local rowH = Dropdown.AbsoluteSize.Y
					local width = math.max(Dropdown.AbsoluteSize.X - 20, 120)
					local height = math.min(expandedHeight, OverlayLayer.AbsoluteSize.Y - 16)

					local y = row.Y - origin.Y + rowH + 4
					if y + height > OverlayLayer.AbsoluteSize.Y - 8 then
						local above = row.Y - origin.Y - height - 4
						if above >= 8 then
							y = above
						else
							y = math.max(8, OverlayLayer.AbsoluteSize.Y - 8 - height)
						end
					end

					OptionList.Position = UDim2.fromOffset(row.X - origin.X + 10, y)
					OptionList.Size = UDim2.fromOffset(width, height)
					OptionList.CanvasSize = UDim2.new(0, 0, 0, 0)
					OptionList.Visible = true
				end

				DropdownButton.Activated:Connect(function()
					if locked then return end

					-- If THIS list is already open, the click closes it. Checking
					-- this first matters: the "close every other dropdown" pass
					-- below used to include this one, so the toggle re-opened it
					-- and an open list could never be closed.
					if OptionList.Visible then
						closeList()
						return
					end

					closeAllDropdowns()
					openList()
					OpenDropdowns[#OpenDropdowns + 1] = {
						Header = Dropdown,
						List = OptionList,
						Close = closeList,
					}
				end)

				function DropdownFunc:Set(v, silent)
					if multi then
						if type(v) == "string" then
							DropdownFunc.Value = {v}
						elseif type(v) == "table" then
							DropdownFunc.Value = v
						else
							DropdownFunc.Value = {}
						end
					else
						if type(v) == "table" then
							DropdownFunc.Value = v[1]
						else
							DropdownFunc.Value = v
						end
					end
					ConfigData[configKey] = DropdownFunc.Value
					refreshVisuals()

					if not silent and type(cfg.Callback) == "function" then
						pcall(cfg.Callback, DropdownFunc.Value)
					end
				end

				DropdownFunc.SetValue = function(self, v)
					DropdownFunc:Set(v)
				end

				function DropdownFunc:GetValue()
					return DropdownFunc.Value
				end

				function DropdownFunc:Refresh(list)
					DropdownFunc.Options = list or {}
					buildRows()
					if OptionList.Visible then openList() end
				end

				buildRows()

				-- Scrolling the page moves the row, so re-anchor the floating list;
				-- if the row leaves the viewport, close it instead of leaving it
				-- floating over unrelated rows.
				ScrolLayers:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
					if not OptionList.Visible then return end
					local rowY = Dropdown.AbsolutePosition.Y - ScrolLayers.AbsolutePosition.Y
					if rowY < 0 or rowY > ScrolLayers.AbsoluteSize.Y then
						closeList()
					else
						openList()
					end
				end)

				-- Initial selection: a saved value wins, otherwise cfg.Value.
				-- The first Set is silent because the Soreya callbacks already
				-- start from their own defaults; replaying them here would
				-- re-run side effects before the script has booted.
				local initial = ConfigData[configKey]
				if initial == nil then initial = cfg.Value end
				if multi then
					if type(initial) == "string" then
						initial = {initial}
					elseif type(initial) ~= "table" then
						initial = {}
					end
				end
				DropdownFunc:Set(initial, true)
				DropdownFunc.Default = cfg.Value

				-- A locked dropdown IS the premium row: padlock, the feature name,
				-- and the "Buy Premium" line. The select box is hidden because the
				-- list cannot be opened.
				if locked then
					RenderLockedRow(Dropdown, DropdownTitle, widgetTitle, SectionAdd)
				end

				return registerElement(configKey, DropdownFunc)
			end

			function Items:Input(cfg)
				cfg = cfg or {}
				local widgetTitle = tostring(cfg.Title or "Input")
				local configKey = "Input_" .. widgetTitle
				local initial = tostring(cfg.Value or cfg.Default or "")
				if ConfigData[configKey] ~= nil then initial = tostring(ConfigData[configKey]) end

				local InputFunc = {Value = initial, Type = "Input", Default = cfg.Value or ""}

				local Input = Instance.new("Frame")
				local UICorner12 = Instance.new("UICorner")
				local InputTitle = Instance.new("TextLabel")
				local InputFrame = Instance.new("Frame")
				local UICorner13 = Instance.new("UICorner")
				local InputTextBox = Instance.new("TextBox")

				Input.BackgroundColor3 = SURFACE
				Input.BackgroundTransparency = 0.2
				Input.BorderSizePixel = 0
				Input.LayoutOrder = nextOrder()
				Input.Size = UDim2.new(1, 0, 0, 68)
				Input.Name = "Input"
				Input.Parent = SectionAdd

				UICorner12.CornerRadius = UDim.new(0, 4)
				UICorner12.Parent = Input

				InputTitle.Font = Enum.Font.GothamBold
				InputTitle.Text = widgetTitle
				InputTitle.TextColor3 = Color3.fromRGB(231, 231, 231)
				InputTitle.TextSize = 13
				InputTitle.TextXAlignment = Enum.TextXAlignment.Left
				InputTitle.BackgroundTransparency = 1
				InputTitle.Position = UDim2.new(0, 10, 0, 8)
				InputTitle.Size = UDim2.new(1, -20, 0, 15)
				InputTitle.Name = "InputTitle"
				InputTitle.Parent = Input

				InputFrame.BackgroundColor3 = SURFACE_SOFT
				InputFrame.BackgroundTransparency = 0.3
				InputFrame.BorderSizePixel = 0
				InputFrame.ClipsDescendants = true
				InputFrame.Position = UDim2.new(0, 10, 0, 30)
				InputFrame.Size = UDim2.new(1, -20, 0, 26)
				InputFrame.Name = "InputFrame"
				InputFrame.Parent = Input

				UICorner13.CornerRadius = UDim.new(0, 4)
				UICorner13.Parent = InputFrame

				InputTextBox.Font = Enum.Font.GothamBold
				InputTextBox.PlaceholderText = tostring(cfg.Placeholder or "Input here")
				InputTextBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
				InputTextBox.Text = initial
				InputTextBox.TextColor3 = Color3.fromRGB(220, 220, 220)
				InputTextBox.TextSize = 12
				InputTextBox.TextXAlignment = Enum.TextXAlignment.Left
				InputTextBox.BackgroundTransparency = 1
				InputTextBox.ClearTextOnFocus = false
				InputTextBox.Position = UDim2.new(0, 8, 0, 0)
				InputTextBox.Size = UDim2.new(1, -16, 1, 0)
				InputTextBox.Name = "InputTextBox"
				InputTextBox.Parent = InputFrame

				function InputFunc:Set(v, silent)
					v = tostring(v or "")
					InputTextBox.Text = v
					InputFunc.Value = v
					ConfigData[configKey] = v
					if not silent and type(cfg.Callback) == "function" then
						pcall(cfg.Callback, v)
					end
				end

				InputTextBox.FocusLost:Connect(function()
					InputFunc:Set(InputTextBox.Text)
				end)

				-- Typing is an execution; an open list would sit on top of the
				-- box being typed into.
				InputTextBox.Focused:Connect(function()
					pcall(closeAllDropdowns)
				end)

				ConfigData[configKey] = initial
				-- The Soreya webhook code reaches into the widget to find its
				-- TextBox (live URL sync). Expose the row frame like WindUI does.
				InputFunc.ElementFrame = Input
				return registerElement(configKey, InputFunc)
			end

			function Items:Button(cfg)
				cfg = cfg or {}
				local widgetTitle = tostring(cfg.Title or "Button")
				local locked = cfg.Locked == true

				local Button = Instance.new("Frame")
				local UICorner = Instance.new("UICorner")
				local MainButton = Instance.new("TextButton")
				local ButtonLabel = Instance.new("TextLabel")

				Button.BackgroundTransparency = 1
				Button.Size = UDim2.new(1, 0, 0, 34)
				Button.LayoutOrder = nextOrder()
				Button.Name = "Button"
				Button.Parent = SectionAdd

				MainButton.Font = Enum.Font.GothamBold
				MainButton.Text = ""
				MainButton.BackgroundColor3 = SURFACE
				MainButton.BackgroundTransparency = 0.2
				MainButton.BorderSizePixel = 0
				MainButton.Size = UDim2.new(1, 0, 1, 0)
				MainButton.Name = "MainButton"
				MainButton.Parent = Button

				UICorner.CornerRadius = UDim.new(0, 4)
				UICorner.Parent = MainButton

				ButtonLabel.Font = Enum.Font.GothamBold
				ButtonLabel.Text = widgetTitle
				ButtonLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				ButtonLabel.TextSize = 12
				ButtonLabel.BackgroundTransparency = 1
				ButtonLabel.Size = UDim2.new(1, -16, 1, 0)
				ButtonLabel.Position = UDim2.new(0, 8, 0, 0)
				ButtonLabel.TextTruncate = Enum.TextTruncate.AtEnd
				ButtonLabel.Name = "ButtonLabel"
				ButtonLabel.Parent = MainButton

				local ButtonFunc = {Type = "Button", Value = nil}

				function ButtonFunc:SetTitle(text)
					ButtonLabel.Text = tostring(text)
				end

				MainButton.Activated:Connect(function()
					CircleClick(MainButton, Mouse.X, Mouse.Y)
					-- Running an action closes any floating dropdown list. It is
					-- anchored to its own row, so leaving it up over the page
					-- while a feature executes is just clutter.
					pcall(closeAllDropdowns)
					if locked then return end
					if type(cfg.Callback) == "function" then
						pcall(cfg.Callback)
					end
				end)

				if locked then
					RenderLockedRow(Button, ButtonLabel, widgetTitle, SectionAdd)
				end

				return ButtonFunc
			end

			function Items:Paragraph(cfg)
				cfg = cfg or {}
				local widgetTitle = tostring(cfg.Title or "Info")
				local body = tostring(cfg.Desc or cfg.Content or "")

				local Paragraph = Instance.new("Frame")
				local UICorner14 = Instance.new("UICorner")
				local ParagraphTitle = Instance.new("TextLabel")
				local ParagraphContent = Instance.new("TextLabel")

				Paragraph.BackgroundColor3 = SURFACE
				Paragraph.BackgroundTransparency = 0.2
				Paragraph.BorderSizePixel = 0
				Paragraph.LayoutOrder = nextOrder()
				Paragraph.Size = UDim2.new(1, 0, 0, 44)
				Paragraph.Name = "Paragraph"
				Paragraph.Parent = SectionAdd

				UICorner14.CornerRadius = UDim.new(0, 4)
				UICorner14.Parent = Paragraph

				ParagraphTitle.Font = Enum.Font.GothamBold
				ParagraphTitle.Text = widgetTitle
				ParagraphTitle.TextColor3 = Color3.fromRGB(231, 231, 231)
				ParagraphTitle.TextSize = 13
				ParagraphTitle.TextXAlignment = Enum.TextXAlignment.Left
				ParagraphTitle.BackgroundTransparency = 1
				ParagraphTitle.Position = UDim2.new(0, 10, 0, 8)
				ParagraphTitle.Size = UDim2.new(1, -20, 0, 13)
				ParagraphTitle.Name = "ParagraphTitle"
				ParagraphTitle.Parent = Paragraph

				ParagraphContent.Font = Enum.Font.Gotham
				ParagraphContent.Text = body
				ParagraphContent.TextColor3 = Color3.fromRGB(170, 170, 170)
				ParagraphContent.TextSize = 11
				ParagraphContent.TextXAlignment = Enum.TextXAlignment.Left
				ParagraphContent.TextYAlignment = Enum.TextYAlignment.Top
				ParagraphContent.BackgroundTransparency = 1
				ParagraphContent.Position = UDim2.new(0, 10, 0, 24)
				ParagraphContent.Size = UDim2.new(1, -20, 0, 14)
				ParagraphContent.TextWrapped = true
				ParagraphContent.Name = "ParagraphContent"
				ParagraphContent.Parent = Paragraph

				local ParagraphFunc = {Type = "Paragraph", Value = body}

				function ParagraphFunc:SetContent(text)
					ParagraphContent.Text = tostring(text)
					local lines = math.max(1, math.ceil(#ParagraphContent.Text / 46))
					Paragraph.Size = UDim2.new(1, 0, 0, 24 + 14 * lines)
				end

				ParagraphFunc:SetContent(body)
				return ParagraphFunc
			end

			CountSection = CountSection + 1
			UpdateSizeSection()
			return Items
		end

		-- WindUI also allows tab:Toggle(...) directly; the Soreya code always
		-- goes through Section, so a default section keeps that safe.
		local defaultSection
		local function section()
			if not defaultSection then
				defaultSection = Sections:Section({Title = tabName})
			end
			return defaultSection
		end

		for _, name in ipairs({"Toggle", "Slider", "Dropdown", "Input", "Button", "Paragraph", "Space"}) do
			Tabs[name] = function(_, cfg)
				local sec = section()
				return sec[name](sec, cfg)
			end
		end
		Tabs.Section = function(_, cfg) return Sections:Section(cfg) end

		CountTab = CountTab + 1
		return Tabs
	end

	-- ---------------------------------------------------------------
	-- Config manager (Window.ConfigManager)
	--
	-- Backed by the same JSON files the Save/Load helpers use, so the Config
	-- tab in the Soreya scripts works without a second storage format.
	-- ---------------------------------------------------------------
	local function listConfigs()
		local names = {}
		if not (listfiles and isfile) then return names end
		CheckFolders()
		local ok, files = pcall(listfiles, CONFIG_FOLDER)
		if not ok or type(files) ~= "table" then return names end
		for _, path in ipairs(files) do
			local name = tostring(path):match("([^/\\]+)%.json$")
			if name then names[#names + 1] = name end
		end
		table.sort(names)
		return names
	end

	local ConfigManager = {}

	function ConfigManager:AllConfigs()
		return listConfigs()
	end

	local function makeConfig(name)
		name = tostring(name or "default")
		local config = {Name = name}
		function config:Save()
			return SaveConfig(name)
		end
		function config:Load()
			local ok = LoadConfigFromFile(name)
			if ok then LoadConfigElements() end
			return ok
		end
		return config
	end

	function ConfigManager:Config(name)
		return makeConfig(name)
	end

	function ConfigManager:CreateConfig(name)
		return makeConfig(name)
	end

	GuiFunc.ConfigManager = ConfigManager
	GuiFunc.CurrentConfig = nil

	GuiFunc.User = {
		SetAnonymous = function() end,
	}

	function GuiFunc:Notify(cfg)
		cfg = cfg or {}
		return BananaHub:MakeNotify({
			Title = cfg.Title or cfg.title or "Banana Hub",
			Description = cfg.Description or "",
			Content = cfg.Content or cfg.content or "",
			Delay = cfg.Duration or cfg.duration or 4,
			Image = cfg.Image or cfg.icon,
		})
	end

	function GuiFunc:Destroy()
		GuiFunc:DestroyGui()
	end

	return GuiFunc
end

-- WindUI-style top-level entry points.
function BananaHub:CreateWindow(cfg)
	return BananaHub:Window(cfg)
end

function BananaHub:Notify(cfg)
	cfg = cfg or {}
	return BananaHub:MakeNotify({
		Title = cfg.Title or cfg.title or "Banana Hub",
		Description = cfg.Description or "",
		Content = cfg.Content or cfg.content or "",
		Delay = cfg.Duration or cfg.duration or 4,
		Image = cfg.Image or cfg.icon,
	})
end

function BananaHub:SetTheme() end

-- Let the loader confirm which build it got.
BananaHub.Build = BUILD
BananaHub.BuildMarker = "BANANAHUB_BUILD_BLACK_8"

return BananaHub
