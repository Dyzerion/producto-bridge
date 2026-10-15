-- Parseo de respuestas de la API: hello, whitelist, comandos, 426 y
-- comparación semver.

test("parseo: versionLt compara numéricamente, no lexicográficamente", function()
  assertTrue(BridgeApi.versionLt("0.1.0", "0.2.0"), "minor avanza")
  assertTrue(BridgeApi.versionLt("0.9.0", "0.10.0"), "9 < 10 aunque '10' < '9'")
  assertTrue(BridgeApi.versionLt("1.0.0", "2.0.0"), "major avanza")
  assertFalse(BridgeApi.versionLt("0.1.0", "0.1.0"), "iguales")
  assertFalse(BridgeApi.versionLt("0.2.0", "0.1.0"), "al revés")
  assertFalse(BridgeApi.versionLt("basura", "0.1.0"), "izquierda inválida")
  assertFalse(BridgeApi.versionLt("0.1.0", "basura"), "derecha inválida")
end)

test("parseo: parseHello completo", function()
  local body = json.encode({
    serverId = "4c6f3b1a-1111-4222-8333-555566667777",
    whitelistEnabled = true,
    minBridgeVersion = "0.1.0",
    latestBridgeVersion = "0.2.0",
    intervals = { heartbeatSec = 30, commandsSec = 5, whitelistSec = 600 },
  })
  local hello = BridgeApi.parseHello(body)
  assertTrue(hello.whitelistEnabled, "whitelistEnabled")
  assertEq(hello.latestBridgeVersion, "0.2.0", "latestBridgeVersion")
  assertEq(hello.intervals.commandsSec, 5, "intervals del API")
end)

test("parseo: parseHello usa defaults si intervals falta o es malo", function()
  local hello = BridgeApi.parseHello(json.encode({
    whitelistEnabled = false,
    latestBridgeVersion = "0.1.0",
    intervals = { heartbeatSec = -5, commandsSec = "mucho" },
  }))
  assertFalse(hello.whitelistEnabled, "whitelistEnabled false")
  assertEq(hello.intervals.heartbeatSec, Config.intervals.heartbeatSec, "negativo → default")
  assertEq(hello.intervals.commandsSec, Config.intervals.commandsSec, "texto → default")
  assertEq(hello.intervals.whitelistSec, Config.intervals.whitelistSec, "faltante → default")
end)

test("parseo: parseHello devuelve nil ante cuerpos rotos o incompletos", function()
  assertNil(BridgeApi.parseHello("{esto no es json"), "JSON roto")
  assertNil(BridgeApi.parseHello(""), "vacío")
  assertNil(BridgeApi.parseHello(nil), "sin cuerpo")
  assertNil(BridgeApi.parseHello(json.encode({ whitelistEnabled = true })), "sin latestBridgeVersion")
end)

test("parseo: parseWhitelist filtra IDs que no son dígitos 17-20", function()
  local body = json.encode({
    version = 42,
    enabled = true,
    discordIds = {
      "570885174588854282",             -- 18 dígitos ✓
      "123",                            -- muy corto ✗
      "abcdefghijklmnopq",              -- no dígitos ✗
      string.rep("9", 21),              -- muy largo ✗
      "12345678901234567890",           -- 20 dígitos ✓
    },
  })
  local parsed = BridgeApi.parseWhitelist(body)
  assertEq(parsed.version, 42, "version")
  assertTrue(parsed.enabled, "enabled")
  assertEq(#parsed.discordIds, 2, "solo los dos válidos")
  assertEq(parsed.discordIds[1], "570885174588854282", "primero")
  assertEq(parsed.discordIds[2], "12345678901234567890", "segundo")
end)

test("parseo: parseWhitelist es nil si falta version", function()
  assertNil(BridgeApi.parseWhitelist(json.encode({ enabled = true, discordIds = {} })), "sin version")
  assertNil(BridgeApi.parseWhitelist("garbage"), "JSON roto")
end)

test("parseo: parseCommands conserva id/tipo/payload y descarta basura", function()
  local body = json.encode({
    commands = {
      {
        id = "11111111-1111-4111-8111-111111111111",
        type = "whitelist.add",
        payload = { discordId = "570885174588854282" },
      },
      {
        id = "22222222-2222-4222-8222-222222222222",
        type = "whitelist.remove",
      },
      { type = "sin-id" },
      {
        id = "33333333-3333-4333-8333-333333333333",
        payload = {},
      },
    },
  })
  local commands = BridgeApi.parseCommands(body)
  assertEq(#commands, 2, "solo los dos con id y tipo")
  assertEq(commands[1].type, "whitelist.add", "tipo")
  assertEq(commands[1].payload.discordId, "570885174588854282", "payload")
  assertEq(commands[2].type, "whitelist.remove", "sin payload → {}")
  assertEq(type(commands[2].payload), "table", "payload default tabla")
end)

test("parseo: parseMinVersion lee details.minVersion del sobre 426", function()
  local body = json.encode({
    error = {
      code = "BRIDGE_VERSION_UNSUPPORTED",
      message = "La versión del bridge ya no es compatible. Actualízala.",
      details = { minVersion = "0.2.0" },
    },
  })
  assertEq(BridgeApi.parseMinVersion(body), "0.2.0", "minVersion")
  assertNil(BridgeApi.parseMinVersion(json.encode({ error = { code = "X", message = "y" } })), "sin details")
  assertNil(BridgeApi.parseMinVersion("garbage"), "JSON roto")
end)

test("parseo: decodeBody tolera cuerpos nulos y rotos", function()
  assertNil(BridgeApi.decodeBody(nil), "nil")
  assertNil(BridgeApi.decodeBody(""), "vacío")
  assertNil(BridgeApi.decodeBody("no es json"), "roto")
  assertNil(BridgeApi.decodeBody('"string"'), "escalar no es tabla")
  assertEq(type(BridgeApi.decodeBody('{"a": 1}')), "table", "objeto válido")
end)
