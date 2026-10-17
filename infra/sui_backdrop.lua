-- sui_backdrop.lua — Simple UI
-- Translucent surface painting shared by every bar, card and label that can
-- sit over a background image.
--
-- A surface has three properties:
--   strength  0–100 opacity of the fill
--               0    transparent — nothing is painted
--               1–99 scrim — the tone blended over what is already there
--               100  solid
--   tone      "white" or "gray": the colour of the fill
--   frame     whether a border is drawn around the surface
--
-- This module provides:
--   * the strength scale: clamping, persistence and menu label;
--   * the tones and the registry of surfaces with their semantic defaults;
--   * surface descriptors: where a surface keeps its settings, and resolve,
--     which turns them into the values a painter needs;
--   * the painters: paintBackdrop (anti-aliased fill), paintFrame
--     (anti-aliased border), paintSurface (a resolved box surface) and
--     paintBar (a resolved full-width bar);
--   * BackdropFill, a background-layer widget built on the painters.
--
-- It knows nothing about the wallpaper itself. Deciding whether a backdrop
-- applies (for instance, only while a wallpaper is active) is left to callers.

local Device      = require("device")
local Screen      = Device.screen
local Geom        = require("ui/geometry")
local Widget      = require("ui/widget/widget")
local AA          = require("infra/sui_aa_paint")
local SUISettings = require("infra/sui_store")
local translate   = require("infra/sui_i18n").translate

local M = {}

-- The style catalogue lives in a higher layer, so it is resolved on first use
-- rather than at load time.
local function _style()
    return require("features/sui_style")
end

-- ---------------------------------------------------------------------------
-- Strength scale
-- ---------------------------------------------------------------------------

local STRENGTH_MIN, STRENGTH_MAX = 0, 100
M.STRENGTH_MIN, M.STRENGTH_MAX = STRENGTH_MIN, STRENGTH_MAX

-- Rounds and clamps n to the strength scale; nil when n is not a number.
local function _clampBackdrop(n)
    n = tonumber(n)
    if not n then return nil end
    return math.max(STRENGTH_MIN, math.min(STRENGTH_MAX, math.floor(n + 0.5)))
end
M.clampBackdropStrength = _clampBackdrop

-- Reads a strength setting; `default` applies when it is unset or invalid.
function M.readBackdropStrength(key, default)
    return _clampBackdrop(SUISettings:readSetting(key)) or default
end

-- Stores a strength setting and returns the stored value. Invalid input is
-- ignored and returns nil.
function M.saveBackdropStrength(key, n)
    local v = _clampBackdrop(n)
    if v then SUISettings:saveSetting(key, v) end
    return v
end

-- Human-readable strength label for menus: Transparent / N% / Solid.
-- `_lc` overrides the translator for callers that carry their own.
function M.formatBackdropStrength(s, _lc)
    _lc = _lc or translate
    s = tonumber(s) or 0
    if s <= STRENGTH_MIN then return _lc("Transparent") end
    if s >= STRENGTH_MAX then return _lc("Solid") end
    return tostring(s) .. "%"
end

-- ---------------------------------------------------------------------------
-- Tones
-- ---------------------------------------------------------------------------

M.TONE = { WHITE = "white", GRAY = "gray" }
M.TONE_IDS = { M.TONE.WHITE, M.TONE.GRAY }
local WHITE, GRAY = M.TONE.WHITE, M.TONE.GRAY

-- Colour token of each tone in the style catalogue.
local TONE_TOKEN = { [WHITE] = "surface", [GRAY] = "surface_flat" }

-- Fill colour of a tone; white for an unknown tone.
function M.toneColor(tone)
    return _style().COLOR[TONE_TOKEN[tone] or TONE_TOKEN[WHITE]]
end

-- ---------------------------------------------------------------------------
-- Surfaces
-- ---------------------------------------------------------------------------

-- Semantic defaults of every kind of surface, as { strength, tone, frame }.
-- Bars keep the solid look of a plain UI; the navigation bar starts with its
-- frame on (a rule along its top edge, or a border while floating). Cards,
-- buttons, the cover strip and tab bars start solid; modules start
-- transparent over the wallpaper.
M.SURFACE_DEFAULT = {
    statusbar      = { strength = 100, tone = WHITE, frame = false },
    navbar         = { strength = 100, tone = WHITE, frame = true  },
    pagination     = { strength = 100, tone = WHITE, frame = false },
    titlebar       = { strength = 100, tone = WHITE, frame = false },
    module         = { strength = 0,   tone = WHITE, frame = false },
    tab_bar        = { strength = 100, tone = WHITE, frame = true  },
    cover_strip    = { strength = 100, tone = WHITE, frame = false },
    folder_label   = { strength = 75,  tone = WHITE, frame = false },
    card           = { strength = 100, tone = WHITE, frame = true  },
    button         = { strength = 100, tone = WHITE, frame = true  },
    quick_settings = { strength = 100, tone = GRAY,  frame = false },
}

