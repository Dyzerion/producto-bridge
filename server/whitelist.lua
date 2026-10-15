-- Caché de whitelist en memoria + persistencia en cache/whitelist.json.
-- La lógica pura no toca natives salvo LoadResourceFile/SaveResourceFile,
-- simuladas en los tests.
BridgeWhitelist = {}
BridgeWhitelist.CACHE_PATH = "cache/whitelist.json"

local state = { enabled = false, version = 0, ids = {} }

function BridgeWhitelist.reset()
  state = { enabled = false, version = 0, ids = {} }
end

function BridgeWhitelist.isEnabled()
  return state.enabled
end

function BridgeWhitelist.setEnabled(enabled)
  state.enabled = enabled == true
end

function BridgeWhitelist.version()
  return state.version
end

function BridgeWhitelist.count()
  local count = 0
  for _ in pairs(state.ids) do count = count + 1 end
  return count
end

function BridgeWhitelist.has(discordId)
  return state.ids[discordId] == true
end

-- true si cambió la caché; false si el ID era inválido o ya estaba.
function BridgeWhitelist.add(discordId)
  if not BridgeApi.isValidDiscordId(discordId) then return false end
  if state.ids[discordId] then return false end
  state.ids[discordId] = true
  return true
end

-- true si había algo que quitar.
function BridgeWhitelist.remove(discordId)
  if state.ids[discordId] == nil then return false end
  state.ids[discordId] = nil
  return true
end

-- Reemplazo completo (GET /whitelist o archivo de caché ya parseado).
-- Los IDs inválidos se descartan.
function BridgeWhitelist.replace(version, enabled, discordIds)
  local ids = {}
  for _, discordId in ipairs(discordIds or {}) do
    if BridgeApi.isValidDiscordId(discordId) then ids[discordId] = true end
  end
  state = {
    version = type(version) == "number" and math.floor(version) or 0,
    enabled = enabled == true,
    ids = ids,
  }
end

-- ETag del recurso: "wl-{version}" (con comillas, como manda HTTP).
function BridgeWhitelist.etag()
  return string.format('"wl-%d"', state.version)
end

function BridgeWhitelist.serialize()
  local ids = {}
  for discordId in pairs(state.ids) do ids[#ids + 1] = discordId end
  table.sort(ids)
  return json.encode({
    v = state.version,
    enabled = state.enabled,
    ids = ids,
  })
end

-- false ante JSON roto o vacío: la caché queda como estaba.
function BridgeWhitelist.deserialize(text)
  if type(text) ~= "string" or text == "" then return false end
  local ok, data = pcall(json.decode, text)
  if not ok or type(data) ~= "table" then return false end
  local ids = type(data.ids) == "table" and data.ids or nil
  BridgeWhitelist.replace(data.v, data.enabled, ids)
  return true
end

function BridgeWhitelist.save()
  SaveResourceFile(GetCurrentResourceName(), BridgeWhitelist.CACHE_PATH, BridgeWhitelist.serialize(), -1)
end

function BridgeWhitelist.load()
  local text = LoadResourceFile(GetCurrentResourceName(), BridgeWhitelist.CACHE_PATH)
  if text == nil then return false end
  return BridgeWhitelist.deserialize(text)
end

-- GET /whitelist con If-None-Match: 304 no hace nada; 200 reemplaza la
-- caché y la guarda. Devuelve el delay de backoff (nil = todo bien).
function BridgeWhitelist.fetch()
  local status, body = BridgeApi.await("/v1/bridge/whitelist", {
    headers = { ["If-None-Match"] = BridgeWhitelist.etag() },
  }, 10000)
  if status == 304 then
    BridgeApi.reportSuccess("whitelist")
    return nil
  end
  if status ~= 200 or body == nil then
    return BridgeApi.reportFailure("whitelist")
  end
  local parsed = BridgeApi.parseWhitelist(body)
  if parsed == nil then
    return BridgeApi.reportFailure("whitelist")
  end
  BridgeWhitelist.replace(parsed.version, parsed.enabled, parsed.discordIds)
  BridgeWhitelist.save()
  BridgeApi.reportSuccess("whitelist")
  return nil
end

-- Verificación en vivo (4 s). true/false = respuesta de la API,
-- nil = sin respuesta (timeout o red).
function BridgeWhitelist.check(discordId)
  local status, body = BridgeApi.await("/v1/bridge/whitelist/" .. discordId, nil, 4000)
  if status ~= 200 or body == nil then return nil end
  local data = BridgeApi.decodeBody(body)
  if type(data) ~= "table" then return nil end
  if data.allowed == true then return true end
  if data.allowed == false then return false end
  return nil
end
