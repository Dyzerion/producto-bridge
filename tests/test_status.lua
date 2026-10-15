-- Snapshot del heartbeat con natives simuladas (GetPlayers,
-- GetConvarInt, GetGameTimer).

test("status: snapshot usa jugadores, convar y timer simulados", function()
  SimulatedNatives.players = { "1", "2", "3" }
  SimulatedNatives.convars = { sv_maxclients = 64 }
  SimulatedNatives.gameTimer = 5500
  local snapshot = BridgeStatus.snapshot()
  assertEq(snapshot.players, 3, "players")
  assertEq(snapshot.maxPlayers, 64, "maxPlayers desde la convar")
  assertEq(snapshot.uptimeSec, 5, "uptime en segundos")
end)

test("status: sin convar sv_maxclients cae en 32 (default del documento)", function()
  SimulatedNatives.players = {}
  SimulatedNatives.convars = {}
  SimulatedNatives.gameTimer = 0
  local snapshot = BridgeStatus.snapshot()
  assertEq(snapshot.players, 0, "sin jugadores")
  assertEq(snapshot.maxPlayers, 32, "default 32")
  assertEq(snapshot.uptimeSec, 0, "uptime 0")
end)
