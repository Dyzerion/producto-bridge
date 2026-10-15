-- Aplicación de comandos del panel a la caché.

local function cleanState()
  BridgeWhitelist.reset()
  SimulatedNatives.files = {}
end

local ID = "570885174588854282"

test("commands: whitelist.add → applied y después noop", function()
  cleanState()
  local command = { type = "whitelist.add", payload = { discordId = ID } }
  assertEq(BridgeCommands.apply(command), "applied", "primera vez")
  assertTrue(BridgeWhitelist.has(ID), "quedó en la caché")
  assertEq(BridgeCommands.apply(command), "noop", "ya estaba")
end)

test("commands: whitelist.remove → applied y después noop", function()
  cleanState()
  BridgeWhitelist.add(ID)
  local command = { type = "whitelist.remove", payload = { discordId = ID } }
  assertEq(BridgeCommands.apply(command), "applied", "primera vez")
  assertFalse(BridgeWhitelist.has(ID), "salió de la caché")
  assertEq(BridgeCommands.apply(command), "noop", "ya no estaba")
end)

test("commands: IDs inválidos → invalid y no tocan la caché", function()
  cleanState()
  assertEq(
    BridgeCommands.apply({ type = "whitelist.add", payload = { discordId = "no" } }),
    "invalid", "add con ID malo")
  assertEq(
    BridgeCommands.apply({ type = "whitelist.remove", payload = { discordId = "1234" } }),
    "invalid", "remove con ID malo")
  assertEq(
    BridgeCommands.apply({ type = "whitelist.add", payload = {} }),
    "invalid", "sin discordId")
  assertEq(BridgeWhitelist.count(), 0, "la caché no cambió")
end)

test("commands: tipo desconocido → unknown", function()
  cleanState()
  assertEq(
    BridgeCommands.apply({ type = "whitelist.ban", payload = { discordId = ID } }),
    "unknown", "tipo fuera de contrato")
  assertEq(
    BridgeCommands.apply({ type = "otra.cosa", payload = {} }),
    "unknown", "otro tipo")
  assertEq(BridgeWhitelist.count(), 0, "la caché no cambió")
end)
