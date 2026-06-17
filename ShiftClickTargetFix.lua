--[[
  ShiftClickTargetFix

  12.0.7 blocks modified SecureUnitButton clicks that resolve to "target".
  Route Shift+Left through the ungated "click" action to a SecureActionButton

]]

local ADDON = "ShiftClickTargetFix"

local targetProxies = setmetatable({}, { __mode = "k" })
local attachedFrames = {}
local pendingApply = false
local lastAppliedCount = 0

local function SafeTrim(s)
    if strtrim then
        return strtrim(s or "")
    end
    return (s or ""):match("^%s*(.-)%s*$") or ""
end

local function IsSecureUnitButton(frame)
    if not frame or frame.IsForbidden and frame:IsForbidden() then
        return false
    end
    if not frame.SetAttribute or not frame.GetAttribute then
        return false
    end
    if frame:GetAttribute("unit") then
        return true
    end
    if frame.unit then
        return true
    end
    if frame:GetAttribute("type1") or frame:GetAttribute("*type1") then
        return true
    end
    return false
end

local function GetTargetProxy(frame)
    local proxy = targetProxies[frame]
    if not proxy then
        proxy = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
        proxy:SetSize(1, 1)
        proxy:SetAlpha(0)
        proxy:EnableMouse(false)
        proxy:RegisterForClicks("AnyUp")
        proxy:SetAttribute("type", "target")
        for i = 1, 5 do
            proxy:SetAttribute("type" .. i, "target")
        end
        proxy:SetAttribute("useparent-unit", true)
        proxy:SetAttribute("useOnKeyDown", false)
        targetProxies[frame] = proxy
    end
    return proxy
end

local function ShouldAttach(frame)
    if not IsSecureUnitButton(frame) or attachedFrames[frame] then
        return false
    end

    local shiftType = frame:GetAttribute("*shift-type1") or frame:GetAttribute("shift-type1")
    if shiftType and shiftType ~= "target" and shiftType ~= "click" then
        return false
    end

    local proxy = targetProxies[frame]
    local clickBtn = frame:GetAttribute("*shift-clickbutton1") or frame:GetAttribute("shift-clickbutton1")
    if proxy and clickBtn == proxy then
        return false
    end

    return true
end

local function AttachShiftTarget(frame)
    if not ShouldAttach(frame) then
        return false
    end

    local ok, err = pcall(function()
        local proxy = GetTargetProxy(frame)
        frame:SetAttribute("shift-type1", nil)
        frame:SetAttribute("shift-type1", "click")
        frame:SetAttribute("shift-clickbutton1", proxy)
        frame:SetAttribute("*shift-type1", "click")
        frame:SetAttribute("*shift-clickbutton1", proxy)
    end)

    if not ok then
        return false
    end

    attachedFrames[frame] = true
    lastAppliedCount = lastAppliedCount + 1
    return true
end

local function WalkChildren(frame, depth)
    if not frame or depth > 5 or not frame.GetChildren then
        return
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        AttachShiftTarget(child)
        WalkChildren(child, depth + 1)
    end
end

local function TryGlobal(name)
    local frame = _G[name]
    if frame then
        AttachShiftTarget(frame)
        WalkChildren(frame, 0)
    end
end

local function ApplyPartyFrames()
    for i = 1, 5 do
        TryGlobal("CompactPartyFrameMember" .. i)
    end

    local party = _G.PartyFrame
    if party then
        for i = 1, 5 do
            local member = party["MemberFrame" .. i]
            if member then
                AttachShiftTarget(member)
                WalkChildren(member, 0)
            end
        end
        WalkChildren(party, 0)
    end
end

local function ApplyRaidFrames()
    for i = 1, 40 do
        TryGlobal("CompactRaidFrame" .. i)
    end
    for g = 1, 8 do
        for m = 1, 5 do
            TryGlobal(string.format("CompactRaidGroup%dMember%d", g, m))
        end
    end
end

local function ApplyArenaFrames()
    for i = 1, 5 do
        TryGlobal("ArenaEnemyFrame" .. i)
        TryGlobal("ArenaPrepFrame" .. i)
    end
    WalkChildren(_G.ArenaEnemyFrames, 0)
    WalkChildren(_G.ArenaPrepFrames, 0)
end

local function ApplyCoreFrames()
    TryGlobal("PlayerFrame")
    TryGlobal("TargetFrame")
    TryGlobal("TargetFrameToT")
    TryGlobal("FocusFrame")
    TryGlobal("FocusFrameToT")
    TryGlobal("PetFrame")
    TryGlobal("Boss1TargetFrame")
    TryGlobal("Boss2TargetFrame")
    TryGlobal("Boss3TargetFrame")
    TryGlobal("Boss4TargetFrame")
    TryGlobal("Boss5TargetFrame")
    WalkChildren(_G.BossTargetFrameContainer, 0)
    WalkChildren(_G.CompactPartyFrame, 0)
    WalkChildren(_G.CompactRaidFrame, 0)