-- Describes a surface of `kind` (a SURFACE_DEFAULT entry). Its settings live
-- under `key`: <key>_tone, <key>_show_frame and, unless `strength_key` names
-- another setting, <key>_backdrop.
function M.surface(kind, key, strength_key)
    return {
        defaults = M.SURFACE_DEFAULT[kind],
        keys = {
            strength = strength_key or (key .. "_backdrop"),
            tone     = key .. "_tone",
            frame    = key .. "_show_frame",
        },
    }
end

function M.readStrength(surface)
    return M.readBackdropStrength(surface.keys.strength, surface.defaults.strength)
end

function M.saveStrength(surface, n)
    return M.saveBackdropStrength(surface.keys.strength, n)
end

function M.readTone(surface)
    local stored = SUISettings:readSetting(surface.keys.tone)
    return TONE_TOKEN[stored] and stored or surface.defaults.tone
end

function M.saveTone(surface, tone)
    if TONE_TOKEN[tone] then SUISettings:saveSetting(surface.keys.tone, tone) end
end

function M.readFrame(surface)
    local stored = SUISettings:get(surface.keys.frame)
    if stored == nil then return surface.defaults.frame end
    return stored == true
end

function M.saveFrame(surface, on)
    SUISettings:saveSetting(surface.keys.frame, on and true or false)
end

-- Look of a surface: { strength, tone, color, frame, border_sz }, with
-- border_sz 0 while the frame is off. Painters take it as it is and never
-- choose colours.
local function _look(strength, tone, frame)
    return {
        strength  = strength,
        tone      = tone,
        color     = M.toneColor(tone),
        frame     = frame,
        border_sz = frame and _style().BORDER_SZ or 0,
    }
end

-- Look of a described surface (see M.surface). `strength` replaces the stored
-- opacity for callers that resolve it themselves (for instance while a
-- wallpaper gates it).
function M.resolve(surface, strength)
    return _look(strength or M.readStrength(surface), M.readTone(surface), M.readFrame(surface))
end

-- Look of a surface of `kind` with its semantic defaults, for places that
-- draw one without offering settings for it.
function M.resolveDefault(kind)
    local d = M.SURFACE_DEFAULT[kind]
    return _look(d.strength, d.tone, d.frame)
end

-- Looks stored as a single choice before tone and frame were separate
-- settings.
local LEGACY_LOOK = {
    flat        = { tone = GRAY,  frame = false },
    solid       = { tone = WHITE, frame = true },
    transparent = { tone = WHITE, frame = true, strength = STRENGTH_MIN },
}

-- Converts the single-choice look stored under `look_key` into the tone,
-- frame and strength settings of `surface`, then removes it. Settings the
-- user already stored are kept. `aliases` maps other stored values onto
-- "flat" | "solid" | "transparent"; values that name no look are left alone.
function M.migrateLook(surface, look_key, aliases)
    local stored = SUISettings:readSetting(look_key)
    local look = LEGACY_LOOK[stored] or LEGACY_LOOK[aliases and aliases[stored]]
    if not look then return end
    local keys = surface.keys
    if SUISettings:get(keys.tone)  == nil then SUISettings:saveSetting(keys.tone, look.tone) end
    if SUISettings:get(keys.frame) == nil then SUISettings:saveSetting(keys.frame, look.frame) end
    if look.strength and SUISettings:get(keys.strength) == nil then
        SUISettings:saveSetting(keys.strength, look.strength)
    end
    SUISettings:del(look_key)
end

-- ---------------------------------------------------------------------------
-- Painters
-- ---------------------------------------------------------------------------

