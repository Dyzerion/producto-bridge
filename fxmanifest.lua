fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lobbynest-bridge'
description 'Bridge entre Lobbynest y tu servidor FiveM'
author 'Lobbynest'
version '0.1.0'
license 'MIT'

-- Solo servidor: esta versión no tiene scripts de cliente.
server_scripts {
  'config.lua',
  'server/api.lua',
  'server/whitelist.lua',
  'server/commands.lua',
  'server/status.lua',
  'server/main.lua',
}
