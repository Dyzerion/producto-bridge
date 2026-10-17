-- Corre las unitarias fuera de FXServer. Desde la raíz del repo:
--   lua tests/run.lua
-- (o con Docker: ver README.md)

dofile("tests/helpers.lua")
dofile("config.lua")
dofile("server/api.lua")
dofile("server/whitelist.lua")
dofile("server/commands.lua")
dofile("server/status.lua")

-- main.lua corre start() al cargarse: con llave simulada registra el
-- handler y deja el hilo de hello pendiente (CreateThread no ejecuta).
SimulatedNatives.convars["lobbynest_key"] = "pk_live_testllavedetest0000000000"
dofile("server/main.lua")

dofile("tests/test_backoff.lua")
dofile("tests/test_parse.lua")
dofile("tests/test_whitelist.lua")
dofile("tests/test_commands.lua")
dofile("tests/test_status.lua")
dofile("tests/test_plan.lua")

print("")
print(string.format("%d pasaron, %d fallaron", TestResults.passed, TestResults.failed))
if TestResults.failed > 0 then
  os.exit(1)
end
os.exit(0)
