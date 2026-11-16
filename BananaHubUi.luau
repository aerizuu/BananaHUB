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

-- BANANAHUB_BUILD_BLACK_15
-- Build marker. The Soreya scripts look for this exact string before they
-- accept a copy of this library, so a stale workspace cache (or an earlier
-- build, which had no floating open icon) can never be loaded again.
local BUILD = "black-15"

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local GuiService = game:GetService("GuiService")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local viewport = workspace.CurrentCamera.ViewportSize

-- Where the interface actually lives.
--
-- gethui() is the executor's hidden container: it is not a child of CoreGui or of
-- PlayerGui, so a game-side script walking those trees cannot see the window at
-- all. Rayfield and every other hub use it for exactly that reason.
--
-- CoreGui is the fallback for an executor without gethui, and PlayerGui the last
-- resort. Both are visible to the game, which is why they are only fallbacks.
local HIDDEN_PARENT = nil
do
	local ok, hui = pcall(function()
		if type(gethui) == "function" then return gethui() end
		return nil
	end)
	if ok and hui then
		HIDDEN_PARENT = hui
	else
		HIDDEN_PARENT = CoreGui
	end
end

-- Parent a ScreenGui where the game cannot see it.
local function MountGui(gui)
	local ok = pcall(function() gui.Parent = HIDDEN_PARENT end)
	if ok and gui.Parent then return true end
	ok = pcall(function() gui.Parent = CoreGui end)
	if ok and gui.Parent then return true end
	return pcall(function() gui.Parent = LocalPlayer:WaitForChild("PlayerGui", 10) end)
end

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

-- Phone and tablet both report TouchEnabled, so `isMobile` is true for a tablet
-- with a mouse and a Bluetooth keyboard attached too. What actually breaks is
-- small screens, so gate the compact layout on the viewport instead of on the
-- input devices: on a large touch screen the desktop layout fits fine.
local function isCompact()
	-- Live viewport, not the module snapshot: this is called again after a
	-- rotation, where the snapshot would still describe the old orientation.
	local cam = workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize) or viewport
	if vp.X <= 700 or vp.Y <= 420 then return true end
	return isMobile
end

-- Raw pixel fit, no upper clamp. Used for the window's default size on phones,
-- where capping at 50% of the screen would leave a needlessly tiny panel.
local function fitPixels(pxWidth, pxHeight)
	local scaleX = pxWidth / viewport.X
	local scaleY = pxHeight / viewport.Y
	if scaleX > 0.94 then scaleX = 0.94 end
	if scaleY > 0.92 then scaleY = 0.92 end
	return UDim2.new(scaleX, 0, scaleY, 0)
end

local function safeSize(pxWidth, pxHeight)
	local scaleX = pxWidth / viewport.X
	local scaleY = pxHeight / viewport.Y
	if isCompact() then
		if scaleX > 0.94 then scaleX = 0.94 end
		if scaleY > 0.92 then scaleY = 0.92 end
	else
		if scaleX > 0.8 then scaleX = 0.8 end
		if scaleY > 0.85 then scaleY = 0.85 end
	end
	return UDim2.new(scaleX, 0, scaleY, 0)
end

-- ---------------------------------------------------------------
-- Device detection
--
-- TouchEnabled alone cannot tell a phone from a tablet (both report it), and a
-- tablet with a Bluetooth keyboard reports KeyboardEnabled too. So: classify on
-- the pointer first, then fall back to screen size, which is what actually
-- decides whether the compact layout is needed.
-- ---------------------------------------------------------------
local function DetectDevice()
	-- Read the live viewport rather than the module-level snapshot: this runs
	-- again after a rotation, where the snapshot is stale.
	local cam = workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize) or viewport
	local touch = UserInputService.TouchEnabled
	local mouse = UserInputService.MouseEnabled
	local keyboard = UserInputService.KeyboardEnabled
	local shortest = math.min(vp.X, vp.Y)

	local name, kind
	if touch and not mouse then
		-- A finger is the only pointer: phone or tablet, decided by screen size.
		-- 600px is the usual short-side breakpoint between the two.
		if shortest >= 600 then
			name, kind = "Tablet", "tablet"
		else
			name, kind = "Mobile", "mobile"
		end
	elseif touch and mouse and shortest < 700 then
		-- Touch plus a pointer on a small screen. Some mobile executors report a
		-- virtual mouse; a 390px-wide screen is a phone regardless.
		name, kind = "Mobile", "mobile"
	else
		-- Keyboard and pointer: desktop or laptop, possibly with a touchscreen.
		name, kind = "PC", "pc"
	end

	return {
		Name     = name,
		Kind     = kind,
		Touch    = touch,
		Mouse    = mouse,
		Keyboard = keyboard,
		Width    = vp.X,
		Height   = vp.Y,
		Compact  = isCompact(),
	}
end

local DEVICE = DetectDevice()

