-- Andamiaje de tests: framework de 20 líneas, stub de JSON y natives
-- simuladas para correr la lógica pura fuera de FXServer.
--
-- IMPORTANTE: los módulos de server/ se cargan DESPUÉS de este archivo,
-- así que json y las natives simuladas ya existen cuando se ejecutan.

-- ---------------------------------------------------------------- framework

TestResults = { passed = 0, failed = 0 }

function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    TestResults.passed = TestResults.passed + 1
    print("ok   " .. name)
  else
    TestResults.failed = TestResults.failed + 1
    print("FAIL " .. name)
    print("     " .. tostring(err))
  end
end

local function failExpect(label, message, level)
  error(label .. ": " .. message, level or 3)
end

function assertEq(actual, expected, label)
  if actual ~= expected then
    failExpect(label or "assertEq",
      string.format("esperado %s, llegó %s", tostring(expected), tostring(actual)))
  end
end

function assertTrue(value, label)
  if value ~= true then
    failExpect(label or "assertTrue", "esperado true, llegó " .. tostring(value))
  end
end

function assertFalse(value, label)
  if value ~= false then
    failExpect(label or "assertFalse", "esperado false, llegó " .. tostring(value))
  end
end

function assertNil(value, label)
  if value ~= nil then
    failExpect(label or "assertNil", "esperado nil, llegó " .. tostring(value))
  end
end

function assertContains(text, needle, label)
  if type(text) ~= "string" or not text:find(needle, 1, true) then
    failExpect(label or "assertContains",
      string.format("'%s' no contiene '%s'", tostring(text), tostring(needle)))
  end
end

