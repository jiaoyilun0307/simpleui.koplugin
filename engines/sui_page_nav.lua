-- sui_page_nav.lua — Simple UI
-- Page-turn controls shared by every surface that paginates inline (section
-- labels, tab bars, bottom pagers).
--
-- Chevron buttons are built as a pair so both share one geometry: `prev` is
-- dimmed and disabled on the first page, `next` on the last, unless the caller
-- asks for the disabled one to be left out. buildPager adds the indicator text
-- between them. buildProgressBar draws the current page as a read-only bar.

local Button          = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Screen          = require("device").screen
local Size            = require("ui/size")
local Widget          = require("ui/widget/widget")

local AAPaint   = require("infra/sui_aa_paint")
local Bottombar = require("screens/sui_bottombar")
local SUIStyle  = require("features/sui_style")

local M = {}

-- Icon size of the chevrons (base pixels, scaled at use time).
M.ICON_SIZE = 16

-- Builds the chevron pair for a row `row_h` pixels tall.
--   page, npages   current page and page count (1-based)
--   row_h          height of the row the buttons sit in; each button is
--                  padded vertically up to that height, never below the
--                  standard button padding
--   turn_page      function(delta) called on tap with -1 or 1
--   opts           optional table:
--     has_wallpaper  icons are alpha-blended at construction time and the
--                    button frame paints transparently over the wallpaper
--     transparent    the button frame paints transparently even without a
--                    wallpaper, for buttons drawn over a border or fill
--     h_pad          horizontal padding on each side of the icon, to widen
--                    the tap zone (default: standard button padding)
--     hide_disabled  a button that cannot turn the page is returned as nil
--                    instead of dimmed
-- Returns prev_button, next_button.
function M.buildButtons(page, npages, row_h, turn_page, opts)
    opts = opts or {}
    local has_wallpaper = opts.has_wallpaper
    local transparent   = has_wallpaper or opts.transparent
    local icon_size = Screen:scaleBySize(M.ICON_SIZE)
    local v_pad = math.max(Size.padding.button, math.floor((row_h - icon_size) / 2))
    local function make(icon, enabled, delta)
        if not enabled and opts.hide_disabled then return nil end
        local btn = Button:new{
            icon            = icon,
            icon_width      = icon_size,
            icon_height     = icon_size,
            bordersize      = 0,
            margin          = 0,
            padding_v       = v_pad,
            padding_h       = opts.h_pad,
            enabled         = enabled,
            callback        = function() turn_page(delta) end,
        }
        Bottombar.patchDimmedIcon(btn)
        if transparent then Bottombar.patchWallpaperIcon(btn) end
        return btn
    end
    local function makePair()
        return make("chevron.left", page > 1, -1), make("chevron.right", page < npages, 1)
    end
    if not has_wallpaper then return makePair() end
    local prev_btn, next_btn
    Bottombar.withWallpaperAlphaIcons(function()
        prev_btn, next_btn = makePair()
    end)
    return prev_btn, next_btn
end

-- Builds a pager row: prev chevron, `text_widget` (the page indicator), next
-- chevron. Takes the buildButtons arguments, with `has_wallpaper` in place of
-- `opts`, plus
--   text_widget    widget shown between the chevrons
--   gap            space between the chevrons and the text
-- Returns a HorizontalGroup `row_h` tall.
function M.buildPager(page, npages, row_h, text_widget, gap, turn_page, has_wallpaper)
    local prev_btn, next_btn = M.buildButtons(page, npages, row_h, turn_page, { has_wallpaper = has_wallpaper })
    return HorizontalGroup:new{
        align = "center",
        prev_btn,
        HorizontalSpan:new{ width = gap },
        CenterContainer:new{
            dimen = Geom:new{ w = text_widget:getSize().w, h = row_h },
            text_widget,
        },
        HorizontalSpan:new{ width = gap },
        next_btn,
    }
end

-- ---------------------------------------------------------------------------
-- Progress bar
-- ---------------------------------------------------------------------------

-- Pill track with a pill filled from the left up to `fraction` of its width.
-- The fill is never narrower than the bar is tall, so it stays a full pill.
local ProgressBar = Widget:extend{
    width    = 0,
    height   = 0,
    fraction = 0,
}

function ProgressBar:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function ProgressBar:getSize()
    return self.dimen
end

function ProgressBar:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local fill_w = math.min(self.width, math.max(self.height, math.floor(self.width * self.fraction + 0.5)))
    AAPaint.fillPill(bb, x, y, self.width, self.height, SUIStyle.COLOR.track, 255)
    AAPaint.fillPill(bb, x, y, fill_w, self.height, SUIStyle.COLOR.text_primary, 255)
end

-- Builds a `w` x `h` bar showing page `page` of `npages` (1-based): full on
-- the last page.
function M.buildProgressBar(page, npages, w, h)
    return ProgressBar:new{ width = w, height = h, fraction = page / npages }
end

return M
