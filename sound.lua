-- The sound played on Enter: the first pop of macOS's Pop sound. Pop.aiff has
-- a second pop 60 ms in, so played whole it sounds like two.

local M = {}

local SOURCE = "/System/Library/Sounds/Pop.aiff"
local CACHE = os.getenv("HOME") .. "/Library/Caches/rex-tab-preview"
M.PATH = CACHE .. "/pop.wav"
-- The first pop has died away by 30 ms and the second starts at 60 ms; fading
-- out across that quiet gap ends the sound without a click.
local FADE_START, END = 0.030, 0.055

local function u16(s, i) return s:byte(i) + s:byte(i + 1) * 256 end
local function u32(s, i) return u16(s, i) + u16(s, i + 2) * 65536 end
local function le16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function le32(n) return le16(n % 65536) .. le16(math.floor(n / 65536)) end

local function read_sample(s, i)
  local v = u16(s, i)
  return v >= 32768 and v - 65536 or v
end

local function write_sample(v)
  return le16(v < 0 and v + 65536 or v)
end

-- The "fmt " and "data" chunks of a 16-bit WAV file.
local function parse_wav(wav)
  local fmt, data, i = nil, nil, 13
  while i + 7 <= #wav do
    local id, size = wav:sub(i, i + 3), u32(wav, i + 4)
    if id == "fmt " then fmt = wav:sub(i + 8, i + 7 + size) end
    if id == "data" then data = wav:sub(i + 8, i + 7 + size) end
    i = i + 8 + size + size % 2
  end
  return fmt, data
end

-- Rex's Lua can't table.concat much past 2000 pieces at once.
local CONCAT_LIMIT = 1000

local function join(parts)
  local chunks = {}
  for i = 1, #parts, CONCAT_LIMIT do
    chunks[#chunks + 1] = table.concat(parts, "", i, math.min(i + CONCAT_LIMIT - 1, #parts))
  end
  return table.concat(chunks)
end

local function first_pop(data, rate, channels)
  local start, stop = math.floor(FADE_START * rate), math.floor(END * rate)
  local out = {}
  for frame = 0, stop - 1 do
    local gain = frame < start and 1 or (stop - frame) / (stop - start)
    for c = 0, channels - 1 do
      local i = (frame * channels + c) * 2 + 1
      out[#out + 1] = write_sample(math.floor(read_sample(data, i) * gain))
    end
  end
  return join(out)
end

local function wav_file(fmt, data)
  return "RIFF" .. le32(4 + 8 + #fmt + 8 + #data) .. "WAVE"
    .. "fmt " .. le32(#fmt) .. fmt .. "data" .. le32(#data) .. data
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- Write the sound to M.PATH, unless it's already there.
function M.ensure()
  if read_file(M.PATH) then return end
  local whole = os.tmpname()
  rex.exec{ "mkdir", "-p", CACHE }
  rex.exec{ "afconvert", "-f", "WAVE", "-d", "LEI16", SOURCE, whole }
  local fmt, data = parse_wav(read_file(whole) or "")
  os.remove(whole)
  if not (fmt and data) then return end
  local channels, rate = u16(fmt, 3), u32(fmt, 5)
  -- Written beside M.PATH then renamed, so a half-written file is never played.
  local f = io.open(M.PATH .. ".tmp", "wb")
  f:write(wav_file(fmt, first_pop(data, rate, channels)))
  f:close()
  os.rename(M.PATH .. ".tmp", M.PATH)
end

return M
