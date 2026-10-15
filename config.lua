-- Valores por defecto. El server.cfg manda en runtime con estas convars:
--   set producto_key "pk_live_..."
--   set producto_fail_mode "open" | "closed"
--   set producto_api_url "https://api.lobbynest.xyz"   (solo para pruebas)
Config = {
  version = "0.1.0",

  -- Producción es F1-17; hasta entonces el único entorno es staging.
  apiUrl = "https://api.lobbynest.xyz",
  failMode = "open",

  -- Intervalos por defecto: el saludo (hello) puede ajustarlos.
  intervals = {
    heartbeatSec = 30,
    commandsSec = 5,
    whitelistSec = 600,
  },

  messages = {
    noKey = '[producto] Sin llave: agrega  set producto_key "pk_live_..."  a tu server.cfg y reinicia el servidor.',
    connected = "[producto] conectado · %s · whitelist %s",
    updateOnce = "[producto] hay una versión nueva disponible: %s (instalada: %s)",
    updateRequired = "[producto] actualiza el recurso a la versión %s",
    invalidKey = "[producto] llave inválida",
    netError = "[producto] sin conexión con la API; reintentando",
    netRecovered = "[producto] conexión restablecida",
    noDiscord = "Abre Discord antes de entrar al servidor.",
    notWhitelisted = "No estás en la whitelist de este servidor. Pide tu acceso en el Discord del servidor para poder entrar.",
    verifyFailed = "No pudimos verificar tu acceso. Intenta en unos minutos.",
  },
}
