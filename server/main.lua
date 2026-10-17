-- Arranque, hello, bucles y conexión de jugadores (F1-13).
Bridge = {}

local connected = false  -- hello respondió 200 y los bucles corren
local stopped = false    -- 401/426: ya no se reintenta nada
local updateNotified = false

local function failOpen()
  return Config.failMode ~= "closed"
end

local function readConvars()
  BridgeApi.key = GetConvar("lobbynest_key", "")
  local apiUrl = GetConvar("lobbynest_api_url", "")
  if apiUrl ~= "" then Config.apiUrl = apiUrl end
  local failMode = GetConvar("lobbynest_fail_mode", "")
  if failMode == "open" or failMode == "closed" then
    Config.failMode = failMode
  end
end

-- Versión del FXServer para el hello (convar `version`; la API acepta
-- hasta 60 caracteres, lo que sobra se recorta).
local function fxserverVersion()
  local version = GetConvar("version", "unknown")
  if #version > 60 then version = version:sub(1, 60) end
  return version
end

-- Bucles de heartbeat / whitelist / comandos. Cada uno espera su
-- intervalo normal o el backoff si la última ronda falló.
local function startLoops()
  CreateThread(function()
    while true do
      local backoff = BridgeStatus.heartbeat()
      Wait((backoff or Config.intervals.heartbeatSec) * 1000)
    end
  end)
  CreateThread(function()
    while true do
      local backoff = BridgeWhitelist.fetch()
      Wait((backoff or Config.intervals.whitelistSec) * 1000)
    end
  end)
  CreateThread(function()
    while true do
      local backoff = BridgeCommands.poll()
      Wait((backoff or Config.intervals.commandsSec) * 1000)
    end
  end)
end

-- Respuesta del hello. Devuelve:
--   'connected' → todo bien, arrancan los bucles
--   'stopped'   → 401 o 426: se detiene
--   'retry'     → error de red o cuerpo ilegible (+ delay de backoff)
local function onHello(status, body)
  if status == 200 and body ~= nil then
    local hello = BridgeApi.parseHello(body)
    if hello ~= nil then
      connected = true
      BridgeApi.reportSuccess("hello")
      Config.intervals = hello.intervals
      BridgeWhitelist.setEnabled(hello.whitelistEnabled)
      if not updateNotified
        and BridgeApi.versionLt(Config.version, hello.latestBridgeVersion) then
        updateNotified = true
        print(string.format(Config.messages.updateOnce, hello.latestBridgeVersion, Config.version))
      end
      print(string.format(
        Config.messages.connected,
        "v" .. Config.version,
        BridgeWhitelist.isEnabled() and "activa" or "inactiva"
      ))
      startLoops()
      return "connected"
    end
    return "retry", BridgeApi.reportFailure("hello")
  end
  if status == 401 then
    stopped = true
    print(Config.messages.invalidKey)
    return "stopped"
  end
  if status == 426 then
    stopped = true
    local target = BridgeApi.parseMinVersion(body) or "la última versión disponible"
    print(string.format(Config.messages.updateRequired, target))
    return "stopped"
  end
  return "retry", BridgeApi.reportFailure("hello")
end

local function helloLoop()
  CreateThread(function()
    while true do
      local status, body = BridgeApi.await("/v1/bridge/hello", {
        method = "POST",
        body = {
          bridgeVersion = Config.version,
          fxserverVersion = fxserverVersion(),
          resourceName = GetCurrentResourceName(),
        },
      }, 10000)
      local action, delay = onHello(status, body)
      if action ~= "retry" then return end
      Wait((delay or 5) * 1000)
    end
  end)
end

-- playerConnecting con deferrals, en el orden del documento (F1-13):
-- siempre defer() + Wait(0) antes de cualquier HTTP.
local function registerConnecting()
  AddEventHandler("playerConnecting", function(_playerName, _setKickReason, deferrals)
    local sourceId = source
    deferrals.defer()
    Wait(0)

    if not BridgeWhitelist.isEnabled() then
      deferrals.done()
      return
    end

    local identifier = GetPlayerIdentifierByType(sourceId, "discord")
    local discordId = ""
    if identifier ~= nil then discordId = identifier:gsub("^discord:", "") end
    if not BridgeApi.isValidDiscordId(discordId) then
      deferrals.done(Config.messages.noDiscord)
      return
    end

    if BridgeWhitelist.has(discordId) then
      deferrals.done()
      return
    end

    local allowed = BridgeWhitelist.check(discordId)
    if allowed == true then
      if BridgeWhitelist.add(discordId) then BridgeWhitelist.save() end
      deferrals.done()
      return
    end
    if allowed == false then
      deferrals.done(Config.messages.notWhitelisted)
      return
    end
    -- Sin respuesta (timeout o red): manda fail_mode.
    if failOpen() then
      deferrals.done()
    else
      deferrals.done(Config.messages.verifyFailed)
    end
  end)
end

local function start()
  readConvars()
  if BridgeApi.key == "" then
    print(Config.messages.noKey)
    return
  end
  BridgeWhitelist.load()
  registerConnecting()
  helloLoop()
end

start()
