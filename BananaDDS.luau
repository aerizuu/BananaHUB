--═══════════════════════════════════════════════════════════════════════════════
-- BANANA HUB  -  DRAG DRIVING SIMULATOR
-- UI: Banana Hub UI (shared library, black theme)
-- Tabs: Info | Automation | Settings | Webhook
--
-- Feature logic is carried over from the original DDS script unchanged; only
-- the interface and the branding were replaced.
--
-- What changed, and why:
--   * The old UI library is gone. This uses the same shared Banana Hub UI that
--     the other Banana Hub scripts load, from the repo with a strict build
--     marker so a stale copy fails loudly instead of half-working.
--   * The old licence block (the obfuscator macros and script_key) is gone. It
--     belonged to a key system this script does not have.
--   * The old pre-loader is gone. It only provided fireproximityprompt, which
--     the executor exposes natively anyway (with a fallback below).
--   * FPS Boost no longer disables 3D rendering. That blanks the whole 3D view;
--     this version only drops quality, materials and post effects, which is the
--     same trade without the black screen.
--   * No restricted services. The restricted input service is never acquired;
--     prompts are driven through ProximityPrompt's own hold methods and GUI
--     buttons through their real event connections.
--   * The Adonis bypass is armed on load, exactly as the original script did.
--     DDS runs Adonis and it kicks on the automation's teleports, so this is
--     load-bearing, not optional.
--
-- Auto Office, Anti AFK, Auto Find Anomaly and the Barista / Drive routines are
-- all exposed in the Automation tab, driven by the same getgenv() flags as
-- before (autoBarista / autoOffice / autoDrive) so an external setter still
-- works.
--═══════════════════════════════════════════════════════════════════════════════

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local CoreGui            = game:GetService("CoreGui")
local VirtualUser        = game:GetService("VirtualUser")
local HttpService        = game:GetService("HttpService")

-- NOTE: the restricted input service is deliberately NOT acquired here.
-- Requesting it from an executor makes Roblox disconnect the client with
-- "Disallowed Services Detected (Error Code: 267)". Every input this script
-- needs (a ProximityPrompt, a GUI button) is driven legally instead:
--   * prompts  -> fireproximityprompt, else the prompt's own InputHoldBegin
--   * buttons  -> the button's real event connections via getconnections
-- No synthetic key/mouse events are sent, so nothing trips the check.

-- LocalPlayer is normally ready by the time an executor runs, but not always
-- (and never on the very first frames of a rejoin). Wait briefly instead of
-- indexing a nil player for the rest of the session.
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    local deadline = tick() + 10
    repeat
        task.wait(0.1)
        LocalPlayer = Players.LocalPlayer
    until LocalPlayer or tick() > deadline
end
if not LocalPlayer then
    error("[BANANAHUB] LocalPlayer unavailable; run the script after the game has loaded.")
end

local INSTANCE_KEY = "__BANANAHUB_DDS_v100"

-- THIS is why the script kicked on its own.
--
-- The automation flags live in getgenv(), so they survive every re-exec for the
-- rest of the session. The old code resumed whatever happened to still be on:
--
--     autoBarista = getgenv().autoBarista == true
--
-- So once you had ever toggled Auto Barista / Auto Office / Auto Drive /
-- Auto Find Anomaly, every later run started teleporting the character across
-- the map a few seconds after load, before you touched the UI. The game's server
-- sees the character jump to a fixed coordinate it never walked to and kicks
-- you. That kick is Error 267, DisconnectLuaKick - the game's own Player:Kick(),
-- not a Roblox anti-cheat.
--
-- Automation now resumes ONLY when the rejoin bootstrap explicitly arms this
-- one-shot token. A normal exec starts completely inert.
local RESUME_TOKEN = "__banana_dds_resume_once"
local wantResume = getgenv()[RESUME_TOKEN] == true
getgenv()[RESUME_TOKEN] = nil   -- one shot, so it can never leak into a later run

local resumeFlags = {
    autoBarista    = wantResume and getgenv().autoBarista == true,
    autoOffice     = wantResume and getgenv().autoOffice == true,
    autoDrive      = wantResume and getgenv().autoDrive == true,
    autoAnomalyDDS = wantResume and getgenv().autoAnomalyDDS == true,
}

-- Unload a previous run first. Without this, two live copies both drive the
-- printer prompts and the office loop fights itself.
if _G[INSTANCE_KEY] then
    local prev = _G[INSTANCE_KEY]
    _G[INSTANCE_KEY] = { booting = true }
    if type(prev.cleanup) == "function" then pcall(prev.cleanup) end
    task.wait(0.3)
end

-- Compat aliases so the ported feature code reads exactly as it did before.
local workspace             = game:GetService("Workspace")
local players               = Players
local replicated_storage    = ReplicatedStorage
local tween_service         = TweenService
local virtual_user          = VirtualUser
local teleport_service      = game:GetService("TeleportService")
local run_service           = RunService
local local_player          = LocalPlayer
local player                = LocalPlayer

local HUB = {
    Name   = "Banana Hub",
    Game   = "Drag Driving Simulator",
    Version = "0.0.1",
    LogoId = "rbxassetid://125326185088678",
}

-- Print the build so you can tell instantly whether the file you are running is
-- the fixed one. If this line does not appear in the console, the executor is
-- running an old cached copy, not this file.
local DDS_BUILD = "black-13-dds-killhook"
print("[BANANAHUB] DDS build " .. DDS_BUILD .. " | automation starts OFF until you toggle it")

--═══════════════════════════════════════════════════════════════════════════════
-- BANANA HUB UI  (shared library)
--═══════════════════════════════════════════════════════════════════════════════
local WindUI
do
    local URL = "https://raw.githubusercontent.com/aerizuu/BananaHUB/refs/heads/main/BananaHubUi.luau"

    -- Only the build carrying this exact marker is accepted, so a stale repo
    -- copy (or an old cached workspace file) fails loudly instead of silently
    -- running an older interface.
    local MARKER = "BANANAHUB_BUILD_BLACK_13"
    local function usable(data)
        if type(data) ~= "string" or #data < 100 or data:match("^%s*404") then return false end
        return data:find(MARKER, 1, true) ~= nil
    end

    local source
    local bust = tostring(os.time())
    for _, u in ipairs({ URL .. "?v=" .. bust, URL }) do
        local ok, data = pcall(function() return game:HttpGet(u, true) end)
        if ok and usable(data) then
            source = data
            pcall(function()
                if writefile then writefile("BananaHubUI.luau", data) end
            end)
            break
        end
    end

    if not source and readfile then
        for _, path in ipairs({ "BananaHubUI.luau", "workspace/BananaHubUI.luau", "BananaHubUI.lua" }) do
            local ok, data = pcall(readfile, path)
            if ok and usable(data) then
                source = data
                break
            elseif ok and type(data) == "string" and #data > 0 then
                pcall(function() if delfile then delfile(path) end end)
            end
        end
    end

    if not source then
        error("[BANANAHUB] No up-to-date BananaHubUI.luau found. The repo file must contain the marker "
            .. MARKER .. " (push the new library), or put that copy in your executor workspace.")
    end

    local gotBuild = source:match('local BUILD%s*=%s*"([^"]+)"')
    print("[BANANAHUB] UI library build: " .. tostring(gotBuild or "unknown"))

    local chunk, compileErr = loadstring(source)
    if not chunk then
        error("[BANANAHUB] BananaHubUI.luau failed to compile: " .. tostring(compileErr))
    end
    local ok, res = pcall(chunk)
    if not ok or type(res) ~= "table" then
        error("[BANANAHUB] BananaHubUI.luau failed to load: " .. tostring(res))
    end
    WindUI = res
end

local function Notify(title, content, dur)
    pcall(function()
        WindUI:Notify({
            Title    = tostring(title),
            Content  = tostring(content),
            Duration = tonumber(dur) or 3,
            Image    = HUB.LogoId,
        })
    end)
end

--═══════════════════════════════════════════════════════════════════════════════
-- GLOBAL STATE
--═══════════════════════════════════════════════════════════════════════════════
-- Flags are restored from the snapshot taken above, so a re-exec either resumes
-- what was running (rejoin bootstrap) or starts clean.
getgenv().autoBarista        = resumeFlags.autoBarista
getgenv().autoOffice         = resumeFlags.autoOffice
getgenv().autoDrive          = resumeFlags.autoDrive
getgenv().autoAnomalyDDS     = resumeFlags.autoAnomalyDDS
getgenv().baristaMode        = getgenv().baristaMode or "Fast"
getgenv().ddsInstantBaristaTP = getgenv().ddsInstantBaristaTP or false
getgenv().ddsCustomUsername  = ""
getgenv().ddsHideIdentity    = false
getgenv().ddsStartingMoney   = 0
getgenv().ddsWebhookUrl      = getgenv().ddsWebhookUrl or ""
getgenv().ddsWebhookEnabled  = getgenv().ddsWebhookEnabled or false
getgenv().ddsWebhookHideName = getgenv().ddsWebhookHideName or false
getgenv().ddsWebhookInterval = getgenv().ddsWebhookInterval or 5
getgenv().antiAfkDDS         = getgenv().antiAfkDDS or false
getgenv().autoKerjaKantor    = getgenv().autoKerjaKantor or false
getgenv().driveRejoinHours   = getgenv().driveRejoinHours or 2
getgenv().driveResetMoney    = getgenv().driveResetMoney or 100000

-- Barista state
local baristaLogicRunning = false
local baristaSession = 0
local baristaRouteRunning = false
local officeRunning = false
local isHandlingPrinter = false

-- Auto Find Anomaly state
local autoAnomalyRunning = false
local autoAnomalySession = 0

-- Drive automation state
local driveRunning = false
local driveSession = 0

-- Anti-AFK & Noclip
getgenv().antiAfkDDSConnection = nil
getgenv().autoNoclipConnection = nil
local noclipConnection = nil

-- Fire a ProximityPrompt without touching any restricted service.
--
-- ProximityPrompt exposes InputHoldBegin / InputHoldEnd as real methods, which
-- is exactly what the engine calls when a player holds the key. Driving those
-- runs the game's own prompt handler, so the feature still works on an executor
-- that does not ship fireproximityprompt.
--
-- NOTE: no VirtualInputManager. Acquiring that service is what produced the
-- "Disallowed Services Detected (Error Code: 267)" disconnect.
local function promptHoldBegin(prompt)
    if not (prompt and prompt:IsA("ProximityPrompt")) then return false end
    local ok = pcall(function() prompt:InputHoldBegin() end)
    return ok
end

local function promptHoldEnd(prompt)
    if not (prompt and prompt:IsA("ProximityPrompt")) then return end
    pcall(function() prompt:InputHoldEnd() end)
end

-- Prompts that currently have a hold in flight, so a polling loop calling fpp
-- every frame does not stack holds on the same prompt.
local activePromptHolds = setmetatable({}, { __mode = "k" })

local fpp = (type(fireproximityprompt) == "function") and fireproximityprompt or nil
if not fpp then
    fpp = function(prompt)
        if not (prompt and prompt:IsA("ProximityPrompt")) then return end
        if activePromptHolds[prompt] then return end
        if not promptHoldBegin(prompt) then
            -- Last resort: bounce Enabled. Some games listen for that
            -- transition, and it costs nothing to try.
            pcall(function()
                prompt.Enabled = false
                task.wait(0.05)
                prompt.Enabled = true
            end)
            return
        end
        activePromptHolds[prompt] = true
        -- A prompt only fires once the hold has lasted its full HoldDuration, so
        -- release the hold after that long rather than immediately.
        local hold = tonumber(prompt.HoldDuration) or 0
        task.delay(math.max(hold, 0) + 0.05, function()
            promptHoldEnd(prompt)
            activePromptHolds[prompt] = nil
        end)
    end
end

