-- Estado del servidor hacia la API: snapshot + heartbeat (F1-13).
BridgeStatus = {}

function BridgeStatus.snapshot()
  return {
    players = #GetPlayers(),
    maxPlayers = GetConvarInt("sv_maxclients", 32),
    uptimeSec = math.floor(GetGameTimer() / 1000),
  }
end

-- POST /heartbeat → 204. Devuelve el delay de backoff (nil = todo bien).
function BridgeStatus.heartbeat()
  local status = BridgeApi.await("/v1/bridge/heartbeat", {
    method = "POST",
    body = BridgeStatus.snapshot(),
  }, 10000)
  if status == 204 then
    BridgeApi.reportSuccess("heartbeat")
    return nil
  end
  return BridgeApi.reportFailure("heartbeat")
end
