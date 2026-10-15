-- Capa HTTP (PerformHttpRequest) y lógica pura de backoff y parseo.
-- Los parsers, el backoff y el estado de error no tocan natives: se
-- unit-testean fuera de FXServer (tests/run.lua).
BridgeApi = {}
BridgeApi.key = nil

local BACKOFF_BASE_SEC = 5
local BACKOFF_MAX_SEC = 60

-- Backoff exponencial: 5 → 10 → 20 → 40 → 60 (tope en 60 s).
function BridgeApi.backoffDelay(attempt)
  if attempt < 1 then attempt = 1 end
  local delay = BACKOFF_BASE_SEC * 2 ^ (attempt - 1)
  if delay > BACKOFF_MAX_SEC then return BACKOFF_MAX_SEC end
  return math.floor(delay)
end

local failures = {}
local inError = false

-- Fallo de un bucle: un solo aviso de consola al entrar en error y el
-- delay de backoff para que ese bucle reintente.
function BridgeApi.reportFailure(name)
  failures[name] = (failures[name] or 0) + 1
  if not inError then
    inError = true
    print(Config.messages.netError)
  end
  return BridgeApi.backoffDelay(failures[name])
end

-- Éxito de un bucle: resetea su backoff. El aviso de recuperación solo
-- sale cuando TODOS los bucles están sanos.
function BridgeApi.reportSuccess(name)
  failures[name] = 0
  if not inError then return end
  for _, count in pairs(failures) do
    if count > 0 then return end
  end
  inError = false
  print(Config.messages.netRecovered)
end

-- Solo para tests: limpia el estado de error.
function BridgeApi.resetErrors()
  failures = {}
  inError = false
end

-- JSON → tabla. nil ante cuerpo vacío o roto.
function BridgeApi.decodeBody(body)
  if type(body) ~= "string" or body == "" then return nil end
  local ok, value = pcall(json.decode, body)
  if not ok or type(value) ~= "table" then return nil end
  return value
end

-- ¿a < b en semver (x.y.z)? Solo compara si ambos lados parsean.
function BridgeApi.versionLt(a, b)
  local function parts(value)
    local major, minor, patch = tostring(value):match("^(%d+)%.(%d+)%.(%d+)$")
    if major == nil then return nil end
    return tonumber(major), tonumber(minor), tonumber(patch)
  end
  local a1, a2, a3 = parts(a)
  if a1 == nil then return false end
  local b1, b2, b3 = parts(b)
  if b1 == nil then return false end
  if a1 ~= b1 then return a1 < b1 end
  if a2 ~= b2 then return a2 < b2 end
  return a3 < b3
end

local function positiveInt(value, fallback)
  if type(value) ~= "number" or value < 1 or value ~= value then
    return fallback
  end
  return math.floor(value)
end

function BridgeApi.parseIntervals(intervals)
  if type(intervals) ~= "table" then return nil end
  return {
    heartbeatSec = positiveInt(intervals.heartbeatSec, Config.intervals.heartbeatSec),
    commandsSec = positiveInt(intervals.commandsSec, Config.intervals.commandsSec),
    whitelistSec = positiveInt(intervals.whitelistSec, Config.intervals.whitelistSec),
  }
end

function BridgeApi.parseHello(body)
  local data = BridgeApi.decodeBody(body)
  if type(data) ~= "table" or type(data.latestBridgeVersion) ~= "string" then
    return nil
  end
  local intervals = BridgeApi.parseIntervals(data.intervals)
  if intervals == nil then
    intervals = {
      heartbeatSec = Config.intervals.heartbeatSec,
      commandsSec = Config.intervals.commandsSec,
      whitelistSec = Config.intervals.whitelistSec,
    }
  end
  return {
    whitelistEnabled = data.whitelistEnabled == true,
    latestBridgeVersion = data.latestBridgeVersion,
    intervals = intervals,
  }
end

function BridgeApi.isValidDiscordId(value)
  return type(value) == "string"
    and #value >= 17
    and #value <= 20
    and value:match("^%d+$") ~= nil
end

function BridgeApi.parseWhitelist(body)
  local data = BridgeApi.decodeBody(body)
  if type(data) ~= "table" or type(data.version) ~= "number" then return nil end
  local discordIds = {}
  if type(data.discordIds) == "table" then
    for _, discordId in ipairs(data.discordIds) do
      if BridgeApi.isValidDiscordId(discordId) then
        discordIds[#discordIds + 1] = discordId
      end
    end
  end
  return {
    version = math.floor(data.version),
    enabled = data.enabled == true,
    discordIds = discordIds,
  }
end

function BridgeApi.parseCommands(body)
  local data = BridgeApi.decodeBody(body)
  if type(data) ~= "table" or type(data.commands) ~= "table" then return nil end
  local commands = {}
  for _, raw in ipairs(data.commands) do
    if type(raw) == "table" and type(raw.id) == "string" and type(raw.type) == "string" then
      commands[#commands + 1] = {
        id = raw.id,
        type = raw.type,
        payload = type(raw.payload) == "table" and raw.payload or {},
      }
    end
  end
  return commands
end

-- Sobre de error 426: details.minVersion (si no, nil y el llamador cae
-- en el mensaje genérico).
function BridgeApi.parseMinVersion(body)
  local data = BridgeApi.decodeBody(body)
  if type(data) ~= "table" or type(data.error) ~= "table" then return nil end
  local details = data.error.details
  if type(details) == "table" and type(details.minVersion) == "string" then
    return details.minVersion
  end
  return nil
end

-- Lanza el request. options: { method, body, headers }.
-- cb(status, body); status es nil cuando no hubo respuesta de red.
function BridgeApi.perform(path, options, cb)
  options = options or {}
  local payload = ""
  local headers = {
    ["Authorization"] = "Bearer " .. tostring(BridgeApi.key),
    ["x-bridge-version"] = Config.version,
  }
  if options.body ~= nil then
    payload = json.encode(options.body)
    headers["content-type"] = "application/json"
  end
  if options.headers ~= nil then
    for name, value in pairs(options.headers) do headers[name] = value end
  end
  PerformHttpRequest(Config.apiUrl .. path, function(status, response)
    cb(status, response)
  end, options.method or "GET", payload, headers)
end

-- Igual que perform, pero espera la respuesta cediendo el hilo (Wait(0))
-- hasta timeoutMs: nunca bloquea el hilo. Devuelve status (nil si no hubo
-- respuesta o hubo timeout) y body.
function BridgeApi.await(path, options, timeoutMs)
  local done, status, response = false, nil, nil
  BridgeApi.perform(path, options, function(requestStatus, body)
    done, status, response = true, requestStatus, body
  end)
  local deadline = GetGameTimer() + (timeoutMs or 10000)
  while not done and GetGameTimer() < deadline do
    Wait(0)
  end
  if not done then return nil, nil end
  return status, response
end
