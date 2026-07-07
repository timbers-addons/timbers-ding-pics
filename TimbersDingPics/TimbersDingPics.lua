local addon = ...

local TDP = _G[addon] or {}
_G[addon] = TDP

TDP.slashCmdName = "tdp"
TDP.addonHash = "c43a2a1"
TDP.manifestVersion = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addon, "Version")) or GetAddOnMetadata(addon, "Version") or "unknown"
TDP.manifestAuthor = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addon, "Author")) or GetAddOnMetadata(addon, "Author") or "unknown"
TDP.deathScreenshots = false
TDP.showStartupMessage = true
TDP.levelStartTimestamp = nil
TDP.awaitingTimePlayed = false

local DB_NAME = "TimbersDingPicsDB"

function TDP:LoadSettings()
  local db = _G[DB_NAME]
  if type(db) ~= "table" then
    db = {}
  end
  _G[DB_NAME] = db

  if db.deathScreenshots == nil then
    db.deathScreenshots = false
  end
  if db.showStartupMessage == nil then
    db.showStartupMessage = true
  end

  self.deathScreenshots = db.deathScreenshots and true or false
  self.showStartupMessage = db.showStartupMessage and true or false
end

function TDP:SaveSettings()
  local db = _G[DB_NAME]
  if type(db) ~= "table" then
    db = {}
    _G[DB_NAME] = db
  end
  db.deathScreenshots = self.deathScreenshots and true or false
  db.showStartupMessage = self.showStartupMessage and true or false
end

local addonTitle = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addon, "Title")) or GetAddOnMetadata(addon, "Title") or addon
local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[" .. addonTitle .. "]:|r " .. msg)
end

local function FormatDuration(seconds)
  seconds = math.max(0, math.floor(seconds or 0))
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  local secs = seconds % 60
  if hours > 0 then
    return string.format("%d hours %d minutes %d seconds", hours, minutes, secs)
  end
  if minutes > 0 then
    return string.format("%d minutes %d seconds", minutes, secs)
  end
  return string.format("%d seconds", secs)
end

function TDP:SetDeathScreenshots(enabled)
  self.deathScreenshots = enabled and true or false
  self:SaveSettings()
  Print("Death screenshots " .. (self.deathScreenshots and "enabled." or "disabled."))
end

function TDP:SetStartupMessage(enabled)
  self.showStartupMessage = enabled and true or false
  self:SaveSettings()
  Print("Startup message " .. (self.showStartupMessage and "enabled." or "disabled."))
end

function TDP:ToggleStartupMessage()
  self:SetStartupMessage(not self.showStartupMessage)
end

function TDP:ToggleDeathScreenshots()
  self:SetDeathScreenshots(not self.deathScreenshots)
end

-- Track the frame timestamp of the most recent external RequestTimePlayed call.
-- GetTime() is frame-locked in WoW, so calls within the same event frame share
-- the same value. This lets us distinguish "another addon called it this frame"
-- (same timestamp = same level-up event) from stale calls in earlier frames.
local tdpRequesting = false
local lastExternalPlayedTime = -math.huge

hooksecurefunc("RequestTimePlayed", function()
  if not tdpRequesting then
    lastExternalPlayedTime = GetTime()
  end
end)

function TDP:RequestLevelPlayedBaseline()
  self.awaitingTimePlayed = true
  tdpRequesting = true
  RequestTimePlayed()
  tdpRequesting = false
end

function TDP:HandleTimePlayed(_totalPlayedSeconds, levelPlayedSeconds)
  local levelSeconds = tonumber(levelPlayedSeconds)
  local now = time()
  if levelSeconds and levelSeconds >= 0 then
    self.levelStartTimestamp = now - levelSeconds
  else
    self.levelStartTimestamp = now
  end
  self.awaitingTimePlayed = false
end

function TDP:PrintLevelTiming(newLevel)
  local level = tonumber(newLevel) or UnitLevel("player")
  local now = time()

  if self.levelStartTimestamp and level > 1 then
    local elapsed = now - self.levelStartTimestamp
    Print(string.format("Ding! Level %d! That took %s", level, FormatDuration(elapsed)))
  else
    Print(string.format("Level %d reached.", level))
  end

  self.levelStartTimestamp = now
end

local function TakeScreenshotWithDelay()
  -- Capture the current frame timestamp. After one frame (C_Timer.After(0)) all
  -- other PLAYER_LEVEL_UP handlers will have run. If any called RequestTimePlayed
  -- in this same frame, lastExternalPlayedTime will equal scheduledAt and we skip
  -- our call. Calls from earlier frames have a smaller timestamp and are ignored.
  local scheduledAt = GetTime()
  C_Timer.After(0, function()
    if lastExternalPlayedTime < scheduledAt then
      tdpRequesting = true
      RequestTimePlayed()
      tdpRequesting = false
    end
  end)
  C_Timer.After(0.8, function()
    Screenshot()
  end)
end

function TDP:Help(extra)
  if extra then
    Print(extra)
  end
  local status = self.deathScreenshots and "enabled" or "disabled"
  Print(string.format(
    "Commands:\n/tdp death -- take a screenshot whenever your character dies (Current status: %s)\n/tdp startup -- toggle startup message (Current status: %s)\n/tdp version -- shows addon version",
    status,
    self.showStartupMessage and "enabled" or "disabled"
  ))
end

function TDP:Slash(arg)
  local cmd = string.lower(strtrim(arg or ""))

  if cmd == "" then
    self:Help()
    return
  end

  if cmd == "v" or cmd == "version" then
    Print("Version " .. self.manifestVersion)
  elseif cmd == "death" then
    self:ToggleDeathScreenshots()
  elseif cmd == "startup" then
    self:ToggleStartupMessage()
  else
    self:Help("Unknown command: " .. cmd)
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("TIME_PLAYED_MSG")

frame:SetScript("OnEvent", function(_frame, event, ...)
  if event == "ADDON_LOADED" then
    local loadedAddon = ...
    if loadedAddon ~= addon then
      return
    end
    TDP:LoadSettings()
    if TDP.showStartupMessage then
      Print("by " .. TDP.manifestAuthor .. ". Type /tdp for commands")
    end
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    TDP:RequestLevelPlayedBaseline()
  elseif event == "TIME_PLAYED_MSG" then
    local totalPlayedSeconds, levelPlayedSeconds = ...
    if TDP.awaitingTimePlayed or not TDP.levelStartTimestamp then
      TDP:HandleTimePlayed(totalPlayedSeconds, levelPlayedSeconds)
    end
  elseif event == "PLAYER_LEVEL_UP" then
    local newLevel = ...
    TDP:PrintLevelTiming(newLevel)
    TakeScreenshotWithDelay()
  elseif event == "PLAYER_DEAD" and TDP.deathScreenshots then
    TakeScreenshotWithDelay()
  end
end)

SlashCmdList["TimbersDingPics_Slash_Command"] = function(arg)
  TDP:Slash(arg)
end
SLASH_TimbersDingPics_Slash_Command1 = "/tdp"
SLASH_TimbersDingPics_Slash_Command2 = "/timbersdingpics"