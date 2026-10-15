-- Polling de comandos del panel: aplica whitelist.add / whitelist.remove
-- a la caché, guarda y manda ack (F1-13).
BridgeCommands = {}

-- 'applied' → cambió la caché (se persiste)
-- 'noop'    → ya estaba en ese estado
-- 'invalid' → payload.discordId inválido
-- 'unknown' → tipo fuera de contrato; se ack igual para que la API no lo
--             reenvíe para siempre.
function BridgeCommands.apply(command)
  local discordId = command.payload and command.payload.discordId
  if command.type == "whitelist.add" then
    if not BridgeApi.isValidDiscordId(discordId) then return "invalid" end
    return BridgeWhitelist.add(discordId) and "applied" or "noop"
  elseif command.type == "whitelist.remove" then
    if not BridgeApi.isValidDiscordId(discordId) then return "invalid" end
    return BridgeWhitelist.remove(discordId) and "applied" or "noop"
  end
  return "unknown"
end

-- Fire-and-forget: si el ack se pierde, la API reentrega el comando a los
-- 60 s y aplicarlo de nuevo es un noop.
function BridgeCommands.ack(commandId, ok, errorMessage)
  local body = ok and { ok = true } or { ok = false, error = errorMessage or "error" }
  BridgeApi.perform("/v1/bridge/commands/" .. commandId .. "/ack", {
    method = "POST",
    body = body,
  }, function() end)
end

-- GET /commands → aplica cada comando, guarda si cambió y manda ack.
-- Devuelve el delay de backoff (nil = usa el intervalo normal).
function BridgeCommands.poll()
  local status, body = BridgeApi.await("/v1/bridge/commands", nil, 10000)
  if status ~= 200 or body == nil then
    return BridgeApi.reportFailure("commands")
  end
  BridgeApi.reportSuccess("commands")
  local commands = BridgeApi.parseCommands(body)
  if commands == nil then return nil end
  for _, command in ipairs(commands) do
    local outcome = BridgeCommands.apply(command)
    if outcome == "applied" then
      BridgeWhitelist.save()
      BridgeCommands.ack(command.id, true)
    elseif outcome == "unknown" then
      BridgeCommands.ack(command.id, false, "comando desconocido")
    elseif outcome == "invalid" then
      BridgeCommands.ack(command.id, false, "discordId inválido")
    else
      BridgeCommands.ack(command.id, true)
    end
  end
  return nil
end
