# lobbynest-bridge

Bridge entre **Lobbynest** y tu servidor FiveM: mantiene la whitelist del
panel sincronizada con el servidor, reporta estado y aplica cambios al
vuelo. **Solo servidor** (no hay scripts de cliente).

## Instalación en 5 pasos

1. Descarga la [última release](https://github.com/dyzerion/lobbynest-bridge/releases/latest)
   y descomprime la carpeta `lobbynest-bridge` dentro de tu `resources/`.
2. Agrega esta línea en tu `server.cfg`:

   ```cfg
   ensure lobbynest-bridge
   ```

3. Copia la llave desde el panel de Lobbynest (menú **Servidor** →
   **Generar llave**) y pégala en el `server.cfg`
   (`set`, **NO** `setr` — con `setr` cualquier jugador podría leerla):

   ```cfg
   set lobbynest_key "pk_live_…"
   ```

4. Elige cómo fallar cuando la API no responda:

   ```cfg
   set lobbynest_fail_mode "open"    # open: deja pasar · closed: no deja pasar
   ```

5. Reinicia el servidor y mira la consola:

   ```text
   [lobbynest] conectado · v0.2.0 · whitelist activa
   ```

Opcional (solo para pruebas): apuntar a otro entorno con
`set lobbynest_api_url "https://api.lobbynest.xyz"`.

## Qué hace

| Momento | Hace |
|---|---|
| Arranque | Lee convars, carga `cache/whitelist.json` y saluda a la API |
| Cada 30 s | Heartbeat: jugadores, slots y uptime |
| Cada 5 s | Aplica los comandos `whitelist.add` / `whitelist.remove` del panel |
| Cada 600 s | Refresca la whitelist completa (con ETag) |
| Un jugador entra | Verifica su Discord contra la caché; si no está, consulta en vivo (4 s) |
| Plan sin conexión in-game (402) | Un aviso en consola, se detienen los bucles y la whitelist guardada sigue decidiendo quién entra; reintenta solo cada 15 min |

Los intervalos 30 / 5 / 600 son los valores por defecto: la API puede
ajustarlos durante el saludo inicial. Si la API falla, cada bucle reintenta
con backoff 5 → 10 → 20 → 40 → 60 s y la consola avisa una sola vez.

## Planes y la whitelist

Si tu plan de Lobbynest deja de incluir la conexión in-game, el recurso
imprime **una sola vez** `[lobbynest] tu plan no incluye la conexión
in-game; la whitelist guardada sigue funcionando` y deja de hablar con la
API. Nada se borra: los jugadores aprobados siguen entrando con la caché
local (`cache/whitelist.json`) y tu `lobbynest_fail_mode` decide qué pasa
con quien no está en ella. Si el plan vuelve a incluir la conexión, el
recurso reconecta solo en ≤ 15 minutos, sin reiniciar el servidor.

## Pruebas

Unitarias de la lógica pura (caché, backoff, parseo) fuera de FXServer, con
natives simuladas:

```sh
lua tests/run.lua        # con Lua 5.4 instalado
```

O sin instalar nada (Docker):

```sh
# Linux / macOS
docker run --rm -v "$(pwd):/src" -w /src alpine:3.20 sh -c "apk add --no-cache lua5.4 >/dev/null; lua5.4 tests/run.lua"

# Windows (PowerShell)
docker run --rm -v "${PWD}:/src" -w /src alpine:3.20 sh -c "apk add --no-cache lua5.4 >/dev/null; lua5.4 tests/run.lua"
```

## Licencia

MIT — ver [LICENSE](LICENSE).