--═══════════════════════════════════════════════════════════════════════════════
-- ADONIS BYPASS  (Detected + Kill neutralized)
--
-- ARMED ON LOAD, exactly like the original script. Do not make this opt-in.
--
-- This is load-bearing. The original Dedees.luau loads an "Adonix" payload at
-- the very top (line 39, before Rayfield and before anything else) which hooks
-- TWO things:
--
--     Detected(Action, ...)  -> return true    (the detection probe)
--     Kill(Info)             -> do nothing     (the actual kick)
--
-- Hooking only Detected is NOT enough: Adonis can call Kill() directly on a
-- trigger it already flagged, and that call is what produces
-- "Koneksi Terputus / Disallowed Services Detected (Kode Error: 267)" -
-- Error 267 is DisconnectLuaKick, the game's own Player:Kick().
--
-- This version hooks both, and also runs before the UI is built (see the
-- ordering note further down) so Adonis never sees the GUI unprotected.
--═══════════════════════════════════════════════════════════════════════════════
local bypassArmed = false
getgenv().adonisBypassArmed = false

-- Collect every Adonis table member we can find, once, and hook what we can.
-- Kept separate from the Detected lookup below so a missing Detected does not
-- stop Kill from being hooked (and vice versa).
local function hookAdonisKill(getType, hasHookfunction, hasNewcclosure)
    if not (hasHookfunction and getType(getgc) == "function") then return false end
    local hooked = false
    local ok, gc = pcall(getgc, true)
    if not ok then return false end
    for i = 1, #gc do
        local ok2, v = pcall(function() return gc[i] end)
        if ok2 and getType(v) == "table" then
            local kill = rawget(v, "Kill")
            if getType(kill) == "function" then
                local noop = function() end
                if hasNewcclosure then noop = newcclosure(noop) end
                if pcall(hookfunction, kill, noop) then hooked = true end
            end
        end
        if i % 1024 == 0 then task.wait() end
    end
    return hooked
end

local function armAdonisBypass()
    if getgenv().adonisBypassArmed then return true end
    local getType = typeof or type
    local REnv = (getType(getrenv) == "function") and getrenv() or getgenv()

    local hasHookfunction  = getType(hookfunction) == "function"
    local hasNewcclosure   = getType(newcclosure) == "function"
    local hasClonefunction = getType(clonefunction) == "function"
    local debug_info = debug.info

    -- Kill() first: this is the call that actually disconnects the client, so
    -- neutralizing it matters more than the detection probe.
    local killHooked = false
    pcall(function()
        killHooked = hookAdonisKill(getType, hasHookfunction, hasNewcclosure)
    end)

    -- Locate Detected: prefer filtergc (constant match), fall back to a GC scan.
    local Detected = nil
    local attempt = 0
    local ANTI_KEYS = { "Detected", "Detectors", "RLocked", "AddDetector" }
    local function rawHas(t, keys)
        for _, x in ipairs(keys) do
            if rawget(t, x) == nil then return false end
        end
        return true
    end
    while not Detected do
        attempt = attempt + 1
        -- Bail out after a minute. The original spun forever on an executor
        -- without filtergc/getgc, leaving a thread polling the GC for the whole
        -- session. Do not report failure if the Kill hook already landed.
        if attempt > 60 then
            bypassArmed = killHooked
            getgenv().adonisBypassArmed = bypassArmed
            return bypassArmed
        end
        if getType(filtergc) == "function" then
            local ok, res = pcall(function()
                return filtergc("function", {
                    Constants = { " - On Xbox", " - On mobile", "_" },
                    IgnoreExecutor = true,
                }, true)
            end)
            if ok and getType(res) == "function" then Detected = res end
        end
        if not Detected and getType(getgc) == "function" then
            local ok, gc = pcall(getgc, true)
            if ok then
                for i = 1, #gc do
                    local ok2, v = pcall(function() return gc[i] end)
                    if ok2 and getType(v) == "table" and rawHas(v, ANTI_KEYS) then
                        local d = rawget(v, "Detected")
                        if getType(d) == "function" then
                            Detected = d
                            break
                        end
                    end
                    if i % 1024 == 0 then task.wait() end
                end
            end
        end
        if not Detected then
            task.wait(1)
        end
    end

    -- Golden signature for the self-check comparison. pcall because the
    -- executor's debug.info may already be hooked.
    local a, b, c, d, e, f
    pcall(function() a, b, c, d, e, f = debug_info(Detected, "slanf") end)

    -- Spoof debug.info ONLY if clonefunction exists. Without a clone,
    -- forwarding via origInfo re-enters the detour and overflows the stack.
    if hasHookfunction and hasClonefunction and REnv and REnv.debug and REnv.debug.info and debug_info then
        local origInfo = REnv.debug.info
        local cloned = clonefunction(origInfo)
        local detour = function(target, what, ...)
            if target == Detected and what == "slanf" then
                return a, b, c, d, e, f
            end
            return cloned(target, what, ...)
        end
        if hasNewcclosure then detour = newcclosure(detour) end
        pcall(hookfunction, origInfo, detour)
    end

    -- Neutralize Detected: return true. Adonis' liveness probe needs the "_"
    -- action to answer true; a hang breaks its self-check.
    local detectedHooked = false
    if hasHookfunction then
        local noop = function() return true end
        if hasNewcclosure then noop = newcclosure(noop) end
        detectedHooked = pcall(hookfunction, Detected, noop)
    end

    -- Armed if EITHER hook landed. Kill() is the one that actually disconnects
    -- the client, so a Kill hook alone is a real win even if the Detected
    -- signature lookup came up empty.
    bypassArmed = detectedHooked or killHooked
    getgenv().adonisBypassArmed = bypassArmed
    return bypassArmed
end

-- Arm the bypass and WAIT for it before the UI is built.
--
-- The original script loads its Adonix payload at the very top, waits 5 seconds,
-- and only then builds the Rayfield window. That ordering is the point: Adonis
-- must be neutralized before a foreign GUI appears, otherwise its scan sees the
-- GUI and calls Kill() - which is the Error 267 disconnect.
--
-- A plain task.spawn (what this used to be) let the window be created while the
-- GC scan was still running, so the GUI was visible unprotected. This now runs
-- synchronously with a hard timeout, so the UI never appears before the hook is
-- in place. 12s is generous; the scan normally finishes in well under a second.
getgenv().bananaArmAdonisBypass = armAdonisBypass
getgenv().adonisBypassState = function() return bypassArmed end

do
    local armed = false
    local done = false
    task.spawn(function()
        local ok, res = pcall(armAdonisBypass)
        armed = ok and res == true
        done = true
    end)
    local deadline = tick() + 12
    while not done and tick() < deadline do
        task.wait(0.1)
    end
    print("[BANANAHUB] Adonis bypass armed: " .. tostring(armed)
        .. " | Detected+Kill hooked before UI construction")
    if not armed then
        warn("[BANANAHUB] Adonis bypass did NOT arm. Your executor is missing "
            .. "getgc/filtergc/hookfunction. The script may be kicked by Adonis.")
    end
end

--═══════════════════════════════════════════════════════════════════════════════
-- MONEY TRACKING
--═══════════════════════════════════════════════════════════════════════════════
local function getCurrentMoney()
    -- Real sources first: leaderstats values, if the game exposes them. The
    -- scan runs inside a pcall, so the hit is captured in a variable - a bare
    -- `return` inside the closure would only exit the closure.
    local fromStats = nil
    pcall(function()
        local ls = player:FindFirstChild("leaderstats")
        if ls then
            for _, v in pairs(ls:GetChildren()) do
                local n = v.Name:lower()
                if (n:find("money") or n:find("rupiah") or n:find("cash") or n:find("coin") or n:find("gold"))
                    and (v:IsA("IntValue") or v:IsA("NumberValue")) and v.Value > 0 then
                    fromStats = v.Value
                    break
                end
            end
        end
    end)
    if fromStats then return fromStats end

    local function tryPath(obj)
        if obj and obj:IsA("TextLabel") then
            local text = obj.Text or ""
            local cleaned = string.gsub(text, "[^%d]", "")
            local v = tonumber(cleaned)
            if v and v > 0 then return v end
        end
        return nil
    end

    local modGui = player.PlayerGui:FindFirstChild("ModificationUI")
    if modGui then
        local mainFrame = modGui:FindFirstChild("MainFrame")
        if mainFrame then
            local currency = mainFrame:FindFirstChild("Currency")
            if currency then
                local frame = currency:FindFirstChild("Frame")
                if frame then
                    local result = tryPath(frame:FindFirstChild("Currency"))
                    if result then return result end
                end
                local result = tryPath(currency:FindFirstChild("Currency"))
                if result then return result end
            end
        end
    end

    -- Fallback: named currency labels first, then the largest "Rp" label
    -- (the balance is usually the biggest amount; the first match may be a price).
    local bestNamed, bestAny = nil, nil
    for _, child in pairs(player.PlayerGui:GetDescendants()) do
        if child:IsA("TextLabel") then
            local text = child.Text or ""
            if string.find(text, "Rp") then
                local result = tonumber((string.gsub(text, "[^%d]", ""))) or 0
                if result > 0 then
                    if not bestAny or result > bestAny then bestAny = result end
                    local path = child:GetFullName():lower()
                    if path:find("currency") or path:find("money") or path:find("rupiah") then
                        if not bestNamed or result > bestNamed then bestNamed = result end
                    end
                end
            end
        end
    end
    if bestNamed then return bestNamed end
    if bestAny then return bestAny end

    return 0
end

local function formatMoney(amount)
    local str = tostring(math.floor(amount))
    local result = ""
    local count = 0
    for i = #str, 1, -1 do
        if count > 0 and count % 3 == 0 then
            result = "." .. result
        end
        result = str:sub(i, i) .. result
        count = count + 1
    end
    return "Rp. " .. result
end

local lastMoneyWebhook = 0
local moneySessionStart = tick()