end

local function ApplyToClickCastFrames()
    if type(ClickCastFrames) ~= "table" then
        return
    end
    for frame in pairs(ClickCastFrames) do
        AttachShiftTarget(frame)
    end
end

local function ApplyToNameplates()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then
        return
    end
    for _, nameplate in ipairs(C_NamePlate.GetNamePlates()) do
        WalkChildren(nameplate, 0)
        if nameplate.UnitFrame then
            AttachShiftTarget(nameplate.UnitFrame)
            WalkChildren(nameplate.UnitFrame, 0)
        end
    end
end

local function ApplyAll()
    if InCombatLockdown() then
        pendingApply = true
        return false, "combat"
    end

    lastAppliedCount = 0
    ApplyCoreFrames()
    ApplyPartyFrames()
    ApplyRaidFrames()
    ApplyArenaFrames()
    ApplyToClickCastFrames()
    ApplyToNameplates()
    return true
end

-------------------------------------------------------------------------------
-- Click Casting profile fallback
-------------------------------------------------------------------------------

local function ModifierLabel(mod)
    if GetStringFromModifiers then
        return GetStringFromModifiers(mod or 0)
    end
end

local function IsShiftOnlyModifier(mod)
    local label = ModifierLabel(mod)
    if not label or label == "" then
        return false
    end
    local upper = label:upper()
    return upper:find("SHIFT", 1, true)
        and not upper:find("CTRL", 1, true)
        and not upper:find("CONTROL", 1, true)
        and not upper:find("ALT", 1, true)
        and not upper:find("META", 1, true)
end

local function ResolveShiftModifier()
    for mod = 0, 63 do
        if IsShiftOnlyModifier(mod) then
            return mod
        end
    end
    return 1
end

local function EnsureClickCastingBinding()
    if not C_ClickBindings or not C_ClickBindings.GetProfileInfo or not C_ClickBindings.SetProfileByInfo then
        return false, "api_unavailable"
    end
    if InCombatLockdown() then
        return false, "combat"
    end

    local profile = C_ClickBindings.GetProfileInfo()
    if type(profile) ~= "table" then
        return false, "no_profile"
    end

    for _, info in ipairs(profile) do
        local isLeft = info.button == "LeftButton" or info.button == "Button1"
        if isLeft and IsShiftOnlyModifier(info.modifiers or 0) then
            if info.type == Enum.ClickBindingType.Interaction
                and info.actionID == Enum.ClickBindingInteraction.Target then
                return true, "already_bound"
            end
            return false, "conflict"
        end
    end

    local shiftMod = ResolveShiftModifier()
    for _, info in ipairs(profile) do
        if info.type == Enum.ClickBindingType.Interaction
            and info.actionID == Enum.ClickBindingInteraction.Target
            and not info.button then
            info.button = "LeftButton"
            info.modifiers = shiftMod
            C_ClickBindings.SetProfileByInfo(profile)
            return true, "updated_default"
        end
    end

    profile[#profile + 1] = {
        type = Enum.ClickBindingType.Interaction,
        actionID = Enum.ClickBindingInteraction.Target,
        button = "LeftButton",
        modifiers = shiftMod,
    }
    C_ClickBindings.SetProfileByInfo(profile)
    return true, "added"
end

-------------------------------------------------------------------------------
-- BetterBlizzPlates friendly clickthrough
-------------------------------------------------------------------------------

local friendlyInsetsCollapsed = false

local function FriendlyClickthroughEnabled()
    local db = _G.BetterBlizzPlatesDB
    return db and db.friendlyNameplateClickthrough
end

local function NormalFriendlyInsets()
    local db = _G.BetterBlizzPlatesDB or {}
    local halfExtraWidth = (db.nameplateExtraClickWidth or 0) / 2
    local halfExtraHeight = (db.nameplateExtraClickHeight or 0) / 2
    local halfVertAdj = (db.nameplateClickVerticalAdjustment or 0) / 2
    return
        1 - halfExtraWidth,
        1 - halfExtraWidth,
        -10 - halfExtraHeight + halfVertAdj,
        -1 - halfExtraHeight - halfVertAdj
end

local function UpdateFriendlyNameplateHitTest()
    if not C_NamePlateManager or not C_NamePlateManager.SetNamePlateHitTestInsets then
        return
    end
    if not FriendlyClickthroughEnabled() then
        friendlyInsetsCollapsed = false
        return
    end

    if IsShiftKeyDown() then
        if not friendlyInsetsCollapsed then
            return
        end
        local l, r, t, b = NormalFriendlyInsets()
        C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Friendly, l, r, t, b)
        friendlyInsetsCollapsed = false
    elseif not friendlyInsetsCollapsed then
        C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Friendly, 10000, 10000, 10000, 10000)
        friendlyInsetsCollapsed = true
    end
end

-------------------------------------------------------------------------------
-- Run / events
-------------------------------------------------------------------------------

