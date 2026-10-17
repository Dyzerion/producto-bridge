-- Valores por defecto. El server.cfg manda en runtime con estas convars:
--   set lobbynest_key "pk_live_..."
--   set lobbynest_fail_mode "open" | "closed"
--   set lobbynest_api_url "https://api.lobbynest.xyz"   (solo para pruebas)
Config = {
  version = "0.2.0",

  -- TODO(D1): apuntar a producción al cerrar el dominio. F1-13 sigue
  -- abierta hasta D1: hoy el único entorno es staging.
  apiUrl = "https://api.lobbynest.xyz",
  failMode = "open",

  -- Reintento de hello cuando la API responde 402 (plan sin bridge):
  -- si el tenant sube de plan, el recurso reconecta solo en ≤ 15 min.
  planRetrySec = 900,

  -- Intervalos por defecto: el saludo (hello) puede ajustarlos.
  intervals = {
    heartbeatSec = 30,
    commandsSec = 5,
    whitelistSec = 600,
  },

  messages = {
    noKey = '[lobbynest] Sin llave: agrega  set lobbynest_key "pk_live_..."  a tu server.cfg y reinicia el servidor.',
    connected = "[lobbynest] conectado · %s · whitelist %s",
    updateOnce = "[lobbynest] hay una versión nueva disponible: %s (instalada: %s)",
    updateRequired = "[lobbynest] actualiza el recurso a la versión %s",
    invalidKey = "[lobbynest] llave inválida",
    netError = "[lobbynest] sin conexión con la API; reintentando",
    netRecovered = "[lobbynest] conexión restablecida",
    planUnavailable = "[lobbynest] tu plan no incluye la conexión in-game; la whitelist guardada sigue funcionando",
    noDiscord = "Abre Discord antes de entrar al servidor.",
    notWhitelisted = "No estás en la whitelist de este servidor. Pide tu acceso en el Discord del servidor para poder entrar.",
    verifyFailed = "No pudimos verificar tu acceso. Intenta en unos minutos.",
  },
}
