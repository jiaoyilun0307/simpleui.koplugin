-- sui_raster_cache.lua — Simple UI
-- Byte-budgeted LRU for rasters that depend only on their geometry:
-- anti-aliased masks, shadows and sprites that are built once and blitted on
-- every paint.
--
-- An entry is a table. Its Blitbuffer fields are freed when the entry is
-- evicted or cleared, so an entry is only valid until the next get(): callers
-- fetch it and blit straight away, and never keep a reference.
--
-- Entries are grouped by kind. Keys are scoped to their kind, so each kind
-- picks the cheapest key for its geometry. The byte budget is shared by all
-- kinds; when it is exceeded the least recently used entries are dropped,
-- never the one just built.

local RasterCache = {}

local BYTE_BUDGET = 3 * 1024 * 1024

local _kinds       = {}   -- kind name -> { [key] = { value, bytes, tick } }
local _total_bytes = 0
local _tick        = 0

-- Resident byte size of a Blitbuffer. `stride` is the bytes per row of the
-- underlying C allocation, so `stride * height` is the true RAM footprint,
-- including row padding, at any bit depth (1 byte/px on grayscale e-ink,
-- 4 bytes/px on a colour panel). Shared by every cache that budgets by bytes.
function RasterCache.bbBytes(bb)
    if not bb then return 0 end
    local ok, bytes = pcall(function()
        local h = (bb.getHeight and bb:getHeight()) or tonumber(bb.h) or 0
        local stride = tonumber(bb.stride)
        if stride and h > 0 then return stride * h end
        local w   = (bb.getWidth and bb:getWidth()) or 0
        local bpp = (bb.getBpp and bb:getBpp()) or 8
        return w * h * math.ceil(bpp / 8)
    end)
    return (ok and bytes) or 0
end

local function entryBytes(value)
    local bytes = 0
    for _, field in pairs(value) do
        if type(field) == "cdata" then bytes = bytes + RasterCache.bbBytes(field) end
    end
    return bytes
end

local function freeEntry(record)
    for _, field in pairs(record.value) do
        if type(field) == "cdata" then field:free() end
    end
    _total_bytes = _total_bytes - record.bytes
end

-- Drops least recently used entries until the budget holds again. `keep` is
-- the record that was just inserted and is never evicted.
local function evictOverBudget(keep)
    while _total_bytes > BYTE_BUDGET do
        local oldest_kind, oldest_key, oldest
        for kind_name, entries in pairs(_kinds) do
            for key, record in pairs(entries) do
                if record ~= keep and (not oldest or record.tick < oldest.tick) then
                    oldest_kind, oldest_key, oldest = kind_name, key, record
                end
            end
        end
        if not oldest then return end
        freeEntry(oldest)
        _kinds[oldest_kind][oldest_key] = nil
    end
end

-- Returns the entry cached under (kind, key), building it with
-- build(...) on a miss. `build` returns the entry table.
function RasterCache.get(kind, key, build, ...)
    local entries = _kinds[kind]
    if not entries then
        entries = {}
        _kinds[kind] = entries
    end
    _tick = _tick + 1
    local record = entries[key]
    if record then
        record.tick = _tick
        return record.value
    end
    local value = build(...)
    record = { value = value, bytes = entryBytes(value), tick = _tick }
    entries[key] = record
    _total_bytes = _total_bytes + record.bytes
    evictOverBudget(record)
    return value
end

-- Frees every entry of `kind`, or of all kinds when `kind` is nil.
function RasterCache.clear(kind)
    for kind_name, entries in pairs(_kinds) do
        if kind == nil or kind == kind_name then
            for _, record in pairs(entries) do freeEntry(record) end
            _kinds[kind_name] = nil
        end
    end
end

return RasterCache