local function RunFix(silent)
    local proxyOk, proxyReason = ApplyAll()
    local bindOk, bindReason = EnsureClickCastingBinding()
    UpdateFriendlyNameplateHitTest()

    if silent then
        return proxyOk, bindOk, bindReason, lastAppliedCount
    end

    if proxyOk then
        print(string.format(
            "|cff00ff00[%s]|r Applied secure proxy on %d unit button(s).",
            ADDON, lastAppliedCount))
    elseif proxyReason == "combat" then
        print("|cffff9900[" .. ADDON .. "]|r In combat - queued, will retry when combat ends.")
        pendingApply = true
    end

    if bindOk then
        if bindReason ~= "already_bound" then
            print("|cff00ff00[" .. ADDON .. "]|r Also registered Shift+Left -> Target in Click Casting.")
        end
    elseif bindReason == "conflict" then
        print("|cffff9900[" .. ADDON .. "]|r Shift+Left already bound in Click Casting to another action.")
    end

    if FriendlyClickthroughEnabled() then
        print("|cff00ff00[" .. ADDON .. "]|r Friendly nameplate clickthrough: hold Shift to click nameplates.")
    end

    return proxyOk, bindOk, bindReason, lastAppliedCount
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("MODIFIER_STATE_CHANGED")

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "MODIFIER_STATE_CHANGED" then
        UpdateFriendlyNameplateHitTest()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" and pendingApply then
        pendingApply = false
        RunFix(true)
        return
    end

    if event == "NAME_PLATE_UNIT_ADDED" then
        if not InCombatLockdown() then
            C_Timer.After(0, ApplyToNameplates)
        else
            pendingApply = true
        end
        return
    end

    if event == "PLAYER_LOGIN"
        or event == "PLAYER_ENTERING_WORLD"
        or event == "GROUP_ROSTER_UPDATE"
        or event == "PLAYER_SPECIALIZATION_CHANGED" then
        C_Timer.After(0, function() RunFix(true) end)
        C_Timer.After(1, function() RunFix(true) end)
    end
end)

if CompactUnitFrame_SetUpFrame then
    hooksecurefunc("CompactUnitFrame_SetUpFrame", function(frame)
        if not InCombatLockdown() then
            AttachShiftTarget(frame)
        else
            pendingApply = true
        end
    end)
end

do
    local hooked
    local function InstallClickCastHook()
        if hooked or type(ClickCastFrames) ~= "table" then
            return
        end
        hooked = true
        local old = ClickCastFrames
        ClickCastFrames = setmetatable({}, {
            __newindex = function(_, frame, value)
                if old then
                    rawset(old, frame, value)
                end
                if value and not InCombatLockdown() then
                    AttachShiftTarget(frame)
                end
            end,
            __index = function(_, frame)
                if old then
                    return rawget(old, frame)
                end
            end,
            __pairs = function()
                if old then
                    return pairs(old)
                end
                return pairs({})
            end,
        })
        for frame, val in pairs(old) do
            if val then
                AttachShiftTarget(frame)
            end
        end
    end

    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", InstallClickCastHook)
end

-------------------------------------------------------------------------------
-- Slash
-------------------------------------------------------------------------------

local function DebugDump()
    print("|cff00ff00[" .. ADDON .. " debug]|r")
    local attached = 0
    for _ in pairs(attachedFrames) do
        attached = attached + 1
    end
    print("  Attached frames: " .. attached)
    print("  Last apply count: " .. lastAppliedCount)
    print("  In combat: " .. tostring(InCombatLockdown()))

    if PlayerFrame and PlayerFrame.GetAttribute then
        print("  PlayerFrame shift-type1: " .. tostring(PlayerFrame:GetAttribute("shift-type1")))
        print("  PlayerFrame *shift-type1: " .. tostring(PlayerFrame:GetAttribute("*shift-type1")))
        print("  PlayerFrame unit attr: " .. tostring(PlayerFrame:GetAttribute("unit")))
        print("  PlayerFrame .unit: " .. tostring(PlayerFrame.unit))
    end

    if C_ClickBindings and C_ClickBindings.GetBindingType then
        local shiftMod = ResolveShiftModifier()
        local btype, action = C_ClickBindings.GetBindingType("LeftButton", shiftMod)
        print("  GetBindingType(shift+left): type=" .. tostring(btype) .. " action=" .. tostring(action))
    end
end

SLASH_SHIFTCLICKTARGETFIX1 = "/shiftfix"
SLASH_SHIFTCLICKTARGETFIX2 = "/shiftclicktargetfix"
SlashCmdList["SHIFTCLICKTARGETFIX"] = function(msg)
    msg = SafeTrim(msg):lower()
    print("|cff00ff00[" .. ADDON .. "]|r Running...")
    C_Timer.After(0, function()
        if msg == "debug" then
            RunFix(true)
            DebugDump()
        else
            RunFix(false)
        end
    end)
end