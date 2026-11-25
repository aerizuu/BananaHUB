-- ==== Atomic Cdid : NPC / player detector + teleporter (WindUI) ====

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()

-- ---------- detection ----------
local G = {}
local Detect = false

local function GetAtomicObjects()
    local out = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and not obj.Anchored then
            local name = obj:GetAttribute("Name") or obj.Name
            if type(name) == "string" and name:lower():find("atomic") then
                out[#out + 1] = {
                    Name = name,
                    Position = obj.Position,
                    IsNPC = obj:FindFirstChildWhichIsA("Humanoid") ~= nil,
                    Class = obj.ClassName,
                    Part = obj,
                }
            end
        end
    end
    return out
end

local function Refresh() G = GetAtomicObjects() end

local function RootPart()
    local ch = LocalPlayer.Character
    return ch and ch:FindFirstChild("HumanoidRootPart") or nil
end

local function TeleportTo(pos)
    local root = RootPart()
    if not root or not pos then return false end
    local ch = root.Parent
    pcall(function()
        if ch then ch:PivotTo(CFrame.new(pos + Vector3.new(0, 3, 0))) end
        root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
        root.AssemblyLinearVelocity = Vector3.zero
    end)
    return true
end

local function NearestAtomic()
    Refresh()
    local root = RootPart()
    local best, bestD = nil, math.huge
    for _, v in ipairs(G) do
        local d = root and (v.Position - root.Position).Magnitude or 0
        if v.IsNPC and d < bestD then best, bestD = v, d end
    end
    if not best then
        for _, v in ipairs(G) do
            local d = root and (v.Position - root.Position).Magnitude or 0
            if d < bestD then best, bestD = v, d end
        end
    end
    return best
end

local function TeleportToNPC()
    local t = NearestAtomic()
    if not t then return false end
    return TeleportTo(t.Position)
end

-- ---------- player list ----------
local function PlayerNames()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then list[#list + 1] = p.Name end
    end
    return list
end

local function FindPlayer(name)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name == name then return p end
    end
    return nil
end

local function TeleportToPlayer(name)
    local p = FindPlayer(name)
    if not p then return false, "player not found" end
    local ch = p.Character
    local root = ch and ch:FindFirstChild("HumanoidRootPart")
    if not root then return false, "no character" end
    return TeleportTo(root.Position)
end

-- ---------- UI ----------
local Window = WindUI:CreateWindow({
    Title = "Atomic Cdid",
    Folder = "AtomicCdid",
    Icon = "crosshair",
    NewElements = true,
})

local MainTab = Window:Tab({ Title = "Main", Icon = "radar" })
local PlayerTab = Window:Tab({ Title = "Players", Icon = "users" })

local MainSec = MainTab:Section({ Title = "Detect" })

MainSec:Toggle({
    Title = "Detect NPC In Map",
    Desc = "Scans workspace for Atomic-tagged parts",
    Value = false,
    Callback = function(on)
        Detect = on == true
        if Detect then
            local n = 0
            Refresh()
            for _, v in ipairs(G) do if v.IsNPC then n = n + 1 end end
            WindUI:Notify({
                Title = "Detect NPC",
                Content = n .. " NPC(s) found in map",
                Icon = "search",
            })
        end
    end,
})

MainSec:Space()

MainSec:Button({
    Title = "Teleport To Nearest Atomic NPC",
    Justify = "Center",
    Callback = function()
        local ok, err = TeleportToNPC()
        if not ok then
            WindUI:Notify({ Title = "Teleport", Content = tostring(err or "no NPC found"), Icon = "triangle-alert" })
        end
    end,
})

MainSec:Space()

MainSec:Button({
    Title = "Scan Now",
    Justify = "Center",
    Callback = function()
        Refresh()
        local n = #G
        WindUI:Notify({ Title = "Scan", Content = n .. " Atomic object(s) found", Icon = "search" })
    end,
})

local PlayerSec = PlayerTab:Section({ Title = "Teleport To Player" })

local Selected = nil

local Dropdown
Dropdown = PlayerSec:Dropdown({
    Title = "Select Player",
    Values = PlayerNames(),
    Value = nil,
    Callback = function(v) Selected = v end,
})

PlayerSec:Space()

PlayerSec:Button({
    Title = "Refresh Player List",
    Justify = "Center",
    Callback = function()
        Dropdown:Refresh(PlayerNames())
        WindUI:Notify({ Title = "Players", Content = "List refreshed", Icon = "refresh-cw" })
    end,
})

PlayerSec:Space()

PlayerSec:Button({
    Title = "Teleport To Selected Player",
    Justify = "Center",
    Callback = function()
        if not Selected then
            WindUI:Notify({ Title = "Teleport", Content = "No player selected", Icon = "triangle-alert" })
            return
        end
        local ok, err = TeleportToPlayer(Selected)
        if not ok then
            WindUI:Notify({ Title = "Teleport", Content = tostring(err), Icon = "triangle-alert" })
        end
    end,
})

-- ---------- auto teleport loop ----------
task.spawn(function()
    while task.wait(1) do
        if Detect and RootPart() then
            TeleportToNPC()
        end
    end
end)

-- ---------- module ----------
local M = {
    G = G,
    GetAtomicObjects = GetAtomicObjects,
    Refresh = Refresh,
    GetFirst = function() Refresh(); return G[1] end,
    TeleportToNPC = TeleportToNPC,
    TeleportToPlayer = TeleportToPlayer,
    SetDetect = function(on) Detect = on == true end,
    Window = Window,
}

_G.AtomicCdid = M
return M
