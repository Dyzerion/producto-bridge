-- F2-02 (modo 402, B-11/B-12): el hello con 402 avisa UNA vez, detiene
-- los bucles y al volver 200 los reanuda sin reiniciar.
--
-- Ojo con el estado compartido: este archivo se carga al final y los
-- tests 200/402 se apoyan en el orden de ejecución (200 → 402 → 402 →
-- 200), como el ciclo real de un tenant que baja y sube de plan.

local function callHello(status, body)
  local logs = {}
  local original = print
  print = function(...)
    local parts = {}
    for index = 1, select("#", ...) do
      parts[#parts + 1] = tostring(select(index, ...))
    end
    logs[#logs + 1] = table.concat(parts, " ")
  end
  local ok, action = pcall(Bridge.onHello, status, body)
  print = original
  if not ok then error(action, 0) end
  return action, logs
end

local function helloBody()
  return json.encode({
    whitelistEnabled = true,
    latestBridgeVersion = Config.version,
    intervals = { heartbeatSec = 30, commandsSec = 5, whitelistSec = 600 },
  })
end

test("hello 200 conecta y arranca los bucles", function()
  local action, logs = callHello(200, helloBody())
  assertEq(action, "connected")
  assertEq(#logs, 1, "aviso de conexión")
  assertContains(logs[1], "conectado · v0.2.0 · whitelist activa")
  assertTrue(Bridge.loopsRunning(), "bucles activos tras 200")
end)

test("hello 402 imprime el aviso de plan UNA vez y detiene los bucles", function()
  local action, logs = callHello(402, nil)
  assertEq(action, "plan")
  assertEq(#logs, 1, "un solo aviso")
  assertContains(logs[1], "tu plan no incluye la conexión in-game")
  assertContains(logs[1], "[lobbynest]")
  assertFalse(Bridge.loopsRunning(), "bucles detenidos en modo 402")

  -- Reintento a los 15 min con el plan todavía sin bridge: sin spam.
  local action2, logs2 = callHello(402, nil)
  assertEq(action2, "plan")
  assertEq(#logs2, 0, "sin aviso repetido")
end)

test("el jugador de la caché sigue entrando en modo 402", function()
  -- El handler de playerConnecting queda registrado desde start() aunque
  -- los bucles estén detenidos: el acceso con caché no depende de red.
  assertTrue(SimulatedNatives.handlers["playerConnecting"] ~= nil,
    "handler de playerConnecting registrado")
end)

test("al volver 200 se reanudan los bucles sin reiniciar", function()
  local action, logs = callHello(200, helloBody())
  assertEq(action, "connected")
  assertEq(#logs, 1, "aviso de reconexión")
  assertContains(logs[1], "conectado")
  assertTrue(Bridge.loopsRunning(), "bucles reanudados")

  -- Y si el plan vuelve a bajar, el aviso de plan se emite de nuevo
  -- (una vez por entrada en modo 402).
  local action3, logs3 = callHello(402, nil)
  assertEq(action3, "plan")
  assertEq(#logs3, 1, "aviso de plan otra vez, una sola vez")
  assertFalse(Bridge.loopsRunning(), "bucles vueltos a detener")
end)