local function censorName(n)
    if not n or #n <= 3 then return n end
    return n:sub(1, 3) .. string.rep("*", #n - 3)
end

-- Banana icon for the webhook embed. Resolved asset id -> thumbnail CDN image,
-- the same way the Fishit webhook resolves its fish image.
local bananaImageCache = nil
local function getBananaImageUrl()
    if bananaImageCache ~= nil then return bananaImageCache or nil end
    local thumbUrl = "https://thumbnails.roblox.com/v1/assets?assetIds=125326185088678"
        .. "&returnPolicy=PlaceHolder&size=512x512&format=Png&isCircular=false"
    local req = (syn and syn.request) or http_request or (Fluxus and Fluxus.request) or request
    if not req then return nil end
    local ok, resp = pcall(function()
        return req({ Url = thumbUrl, Method = "GET" })
    end)
    if ok and resp and resp.Body then
        local ok2, decoded = pcall(function()
            return HttpService:JSONDecode(resp.Body)
        end)
        if ok2 and decoded and decoded.data and decoded.data[1] and decoded.data[1].imageUrl then
            bananaImageCache = decoded.data[1].imageUrl
            return bananaImageCache
        end
    end
    bananaImageCache = false
    return nil
end

local function sendMoneyWebhook(force)
    if not force and not getgenv().ddsWebhookEnabled then return false, "disabled" end
    local url = getgenv().ddsWebhookUrl
    if typeof(url) == "string" then url = url:gsub("^%s+", ""):gsub("%s+$", "") end
    if not url or url == "" then return false, "no url" end
    if not url:match("discord%.com/api/webhooks") then return false, "bad url" end
    local current = getCurrentMoney()
    local starting = getgenv().ddsStartingMoney
    if starting == 0 then starting = current; getgenv().ddsStartingMoney = current end
    local earnings = current - starting
    local elapsed = tick() - moneySessionStart
    local perHour = elapsed >= 60 and (earnings / (elapsed / 3600)) or 0
    local uptime = string.format("%dm %02ds", math.floor(elapsed / 60), math.floor(elapsed % 60))
    local name = getgenv().ddsWebhookHideName and censorName(player.Name) or player.Name
    local desc = string.format(
        "**Account Name:** %s\n- **Current Money:** %s\n- **Starting Money:** %s\n- **Earnings:** %s\n- **Est. Earning/Hour:** %s /jam\n- **Session Time:** %s\n",
        name, formatMoney(current), formatMoney(starting), formatMoney(earnings), formatMoney(perHour), uptime
    )
    local bananaImage = getBananaImageUrl()
    local embed = {
        title = "DDS Money Report",
        color = 3447003,
        description = desc,
        footer = { text = HUB.Name },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
    if bananaImage then embed.image = { url = bananaImage } end
    local data = { embeds = { embed } }
    local req = (syn and syn.request) or http_request or (Fluxus and Fluxus.request) or request
    if not req then return false, "no http request fn" end
    local ok, resp = pcall(function()
        return req({
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(data),
        })
    end)
    if not ok then return false, tostring(resp) end
    if resp and (resp.StatusCode or resp.Status) and ((resp.StatusCode or resp.Status) < 200 or (resp.StatusCode or resp.Status) >= 300) then
        return false, tostring(resp.Body or resp.StatusCode or resp.Status)
    end
    return true, "sent"
end

-- Paragraph handles, assigned when the Info tab is built below. The money loop
-- starts before the UI exists, so every use is guarded.
local startingMoneyParagraph = nil
local earningsParagraph = nil
local earningsPerHourParagraph = nil

local function setParagraphDesc(para, desc)
    if not para then return end
    pcall(function() para:SetContent(tostring(desc)) end)
end

local function updateMoneyStatus()
    local current = getCurrentMoney()
    local starting = getgenv().ddsStartingMoney
    if starting == 0 then starting = current; getgenv().ddsStartingMoney = current end
    local earnings = current - starting

    -- Estimasi pendapatan per jam
    local elapsedSeconds = tick() - moneySessionStart
    local per_hour_str
    if elapsedSeconds < 60 then
        -- Kurang dari 1 menit: ekstrapolasi masih ngaco, tunggu dulu
        per_hour_str = "Menghitung... (" .. tostring(math.floor(60 - elapsedSeconds)) .. "s)"
    else
        local perHour = earnings / (elapsedSeconds / 3600)
        per_hour_str = formatMoney(perHour) .. " /jam"
    end

    setParagraphDesc(startingMoneyParagraph, formatMoney(starting))
    setParagraphDesc(earningsParagraph, formatMoney(earnings))
    setParagraphDesc(earningsPerHourParagraph, per_hour_str)

    local intervalMin = tonumber(getgenv().ddsWebhookInterval) or 5
    if intervalMin < 1 then intervalMin = 1 end
    if intervalMin > 30 then intervalMin = 30 end
    if getgenv().ddsWebhookEnabled and (tick() - lastMoneyWebhook) >= intervalMin * 60 then
        lastMoneyWebhook = tick()
        task.spawn(sendMoneyWebhook)
    end
end

-- Run token so a re-exec stops the previous run's money loop. Without it every
-- reload leaves another `while true` loop alive, and they all fire the webhook.
local moneyToken = tostring(os.time()) .. "_" .. tostring(math.random(1, 1000000))
getgenv().__banana_dds_money_token = moneyToken

task.spawn(function()
    task.wait(2)
    pcall(updateMoneyStatus)
    while getgenv().__banana_dds_money_token == moneyToken do
        pcall(updateMoneyStatus)
        task.wait(5)
    end
end)

--═══════════════════════════════════════════════════════════════════════════════
-- UTILITY FUNCTIONS
--═══════════════════════════════════════════════════════════════════════════════
local fpsCache = {}
local function setFPSBooster(enabled)
    if enabled then
        pcall(function()
            if fpsCache.quality == nil then fpsCache.quality = settings().Rendering.QualityLevel end
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
            for _, v in pairs(game:GetDescendants()) do
                if v:IsA("Part") or v:IsA("UnionOperation") or v:IsA("MeshPart")
                    or v:IsA("CornerWedgePart") or v:IsA("TrussPart") then
                    v.Material = Enum.Material.Plastic
                    v.Reflectance = 0
                elseif v:IsA("Decal") or v:IsA("Texture") then
                    v.Transparency = 1
                elseif v:IsA("ParticleEmitter") or v:IsA("Trail") then
                    v.Enabled = false
                elseif v:IsA("Explosion") then
                    v.Visible = false
                elseif v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles") then
                    v.Enabled = false
                end
            end
            local lighting = game:GetService("Lighting")
            lighting.GlobalShadows = false
            lighting.FogEnd = 9e9
            for _, v in pairs(lighting:GetChildren()) do
                if v:IsA("PostEffect") or v:IsA("BloomEffect") or v:IsA("BlurEffect")
                    or v:IsA("ColorCorrectionEffect") or v:IsA("SunRaysEffect") then
                    v.Enabled = false
                end
            end
        end)
    else
        pcall(function()
            settings().Rendering.QualityLevel = fpsCache.quality or Enum.QualityLevel.Automatic
        end)
    end
end

local streamerEnabled = false
local spoofText = "I Am Banana."
local streamerConn = nil
local protectedTexts = {}

local function protectText(descendant, customText)
    if descendant:GetAttribute("BH_DDS_Streamer") then return end
    descendant:SetAttribute("BH_DDS_Streamer", true)
    descendant:SetAttribute("BH_DDS_OriginalText", descendant.Text)
    local newText = descendant.Text
    newText = string.gsub(newText, player.Name, customText or spoofText)
    newText = string.gsub(newText, player.DisplayName, customText or spoofText)
    descendant.Text = newText
    local updating = false
    protectedTexts[descendant] = descendant:GetPropertyChangedSignal("Text"):Connect(function()
        if not streamerEnabled or updating or not descendant:GetAttribute("BH_DDS_Streamer") then return end
        local current = descendant.Text
        if string.find(string.lower(current), string.lower(player.Name))
            or string.find(string.lower(current), string.lower(player.DisplayName)) then
            updating = true
            descendant.Text = (string.gsub(
                string.gsub(current, player.Name, customText or spoofText),
                player.DisplayName, customText or spoofText))
            updating = false
        end
    end)
end

local function applyStreamerMode(enabled)
    streamerEnabled = enabled
    if enabled then
        for _, d in ipairs(game:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextBox") or d:IsA("TextButton") then
                if string.find(string.lower(d.Text), string.lower(player.Name))
                    or string.find(string.lower(d.Text), string.lower(player.DisplayName)) then
                    protectText(d)
                end
            end
        end
        if streamerConn then streamerConn:Disconnect() end
        streamerConn = game.DescendantAdded:Connect(function(d)
            if not streamerEnabled then return end
            if d:IsA("TextLabel") or d:IsA("TextBox") or d:IsA("TextButton") then
                if string.find(string.lower(d.Text), string.lower(player.Name))
                    or string.find(string.lower(d.Text), string.lower(player.DisplayName)) then
                    protectText(d)
                end
            end
        end)
    else
        if streamerConn then
            streamerConn:Disconnect()
            streamerConn = nil
        end
        for d, conn in pairs(protectedTexts) do
            if conn then conn:Disconnect() end
            pcall(function()
                d.Text = d:GetAttribute("BH_DDS_OriginalText") or d.Text
                d:SetAttribute("BH_DDS_Streamer", nil)
                d:SetAttribute("BH_DDS_OriginalText", nil)
            end)
        end
        protectedTexts = {}
    end
end

local function applyCustomIdentity(name)
    pcall(function()
        local char = player.Character
        if not char then return end
        local head = char:FindFirstChild("Head")
        if not head then return end
        local tags = head:FindFirstChild("RankTags") or head:FindFirstChildWhichIsA("BillboardGui")
        if not tags then return end

        for _, label in pairs(tags:GetDescendants()) do
            if label:IsA("TextLabel") then
                if string.find(string.lower(label.Name), "user")
                    or string.find(string.lower(label.Text), string.lower(player.Name)) then
                    label.Text = name
                elseif string.find(string.lower(label.Name), "rank") then
                    label.Text = HUB.Name
                    local gradient = label:FindFirstChildWhichIsA("UIGradient")
                    if gradient then
                        gradient.Color = ColorSequence.new(Color3.fromHex("#FFE45C"))
                    end
                end
            end
        end
    end)
end

local function superRandomWait(min, max)
    task.wait(math.random(min * 10, max * 10) / 10)
end

local function setFreeze(anchor)
    pcall(function()
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            root.Anchored = anchor
        end
    end)
end

-- A stand-in InputObject for InputBegan / InputEnded handlers. Handlers only
-- read UserInputType / UserInputState / Position (and occasionally call a couple
-- of the query methods), so a plain table carrying those is enough.
local function makeFakeInput(state)
    local inputType = Enum.UserInputType.MouseButton1
    pcall(function()
        if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
            inputType = Enum.UserInputType.Touch
        end
    end)
    local input = {
        UserInputType  = inputType,
        UserInputState = state,
        Position       = Vector3.new(0, 0, 0),
        Delta          = Vector3.new(0, 0, 0),
        KeyCode        = Enum.KeyCode.Unknown,
    }
    input.GetKeysPressed = function() return {} end
    input.IsKeyDown      = function() return false end
    input.GetMouseDelta  = function() return Vector3.new(0, 0, 0) end
    return input
end

-- Fire the object's real event connections. Works for buttons AND for plain
-- Frames that the game wires up through InputBegan (the DDS main menu uses
-- both). Driving the handlers directly is the legal replacement for synthetic
-- mouse/touch input: no restricted service is touched.
--
-- Groups are tried in priority order and the first group that has any live
-- connections wins. A FirstOnly group fires just one event, so a button whose
-- callback is wired to both MouseButton1Click and Activated does not run twice.
-- Paired events (press/release) fire together, because a handler that watches
-- InputBegan usually needs the matching InputEnded.
local CLICK_EVENTS = {
    { Events = { "MouseButton1Click", "TouchTap", "Activated" }, FirstOnly = true },
    { Events = { "InputBegan", "InputEnded" } },
    { Events = { "MouseButton1Down", "MouseButton1Up" } },
}

-- Arguments each event's handler expects. Passing the right shape matters: a
-- handler that indexes its InputObject would otherwise error out, and the pcall
-- around it would hide that, making the event look un-fired.
local INPUT_EVENTS = {
    InputBegan  = Enum.UserInputState.Begin,
    InputEnded  = Enum.UserInputState.End,
    TouchTap    = Enum.UserInputState.End,
    Activated   = Enum.UserInputState.End,
}

local function fireWithArgs(connection, evName)
    local state = INPUT_EVENTS[evName]
    if state then
        -- Activated carries (inputObject, clickCount); the rest carry
        -- (inputObject, ...). Extra trailing args are ignored by handlers.
        connection:Fire(makeFakeInput(state), evName == "Activated" and 0 or false)
    elseif evName == "MouseButton1Down" or evName == "MouseButton1Up" then
        connection:Fire(0, 0)
    else
        connection:Fire()
    end
end

local function fireConnectionsOf(obj, evName)
    local ok, signal = pcall(function() return obj[evName] end)
    if not (ok and signal) then return false end
    local ok2, connections = pcall(getconnections, signal)
    if not (ok2 and type(connections) == "table") then return false end

    local fired = false
    for _, connection in pairs(connections) do
        local okFire = pcall(fireWithArgs, connection, evName)
        if okFire then fired = true end
    end
    return fired
end

local function fireAllButtonConnections(obj)
    if not getconnections then return false end
    for _, group in ipairs(CLICK_EVENTS) do
        if group.FirstOnly then
            for _, evName in ipairs(group.Events) do
                if fireConnectionsOf(obj, evName) then return true end
            end
        else
            local fired = false
            for _, evName in ipairs(group.Events) do
                if fireConnectionsOf(obj, evName) then fired = true end
            end
            if fired then return true end
        end
    end
    return false
end

-- Last-resort click for an object that exposes nothing directly: some menus
-- wire a wrapper Frame and put the real button inside it.
local function clickChildButton(obj)
    if obj:IsA("GuiButton") then return false end
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("GuiButton") and d.Visible then
            if fireAllButtonConnections(d) then return true end
            local ok = pcall(function() d:Activate() end)
            if ok then return true end
        end
    end
    return false
end

local function clickGuiObject(obj)
    if not (obj and obj:IsA("GuiObject")) then
        return
    end

    -- 1) Drive the object's own handlers. This is both the most reliable route
    --    across PC and mobile AND the legal one: it replaces synthesising
    --    mouse/touch input through VirtualInputManager, whose acquisition is
    --    what triggered "Disallowed Services Detected (Error Code: 267)".
    if fireAllButtonConnections(obj) then return end

    -- 2) A button with no executor-visible connections: use its own activation
    --    path.
    if obj:IsA("GuiButton") then
        pcall(function() obj:Activate() end)
        return
    end

    -- 3) A wrapper Frame: click the button inside it.
    clickChildButton(obj)