local function MakeDraggable(topbarobject, object)
	-- Absolute-position helpers. Working in absolute pixels instead of adding to
	-- Position.Offset is what makes the window behave the same whether its size
	-- is scale-based (the default, so it fits any screen) or offset-based (after
	-- a resize). Reading AbsoluteSize also means the resize maths sees the real
	-- on-screen size rather than a UDim2 whose offset may be 0.
	local function ParentSize(gui)
		local p = gui.Parent
		if p and p:IsA("GuiObject") then return p.AbsoluteSize end
		return viewport
	end

	local function SetAbsoluteTopLeft(gui, ax, ay)
		local parentSize = ParentSize(gui)
		if parentSize.X <= 0 or parentSize.Y <= 0 then return end
		local absSize = gui.AbsoluteSize
		local anchor = gui.AnchorPoint
		-- Position is resolved as: parentSize * scale - absSize * anchor
		local scaleX = (ax + absSize.X * anchor.X) / parentSize.X
		local scaleY = (ay + absSize.Y * anchor.Y) / parentSize.Y
		gui.Position = UDim2.new(scaleX, 0, scaleY, 0)
	end

	local function CustomPos(bar, frame)
		local Dragging, DragInput, DragStart, StartAbs

		local function UpdatePos(input)
			if not StartAbs then return end
			local delta = input.Position - DragStart
			local absSize = frame.AbsoluteSize
			local parentSize = ParentSize(frame)
			local maxX = math.max(parentSize.X - absSize.X, 0)
			local maxY = math.max(parentSize.Y - absSize.Y, 0)
			-- Keep a sliver of the window reachable so it can never be dragged
			-- fully off-screen and stranded (easy to do with a thumb on a phone).
			local minVisible = math.min(48, absSize.X * 0.5)
			local x = math.clamp(StartAbs.X + delta.X, -(absSize.X - minVisible), maxX)
			local y = math.clamp(StartAbs.Y + delta.Y, 0, maxY)

			SetAbsoluteTopLeft(frame, x, y)
			-- Remember where the user parked the window so the open/close
			-- animation reopens it in the same spot.
			frame:SetAttribute("BH_RestingX", frame.Position.X.Scale)
			frame:SetAttribute("BH_RestingY", frame.Position.Y.Scale)
		end

		local function Finish()
			Dragging = false
			DragInput = nil
		end

		bar.Active = true
		bar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				Dragging = true
				DragStart = input.Position
				StartAbs = frame.AbsolutePosition
			end
		end)

		bar.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				DragInput = input
			end
		end)

		-- Release is detected on the bar itself (reliable for mouse AND touch;
		-- a mouse InputObject never reports UserInputState.End through Changed,
		-- which is why a release could previously be missed) plus the global
		-- InputEnded as a safety net for a finger that slides off the bar.
		bar.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				Finish()
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				Finish()
			end
		end)

		UserInputService.InputChanged:Connect(function(input)
			if not Dragging then return end
			if input ~= DragInput then return end
			UpdatePos(input)
		end)
	end

	local function CustomSize(frame)
		local Dragging, DragInput, DragStart, StartAbsSize, StartAbsPos
		local minSizeX, minSizeY = 260, 200

		-- Default size: on a phone the window should fill most of the screen,
		-- because a 470x270 panel on a 390x844 viewport is unusable.
		frame.Size = safeSize(640, 400)

		-- Grab area: sits over the bottom-right corner of the shadow ring and the
		-- very corner of the panel. The visible lines are drawn inside this box
		-- but outside the panel itself. It is deliberately larger on a touch
		-- screen: a 34px target is fine for a mouse and near-impossible for a
		-- fingertip.
		local gripSize = isCompact() and 52 or 34

		local changesizeobject = Instance.new("Frame")
		changesizeobject.AnchorPoint = Vector2.new(1, 1)
		changesizeobject.BackgroundTransparency = 1
		changesizeobject.Size = UDim2.new(0, gripSize, 0, gripSize)
		changesizeobject.Position = UDim2.new(1, 0, 1, 0)
		changesizeobject.ZIndex = 10
		changesizeobject.Name = "changesizeobject"
		changesizeobject.Active = true   -- required to receive InputBegan
		changesizeobject.Parent = frame

		-- Resize grip: two short 45-degree lines just OUTSIDE the panel's
		-- bottom-right corner, in the transparent shadow margin around it, so it
		-- reads as "drag me bigger" without stealing space inside the UI.
		-- The panel is inset 23.5px inside the holder, so offsets around 14-21px
		-- from the holder corner hug the panel's corner from just outside it.
		local lineLength = isCompact() and 16 or 11
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

		GripLine(14, lineLength)
		GripLine(21, lineLength)

		local function UpdateSize(input)
			if not StartAbsSize then return end
			local delta = input.Position - DragStart
			local parentSize = ParentSize(frame)

			-- Resize in absolute pixels and clamp to the screen, so the window
			-- can neither collapse to nothing nor grow past the viewport where
			-- its own grip would end up off-screen and unreachable.
			local maxW = math.max(parentSize.X * 0.98, minSizeX)
			local maxH = math.max(parentSize.Y * 0.98, minSizeY)
			local newW = math.clamp(StartAbsSize.X + delta.X, math.min(minSizeX, maxW), maxW)
			local newH = math.clamp(StartAbsSize.Y + delta.Y, math.min(minSizeY, maxH), maxH)

			frame.Size = UDim2.new(0, math.floor(newW), 0, math.floor(newH))

			-- Growing right/down must not push the window off the screen, and
			-- because the holder is anchored at its centre its top-left drifts
			-- as it grows. Re-anchor to the corner the user started from.
			local ax = StartAbsPos.X
			local ay = StartAbsPos.Y
			ax = math.clamp(ax, 0, math.max(parentSize.X - newW, 0))
			ay = math.clamp(ay, 0, math.max(parentSize.Y - newH, 0))
			SetAbsoluteTopLeft(frame, ax, ay)

			-- Remember the user's size so the open/close animation zooms back
			-- to it instead of the size the script originally requested.
			frame:SetAttribute("BH_RestingW", math.floor(newW))
			frame:SetAttribute("BH_RestingH", math.floor(newH))
			frame:SetAttribute("BH_RestingX", frame.Position.X.Scale)
			frame:SetAttribute("BH_RestingY", frame.Position.Y.Scale)
		end

		local function Finish()
			Dragging = false
			DragInput = nil
		end

		changesizeobject.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				Dragging = true
				DragStart = input.Position
				StartAbsSize = frame.AbsoluteSize
				StartAbsPos = frame.AbsolutePosition
			end
		end)

		changesizeobject.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				DragInput = input
			end
		end)

		changesizeobject.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				Finish()
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				Finish()
			end
		end)

		UserInputService.InputChanged:Connect(function(input)
			if not Dragging then return end
			if input ~= DragInput then return end
			UpdateSize(input)
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
BananaHub.Device = DEVICE
BananaHub.DetectDevice = DetectDevice

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
		-- Notifications live in the same hidden container as the window, so a
		-- game-side script walking CoreGui sees neither.
		local NotifyRoot = HIDDEN_PARENT
		local existing = NotifyRoot:FindFirstChild("NotifyGui")
		if not existing then
			local NotifyGui = Instance.new("ScreenGui")
			NotifyGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			NotifyGui.Name = "NotifyGui"
			NotifyGui.ResetOnSpawn = false
			local okMount = pcall(function() NotifyGui.Parent = NotifyRoot end)
			if not okMount or not NotifyGui.Parent then
				pcall(function() NotifyGui.Parent = CoreGui end)
			end
			existing = NotifyGui
		end

		local NotifyGuiRef = existing
		if not NotifyGuiRef:FindFirstChild("NotifyLayout") then
			local NotifyLayout = Instance.new("Frame")
			NotifyLayout.AnchorPoint = Vector2.new(1, 1)
			NotifyLayout.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			NotifyLayout.BackgroundTransparency = 0.999
			NotifyLayout.BorderSizePixel = 0
			NotifyLayout.Position = UDim2.new(1, -30, 1, -30)
			NotifyLayout.Size = UDim2.new(0, 320, 1, 0)
			NotifyLayout.Name = "NotifyLayout"
			NotifyLayout.Parent = NotifyGuiRef

			NotifyGuiRef.NotifyLayout.ChildRemoved:Connect(function()
				local Count = 0
				for _, v in ipairs(NotifyGuiRef.NotifyLayout:GetChildren()) do
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
		for _, v in ipairs(NotifyGuiRef.NotifyLayout:GetChildren()) do
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
		NotifyFrame.Parent = NotifyGuiRef.NotifyLayout
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

	-- ---------------------------------------------------------------
	-- Device glyphs
	--
	-- Drawn from frames rather than asset ids, like the padlock above, so they
	-- cannot come out blank if an image id is wrong or unmoderated. Each glyph
	-- is a simple silhouette: a monitor with a stand, a phone, or a tablet.
	-- `parent` is any GuiObject; the glyph fills it.
	-- ---------------------------------------------------------------
	local function MakeDeviceGlyph(parent, kind, colour, zIndex)
		colour = colour or Color3.fromRGB(215, 215, 215)

		local Root = Instance.new("Frame")
		Root.Name = "DeviceGlyph"
		Root.BackgroundTransparency = 1
		Root.Size = UDim2.new(1, 0, 1, 0)
		Root.ZIndex = zIndex or 4
		Root.Parent = parent

		local function bar(x, y, w, h, radius)
			local f = Instance.new("Frame")
			f.BackgroundColor3 = colour
			f.BorderSizePixel = 0
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.new(x, 0, y, 0)
			f.Size = UDim2.new(w, 0, h, 0)
			f.ZIndex = (zIndex or 4) + 1
			f.Parent = Root
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, radius or 1)
			c.Parent = f
			return f
		end

		-- Each glyph is a filled silhouette. At 12px an outline would just blur
		-- into a smudge, so shape carries the meaning: a monitor is wide and
		-- low with a stand, a tablet is a wide tall slab, a phone is a narrow
		-- tall slab with a home indicator.
		if kind == "pc" then
			bar(0.5, 0.38, 0.86, 0.52, 1)      -- monitor
			bar(0.5, 0.70, 0.10, 0.14, 0)      -- stand
			bar(0.5, 0.84, 0.38, 0.09, 1)      -- base
		elseif kind == "tablet" then
			bar(0.5, 0.50, 0.66, 0.90, 2)      -- body
		else
			bar(0.5, 0.46, 0.42, 0.78, 2)      -- body
			bar(0.5, 0.90, 0.16, 0.06, 1)      -- home indicator
		end

		return Root
	end

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

	-- Forward-declared: BuildFloatIcon below parents the icon into this ScreenGui,
	-- but the Gui itself is only built further down.
	local BananaHubGui

	-- ---------------------------------------------------------------
	-- Floating open button
	--
	-- A round banana icon that stays on screen when the window is closed, so the
	-- window can be reopened without the Insert key (which does not exist on a
	-- phone). It is created once the ScreenGui exists (BuildFloatIcon, called
	-- below), and shown/hidden by the open and close animations.
	--
	-- GuiConfig.OpenButton.Enabled = false turns it off for scripts that want a
	-- hotkey-only window.
	-- ---------------------------------------------------------------
	local OpenButtonConfig = GuiConfig.OpenButton
	if type(OpenButtonConfig) ~= "table" then OpenButtonConfig = {} end
	local WantFloatIcon = OpenButtonConfig.Enabled ~= false

	local FloatIcon = nil

	local function BuildFloatIcon()
		if not WantFloatIcon or FloatIcon or not BananaHubGui then return end

		FloatIcon = Instance.new("TextButton")
		FloatIcon.Name = "BananaHubFloatIcon"
		FloatIcon.AnchorPoint = Vector2.new(0, 0)
		-- Bottom-left, clear of the Roblox jump button and the chat bar.
		FloatIcon.Position = UDim2.new(0, 20, 1, -120)
		FloatIcon.Size = UDim2.new(0, 46, 0, 46)
		FloatIcon.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
		FloatIcon.BackgroundTransparency = 0.15
		FloatIcon.BorderSizePixel = 0
		FloatIcon.AutoButtonColor = false
		FloatIcon.Text = ""
		FloatIcon.ClipsDescendants = false
		-- Above the window: the icon is how you reopen a closed window, so it must
		-- never end up behind the panel.
		FloatIcon.ZIndex = 900
		FloatIcon.Parent = BananaHubGui

		local FloatCorner = Instance.new("UICorner")
		FloatCorner.CornerRadius = UDim.new(1, 0)
		FloatCorner.Parent = FloatIcon

		local FloatStroke = Instance.new("UIStroke")
		FloatStroke.Color = GuiConfig.Color
		FloatStroke.Thickness = 1.4
		FloatStroke.Transparency = 0.55
		FloatStroke.Parent = FloatIcon

		local FloatImage = Instance.new("ImageLabel")
		FloatImage.Name = "FloatImage"
		FloatImage.BackgroundTransparency = 1
		FloatImage.BorderSizePixel = 0
		FloatImage.AnchorPoint = Vector2.new(0.5, 0.5)
		FloatImage.Position = UDim2.new(0.5, 0, 0.5, 0)
		FloatImage.Size = UDim2.new(1, -8, 1, -8)
		FloatImage.ScaleType = Enum.ScaleType.Fit
		FloatImage.Image = GuiConfig.Icon
		FloatImage.ZIndex = 901
		FloatImage.Parent = FloatIcon

		-- Keep the icon on screen when the viewport changes, and never let a drag
		-- strand it off the edge (a thumb drag on a phone makes that easy).
		local function ClampFloatIcon()
			if not FloatIcon or not FloatIcon.Parent then return end
			local cam = workspace.CurrentCamera
			local vp = cam and cam.ViewportSize or viewport
			if not vp or vp.X <= 0 or vp.Y <= 0 then return end
			local abs = FloatIcon.AbsolutePosition
			local size = FloatIcon.AbsoluteSize
			local maxX = math.max(vp.X - size.X, 0)
			local maxY = math.max(vp.Y - size.Y, 0)
			local x = math.clamp(abs.X, 0, maxX)
			local y = math.clamp(abs.Y, 0, maxY)
			if math.abs(x - abs.X) > 0.5 or math.abs(y - abs.Y) > 0.5 then
				FloatIcon.Position = UDim2.new(0, math.floor(x), 0, math.floor(y))
			end
		end

		-- Drag, and treat a release without movement as a click. Doing both from
		-- one handler is what keeps the icon usable on touch, where there is no
		-- hover and a separate click target would fight the drag.
		local dragging, dragInput, dragStart, startAbs, moved = false, nil, nil, nil, false
		FloatIcon.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				moved = false
				dragStart = input.Position
				startAbs = FloatIcon.AbsolutePosition
			end
		end)
		FloatIcon.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				dragInput = input
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if not dragging or input ~= dragInput or not startAbs then return end
			local delta = input.Position - dragStart
			if math.abs(delta.X) > 4 or math.abs(delta.Y) > 4 then moved = true end
			FloatIcon.Position = UDim2.new(
				0, math.floor(startAbs.X + delta.X), 0, math.floor(startAbs.Y + delta.Y))
		end)
		local function EndFloatDrag()
			if not dragging then return end
			dragging = false
			dragInput = nil
			ClampFloatIcon()
		end
		FloatIcon.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				EndFloatDrag()
				-- A tap (not a drag) opens the window.
				if not moved then
					pcall(function() CircleClick(FloatIcon, Mouse.X, Mouse.Y) end)
					if GuiFunc.OnFloatClick then pcall(GuiFunc.OnFloatClick) end
				end
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				EndFloatDrag()
			end
		end)
		pcall(function()
			local cam = workspace.CurrentCamera
			if cam then
				cam:GetPropertyChangedSignal("ViewportSize"):Connect(ClampFloatIcon)
			end
		end)
	end

	BananaHubGui = Instance.new("ScreenGui")
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
	MountGui(BananaHubGui)

	DropShadowHolder.BackgroundTransparency = 1
	DropShadowHolder.BorderSizePixel = 0
	DropShadowHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	DropShadowHolder.Position = UDim2.new(0.5, 0, 0.5, 0)
	-- Placeholder size; MakeDraggable and the GuiConfig.Size block below set the
	-- real one. safeSize keeps it inside the viewport on every screen.
	DropShadowHolder.Size = safeSize(640, 400)
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
	TextLabel.TextTruncate = Enum.TextTruncate.AtEnd
	TextLabel.BackgroundTransparency = 0.999
	-- Title keeps clear of the footer text and the device badge to its right.
	TextLabel.Size = UDim2.new(1, -300, 1, 0)
	TextLabel.Position = UDim2.new(0, 35, 0, 0)
	TextLabel.Parent = Top

	TextLabel1.Font = Enum.Font.GothamBold
	TextLabel1.Text = GuiConfig.Footer
	TextLabel1.TextColor3 = GuiConfig.Color
	TextLabel1.TextSize = 14
	TextLabel1.BackgroundTransparency = 0.999
	TextLabel1.TextXAlignment = Enum.TextXAlignment.Right
	TextLabel1.TextTruncate = Enum.TextTruncate.AtEnd
	-- Sits between the title and the badge. 150px is enough for "Soreya | V 1.0"
	-- and stops it running under the badge on a narrow window.
	TextLabel1.Size = UDim2.new(0, 150, 1, 0)
	TextLabel1.Position = UDim2.new(1, -300, 0, 0)
	TextLabel1.Parent = Top

	-- ---------------------------------------------------------------
	-- Device badge
	--
	-- A small pill in the title bar showing which device this session is running
	-- on (PC / Mobile / Tablet) with a matching icon. Purely informational: the
	-- compact layout is chosen by isCompact(), not by this.
	--
	-- Layout budget in the title bar, from the right edge: Close occupies
	-- -33..-8, Min -63..-38. The badge ends at -70 so it cannot overlap either.
	-- ---------------------------------------------------------------
	local DeviceBadge = Instance.new("Frame")
	DeviceBadge.Name = "DeviceBadge"
	DeviceBadge.AnchorPoint = Vector2.new(1, 0.5)
	DeviceBadge.Position = UDim2.new(1, -70, 0.5, 0)
	-- Sized from the label length: "Mobile"/"Tablet" are the longest at 6 chars
	-- plus the 12px icon and padding, so the pill never clips its own text.
	DeviceBadge.Size = UDim2.new(0, 26 + (#DEVICE.Name * 6), 0, 20)
	DeviceBadge.BackgroundColor3 = SURFACE_SOFT
	DeviceBadge.BackgroundTransparency = 0.25
	DeviceBadge.BorderSizePixel = 0
	DeviceBadge.ZIndex = 3
	DeviceBadge.Parent = Top

	local DeviceBadgeCorner = Instance.new("UICorner")
	DeviceBadgeCorner.CornerRadius = UDim.new(1, 0)
	DeviceBadgeCorner.Parent = DeviceBadge

	local DeviceBadgeStroke = Instance.new("UIStroke")
	DeviceBadgeStroke.Color = GuiConfig.Color
	DeviceBadgeStroke.Thickness = 1
	DeviceBadgeStroke.Transparency = 0.82
	DeviceBadgeStroke.Parent = DeviceBadge

	-- Glyph is drawn from frames (see MakeDeviceGlyph), so it can never come out
	-- as a blank image if an asset id is wrong.
	local DeviceIcon = Instance.new("Frame")
	DeviceIcon.Name = "DeviceIcon"
	DeviceIcon.AnchorPoint = Vector2.new(0, 0.5)
	DeviceIcon.Position = UDim2.new(0, 6, 0.5, 0)
	DeviceIcon.Size = UDim2.new(0, 12, 0, 12)
	DeviceIcon.BackgroundTransparency = 1
	DeviceIcon.ZIndex = 4
	DeviceIcon.Parent = DeviceBadge
	MakeDeviceGlyph(DeviceIcon, DEVICE.Kind, Color3.fromRGB(215, 215, 215), 4)

	local DeviceText = Instance.new("TextLabel")
	DeviceText.Name = "DeviceText"
	DeviceText.Font = Enum.Font.GothamBold
	DeviceText.Text = DEVICE.Name
	DeviceText.TextColor3 = Color3.fromRGB(215, 215, 215)
	DeviceText.TextSize = 10
	DeviceText.TextXAlignment = Enum.TextXAlignment.Left
	DeviceText.BackgroundTransparency = 1
	DeviceText.Position = UDim2.new(0, 21, 0, 0)
	DeviceText.Size = UDim2.new(1, -25, 1, 0)
	DeviceText.ZIndex = 4
	DeviceText.Parent = DeviceBadge

	-- The long "Game | V x.y" line does not fit beside the badge on a phone, so
	-- hide it there rather than letting it run under the close button. The title
	-- then takes over that space: with the footer gone the badge is the only
	-- thing to its right, so stop at -165 instead of -300.
	if isCompact() then
		TextLabel1.Visible = false
		DeviceBadge.Size = UDim2.new(0, 24 + (#DEVICE.Name * 6), 0, 18)
		TextLabel.Size = UDim2.new(1, -165, 1, 0)
	end

	-- The window is resizable down to 260px, where the footer text and the badge
	-- cannot both fit. Drop the footer first (it is decorative) and only then
	-- let the title run under the badge's left edge.
	local function LayoutTitleBar()
		local w = DropShadowHolder.AbsoluteSize.X
		if w <= 0 then return end
		if w < 420 then
			TextLabel1.Visible = false
			TextLabel.Size = UDim2.new(1, -165, 1, 0)
		elseif not isCompact() then
			TextLabel1.Visible = true
			TextLabel.Size = UDim2.new(1, -300, 1, 0)
		end
	end
	DropShadowHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(LayoutTitleBar)
	task.defer(LayoutTitleBar)

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

	-- Sidebar width. 120px is a desktop-sized rail; on a phone the same width
	-- eats a third of a 390px screen, so use a narrower rail and a smaller tab
	-- row. The numbers stay in GuiConfig["Tab Width"] so the content pane's
	-- offsets below still line up.
	if isCompact() then
		local w = math.clamp(math.floor(viewport.X * 0.22), 76, 96)
		GuiConfig["Tab Width"] = w
	end

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
	PlayerName.Position = UDim2.new(0, 38, 0, -2)
	PlayerName.Size = UDim2.new(1, -38, 0, 16)
	PlayerName.TextTruncate = Enum.TextTruncate.AtEnd
	PlayerName.Parent = PlayerFooter

	-- Device + resolution line under the name. The resolution matters when
	-- reporting a layout problem: "Mobile 390x844" says far more than "Mobile".
	-- The sidebar is only ~58px wide on a phone, where even the player name
	-- truncates, so this line is desktop-only; the title-bar badge and the Info
	-- tab's Device Info section cover the compact layout.
	local DeviceLine = Instance.new("TextLabel")
	DeviceLine.Name = "DeviceLine"
	DeviceLine.Font = Enum.Font.Gotham
	DeviceLine.Text = string.format("%s  %dx%d", DEVICE.Name, math.floor(DEVICE.Width), math.floor(DEVICE.Height))
	DeviceLine.TextColor3 = Color3.fromRGB(120, 120, 120)
	DeviceLine.TextSize = 9
	DeviceLine.TextXAlignment = Enum.TextXAlignment.Left
	DeviceLine.BackgroundTransparency = 1
	DeviceLine.Position = UDim2.new(0, 38, 0, 14)
	DeviceLine.Size = UDim2.new(1, -38, 0, 12)
	DeviceLine.TextTruncate = Enum.TextTruncate.AtEnd
	DeviceLine.Parent = PlayerFooter
	DeviceLine.Visible = not isCompact()

	local ScrollTab = Instance.new("ScrollingFrame")
	local UIListLayout = Instance.new("UIListLayout")

	-- Scrollable on every platform. AutomaticCanvasSize lets the layout drive
	-- the canvas, which is what makes touch panning reliable: a hand-maintained
	-- CanvasSize that is even 1px short leaves the frame with nothing to scroll.
	ScrollTab.CanvasSize = UDim2.new(0, 0, 0, 0)
	ScrollTab.AutomaticCanvasSize = Enum.AutomaticSize.Y
	ScrollTab.ScrollingDirection = Enum.ScrollingDirection.Y
	ScrollTab.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	ScrollTab.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 80)
	ScrollTab.ScrollBarThickness = isCompact() and 3 or 2
	ScrollTab.Active = true
	ScrollTab.ClipsDescendants = true
	ScrollTab.BackgroundTransparency = 0.999
	ScrollTab.Size = UDim2.new(1, 0, 1, -50)
	ScrollTab.Name = "ScrollTab"
	ScrollTab.Parent = LayersTab

	UIListLayout.Padding = UDim.new(0, 2)
	UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	UIListLayout.Parent = ScrollTab

	-- AutomaticCanvasSize handles the height; this only keeps the canvas width
	-- pinned to the frame so rows cannot scroll sideways.
	local function UpdateSize1()
		ScrollTab.CanvasSize = UDim2.new(0, 0, 0, 0)
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
	-- BH_RestingX/Y are stored as Position *scales* (see MakeDraggable), so they
	-- survive a viewport change instead of pinning the window to stale pixels.
	local function RestingPos()
		if not DropShadowHolder then return BASE_POS end
		local x = DropShadowHolder:GetAttribute("BH_RestingX")
		local y = DropShadowHolder:GetAttribute("BH_RestingY")
		if typeof(x) == "number" and typeof(y) == "number" then
			return UDim2.new(x, 0, y, 0)
		end
		return BASE_POS
	end

	-- Shrink a UDim2 size by a factor, keeping BOTH the scale and the offset
	-- part proportional. The default window size is scale-based (so it fits any
	-- screen) while a user-resized window is offset-based; tweening only the
	-- offset would collapse a scale-based window to zero.
	local function ShrunkSize(target, factor)
		return UDim2.new(
			target.X.Scale * factor, math.floor(target.X.Offset * factor),
			target.Y.Scale * factor, math.floor(target.Y.Offset * factor))
	end

	local function PlayOpen()
		if not DropShadowHolder then return end
		-- A list opened before the window was hidden belongs to a row the user
		-- cannot see; start from a clean state.
		pcall(function() GuiFunc.CloseDropdowns() end)
		CancelSizeTween()
		local target = RestingSize()
		DropShadowHolder.Visible = true
		-- The floating icon is the reopen affordance; hide it while the window is
		-- up so it never sits on top of the panel.
		if FloatIcon then FloatIcon.Visible = false end
		DropShadowHolder.AnchorPoint = Vector2.new(0.5, 0.5)
		DropShadowHolder.Position = RestingPos()
		DropShadowHolder.Size = ShrunkSize(target, 0.9)
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
			{ Size = ShrunkSize(target, 0.9) })
		SizeTween:Play()
		local thisTween = SizeTween
		SizeTween.Completed:Connect(function()
			if SizeTween ~= thisTween then return end   -- superseded by a new tween
			if not DropShadowHolder then return end
			DropShadowHolder.Visible = false
			DropShadowHolder.Size = target
			-- Bring the icon back so the window can be reopened.
			if FloatIcon then FloatIcon.Visible = true end
		end)
	end

	-- The icon exists from the start (the window opens closed-ish on a re-exec
	-- only after PlayOpen runs, so keep it hidden until then).
	BuildFloatIcon()
	if FloatIcon then
		FloatIcon.Visible = false
		GuiFunc.OnFloatClick = function()
			if DropShadowHolder and DropShadowHolder.Visible then
				PlayClose()
			else
				PlayOpen()
			end
		end
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

	-- Honour the size the script asked for, but never let it exceed the screen.
	-- The Soreya scripts pass Size = UDim2.fromOffset(600, 480); applying that
	-- verbatim on a 390x844 phone produced a window wider than the display,
	-- which is why the panel could not be resized or scrolled on mobile. A
	-- UDim2 that is already scale-based is left alone.
	local requested = GuiConfig.Size
	if typeof(requested) == "UDim2" then
		local wantW = requested.X.Offset
		local wantH = requested.Y.Offset
		if wantW > 0 or wantH > 0 then
			if wantW <= 0 then wantW = 600 end
			if wantH <= 0 then wantH = 480 end
			-- Only shrink to fit; a small screen gets a full-screen-ish panel.
			wantW = math.min(wantW, viewport.X * 0.94)
			wantH = math.min(wantH, viewport.Y * 0.92)
			-- Keep the requested size from collapsing below something usable.
			wantW = math.max(wantW, math.min(300, viewport.X * 0.9))
			wantH = math.max(wantH, math.min(220, viewport.Y * 0.9))
			DropShadowHolder.Size = UDim2.new(0, math.floor(wantW), 0, math.floor(wantH))
		end
	end
	BASE_SIZE = DropShadowHolder.Size

	-- Keep the window on screen when the viewport changes (phone rotation, a
	-- window resize, a device with a different resolution). Without this a panel
	-- sized for portrait can end up wider than the screen in landscape, with its
	-- resize grip off the edge and unreachable.
	do
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				local vp = camera.ViewportSize
				if vp.X <= 0 or vp.Y <= 0 then return end
				local absW = DropShadowHolder.AbsoluteSize.X
				local absH = DropShadowHolder.AbsoluteSize.Y
				local maxW = vp.X * 0.98
				local maxH = vp.Y * 0.98
				if absW > maxW or absH > maxH then
					local newW = math.min(absW, maxW)
					local newH = math.min(absH, maxH)
					DropShadowHolder.Size = UDim2.new(0, math.floor(newW), 0, math.floor(newH))
					-- Re-centre: the old position may now be off-screen.
					DropShadowHolder.Position = UDim2.new(0.5, 0, 0.5, 0)
					DropShadowHolder:SetAttribute("BH_RestingW", math.floor(newW))
					DropShadowHolder:SetAttribute("BH_RestingH", math.floor(newH))
					DropShadowHolder:SetAttribute("BH_RestingX", 0.5)
					DropShadowHolder:SetAttribute("BH_RestingY", 0.5)
					BASE_SIZE = DropShadowHolder.Size
				end

				-- Rotation changes the resolution the badge reports, so refresh
				-- the readout and re-classify (a 844x390 landscape phone is still
				-- a phone, but the numbers shown should match the screen).
				local recheck = DetectDevice()
				DEVICE.Width  = recheck.Width
				DEVICE.Height = recheck.Height
				DEVICE.Kind   = recheck.Kind
				DEVICE.Name   = recheck.Name
				DEVICE.Compact = recheck.Compact
				pcall(function()
					DeviceText.Text = recheck.Name
					-- The pill is sized from the label length, so a rename
					-- (Mobile <-> Tablet) has to re-measure it too.
					DeviceBadge.Size = UDim2.new(0, (isCompact() and 24 or 26) + (#recheck.Name * 6), 0, isCompact() and 18 or 20)
					-- Redraw the glyph: the device class can change (a small
					-- tablet reclassified as a phone), and the old frame tree
					-- must go or the two glyphs would overlap.
					local oldGlyph = DeviceIcon:FindFirstChild("DeviceGlyph")
					if oldGlyph then oldGlyph:Destroy() end
					MakeDeviceGlyph(DeviceIcon, recheck.Kind, Color3.fromRGB(215, 215, 215), 4)
					DeviceLine.Text = string.format(
						"%s  %dx%d", recheck.Name, math.floor(recheck.Width), math.floor(recheck.Height))
				end)
			end)
		end
	end

	-- Animate in on first launch too, so the window never pops into place.
	task.defer(PlayOpen)

	GuiFunc.__gui = BananaHubGui
	GuiFunc.__nameTab = NameTab
	GuiFunc.__pageLayout = LayersPageLayout
	GuiFunc.__window = GuiConfig
	GuiFunc.__main = Main
	GuiFunc.__device = DEVICE
	GuiFunc.__deviceBadge = DeviceBadge

	-- Only one dropdown list stays open at a time. Each entry is
	-- { Header = row, List = floating list, Close = fn, RowAt = fn,
	--   Apply = fn, PickStamp = fn, Reposition = fn }.
	local OpenDropdowns = {}

	-- Every list the library has created, open or not. A list may only be
	-- visible while it is in OpenDropdowns, which only a click on its own
	-- header can put it into. This sweep enforces that, so nothing else (a
	-- config load, a callback, a resize, a programmatic Set) can leave a list
	-- hanging open over the page.
	local AllDropdownLists = {}

	-- Every dropdown header, so the click shield can hand a click back to the
	-- header the player actually aimed at. Without this, switching from one
	-- open dropdown to another would take two clicks.
	local AllDropdownHeaders = {}

	-- Everything below is declared here and assigned a little further down,
	-- because the pieces refer to each other: the shield needs the header list,
	-- the header list needs the widget factory, and the close helper needs the
	-- shield. Declaring them up front keeps every reference a real upvalue
	-- instead of a nil global.
	local OverlayLayer
	local ClickShield
	local UpdateShield
	local pointInside
	local pointHit
	local inputPoints
	local headerEntryAt
	local shieldClick
	local closeAllDropdowns

	local function SweepDropdownsImpl()
		for _, list in ipairs(AllDropdownLists) do
			if list and list.Parent and list.Visible then
				local registered = false
				for _, entry in ipairs(OpenDropdowns) do
					if type(entry) == "table" and entry.List == list then
						registered = true
						break
					end
				end
				if not registered then list.Visible = false end
			end
		end
		UpdateShield()
	end

	closeAllDropdowns = function()
		-- Snapshot first: a list's Close also unregisters itself.
		local open = OpenDropdowns
		OpenDropdowns = {}
		for _, entry in ipairs(open) do
			if type(entry) == "table" and entry.Close then pcall(entry.Close) end
		end
		UpdateShield()
	end
	GuiFunc.CloseDropdowns = function() closeAllDropdowns() end
	-- Also reachable as a top-level call, so a script can close lists without
	-- knowing about GuiFunc.
	BananaHub.CloseDropdowns = function() closeAllDropdowns() end

	-- Floating layer for open dropdown lists. With ZIndexBehavior.Sibling a
	-- child of Main is always drawn above Main's other children, so a list that
	-- lives here escapes its row, its section and the scrolling frame instead of
	-- being clipped or painted over by later widgets.
	OverlayLayer = Instance.new("Frame")
	OverlayLayer.Name = "OverlayLayer"
	OverlayLayer.BackgroundTransparency = 1
	OverlayLayer.BorderSizePixel = 0
	OverlayLayer.Size = UDim2.new(1, 0, 1, 0)
	OverlayLayer.Active = false
	OverlayLayer.ZIndex = 500
	OverlayLayer.Parent = Main

	-- See-through click catcher, one ZIndex above the page and below the lists
	-- (501+). A TextButton is used rather than a Frame because only a GuiButton
	-- consumes the click that would otherwise fall through to the widget
	-- underneath the open list. It is fitted over the page area only, so the
	-- tab sidebar, the title bar and the footer keep working normally.
	ClickShield = Instance.new("TextButton")
	ClickShield.Name = "DropdownClickShield"
	ClickShield.Text = ""
	ClickShield.Active = true
	ClickShield.AutoButtonColor = false
	ClickShield.BackgroundTransparency = 1
	ClickShield.BorderSizePixel = 0
	ClickShield.Size = UDim2.new(0, 0, 0, 0)
	ClickShield.Position = UDim2.new(0, 0, 0, 0)
	ClickShield.ZIndex = 500
	ClickShield.Visible = false
	ClickShield.Parent = OverlayLayer

	pointInside = function(gui, x, y)
		if not gui or not gui.Visible then return false end
		local p, s = gui.AbsolutePosition, gui.AbsoluteSize
		return x >= p.X and x <= p.X + s.X
			and y >= p.Y and y <= p.Y + s.Y
	end

	-- True when any of the candidate points falls inside the widget.
	pointHit = function(gui, points)
		for _, p in ipairs(points) do
			if pointInside(gui, p[1], p[2]) then return true end
		end
		return false
	end

	-- Turn a raw input into the coordinate space AbsolutePosition lives in.
	-- GetMouseLocation and a touch's raw Position do not agree about the top-bar
	-- inset across clients, so both readings are offered and callers accept
	-- whichever one lands. That is cheaper and far more reliable than betting on
	-- one convention and having the whole hit test miss on some devices.
	inputPoints = function(input)
		local points = {}
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local loc = UserInputService:GetMouseLocation()
			points[1] = {loc.X, loc.Y}
		else
			local inset = GuiService:GetGuiInset()
			points[1] = {input.Position.X, input.Position.Y - inset.Y}
			points[2] = {input.Position.X, input.Position.Y}
		end
		return points
	end

	-- True only when the widget and every GuiObject ancestor up to Main are
	-- visible. A header on a tab that is not the current page is still a
	-- descendant of Main and still has coordinates, so position alone is not
	-- enough to know the player can actually see it. Folders in the chain (the
	-- tab pages live in one) have no Visible property, so they are skipped.
	local function onScreen(gui)
		local node = gui
		while node and node ~= Main do
			if node:IsA("GuiObject") and not node.Visible then return false end
			node = node.Parent
		end
		return node == Main
	end

	UpdateShield = function()
		if not ClickShield then return end
		-- Read the real state of the lists rather than the registry: the two are
		-- updated in a different order when a list opens or closes, and this way
		-- the answer is always correct.
		local anyOpen = false
		for _, list in ipairs(AllDropdownLists) do
			if list and list.Parent and list.Visible then
				anyOpen = true
				break
			end
		end

		if not anyOpen then
			ClickShield.Visible = false
			return
		end

		-- Cover the page area only. The tab sidebar, the title bar and the
		-- footer stay clickable: they are not under a list, and covering them
		-- would make tab switching take two clicks.
		local origin = OverlayLayer.AbsolutePosition
		local pos = Layers.AbsolutePosition
		local size = Layers.AbsoluteSize
		ClickShield.Position = UDim2.fromOffset(pos.X - origin.X, pos.Y - origin.Y)
		ClickShield.Size = UDim2.fromOffset(size.X, size.Y)
		ClickShield.Visible = true
	end

	-- Which dropdown header, if any, sits under one of these points. Only
	-- headers on the page the player is looking at count, so a stale header on
	-- a hidden tab can never answer for the visible one. Each record is
	-- { Frame = the row, Toggle = fn that opens or closes that one list }.
	headerEntryAt = function(points)
		local current = LayersPageLayout.CurrentPage
		for _, record in ipairs(AllDropdownHeaders) do
			local frame = record and record.Frame
			if frame and frame.Parent and frame:IsDescendantOf(Main)
				and onScreen(frame) and pointHit(frame, points)
				and (not current or frame:IsDescendantOf(current)) then
				return record
			end
		end
		return nil
	end

	-- The shield sits just under the lists and just over the page, so a pick can
	-- never be stolen by the Button underneath the open list. Its own click
	-- closes the list, and if the click was really aimed at a dropdown header
	-- that header is opened for the player, so moving from one dropdown to
	-- another stays a single click.
	shieldClick = function(points)
		-- A press on the open list belongs to the list, whatever the hit test
		-- says; closing here would swallow the pick.
		for _, entry in ipairs(OpenDropdowns) do
			if type(entry) == "table" and pointHit(entry.List, points) then return end
		end

		local record = headerEntryAt(points)
		local frame = record and record.Frame
		-- Clicking the header of the list that is already open means "close it",
		-- so that one is closed without being reopened.
		local wasOpen = false
		for _, entry in ipairs(OpenDropdowns) do
			if type(entry) == "table" and entry.Header == frame then
				wasOpen = true
				break
			end
		end
		closeAllDropdowns()
		if record and not wasOpen and type(record.Toggle) == "function" then
			pcall(record.Toggle)
		end
	end

	ClickShield.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		-- Press only. Handling the release too (Activated) would run this twice:
		-- the first pass would open a dropdown header and the second would
		-- immediately close it again.
		shieldClick(inputPoints(input))
	end)

	-- Press/release fallback for option rows. The row buttons normally handle
	-- their own clicks, but a click that lands on a widget drawn under the list
	-- used to be able to take the pick away. Recording the row on press and
	-- completing it on release makes the pick land either way, and the row's own
	-- handler and this one cannot both run: `PickStamp` changes as soon as a
	-- choice is applied.
	local PressedRow = nil
	local function rowEntryUnder(points)
		for _, entry in ipairs(OpenDropdowns) do
			if type(entry) == "table" and type(entry.RowAt) == "function" then
				local row = entry.RowAt(points)
				if row then return entry, row end
			end
		end
		return nil
	end

	UserInputService.InputBegan:Connect(function(input)
		if #OpenDropdowns == 0 then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end

		local points = inputPoints(input)

		-- Every new press starts a fresh pick attempt; a stale record from an
		-- earlier click must never be completed by this one's release.
		PressedRow = nil

		-- Pressing an option row: remember it (and its rectangle, which stays
		-- valid even if the list is closed before the release) and leave the
		-- list alone. The list owns this click.
		local entry, row = rowEntryUnder(points)
		if entry and row then
			local p, s = row.frame.AbsolutePosition, row.frame.AbsoluteSize
			PressedRow = {
				entry = entry,
				row = row,
				stamp = entry.PickStamp(),
				x1 = p.X,
				y1 = p.Y,
				x2 = p.X + s.X,
				y2 = p.Y + s.Y,
			}
			return
		end

		-- Never close on a press that lands on the open list itself (its padding,
		-- a scrollbar) - that click belongs to the list.
		for _, entry in ipairs(OpenDropdowns) do
			if type(entry) == "table" and pointHit(entry.List, points) then return end
		end

		-- Inside the page area the click shield (a real GuiButton over the page)
		-- decides what happens. Closing here as well would hide the list before
		-- the shield could hand the click to another dropdown header. If the
		-- shield is somehow not up, this path closes the list instead so a click
		-- on the page can never leave a list stranded.
		if ClickShield and ClickShield.Visible and pointHit(Layers, points) then
			return
		end

		-- Anywhere else - the sidebar, the title bar, the footer, the game -
		-- closes the list.
		closeAllDropdowns()
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local pressed = PressedRow
		PressedRow = nil
		if not pressed then return end

		-- Releasing somewhere other than the row that was pressed is a drag or
		-- a scroll, not a pick.
		local inside = false
		for _, p in ipairs(inputPoints(input)) do
			local x, y = p[1], p[2]
			if x >= pressed.x1 and x <= pressed.x2
				and y >= pressed.y1 and y <= pressed.y2 then
				inside = true
				break
			end
		end
		if not inside then return end

		-- The row's own button already applied this choice.
		if pressed.entry.PickStamp() ~= pressed.stamp then return end

		-- The list must not have been replaced by a different one in the
		-- meantime: applying a row from a list that is no longer the open one
		-- would change an unrelated dropdown.
		for _, entry in ipairs(OpenDropdowns) do
			if type(entry) == "table" and entry.List ~= pressed.entry.List
				and entry.List and entry.List.Visible then
				return
			end
		end

		pcall(pressed.entry.Apply, pressed.row, true)
	end)

	-- Moving or resizing the window would leave a list behind at its old spot.
	local function repositionAll()
		for _, entry in ipairs(OpenDropdowns) do
			if type(entry) == "table" and entry.List and entry.List.Visible
				and type(entry.Reposition) == "function" then
				pcall(entry.Reposition)
			end
		end
		UpdateShield()
	end

	-- Run the sweep whenever the window geometry changes: those are the moments
	-- a list could be left stranded (a resize, a window open/close). It never
	-- opens anything. The absolute-position hooks keep an open list glued to its
	-- row while the window is dragged, and are pcall'd because a signal that
	-- does not exist in this client must not take the whole UI down.
	DropShadowHolder:GetPropertyChangedSignal("Size"):Connect(SweepDropdownsImpl)
	DropShadowHolder:GetPropertyChangedSignal("Visible"):Connect(SweepDropdownsImpl)
	pcall(function() Main:GetPropertyChangedSignal("AbsoluteSize"):Connect(repositionAll) end)
	pcall(function() Main:GetPropertyChangedSignal("AbsolutePosition"):Connect(repositionAll) end)
	pcall(function() Layers:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() UpdateShield() end) end)

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
		ScrolLayers.ScrollBarThickness = isCompact() and 3 or 2
		ScrolLayers.ScrollingDirection = Enum.ScrollingDirection.Y
		ScrolLayers.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
		ScrolLayers.AutomaticCanvasSize = Enum.AutomaticSize.Y
		ScrolLayers.CanvasSize = UDim2.new(0, 0, 0, 0)
		ScrolLayers.Active = true
		ScrolLayers.ClipsDescendants = true
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
				-- Canvas height is driven by AutomaticCanvasSize (see where
				-- ScrolLayers is created). Clearing the canvas size keeps the
				-- automatic behaviour in charge; a hand-computed total used to
				-- go stale and left the page unable to scroll.
				ScrolLayers.CanvasSize = UDim2.new(0, 0, 0, 0)
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

				-- Show the number at the precision the step implies, then trim the
				-- padding, so a 0.7 reads as "0.7" (not "0.70000000000000" and not
				-- "0.70"). Steps like 0.05 keep both decimals.
				local function stepDecimals(s)
					if type(s) ~= "number" or s <= 0 then return 3 end
					for d = 0, 6 do
						local scaled = s * (10 ^ d)
						if math.abs(scaled - math.floor(scaled + 0.5)) < 1e-6 then return d end
					end
					return 3
				end
				local DEC = math.clamp(stepDecimals(step), 0, 4)
				local function fmt(n)
					local text = string.format("%." .. DEC .. "f", tonumber(n) or 0)
					if text:find("%.") then
						text = text:gsub("0+$", ""):gsub("%.$", "")
					end
					return text
				end

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
				SliderInput.Position = UDim2.new(1, -176, 0.5, 0)
				SliderInput.Size = UDim2.new(0, 52, 0, 20)
				SliderInput.Name = "SliderInput"
				SliderInput.Parent = Slider

				UICorner16.CornerRadius = UDim.new(0, 2)
				UICorner16.Parent = SliderInput

				TextBox.Font = Enum.Font.GothamBold
				TextBox.Text = fmt(default)
				TextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
				TextBox.TextSize = 12
				TextBox.TextXAlignment = Enum.TextXAlignment.Center
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
					-- Snap away the float drift the multiply/divide leaves behind:
					-- 7 * 0.1 is 0.7000000000000001, and that value would both
					-- print badly and be handed to the feature callback.
					return tonumber(string.format("%.6f", Result)) or Result
				end

				function SliderFunc:Set(v, silent)
					v = math.clamp(Round(tonumber(v) or min, step), min, max)
					SliderFunc.Value = v
					TextBox.Text = fmt(v)
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
						TextBox.Text = fmt(SliderFunc.Value)
						return
					end
					SliderFunc:Set(TextBox.Text)
					TextBox.Text = fmt(SliderFunc.Value)
				end)

				if not locked then
					SliderFunc:Set(default, true)
				else
					SliderFunc.Value = default
					TextBox.Text = fmt(default)
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

				-- Register with the window so the sweep can force it shut if it
				-- is ever visible without a click having opened it.
				AllDropdownLists[#AllDropdownLists + 1] = OptionList

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
				-- row click handlers close the list after a pick.
				local closeList, openList

				-- A pick runs the widget's Set, which fires the feature and
				-- closes the list. `pickCount` stops the press/release fallback
				-- below from running the same choice twice: it is a counter, not
				-- a timestamp, so two deliveries in the same instant still differ.
				local pickCount = 0
				local function applyRow(row, force)
					if not row then return end
					-- The list closes on the first pick, so a second delivery of
					-- the same click (the row button's Activated plus the
					-- press/release fallback) finds it shut and does nothing.
					-- `force` is used by the fallback when its stamp proves
					-- nothing has been applied yet - the list may have been shut
					-- mid-press by something else, and the choice must still land.
					if not force and not OptionList.Visible then return end
					pickCount = pickCount + 1
					if multi then
						local list = DropdownFunc.Value or {}
						local at = table.find(list, row.value)
						if at then
							table.remove(list, at)
						else
							list[#list + 1] = row.value
						end
						DropdownFunc:Set(list)
					else
						DropdownFunc:Set(row.value)
					end
					-- Picking an option EXECUTES the choice, so the list closes
					-- every time - single or multi.
					closeList()
				end

				-- Which option row is under one of these points. Used by the
				-- window's press/release fallback so a pick still lands when the
				-- row's own button never sees the click.
				local function rowAt(points)
					if not OptionList.Visible then return nil end
					if not pointHit(OptionList, points) then return nil end
					for _, row in ipairs(rows) do
						if pointHit(row.frame, points) then return row end
					end
					return nil
				end

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

						-- Touch needs a taller target than a mouse. 26px rows are
						-- comfortable with a cursor and fiddly with a fingertip.
						local optionRowH = isCompact() and 38 or 26
						local rowFrame = Instance.new("Frame")
						local rowButton = Instance.new("TextButton")
						local rowLabel = Instance.new("TextLabel")

						rowFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
						rowFrame.BackgroundTransparency = 0.999
						rowFrame.BorderSizePixel = 0
						rowFrame.Size = UDim2.new(1, 0, 0, optionRowH)
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

						local rowRecord = {frame = rowFrame, label = rowLabel, value = value}
						rows[#rows + 1] = rowRecord

						rowButton.Activated:Connect(function()
							applyRow(rowRecord)
						end)
					end

					expandedHeight = math.min(#DropdownFunc.Options, isCompact() and 6 or 9) * (isCompact() and 38 or 26) + 8
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
					UpdateShield()
				end

				-- `userOpening` is set only by a real click on this row's header.
				-- Without it a list can never become visible, so nothing that runs
				-- while the UI is being built (scrolling, Refresh, a config load,
				-- a callback, a programmatic Set) can pop a list open on its own.
				local userOpening = false

				-- Reposition an already-open list under its row. Never makes a
				-- hidden list visible.
				local function reposition()
					-- Anchor the floating panel directly under its row, in the
					-- window overlay's coordinate space, and flip it above the row
					-- when there is not enough room below.
					local row = Dropdown.AbsolutePosition
					local origin = OverlayLayer.AbsolutePosition
					local rowH = Dropdown.AbsoluteSize.Y
					-- Never wider than the panel: on a narrow phone a long option
					-- label would otherwise push the list off the right edge.
					local width = math.clamp(
						Dropdown.AbsoluteSize.X - 20, 120,
						math.max(OverlayLayer.AbsoluteSize.X - 24, 120))
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
				end

				openList = function()
					-- Only a click on the header may open a list.
					if not userOpening then return end
					reposition()
					OptionList.CanvasSize = UDim2.new(0, 0, 0, 0)
					OptionList.Visible = true
					UpdateShield()
				end

				-- HARD GUARD. The instant this list becomes visible it must
				-- already be registered as click-opened, or it is hidden again.
				-- This is what makes "auto open" impossible: registration only
				-- happens inside the click handler below. The shield is refreshed
				-- on every change in either direction, because a script outside
				-- the library (the Soreya dropdown guard) can also hide a list by
				-- setting Visible directly, and a shield left up would block the
				-- whole page.
				OptionList:GetPropertyChangedSignal("Visible"):Connect(function()
					if not OptionList.Visible then
						UpdateShield()
						return
					end
					for _, entry in ipairs(OpenDropdowns) do
						if type(entry) == "table" and entry.List == OptionList then
							UpdateShield()
							return
						end
					end
					OptionList.Visible = false
					UpdateShield()
				end)

				-- One place that opens or closes this list, shared by the header's
				-- own click and by the window's click shield.
				local function toggleList()
					if locked then return end

					-- If THIS list is already open, the click closes it. Checking
					-- this first matters: the "close every other dropdown" pass
					-- below used to include this one, so the toggle re-opened it
					-- and an open list could never be closed.
					if OptionList.Visible then
						userOpening = false
						closeList()
						return
					end

					closeAllDropdowns()
					-- Register FIRST, then show: the visible-guard above only
					-- lets the list appear when its entry already exists.
					OpenDropdowns[#OpenDropdowns + 1] = {
						Header = Dropdown,
						List = OptionList,
						Close = closeList,
						Reposition = reposition,
						RowAt = rowAt,
						Apply = applyRow,
						PickStamp = function() return pickCount end,
					}
					userOpening = true
					openList()
					userOpening = false
				end

				DropdownButton.Activated:Connect(toggleList)

				-- The shield finds this header by position and calls Toggle, so a
				-- click on a second dropdown while one is open opens it at once.
				AllDropdownHeaders[#AllDropdownHeaders + 1] = {
					Frame = Dropdown,
					Toggle = toggleList,
				}

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

					-- Any value change closes the list, including programmatic
					-- ones (a feature calling dd:Set / dd:SetValue). Executing a
					-- choice should never leave the panel open over the page.
					if OptionList.Visible then closeList() end

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
					-- Never re-open a closed list here. Refresh is called while a
					-- feature runs (e.g. "Refresh Players"), and re-opening the
					-- list would pop it back over the page for no reason.
				end

				-- Public: let the feature scripts close every open list after
				-- they finish executing, without reaching into library internals.
				function DropdownFunc:Close()
					closeList()
				end

				buildRows()

				-- Scrolling the page moves the row, so an OPEN list is re-anchored
				-- under it; if the row leaves the viewport the list closes. This
				-- only ever moves or closes a list that is already visible - it
				-- must never open one, or scrolling would pop every dropdown open.
				ScrolLayers:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
					if not OptionList.Visible then return end
					local rowY = Dropdown.AbsolutePosition.Y - ScrolLayers.AbsolutePosition.Y
					if rowY < 0 or rowY > ScrolLayers.AbsoluteSize.Y then
						closeList()
					else
						reposition()
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

	-- Let a script show/hide the floating icon at runtime (the Soreya scripts
	-- keep it on; a script that wants a hotkey-only window can turn it off).
	function GuiFunc:SetFloatIcon(v)
		if not FloatIcon then return end
		FloatIcon.Visible = v ~= false
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
BananaHub.BuildMarker = "BANANAHUB_BUILD_BLACK_15"

return BananaHub