-- Ejecuta fn capturando print y devuelve las líneas impresas.
function capturePrints(fn)
  local logs = {}
  local original = print
  print = function(...)
    local parts = {}
    for index = 1, select("#", ...) do
      parts[#parts + 1] = tostring(select(index, ...))
    end
    logs[#logs + 1] = table.concat(parts, " ")
  end
  local ok, err = pcall(fn)
  print = original
  if not ok then error(err, 0) end
  return logs
end

-- ---------------------------------------------------------------- json stub
-- Codec JSON mínimo (objetivos, arrays, strings, números, boolean) para
-- los tests. `null` se decodifica como nil y nunca se emite. En FXServer
-- esto lo reemplaza el global `json` del runtime.

local function encodeString(value)
  return '"' .. value:gsub('[%c"\\]', function(char)
    local named = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n",
      ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f" }
    return named[char] or string.format("\\u%04x", char:byte())
  end) .. '"'
end

local function isArray(value)
  local count, maxKey = 0, 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
    count = count + 1
    if key > maxKey then maxKey = key end
  end
  if count == 0 then return false end  -- vacío → objeto (como dkjson)
  return maxKey == count
end

local encodeValue
encodeValue = function(value, depth)
  if depth > 32 then error("json: demasiado profundo") end
  if value == nil then return "null" end
  local kind = type(value)
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then
    if math.type(value) == "integer" then return tostring(value) end
    if value ~= value or value == math.huge or value == -math.huge then
      error("json: número inválido")
    end
    return string.format("%.14g", value)
  end
  if kind == "string" then return encodeString(value) end
  if kind == "table" then
    local parts = {}
    if isArray(value) then
      for index = 1, #value do
        parts[index] = encodeValue(value[index], depth + 1)
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for key, item in pairs(value) do
      if type(key) ~= "string" then error("json: clave que no es string") end
      parts[#parts + 1] = encodeString(key) .. ":" .. encodeValue(item, depth + 1)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  error("json: no se puede codificar " .. kind)
end

local function skipWhitespace(text, index)
  while true do
    local char = text:sub(index, index)
    if char == " " or char == "\t" or char == "\r" or char == "\n" then
      index = index + 1
    else
      return index
    end
  end
end

local decodeValue

local function decodeString(text, index)  -- index en la comilla de apertura
  local parts = {}
  index = index + 1
  while true do
    local char = text:sub(index, index)
    if char == "" then error("json: string sin cerrar") end
    if char == '"' then return table.concat(parts), index + 1 end
    if char == "\\" then
      local escape = text:sub(index + 1, index + 1)
      if escape == "u" then
        local code = tonumber(text:sub(index + 2, index + 5), 16)
        if code == nil then error("json: escape \\u inválido") end
        if code < 0x80 then
          parts[#parts + 1] = string.char(code)
        elseif code < 0x800 then
          parts[#parts + 1] = string.char(
            0xC0 + math.floor(code / 64), 0x80 + (code % 64))
        else
          parts[#parts + 1] = string.char(
            0xE0 + math.floor(code / 4096),
            0x80 + (math.floor(code / 64) % 64),
            0x80 + (code % 64))
        end
        index = index + 6
      else
        local named = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
          b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
        local mapped = named[escape]
        if mapped == nil then error("json: escape inválido \\" .. escape) end
        parts[#parts + 1] = mapped
        index = index + 2
      end
    else
      parts[#parts + 1] = char
      index = index + 1
    end
  end
end

decodeValue = function(text, index)
  index = skipWhitespace(text, index)
  local char = text:sub(index, index)
  if char == "{" then
    local object = {}
    index = skipWhitespace(text, index + 1)
    if text:sub(index, index) == "}" then return object, index + 1 end
    while true do
      if text:sub(index, index) ~= '"' then error("json: falta la clave") end
      local key
      key, index = decodeString(text, index)
      index = skipWhitespace(text, index)
      if text:sub(index, index) ~= ":" then error("json: falta ':'") end
      local value
      value, index = decodeValue(text, index + 1)
      object[key] = value
      index = skipWhitespace(text, index)
      local separator = text:sub(index, index)
      if separator == "," then
        index = skipWhitespace(text, index + 1)
      elseif separator == "}" then
        return object, index + 1
      else
        error("json: falta ',' o '}'")
      end
    end
  elseif char == "[" then
    local array = {}
    index = skipWhitespace(text, index + 1)
    if text:sub(index, index) == "]" then return array, index + 1 end
    while true do
      local value
      value, index = decodeValue(text, index)
      array[#array + 1] = value
      index = skipWhitespace(text, index)
      local separator = text:sub(index, index)
      if separator == "," then
        index = skipWhitespace(text, index + 1)
      elseif separator == "]" then
        return array, index + 1
      else
        error("json: falta ',' o ']'")
      end
    end
  elseif char == '"' then
    return decodeString(text, index)
  elseif text:sub(index, index + 3) == "true" then
    return true, index + 4
  elseif text:sub(index, index + 4) == "false" then
    return false, index + 5
  elseif text:sub(index, index + 3) == "null" then
    return nil, index + 4
  else
    local number = text:sub(index):match("^%-?%d+%.?%d*[eE]?[-+]?%d*")
    local parsed = number ~= nil and tonumber(number) or nil
    if parsed == nil then error("json: valor inesperado en " .. index) end
    return parsed, index + #number
  end
end

json = {}

function json.encode(value)
  return encodeValue(value, 0)
end

function json.decode(text)
  if type(text) ~= "string" then error("json: se esperaba string") end
  local value, index = decodeValue(text, 1)
  if not text:sub(index):match("^%s*$") then error("json: basura al final") end
  return value
end

-- ------------------------------------------------------- natives simuladas

SimulatedNatives = {
  resource = "producto-bridge",
  files = {},        -- path → contenido (para Load/SaveResourceFile)
  lastSave = nil,    -- últimos argumentos de SaveResourceFile
  players = {},      -- GetPlayers
  convars = {},      -- GetConvarInt
  gameTimer = 0,     -- GetGameTimer (ms)
}

function GetCurrentResourceName()
  return SimulatedNatives.resource
end

function SaveResourceFile(resourceName, fileName, data, dataLength)
  SimulatedNatives.lastSave = {
    resourceName = resourceName,
    fileName = fileName,
    data = data,
    dataLength = dataLength,
  }
  SimulatedNatives.files[fileName] = data
end

function LoadResourceFile(resourceName, fileName)
  return SimulatedNatives.files[fileName]
end

function GetPlayers()
  return SimulatedNatives.players
end

function GetConvarInt(name, default)
  local value = SimulatedNatives.convars[name]
  if value == nil then return default end
  return value
end

function GetGameTimer()
  return SimulatedNatives.gameTimer
end