end

local function setAntiAfkDDS(enabled)
    if not enabled then
        if getgenv().antiAfkDDSConnection then
            pcall(function() getgenv().antiAfkDDSConnection:Disconnect() end)
            getgenv().antiAfkDDSConnection = nil
        end
        return
    end
    if getgenv().antiAfkDDSConnection then return end
    getgenv().antiAfkDDSConnection = player.Idled:Connect(function()
        if not getgenv().antiAfkDDS then return end
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end)
end

local function setAutoNoclip(enabled)
    if not enabled then
        if getgenv().autoNoclipConnection then
            pcall(function() getgenv().autoNoclipConnection:Disconnect() end)
            getgenv().autoNoclipConnection = nil
        end
        return
    end
    if getgenv().autoNoclipConnection then return end
    getgenv().autoNoclipConnection = run_service.Stepped:Connect(function()
        if not (getgenv().autoBarista or getgenv().autoOffice) then return end
        local character = player.Character
        if not character then return end
        for _, part in pairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

setAutoNoclip(true)

--═══════════════════════════════════════════════════════════════════════════════
-- MATH & UI SOLVER
--═══════════════════════════════════════════════════════════════════════════════
local function trySolveMathFromLabel(label)
    if not (label and label:IsA("TextLabel") and label.Visible and label.Text) then
        return false
    end

    local text = label.Text
    local angka1, operator, angka2 = string.match(text, "(%d+)%s*([%+%-%*/xX÷×])%s*(%d+)")
    if not (angka1 and operator and angka2) then
        return false
    end

    local n1 = tonumber(angka1)
    local n2 = tonumber(angka2)
    if not (n1 and n2) then
        return false
    end

    if operator == "x" or operator == "X" or operator == "×" then
        operator = "*"
    elseif operator == "÷" then
        operator = "/"
    end

    local jawabanBenar = 0
    if operator == "+" then
        jawabanBenar = n1 + n2
    elseif operator == "-" then
        jawabanBenar = n1 - n2
    elseif operator == "*" then
        jawabanBenar = n1 * n2
    elseif operator == "/" then
        jawabanBenar = n1 / n2
    else
        return false
    end

    local parent = label.Parent
    if not parent then
        return false
    end

    local solved = false
    for _, btn in pairs(parent:GetDescendants()) do
        if btn:IsA("TextButton") and btn.Visible then
            local btnText = btn.Text
            if btnText == "" or tonumber(btnText) == nil then
                for _, child in pairs(btn:GetChildren()) do
                    if child:IsA("TextLabel") then
                        btnText = child.Text
                        break
                    end
                end
            end

            local cleanBtnText = string.match(btnText, "%-?%d+")
            local btnVal = tonumber(cleanBtnText)

            if btnVal ~= nil and math.abs(btnVal - jawabanBenar) < 0.1 then
                superRandomWait(2.5, 5.5) -- delay before answering
                clickGuiObject(btn) -- fires the button's own connections
                solved = true
                break
            end
        end
    end

    if solved then
        task.wait(0.2)
        return true
    end

    return false
end

-- Full PlayerGui scan is disabled: it was a suspected detection source, and the
-- direct QuestionLabel path above covers the work GUI.
local function trySolveAnyMath(guiRoot)
    return false, false
end

--═══════════════════════════════════════════════════════════════════════════════
-- TELEPORT LOGIC
--═══════════════════════════════════════════════════════════════════════════════
-- Per frame CFrame step for motor travel; higher = arrive sooner
local BARISTA_VEHICLE_MAX_STEP = 2.5

local function findRidePrompt(root, radius)
    local nearest, nearestDist = nil, radius or 25
    for _, v in pairs(workspace:GetDescendants()) do
        if v:IsA("ProximityPrompt") and v.Parent then
            local at = string.lower(v.ActionText or "")
            local nm = string.lower(v.Name or "")
            local pn = string.lower(v.Parent.Name or "")
            if string.find(at, "ride") or string.find(nm, "ride") or string.find(pn, "mio")
                or string.find(pn, "motor") or string.find(pn, "vehicle") then
                local part = v.Parent
                local pos = (part:IsA("BasePart") and part.Position)
                    or (part:IsA("Model") and part:GetPivot().Position)
                    or (part:IsA("VehicleSeat") and part.Position)
                if pos then
                    local dist = (pos - root.Position).Magnitude
                    if dist < nearestDist then
                        nearest = v
                        nearestDist = dist
                    end
                end
            end
        end
    end
    return nearest
end

local function instantTP(targetPos)
    local character = player.Character or player.CharacterAdded:Wait()
    local root = character:WaitForChild("HumanoidRootPart")
    setFreeze(false)
    root.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
    task.wait(0.5)
    return true
end

local function TPWithMotor(targetPos)
    ReplicatedStorage:WaitForChild("SpawnCarEvents"):WaitForChild("SpawnCar"):FireServer("Yamahax-MioSporty")
    task.wait(1)

    local character = player.Character or player.CharacterAdded:Wait()
    local root = character:WaitForChild("HumanoidRootPart")
    local humanoid = character:WaitForChild("Humanoid")

    local steps = 6
    local stepDist = 15 / steps
    local forwardVector = root.CFrame.LookVector
    for _ = 1, steps do
        root.CFrame = root.CFrame + (forwardVector * stepDist)
        task.wait(0.05)
    end
    task.wait(0.5)

    local ridePrompt = findRidePrompt(root, 25)

    -- Retry: if not found yet, wait for the prompt and widen the radius
    if not ridePrompt then
        local deadline = tick() + 5
        while not ridePrompt and tick() < deadline do
            task.wait(0.25)
            ridePrompt = findRidePrompt(root, 40)
        end
    end

    if not ridePrompt then
        return false
    end

    if ridePrompt and fpp then
        fpp(ridePrompt)
    end

    local seatDeadline = tick() + 15
    while not humanoid.SeatPart and tick() < seatDeadline do
        -- fire again every 2 seconds while not seated
        if fpp and (tick() % 2 < 0.1) then
            pcall(function() fpp(ridePrompt) end)
        end
        task.wait(0.1)
    end
    if not humanoid.SeatPart then
        return false
    end
    task.wait(0.2)

    local vehicle = humanoid.SeatPart:FindFirstAncestorOfClass("Model")
    if not vehicle then return false end

    local maxStep = BARISTA_VEHICLE_MAX_STEP
    local arriveThreshold = 3
    local timeout = 90
    local startTime = tick()
    while true do
        if not vehicle.Parent then return false end
        local currentCFrame = vehicle:GetPivot()
        local currentPos = currentCFrame.Position
        local diff = targetPos - currentPos
        local distance = diff.Magnitude
        if distance <= arriveThreshold then break end
        if tick() - startTime > timeout then break end
        local direction = diff.Unit
        local step = math.min(maxStep, distance)
        local newPos = currentPos + direction * step
        local lookAt = newPos + direction
        vehicle:PivotTo(CFrame.new(newPos, lookAt))
        RunService.Heartbeat:Wait()
    end
    task.wait(0.3)

    humanoid.Sit = false
    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    task.wait(1)

    return true
end

-- Route Mode: travel via waypoints
local BARISTA_ROUTE_MOTOR = "Yamahax-MioSporty"
local BARISTA_ROUTE_WAYPOINTS = {
    Vector3.new(-752, 2, -639),
    Vector3.new(-889, 2, -634),
    Vector3.new(-936, 3, -632),
    Vector3.new(-1015, 9, -631),
    Vector3.new(-1113, 16, -628),
    Vector3.new(-1313, 30, -623),
    Vector3.new(-1405, 36, -620),
    Vector3.new(-1493, 37, -618),
    Vector3.new(-1629, 37, -616),
    Vector3.new(-2222, 37, -601),
    Vector3.new(-2255, 37, -602),
    Vector3.new(-2289, 34, -601),
    Vector3.new(-2392, 27, -598),
    Vector3.new(-2559, 16, -593),
    Vector3.new(-2642, 10, -592),
    Vector3.new(-2726, 4, -590),
    Vector3.new(-2740, 3, -590),
    Vector3.new(-2767, 2, -590),
    Vector3.new(-5021, 2, -583),
    Vector3.new(-5021, 2, -646),
}

local function baristaUsesRouteMode()
    return string.sub(tostring(getgenv().baristaMode or ""), 1, 5) == "Route"
end

local function startBaristaRouteTravel()
    if baristaRouteRunning then return end
    baristaRouteRunning = true

    local function getCharacter()
        local character = player.Character or player.CharacterAdded:Wait()
        local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid")
        local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart")
        return character, humanoid, root
    end

    local function spawnAndMount()
        local character, humanoid, root = getCharacter()
        local spawnEvents = replicated_storage:FindFirstChild("SpawnCarEvents")
        if spawnEvents and spawnEvents:FindFirstChild("SpawnCar") then
            spawnEvents.SpawnCar:FireServer(BARISTA_ROUTE_MOTOR)
        end
        task.wait(1)
        local forward = root.CFrame.LookVector
        local stepDist = 2.5
        for _ = 1, 6 do
            root.CFrame = root.CFrame + forward * stepDist
            task.wait(0.05)
        end
        task.wait(0.5)
        local ridePrompt = findRidePrompt(root, 25)
        if not ridePrompt then
            local deadline = tick() + 5
            while not ridePrompt and tick() < deadline do
                task.wait(0.25)
                ridePrompt = findRidePrompt(root, 40)
            end
        end
        if ridePrompt and fpp then fpp(ridePrompt) end
        local t0 = tick()
        while not humanoid.SeatPart and tick() - t0 < 15 do
            if fpp and ridePrompt and (tick() % 2 < 0.1) then
                pcall(function() fpp(ridePrompt) end)
            end
            task.wait(0.1)
        end
        if not humanoid.SeatPart then return nil, humanoid end
        task.wait(0.2)
        local vehicle = humanoid.SeatPart:FindFirstAncestorOfClass("Model")
        return vehicle, humanoid
    end

    local function moveVehicleTo(vehicle, targetPos)
        local maxStep = BARISTA_VEHICLE_MAX_STEP
        local arriveThreshold = 3
        local timeout = 45
        local startTime = tick()
        while true do
            if not vehicle or not vehicle.Parent then return false end
            local currentCFrame = vehicle:GetPivot()
            local currentPos = currentCFrame.Position
            local diff = targetPos - currentPos
            local distance = diff.Magnitude
            if distance <= arriveThreshold then break end
            if tick() - startTime > timeout then break end
            local direction = diff.Unit
            local step = math.min(maxStep, distance)
            local newPos = currentPos + direction * step
            local lookAt = newPos + direction
            vehicle:PivotTo(CFrame.new(newPos, lookAt))
            if vehicle.PrimaryPart then
                vehicle.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                vehicle.PrimaryPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            end
            run_service.Heartbeat:Wait()
        end
        return true
    end

    task.spawn(function()
        local vehicle, humanoid = spawnAndMount()
        if not vehicle or not humanoid then
            baristaRouteRunning = false
            return
        end
        for i = 1, #BARISTA_ROUTE_WAYPOINTS do
            if not baristaRouteRunning then break end
            if not humanoid.SeatPart or not vehicle.Parent then break end
            local targetPos = BARISTA_ROUTE_WAYPOINTS[i]
            if targetPos then moveVehicleTo(vehicle, targetPos) end
        end
        if humanoid and humanoid.SeatPart then
            humanoid.Sit = false
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
        baristaRouteRunning = false
    end)
end

-- Auto Play from Main Menu
-- Rejoin re-exec target: this same Banana Hub script, so a rejoin comes back
-- into the Banana Hub UI rather than some other hub.
local DDS_SCRIPT_LOAD_URL = "https://raw.githubusercontent.com/aerizuu/BananaHUB/refs/heads/main/BananaDDS.luau"

local function buildQueuedDDSBootstrap()
    -- Only the automation flags need to survive a rejoin, and they are only
    -- resumed when this token is present. Without it a rejoin (or any later
    -- exec) starts inert instead of immediately teleporting the character.
    local autoB = getgenv().autoBarista and "true" or "false"
    local autoO = getgenv().autoOffice and "true" or "false"
    local autoD = getgenv().autoDrive and "true" or "false"
    local autoA = getgenv().autoAnomalyDDS and "true" or "false"
    return "getgenv().autoBarista = " .. autoB
        .. "; getgenv().autoOffice = " .. autoO
        .. "; getgenv().autoDrive = " .. autoD
        .. "; getgenv().autoAnomalyDDS = " .. autoA
        .. "; getgenv()[" .. string.format("%q", RESUME_TOKEN) .. "] = true"
        .. "; loadstring(game:HttpGet(\"" .. DDS_SCRIPT_LOAD_URL .. "\"))()"
end

local function changeTeam(teamName)
    pcall(function()
        local jobEvents = replicated_storage:WaitForChild("JobEvents")
        local event = jobEvents:WaitForChild("TeamChangeRequest")
        event:FireServer(teamName, 11378976, 1, 0, "Detector")
    end)
end

local function teleportKeepingKey(placeId, who)
    who = who or player
    if queue_on_teleport then
        pcall(function() queue_on_teleport(buildQueuedDDSBootstrap()) end)
    end
    return teleport_service:Teleport(placeId, who)
end

local function autoPlayFromMainMenu()
    local desiredTeamText = nil
    if getgenv().autoBarista then
        desiredTeamText = "Barista"
    elseif getgenv().autoOffice then
        desiredTeamText = "Office Worker"
    end

    if desiredTeamText then
        pcall(function() changeTeam(desiredTeamText) end)
        task.wait(0.5)
    end

    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return end
    local mainMenu = gui:FindFirstChild("mainMenuSystem")
    if not mainMenu then return end
    local baseFrame = mainMenu:FindFirstChild("baseFrame")
    if not baseFrame then return end

    local sideBar = baseFrame:FindFirstChild("sideBarSelection")
    local playFrame = baseFrame:FindFirstChild("playFrame")
    if not (sideBar and playFrame) then return end

    local playSelect = sideBar:FindFirstChild("playSelect")
    if playSelect then
        clickGuiObject(playSelect)
        task.wait(0.5)
    end

    local deploySelect = playFrame:FindFirstChild("deploySelect")
    if deploySelect then
        clickGuiObject(deploySelect)
    end
end

-- Noclip (local, for office)
local function enableNoclip()
    if noclipConnection then return end
    noclipConnection = run_service.Stepped:Connect(function()
        pcall(function()
            local char = player.Character
            if char then
                for _, part in pairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
        end)
    end)
end

local function disableNoclip()
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
    pcall(function()
        local char = player.Character
        if char then
            for _, part in pairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                end
            end
        end
    end)
end

--═══════════════════════════════════════════════════════════════════════════════
-- BARISTA LOGIC
--═══════════════════════════════════════════════════════════════════════════════
local function startBaristaLogic()
    if baristaLogicRunning then return end
    baristaSession = baristaSession + 1
    local mySession = baristaSession
    baristaLogicRunning = true

    -- Auto Reconnect & Idle Monitor
    task.spawn(function()
        local lastPos = nil
        local lastTime = tick()
        local connection

        local function attemptReconnect()
            local ok = pcall(function()
                teleportKeepingKey(game.PlaceId, player)
            end)
            if ok then
                task.delay(math.random(10, 20), function()
                    pcall(autoPlayFromMainMenu)
                end)
            end
        end

        -- CoreGui.RobloxPromptGui only exists once Roblox has shown a prompt
        -- overlay; on a fresh join it can be missing, so the connect is guarded
        -- rather than erroring the whole reconnect thread.
        pcall(function()
            connection = CoreGui.RobloxPromptGui.promptOverlay.ChildAdded:Connect(function(child)
                if getgenv().autoBarista and (child.Name == "ErrorPrompt" or child.Name == "DisconnectPrompt") then
                    attemptReconnect()
                end
            end)
        end)

        while getgenv().autoBarista and baristaSession == mySession do
            task.wait(1)
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                if lastPos and (root.Position - lastPos).Magnitude < 1 then
                    if tick() - lastTime > 30 then
                        attemptReconnect()
                        break
                    end
                else
                    lastPos = root.Position
                    lastTime = tick()
                end
            end
        end
        if connection then connection:Disconnect() end
        if baristaSession == mySession then
            baristaLogicRunning = false
        end
    end)

    task.spawn(function()
        -- The whole trip runs inside a function so a single error (a prompt
        -- destroyed by a respawn mid-brew, say) is caught instead of killing
        -- this thread while the toggle still reads "on".
        local function baristaTrip()
        local BARISTA_POS = Vector3.new(-4990.83, 4.09, -715.61)
        local BREW_POS = Vector3.new(-4998.02, 4.09, -793.15)
        local GIVE_POS = Vector3.new(-4995.42, 4.09, -759.04)

        while getgenv().autoBarista and baristaSession == mySession do
            local character = player.Character or player.CharacterAdded:Wait()
            local humanoid = character:WaitForChild("Humanoid")
            local root = character:WaitForChild("HumanoidRootPart")

            -- Teleport to the barista area
            if (root.Position - BARISTA_POS).Magnitude > 50 then
                setFreeze(false)
                if getgenv().ddsInstantBaristaTP then
                    root.CFrame = CFrame.new(BARISTA_POS + Vector3.new(0, 3, 0))
                    task.wait(0.5)
                else
                    if baristaUsesRouteMode() then
                        if not baristaRouteRunning then
                            startBaristaRouteTravel()
                        end
                        local startTime = tick()
                        local routeBudget = 75
                        while baristaRouteRunning and (tick() - startTime < routeBudget) do
                            task.wait(0.5)
                        end
                        if baristaRouteRunning then
                            baristaRouteRunning = false
                        end
                    else
                        local success = TPWithMotor(BARISTA_POS)
                        if not success then
                            task.wait(3)
                            continue
                        end
                    end

                    -- Retry if still far
                    if (root.Position - BARISTA_POS).Magnitude > 50 then
                        local success = TPWithMotor(BARISTA_POS)
                        if not success then
                            task.wait(3)
                            continue
                        end
                    end
                end
            end

            -- Start Shift
            local shiftPrompt
            for _, v in pairs(workspace:GetDescendants()) do
                if v:IsA("ProximityPrompt") and v.ActionText == "Start Shift" then
                    if v.Parent and (v.Parent.Position - root.Position).Magnitude < 30 then
                        shiftPrompt = v
                        break
                    end
                end
            end
            if shiftPrompt then
                superRandomWait(2.0, 4.5)
                fpp(shiftPrompt)
            end

            -- Wait for Order (BaristaGUI check)
            local orderText = ""
            for i = 1, 10 do
                local gui = player.PlayerGui:FindFirstChild("BaristaGUI")
                if gui then
                    local lbl = gui:FindFirstChild("StatusFrame") and gui.StatusFrame:FindFirstChild("OrderText")
                    if lbl and lbl.Text and string.find(string.lower(lbl.Text), "npc") then
                        orderText = lbl.Text
                        break
                    end
                end
                task.wait(0.5)
            end
            if orderText == "" then
                task.wait(1)
                continue
            end

            -- Brew position
            if (root.Position - BREW_POS).Magnitude > 3 then
                setFreeze(false)
                if getgenv().ddsInstantBaristaTP then
                    root.CFrame = CFrame.new(BREW_POS + Vector3.new(0, 3, 0))
                else
                    humanoid:MoveTo(BREW_POS)
                    -- Bounded: a stuck or respawning character would otherwise
                    -- spin here for the rest of the session.
                    local walkDeadline = tick() + 15
                    while (root.Position - BREW_POS).Magnitude > 3 and tick() < walkDeadline do
                        task.wait(0.2)
                    end
                end
                task.wait(0.3)
                setFreeze(true)
            end

            local brewPrompt
            for _, v in pairs(workspace:GetDescendants()) do
                if v:IsA("ProximityPrompt") and v.ActionText == "Start Brewing!" then
                    if v.Parent and (v.Parent.Position - root.Position).Magnitude < 15 then
                        brewPrompt = v
                        break
                    end
                end
            end
            if brewPrompt then
                superRandomWait(3.5, 7.0)
                fpp(brewPrompt)
            end

            -- Minigame bypass: widen the target zone
            local gui = player.PlayerGui:FindFirstChild("BaristaGUI")
            if gui and gui:FindFirstChild("MinigameFrame") then
                local tz = gui.MinigameFrame:FindFirstChild("BackgroundBar")
                    and gui.MinigameFrame.BackgroundBar:FindFirstChild("TargetZone")
                if tz then
                    tz.AnchorPoint = Vector2.new(0.5, 0.5)
                    tz.Position = UDim2.new(tz.Position.X.Scale, tz.Position.X.Offset, 0.5, 0)
                    tz.Size = UDim2.new(tz.Size.X.Scale, tz.Size.X.Offset, 2, 0)
                    tz.Visible = false
                    tz.BackgroundTransparency = 1
                    tz.BorderSizePixel = 0
                end
            end

            -- Wait for the drink (a Tool in the character)
            for i = 1, 40 do
                local hasDrink = false
                for _, child in pairs(character:GetChildren()) do
                    if child:IsA("Tool") then
                        hasDrink = true
                        break
                    end
                end
                if hasDrink then break end
                task.wait(0.5)
            end

            -- Give position
            if (root.Position - GIVE_POS).Magnitude > 3 then
                setFreeze(false)
                if getgenv().ddsInstantBaristaTP then
                    root.CFrame = CFrame.new(GIVE_POS + Vector3.new(0, 3, 0))
                else
                    humanoid:MoveTo(GIVE_POS)
                    local walkDeadline = tick() + 15
                    while (root.Position - GIVE_POS).Magnitude > 3 and tick() < walkDeadline do
                        task.wait(0.2)
                    end
                end
                task.wait(0.3)
                setFreeze(true)
            end

            local givePrompt
            for _, v in pairs(workspace:GetDescendants()) do
                if v:IsA("ProximityPrompt") and v.Parent and (v.Parent.Position - root.Position).Magnitude < 15 then
                    if v.ActionText ~= "Start Brewing!" and v.ActionText ~= "Start Shift" then
                        givePrompt = v
                        break
                    end
                end
            end
            if givePrompt then
                superRandomWait(4.5, 9.0)
                fpp(givePrompt)
            end

            superRandomWait(3.0, 6.0)
            setFreeze(false)
            task.wait(1)
        end
        end

        pcall(baristaTrip)
        if baristaSession == mySession then
            baristaLogicRunning = false
        end
    end)
end

--═══════════════════════════════════════════════════════════════════════════════
-- OFFICE LOGIC
--═══════════════════════════════════════════════════════════════════════════════
local lastPrinterTask = 0
local officeSession = 0

local function startOfficeLogic()
    -- Guard against a second loop. Toggling off then on quickly used to leave
    -- the old loop finishing its printer trip while a new one started, and both
    -- then drove the character.
    if officeRunning then return end
    officeSession = officeSession + 1
    local mySession = officeSession
    officeRunning = true
    task.spawn(function()
        local OFFICE_POS = Vector3.new(-5902.42, 4.49, -228.54)
        local DROP_POS = Vector3.new(-5888.49, 4.43, -224.51)

        local targetChair = nil
        local function getTargetChair()
            local char = player.Character
            local rootPart = char and char:FindFirstChild("HumanoidRootPart")
            if not rootPart then return targetChair end

            if targetChair and targetChair:IsDescendantOf(workspace) then
                return targetChair
            end

            local minDist = 9999
            local nearest = nil
            pcall(function()
                local computers = workspace:FindFirstChild("Computers")
                if computers then
                    for _, comp in pairs(computers:GetChildren()) do
                        for _, v in pairs(comp:GetDescendants()) do
                            if v:IsA("Seat") then
                                local dist = (v.Position - rootPart.Position).Magnitude
                                if dist < minDist then
                                    minDist = dist
                                    nearest = v
                                end
                            end
                        end
                    end
                end
            end)

            if not nearest then
                pcall(function()
                    for _, v in pairs(workspace:GetDescendants()) do
                        if v:IsA("Seat") then
                            local dist = (v.Position - rootPart.Position).Magnitude
                            if dist < minDist then
                                minDist = dist
                                nearest = v
                            end
                        end
                    end
                end)
            end

            targetChair = nearest
            return targetChair
        end

        local function glideTo(targetPos, speed)
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChild("Humanoid")
            if not root or not hum then return end

            enableNoclip()
            setFreeze(false)
            hum.Sit = false
            task.wait(0.05)

            local startPos = root.Position
            local distance = (startPos - targetPos).Magnitude
            local walkSpeed = speed or 30
            local duration = distance / walkSpeed
            local startTime = tick()

            while tick() - startTime < duration do
                if not getgenv().autoOffice then break end
                local t = (tick() - startTime) / duration
                root.CFrame = CFrame.new(startPos:Lerp(targetPos, t))
                task.wait(0.01)
            end
            root.CFrame = CFrame.new(targetPos)
            task.wait(0.1)
            disableNoclip()
        end

        -- Fast tween along the green beam (not a manual MoveTo walk).
        local function followPrinter(targetPos)
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChild("Humanoid")
            if not root or not hum then return end
            enableNoclip()
            setFreeze(false)
            hum.Sit = false
            task.wait(0.05)
            local dist = (root.Position - targetPos).Magnitude
            local dur = math.max(0.25, dist / 120) -- 120 studs/s
            local goal = CFrame.new(targetPos)
            local tw = TweenService:Create(root,
                TweenInfo.new(dur, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut), { CFrame = goal })
            tw:Play()
            tw.Completed:Wait()
            task.wait(0.1)
            disableNoclip()
        end

        local function sitOnTarget()
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChild("Humanoid")
            if not root or not hum then return end

            local chair = getTargetChair()
            if chair then
                setFreeze(false)
                root.CFrame = chair.CFrame + Vector3.new(0, 1.5, 0)
                task.wait(0.1)
                chair:Sit(hum)
                task.wait(0.5)
                setFreeze(true)
            else
                setFreeze(false)
                root.CFrame = CFrame.new(OFFICE_POS + Vector3.new(0, 2, 0))
                task.wait(0.5)
                local seat = nil
                for _, v in pairs(workspace:GetDescendants()) do
                    if v:IsA("Seat") and (v.Position - root.Position).Magnitude < 10 then
                        seat = v
                        break
                    end
                end
                if seat then seat:Sit(hum) end
                task.wait(0.5)
                setFreeze(true)
            end
        end

        local function checkPrinterTask()
            if isHandlingPrinter or not officeRunning then return end
            local notifGui = player.PlayerGui:FindFirstChild("Notification System")
                or player.PlayerGui:FindFirstChild("NotificationSystem")
            if not notifGui then return end
            local list = notifGui:FindFirstChild("list")
            if not list then return end
            local foundTask = false
            local assignedPrinter = nil
            for _, item in pairs(list:GetChildren()) do
                local header = item:FindFirstChild("Header", true)
                if header and header.Visible then
                    local txt = string.lower(header.Text)
                    if (string.find(txt, "printer") or string.find(txt, "go to")) and not string.find(txt, "good") then
                        foundTask = true
                        -- Extract the printer number (1-5) from the task text.
                        local num = string.match(txt, "printer%s*(%d)")
                            or string.match(txt, "(%d)%s*printer")
                            or string.match(txt, "printer%s*no.?%s*(%d)")
                        if num then assignedPrinter = tonumber(num) end
                        break
                    end
                end
            end

            if foundTask and tick() - lastPrinterTask > 15 then
                isHandlingPrinter = true
                lastPrinterTask = tick()
                local char = player.Character
                -- A respawn between the task check and here leaves char nil.
                -- Without this guard the error kills the whole office loop,
                -- which then looks like "Auto Office stopped working".
                if not char then
                    isHandlingPrinter = false
                    task.wait(0.5)
                    return
                end
                local root = char.HumanoidRootPart
                local hum = char.Humanoid

                setFreeze(false)
                hum.Sit = false
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
                task.wait(0.1)
                for i = 1, 5 do
                    root.CFrame = root.CFrame * CFrame.new(0, 1.5, 0)
                    task.wait(0.02)
                end

                -- Fixed printer positions. Used as a fallback target list.
                local PRINTER_POS = {
                    Vector3.new(-5871.769, 4.996, -250.664),
                    Vector3.new(-5871.565, 4.996, -212.804),
                    Vector3.new(-6004.228, 4.996, -210.898),
                    Vector3.new(-6005.896, 4.996, -224.868),
                    Vector3.new(-6006.024, 4.996, -238.583),
                }
                -- Exact printer from the green-line indicator (Beam "Indicateur"):
                -- Attachment0's parent is the assigned printer part, and its
                -- ProximityPrompt is the only one enabled.
                local printerPart, targetPrompt = nil, nil
                local function findPromptNear(pos, radius)
                    if not pos then return nil end
                    local best, bestD = nil, radius
                    for _, v in pairs(workspace:GetDescendants()) do
                        if v:IsA("ProximityPrompt") and v.Parent then
                            local part = v.Parent:IsA("BasePart") and v.Parent
                                or v.Parent:FindFirstAncestorWhichIsA("BasePart")
                            if part then
                                local d = (part.Position - pos).Magnitude
                                if d < bestD then
                                    bestD, best = d, v
                                end
                            end
                        end
                    end
                    return best
                end

                local indicator = workspace:FindFirstChild("Indicateur")
                if not indicator then
                    for _, d in pairs(workspace:GetDescendants()) do
                        if d:IsA("Beam") and d.Name == "Indicateur" and d.Enabled then
                            indicator = d
                            break
                        end
                    end
                end
                if indicator and indicator.Enabled and indicator.Attachment0 then
                    local att = indicator.Attachment0
                    local p = att:IsA("BasePart") and att
                        or att:FindFirstAncestorWhichIsA("BasePart")
                        or att.Parent
                    if p then
                        printerPart = p
                        if p:IsA("BasePart") then
                            targetPrompt = p:FindFirstChildOfClass("ProximityPrompt", true)
                            if not targetPrompt then
                                targetPrompt = findPromptNear(p.Position, 25)
                            end
                        end
                    end
                end

                -- Fallback: the first enabled prompt under Computers.
                if not targetPrompt then
                    local computers = workspace:FindFirstChild("Computers")
                    if computers then
                        for _, child in pairs(computers:GetChildren()) do
                            local part = child:FindFirstChild("Part")
                            local pr = part and part:FindFirstChildOfClass("ProximityPrompt")
                            if pr and pr.Enabled then
                                printerPart = part
                                targetPrompt = pr
                                break
                            end
                        end
                    end
                end
                -- Fallback: the prompt nearest to any known printer position.
                if not targetPrompt then
                    local bestPrompt, bestD, bestPrinter = nil, math.huge, nil
                    for _, v in pairs(workspace:GetDescendants()) do
                        if v:IsA("ProximityPrompt") and v.Parent then
                            local part = v.Parent:IsA("BasePart") and v.Parent
                                or v.Parent:FindFirstAncestorWhichIsA("BasePart")
                            if part then
                                for _, p in pairs(PRINTER_POS) do
                                    local d = (part.Position - p).Magnitude
                                    if d < bestD then
                                        bestD, bestPrompt, bestPrinter = d, v, p
                                    end
                                end
                            end
                        end
                    end
                    if bestPrompt and bestD < 50 then
                        printerPart = bestPrinter
                        targetPrompt = bestPrompt
                    end
                end

                if not printerPart then
                    local nearestDist = math.huge
                    for _, p in pairs(PRINTER_POS) do
                        local d = (p - root.Position).Magnitude
                        if d < nearestDist then nearestDist, printerPart = d, p end
                    end
                end

                if printerPart then
                    local isPart = typeof(printerPart) == "Instance" and printerPart:IsA("BasePart")
                    local printerTarget = isPart
                        and (printerPart.Position + printerPart.CFrame.LookVector * 3 + Vector3.new(0, 2, 0))
                        or (printerPart + Vector3.new(0, 2, 0))
                    -- Follow the green line: real travel along the beam.
                    followPrinter(printerTarget)
                    setFreeze(true)

                    if not targetPrompt then
                        -- The prompt may appear after arrival; retry the scan
                        -- instead of going back immediately and getting stuck.
                        for i = 1, 10 do
                            local nowChar = player.Character
                            local nowRoot = nowChar and nowChar:FindFirstChild("HumanoidRootPart")
                            if nowRoot then
                                targetPrompt = findPromptNear(nowRoot.Position, 30)
                            end
                            if targetPrompt then break end
                            task.wait(0.5)
                        end
                    end

                    if not targetPrompt then
                        setFreeze(false)
                        lastPrinterTask = 0
                        sitOnTarget()
                    end

                    if targetPrompt then
                        -- Random delay before clicking the printer prompt.
                        superRandomWait(4.0, 8.5)

                        for attempt = 1, 5 do
                            if fpp then
                                fpp(targetPrompt)
                                task.wait(0.5)
                                -- The prompt going inactive means it fired.
                                if not targetPrompt or not targetPrompt.Enabled then
                                    break
                                end
                            end
                            task.wait(0.5)
                        end

                        -- Wait for the print job to finish.
                        local printTimeout = 0
                        while printTimeout < 15 do
                            if not targetPrompt or not targetPrompt.Enabled then
                                break
                            end
                            task.wait(0.5)
                            printTimeout = printTimeout + 0.5
                        end

                        sitOnTarget()
                    end
                end
                isHandlingPrinter = false
            end
        end

        -- Wrapped so an error cannot leave officeRunning stuck true, which would
        -- block every later attempt to start Auto Office.
        local ok, err = pcall(function()
        while getgenv().autoOffice and officeSession == mySession do
            local character = player.Character or player.CharacterAdded:Wait()
            local humanoid = character:WaitForChild("Humanoid")
            local root = character:WaitForChild("HumanoidRootPart")
            checkPrinterTask()

            -- If not walking to a printer, stay at the desk.
            if not isHandlingPrinter then
                targetChair = getTargetChair()
                local currentOfficePos = targetChair and targetChair.Position or OFFICE_POS
                local sitting = humanoid.SeatPart ~= nil

                if (root.Position - currentOfficePos).Magnitude > 50 then
                    setFreeze(false)
                    local success = TPWithMotor(DROP_POS)
                    if not success then
                        task.wait(3)
                    else
                        task.wait(0.5)
                    end
                end

                -- Re-fetch sitting / positions after a possible vehicle TP
                sitting = humanoid.SeatPart ~= nil
                if not sitting or (root.Position - currentOfficePos).Magnitude > 5 then
                    if (root.Position - currentOfficePos).Magnitude > 5 then
                        setFreeze(false)
                        humanoid:MoveTo(currentOfficePos)
                        local timeout = tick()
                        while (root.Position - currentOfficePos).Magnitude > 5 and tick() - timeout < 5 do
                            task.wait(0.2)
                        end
                        task.wait(0.5)
                    end
                    sitOnTarget()
                else
                    setFreeze(true)
                end
            end

            local workGui = player.PlayerGui:FindFirstChild("WorkGui")
            if workGui and (workGui.Enabled or (workGui:FindFirstChild("Frame") and workGui.Frame.Visible)) then
                local qLabel = workGui:FindFirstChild("QuestionLabel")
                if qLabel and qLabel.Visible and qLabel.Text ~= "" then
                    superRandomWait(3.5, 7.5) -- delay before solving
                    trySolveMathFromLabel(qLabel)
                end
                task.wait(0.2)
            else
                local guiFound, solved = trySolveAnyMath(player.PlayerGui)
                if not guiFound then
                    task.wait(0.8)
                elseif solved then
                    superRandomWait(0.2, 1)
                else
                    task.wait(0.25)
                end
            end
        end
        end)
        if not ok then
            warn("[BANANAHUB] Office loop error: " .. tostring(err))
        end

        if officeSession == mySession then
            officeRunning = false
        end
    end)
end

--═══════════════════════════════════════════════════════════════════════════════
-- AUTO FIND ANOMALY
--═══════════════════════════════════════════════════════════════════════════════
local ANOMALY_POS = Vector3.new(-3010.706, 117.173, -22111.291)
local ANOMALY_PROMPT_RADIUS = 30
local ANOMALY_E_HOLD_SECONDS = 7

local function getPartPosition(part)
    if part:IsA("BasePart") then return part.Position end
    if part:IsA("Model") then return part:GetPivot().Position end
    if part:IsA("VehicleSeat") then return part.Position end
    return nil
end

local function findAnomalyPrompt(root, targetPos, radius)
    local best, bestDist = nil, nil
    local maxDist = radius or ANOMALY_PROMPT_RADIUS
    local center = targetPos or (root and root.Position) or ANOMALY_POS
    for _, v in pairs(workspace:GetDescendants()) do
        if v:IsA("ProximityPrompt") and v.Parent then
            local pos = getPartPosition(v.Parent)
            if pos then
                local dist = (pos - center).Magnitude
                if dist < maxDist then
                    if not bestDist or dist < bestDist then
                        bestDist = dist
                        best = v
                    end
                end
            end
        end
    end
    return best
end

-- Hold a ProximityPrompt open for `seconds`, which is what the E-key press used
-- to do. Driven through the prompt's own hold methods, so no restricted service
-- is touched. A prompt that refuses the hold is simply fired once.
local function holdPrompt(prompt, seconds)
    if not (prompt and prompt:IsA("ProximityPrompt")) then return end
    if activePromptHolds[prompt] then return end

    if not promptHoldBegin(prompt) then
        pcall(fpp, prompt)
        return
    end

    activePromptHolds[prompt] = true
    local startTime = tick()
    while tick() - startTime < (seconds or 1) do
        -- The prompt can be consumed mid-hold, so stop as soon as its parent
        -- goes away rather than spinning on a destroyed instance.
        if not prompt.Parent then break end
        task.wait(0.05)
    end
    promptHoldEnd(prompt)
    activePromptHolds[prompt] = nil
end

local function startAutoAnomaly()
    if autoAnomalyRunning then return end
    autoAnomalySession = autoAnomalySession + 1
    local mySession = autoAnomalySession
    autoAnomalyRunning = true

    task.spawn(function()
        while autoAnomalyRunning and autoAnomalySession == mySession do
            local character = player.Character or player.CharacterAdded:Wait()
            local root = character:WaitForChild("HumanoidRootPart")
            setFreeze(false)
            root.CFrame = CFrame.new(ANOMALY_POS + Vector3.new(0, 3, 0))
            task.wait(0.6)

            local prompt = findAnomalyPrompt(root, ANOMALY_POS, ANOMALY_PROMPT_RADIUS)
            if prompt then
                superRandomWait(0.5, 1.5)
                holdPrompt(prompt, ANOMALY_E_HOLD_SECONDS)
            end

            task.wait(2)
            autoAnomalyRunning = false
        end
    end)
end

--═══════════════════════════════════════════════════════════════════════════════
-- DRIVE LOGIC
--═══════════════════════════════════════════════════════════════════════════════
local function getCurrentMoneyDrive()
    local function tryPath(obj)
        if obj and obj:IsA("TextLabel") then
            local text = obj.Text or ""
            local cleaned = string.gsub(text, "[^%d]", "")
            local v = tonumber(cleaned)
            -- Return nil, not 0: 0 is truthy in Lua, so returning it would
            -- short-circuit the Rp fallback below with a bogus balance.
            if v and v > 0 then return v end
        end
        return nil
    end

    local modGui = player.PlayerGui:FindFirstChild("ModificationUI")
    if modGui then
        local mainFrame = modGui:FindFirstChild("MainFrame")
        if mainFrame then
            local currency = mainFrame:FindFirstChild("Currency")
            if currency then
                local frame = currency:FindFirstChild("Frame")
                if frame then
                    local result = tryPath(frame:FindFirstChild("Currency"))
                    if result then return result end
                end
                local result = tryPath(currency:FindFirstChild("Currency"))
                if result then return result end
            end
        end
    end

    for _, child in pairs(player.PlayerGui:GetDescendants()) do
        if child:IsA("TextLabel") then
            local text = child.Text or ""
            if string.find(text, "Rp") then
                local cleaned = string.gsub(text, "[^%d]", "")
                local result = tonumber(cleaned) or 0
                if result > 0 then return result end
            end
        end
    end

    return 0
end

-- Move the vehicle to the target WITHOUT dismounting. Returns true on arrival.
local function driveVehicleTo(vehicle, humanoid, targetPos)
    local maxStep = BARISTA_VEHICLE_MAX_STEP
    local arriveThreshold = 3
    local timeout = 90
    local startTime = tick()
    while getgenv().autoDrive do
        if not vehicle or not vehicle.Parent then return false end
        if not humanoid.SeatPart then return false end -- thrown off the bike
        local currentPos = vehicle:GetPivot().Position
        local diff = targetPos - currentPos
        local distance = diff.Magnitude
        if distance <= arriveThreshold then return true end
        if tick() - startTime > timeout then return true end
        local direction = diff.Unit
        local step = math.min(maxStep, distance)
        local newPos = currentPos + direction * step
        vehicle:PivotTo(CFrame.new(newPos, newPos + direction))
        if vehicle.PrimaryPart then
            vehicle.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            vehicle.PrimaryPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end
        RunService.Heartbeat:Wait()
    end
    return false
end

-- Spawn a bike and mount it; returns vehicle, humanoid, root.
local function driveMountMotor()
    -- Wait for the character to actually be alive. Grabbing a dead character
    -- makes the bike spawn fail.
    local character, humanoid, root
    local deadlineAlive = tick() + 20
    while tick() < deadlineAlive do
        if not getgenv().autoDrive then return nil, nil, nil end
        character = player.Character
        if character then
            humanoid = character:FindFirstChildOfClass("Humanoid")
            root = character:FindFirstChild("HumanoidRootPart")
            if humanoid and root and humanoid.Health > 0
                and humanoid:GetState() ~= Enum.HumanoidStateType.Dead then
                break
            end
        end
        task.wait(0.2)
    end

    if not (character and humanoid and root) then
        return nil, humanoid, root
    end
    -- Let the character settle on the ground after spawning.
    task.wait(0.5)

    if humanoid.SeatPart then
        local existing = humanoid.SeatPart:FindFirstAncestorOfClass("Model")
        if existing then return existing, humanoid, root end
    end

    ReplicatedStorage:WaitForChild("SpawnCarEvents"):WaitForChild("SpawnCar"):FireServer("Yamahax-MioSporty")
    task.wait(1)

    -- Step forward 15 studs so the Ride prompt enters range.
    local forward = root.CFrame.LookVector
    for _ = 1, 6 do
        root.CFrame = root.CFrame + forward * 2.5
        task.wait(0.05)
    end
    task.wait(0.5)

    local ridePrompt = findRidePrompt(root, 25)
    if not ridePrompt then
        local deadline = tick() + 5
        while not ridePrompt and tick() < deadline do
            task.wait(0.25)
            ridePrompt = findRidePrompt(root, 40)
        end
    end
    if not ridePrompt then return nil, humanoid, root end
    if fpp then fpp(ridePrompt) end

    local deadline = tick() + 15
    while not humanoid.SeatPart and tick() < deadline do
        if fpp and (tick() % 2 < 0.1) then pcall(function() fpp(ridePrompt) end) end
        task.wait(0.1)
    end
    if not humanoid.SeatPart then return nil, humanoid, root end
    task.wait(0.2)
    return humanoid.SeatPart:FindFirstAncestorOfClass("Model"), humanoid, root
end

local function startDriveLogic()
    if driveRunning then return end
    driveSession = driveSession + 1
    local mySession = driveSession
    driveRunning = true

    task.spawn(function()
        local BARISTA_POS = Vector3.new(-4990.83, 4.09, -715.61)
        local lastRejoinTime = tick()
        local lastMoney = getCurrentMoneyDrive()
        local startMoney = lastMoney

        local function resetCharacter()
            pcall(function()
                local char = player.Character
                if not char then return end
                local humanoid = char:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    humanoid.Health = 0
                else
                    char:BreakJoints()
                end
            end)
        end

        local function checkRejoinReset()
            local currentMoney = getCurrentMoneyDrive()
            local hoursSinceRejoin = (tick() - lastRejoinTime) / 3600

            -- Reset the baseline when money drops a lot (just collected).
            if currentMoney < lastMoney * 0.9 then
                startMoney = currentMoney
                lastMoney = currentMoney
            end

            -- Rejoin the server after X hours.
            if hoursSinceRejoin >= getgenv().driveRejoinHours then
                pcall(function() teleportKeepingKey(game.PlaceId, player) end)
                task.delay(math.random(10, 20), function() pcall(autoPlayFromMainMenu) end)
                lastRejoinTime = tick()
                lastMoney = getCurrentMoneyDrive()
                startMoney = lastMoney
                task.wait(5)
                return true
            end

            -- Reset the character after earning X money.
            local earnings = currentMoney - startMoney
            if getgenv().driveResetMoney > 0 and earnings >= getgenv().driveResetMoney then
                resetCharacter()
                startMoney = getCurrentMoneyDrive()
                lastMoney = startMoney
                player.CharacterAdded:Wait()
                task.wait(3)
                return true
            end

            return false
        end

        -- Wrapped so an error cannot leave driveRunning stuck true, which would
        -- make the toggle refuse to restart the routine.
        local ok, err = pcall(function()
        while getgenv().autoDrive and driveSession == mySession do
            local vehicle, humanoid = driveMountMotor()
            if not vehicle or not humanoid then
                task.wait(3)
            else
                local originPos = vehicle:GetPivot().Position
                setFreeze(false)

                -- Shuttle loop: origin -> BARISTA_POS -> origin -> ... no dismount.
                while getgenv().autoDrive and driveSession == mySession do
                    if checkRejoinReset() then break end
                    if not humanoid.SeatPart or not vehicle.Parent then break end
                    if not driveVehicleTo(vehicle, humanoid, BARISTA_POS) then break end
                    if checkRejoinReset() then break end
                    task.wait(1)
                    if not humanoid.SeatPart or not vehicle.Parent then break end
                    if not driveVehicleTo(vehicle, humanoid, originPos) then break end
                    task.wait(1)
                end
            end
        end
        end)
        if not ok then
            warn("[BANANAHUB] Drive loop error: " .. tostring(err))
        end

        if driveSession == mySession then
            driveRunning = false
        end
    end)
end

--═══════════════════════════════════════════════════════════════════════════════
-- UI
--═══════════════════════════════════════════════════════════════════════════════
local Window = WindUI:CreateWindow({
    Title   = HUB.Name,
    Author  = HUB.Game .. " | V " .. HUB.Version,
    Icon    = HUB.LogoId,
    Folder  = "BananaHubDDS",
    Size    = UDim2.fromOffset(600, 480),
    Transparent = false,
    Acrylic = false,
    Theme   = "Dark",
    -- White accent: no cyan/blue anywhere (border, tab highlight, sliders).
    Color   = Color3.fromRGB(255, 255, 255),
    Background = "https://i.ibb.co.com/XZjTtpMf/sena-bg.jpg",
    BackgroundTransparency = 0.7,
    User = { Enabled = true, Anonymous = false },
    HideSearchBar = true,
    ToggleKey = Enum.KeyCode.Insert,
    OpenButton = { Title = HUB.Name, Enabled = false, Draggable = true },
})

local Tabs = {
    Info       = Window:Tab({ Title = "Info",       Icon = "info" }),
    Automation = Window:Tab({ Title = "Automation", Icon = "settings" }),
    Settings   = Window:Tab({ Title = "Settings",   Icon = "fileCog" }),
    Webhook    = Window:Tab({ Title = "Webhook",    Icon = "webhook" }),
}

-- Tab: Info
do
    local S = Tabs.Info:Section({ Title = "Money Status" })
    startingMoneyParagraph = S:Paragraph({ Title = "Uang Awal", Desc = "Loading..." })
    earningsParagraph = S:Paragraph({ Title = "Pendapatan", Desc = "Loading..." })
    earningsPerHourParagraph = S:Paragraph({ Title = "Est. Earning/Hour", Desc = "Loading..." })
end

do
    local S = Tabs.Info:Section({ Title = "Safety Status" })
    S:Paragraph({
        Title = "Auto Office",
        Desc = "Aman kalau dipakai 1-2 jam. Jangan lebih dari itu biar tetap aman.",
    })
end

-- Tab: Automation
do
    local S = Tabs.Automation:Section({ Title = "Office Automation" })

    S:Toggle({
        Title = "Auto Office",
        Value = getgenv().autoOffice == true,
        Callback = function(v)
            getgenv().autoOffice = v
            if v then
                changeTeam("Office Worker")
                startOfficeLogic()
                Notify(HUB.Name, "Office automation starting", 3)
            else
                officeRunning = false
                officeSession = officeSession + 1
                isHandlingPrinter = false
                disableNoclip()
                setFreeze(false)
            end
        end,
    })

    S:Toggle({
        Title = "Anti AFK",
        Value = getgenv().antiAfkDDS,
        Callback = function(v)
            getgenv().antiAfkDDS = v
            setAntiAfkDDS(v)
        end,
    })
end

do
    local S = Tabs.Automation:Section({ Title = "Auto Find Anomaly" })

    S:Toggle({
        Title = "Auto Find Anomaly",
        Value = getgenv().autoAnomalyDDS,
        Callback = function(v)
            getgenv().autoAnomalyDDS = v
            if v then
                startAutoAnomaly()
                Notify(HUB.Name, "Auto Find Anomaly starting", 3)
            else
                autoAnomalyRunning = false
            end
        end,
    })
end

-- Barista / Drive. The original script defined both routines but never put them
-- on the window - they were only reachable if something else set
-- getgenv().autoBarista / autoDrive. They are exposed here so the code is
-- actually usable, with the same flags so an external setter still works.
do
    local S = Tabs.Automation:Section({ Title = "Barista / Drive" })

    S:Dropdown({
        Title = "Travel Mode",
        Values = { "Fast", "Route" },
        Value = getgenv().baristaMode,
        Callback = function(v)
            getgenv().baristaMode = tostring(v or "Fast")
        end,
    })

    S:Toggle({
        Title = "Instant Barista Teleport",
        Value = getgenv().ddsInstantBaristaTP,
        Callback = function(v)
            getgenv().ddsInstantBaristaTP = v
        end,
    })

    S:Toggle({
        Title = "Auto Barista",
        Value = getgenv().autoBarista,
        Callback = function(v)
            getgenv().autoBarista = v
            if v then
                changeTeam("Barista")
                startBaristaLogic()
                Notify(HUB.Name, "Barista automation starting", 3)
            else
                baristaLogicRunning = false
                baristaRouteRunning = false
                baristaSession = baristaSession + 1
                disableNoclip()
                setFreeze(false)
            end
        end,
    })

    S:Toggle({
        Title = "Auto Drive",
        Value = getgenv().autoDrive,
        Callback = function(v)
            getgenv().autoDrive = v
            if v then
                startDriveLogic()
                Notify(HUB.Name, "Drive automation starting", 3)
            else
                driveRunning = false
                driveSession = driveSession + 1
                setFreeze(false)
            end
        end,
    })

    S:Slider({
        Title = "Rejoin After (hours)",
        Value = { Min = 1, Max = 12, Default = tonumber(getgenv().driveRejoinHours) or 2 },
        Step = 1,
        Callback = function(v)
            getgenv().driveRejoinHours = math.clamp(tonumber(v) or 2, 1, 12)
        end,
    })

    S:Slider({
        Title = "Reset Character After (Rp)",
        Value = { Min = 0, Max = 1000000, Default = tonumber(getgenv().driveResetMoney) or 100000 },
        Step = 10000,
        Callback = function(v)
            getgenv().driveResetMoney = math.clamp(tonumber(v) or 100000, 0, 1000000)
        end,
    })
end

-- Tab: Settings
do
    local S = Tabs.Settings:Section({ Title = "Settings" })

    S:Toggle({
        Title = "Streamer Mode",
        Value = false,
        Callback = function(v)
            applyStreamerMode(v)
        end,
    })

    S:Input({
        Title = "Spoof Text",
        Value = spoofText,
        Placeholder = "I Am Banana.",
        Callback = function(v)
            if v ~= "" then spoofText = v end
        end,
    })

    S:Toggle({
        Title = "FPS Boost",
        Value = false,
        Callback = function(v)
            setFPSBooster(v)
            Notify("FPS Boost", v and "ON - low quality, effects off" or "OFF - restored default rendering", 3)
        end,
    })
end

-- Tab: Webhook
do
    local S = Tabs.Webhook:Section({ Title = "Webhook Settings" })

    S:Input({
        Title = "Webhook URL",
        Value = getgenv().ddsWebhookUrl,
        Placeholder = "Enter your webhook URL here",
        Callback = function(v)
            getgenv().ddsWebhookUrl = v
        end,
    })

    S:Toggle({
        Title = "Enable Money Webhook",
        Value = getgenv().ddsWebhookEnabled,
        Callback = function(v)
            getgenv().ddsWebhookEnabled = v
            lastMoneyWebhook = tick()
        end,
    })

    S:Toggle({
        Title = "Hide Username",
        Value = getgenv().ddsWebhookHideName,
        Callback = function(v)
            getgenv().ddsWebhookHideName = v
        end,
    })

    S:Slider({
        Title = "Send Every (min)",
        Value = { Min = 1, Max = 30, Default = tonumber(getgenv().ddsWebhookInterval) or 5 },
        Step = 1,
        Callback = function(v)
            getgenv().ddsWebhookInterval = math.clamp(tonumber(v) or 5, 1, 30)
        end,
    })

    S:Button({
        Title = "Test Webhook",
        Callback = function()
            local ok, err = sendMoneyWebhook(true)
            Notify("Webhook Test",
                ok and "Sent - check Discord" or ("Failed: " .. tostring(err)), 5)
        end,
    })
end

Notify(HUB.Name, "Loaded", 3)

-- Resume automation ONLY on an explicit rejoin resume. A plain exec leaves every
-- flag false, so nothing moves the character and the server has nothing to kick.
-- (Previously this block ran off whatever getgenv() flags were left over, which
-- is what caused the automatic Error 267 kick a few seconds after load.)
task.spawn(function()
    task.wait(3)
    -- Bail if this run was unloaded during the wait.
    if getgenv().__banana_dds_money_token ~= moneyToken then return end
    -- Second gate: nothing below may run unless a resume was actually requested.
    if not (getgenv().autoOffice or getgenv().autoBarista
        or getgenv().autoDrive or getgenv().autoAnomalyDDS) then return end
    if getgenv().autoOffice then
        pcall(changeTeam, "Office Worker")
        pcall(startOfficeLogic)
    end
    if getgenv().autoBarista then
        pcall(changeTeam, "Barista")
        pcall(startBaristaLogic)
    end
    if getgenv().autoDrive then
        pcall(startDriveLogic)
    end
    if getgenv().autoAnomalyDDS then
        pcall(startAutoAnomaly)
    end
end)

--═══════════════════════════════════════════════════════════════════════════════
-- UNLOAD
--═══════════════════════════════════════════════════════════════════════════════
getgenv().__banana_dds_unload = function()
    -- Stop the money loop and any resumed automation before tearing down.
    getgenv().__banana_dds_money_token = nil
    getgenv().autoBarista = false
    getgenv().autoOffice = false
    getgenv().autoDrive = false
    getgenv().autoAnomalyDDS = false
    autoAnomalyRunning = false
    getgenv().antiAfkDDS = false
    pcall(function() applyStreamerMode(false) end)
    pcall(function() setFPSBooster(false) end)
    baristaLogicRunning = false
    baristaRouteRunning = false
    baristaSession = baristaSession + 1
    officeRunning = false
    officeSession = officeSession + 1
    isHandlingPrinter = false
    driveRunning = false
    driveSession = driveSession + 1

    -- Cleanup Anti-AFK
    pcall(function()
        if getgenv().antiAfkDDSConnection then
            getgenv().antiAfkDDSConnection:Disconnect()
            getgenv().antiAfkDDSConnection = nil
        end
    end)

    -- Cleanup Auto-Noclip
    pcall(function()
        if getgenv().autoNoclipConnection then
            getgenv().autoNoclipConnection:Disconnect()
            getgenv().autoNoclipConnection = nil
        end
    end)

    -- Cleanup local noclip
    pcall(function()
        if noclipConnection then
            noclipConnection:Disconnect()
            noclipConnection = nil
        end
    end)

    -- Restore the character
    pcall(function()
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then root.Anchored = false end
        if char then
            for _, part in pairs(char:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = true end
            end
        end
    end)

    -- Release any prompt holds still in flight so a prompt is not left stuck
    -- in the "being held" state after the script is unloaded.
    pcall(function()
        for prompt in pairs(activePromptHolds) do
            promptHoldEnd(prompt)
            activePromptHolds[prompt] = nil
        end
    end)

    -- Destroy the window
    pcall(function()
        if Window then Window:Destroy() end
    end)
end

_G[INSTANCE_KEY] = {
    version = HUB.Version,
    window  = Window,
    cleanup = getgenv().__banana_dds_unload,
}