-- Tile a rounded rect into non-overlapping horizontal spans so each pixel is
-- written once (blending corners separately would double-tint them).
local _SQUARE_SPAN = { {} }
local function _roundedSpans(x, y, w, h, r)
    r = math.min(r or 0, math.floor(w / 2), math.floor(h / 2))
    if r <= 0 then
        local sp = _SQUARE_SPAN[1]
        sp.x, sp.y, sp.w, sp.h = x, y, w, h
        return _SQUARE_SPAN
    end
    local spans = {}
    for i = 0, r - 1 do
        local dy = r - i - 0.5
        local inset = math.floor(r - math.sqrt(r * r - dy * dy) + 0.5)
        local sw = w - inset * 2
        if sw > 0 then
            spans[#spans + 1] = { x = x + inset, y = y + i,         w = sw, h = 1 }
            spans[#spans + 1] = { x = x + inset, y = y + h - 1 - i, w = sw, h = 1 }
        end
    end
    local mid_h = h - r * 2
    if mid_h > 0 then
        spans[#spans + 1] = { x = x, y = y + r, w = w, h = mid_h }
    end
    return spans
end

-- Runs fn with the buffer's inverse flag cleared on Android, where night
-- mode may set it: the logical colour is then written exactly once and
-- frame inversion turns it into its night-mode counterpart. Returns pcall's
-- results.
function M.withInverseGuard(bb, fn)
    local suppress = Device:isAndroid() and bb.getInverse and bb:getInverse() == 1
    if suppress then bb:setInverse(0) end
    local ok, result = pcall(fn)
    if suppress then bb:setInverse(1) end
    return ok, result
end

-- Paint a backdrop into bb.
-- strength: 0 no-op, 1–99 scrim (what is underneath shows through), 100 solid
-- surface.
-- radius: optional corner radius, drawn with anti-aliased corners.
-- color: optional fill override (e.g. surface_flat for flat cards/buttons).
--
-- No day/night colour branch: always paint the light-mode surface colour
-- (white by default). Frame inversion turns it black in night mode while
-- preserving the same alpha.
function M.paintBackdrop(bb, x, y, w, h, strength, radius, color)
    strength = _clampBackdrop(strength) or STRENGTH_MIN
    if strength <= STRENGTH_MIN or w <= 0 or h <= 0 then return end
    local alpha = math.floor(255 * strength / STRENGTH_MAX + 0.5)
    local c = color or _style().COLOR.surface
    radius = math.max(0, math.floor(tonumber(radius) or 0))

    local ok, drawn = M.withInverseGuard(bb, function()
        return AA.fillRoundedRect(bb, x, y, w, h, radius, c, alpha)
    end)
    if ok and drawn then return end

    -- Corners without anti-aliasing.
    M.withInverseGuard(bb, function()
        for _, sp in ipairs(_roundedSpans(x, y, w, h, radius)) do
            AA.fillRect(bb, sp.x, sp.y, sp.w, sp.h, c, alpha)
        end
    end)
end

-- Paint an opaque rounded border of `thickness` inside (x, y, w, h), with
-- anti-aliased corners where the radius allows it.
function M.paintFrame(bb, x, y, w, h, thickness, radius, color)
    thickness = math.max(1, math.floor(tonumber(thickness) or 1))
    radius = math.max(0, math.floor(tonumber(radius) or 0))

    local ok, drawn = M.withInverseGuard(bb, function()
        return AA.strokeRoundedRect(bb, x, y, w, h, radius, thickness, color)
    end)
    if ok and drawn then return end

    if type(bb.paintBorderRGB32) == "function" then
        M.withInverseGuard(bb, function()
            bb:paintBorderRGB32(x, y, w, h, thickness, color, radius, true)
        end)
    end
end

-- Paint a surface into (x, y, w, h): the fill, then the border over it. Both
-- share `radius`, so their rounded corners always match. `surface` is a
-- resolved surface, or any table with its strength, color and border_sz
-- fields; `surface.border_color` overrides the gray border.
function M.paintSurface(bb, x, y, w, h, surface, radius)
    M.paintBackdrop(bb, x, y, w, h, surface.strength, radius, surface.color)
    local border_sz = surface.border_sz or 0
    if border_sz > 0 then
        M.paintFrame(bb, x, y, w, h, border_sz, radius,
            surface.border_color or _style().COLOR.gray)
    end
end

-- Paint a full-width bar surface over the rows y .. y + h: the fill, then,
-- while the frame is on, a rule of border_sz across the edge facing the
-- content (`edge` is "top" or "bottom"). `surface` is a resolved surface.
function M.paintBar(bb, y, h, surface, edge)
    if h <= 0 then return end
    local w = Screen:getWidth()
    M.paintBackdrop(bb, 0, y, w, h, surface.strength, 0, surface.color)
    local thickness = math.min(surface.border_sz or 0, h)
    if thickness <= 0 then return end
    local rule_y = edge == "top" and y or (y + h - thickness)
    M.withInverseGuard(bb, function()
        bb:paintRect(0, rule_y, w, thickness, surface.border_color or _style().COLOR.gray)
    end)
end

-- ---------------------------------------------------------------------------
-- Widget
-- ---------------------------------------------------------------------------

-- Background layer: a surface (see paintSurface). Owns its size so painting
-- never depends on a parent having assigned dimen first. Meant to sit under
-- content in an OverlapGroup, so the content stays solid while only the
-- background is translucent.
--   width, height  box size
--   surface        resolved surface (see resolve) giving strength, color and
--                  border_sz; when set, the three fields below are ignored
--   strength       0–100, as paintBackdrop (default 100)
--   color          fill colour override (default: white surface)
--   border_sz      border thickness drawn through paintFrame (default 0: none)
--   border_color   border colour (default: gray)
--   radius         corner radius (default 0)
M.BackdropFill = Widget:extend{
    width        = 0,
    height       = 0,
    surface      = nil,
    strength     = STRENGTH_MAX,
    radius       = 0,
    color        = nil,
    border_sz    = 0,
    border_color = nil,
}

function M.BackdropFill:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function M.BackdropFill:paintTo(bb, x, y)
    local w, h = self.width, self.height
    if w <= 0 or h <= 0 then return end
    M.paintSurface(bb, x, y, w, h, self.surface or self, self.radius)
end

return M
