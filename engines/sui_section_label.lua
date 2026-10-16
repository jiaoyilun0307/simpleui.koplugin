-- sui_section_label.lua — Simple UI
-- Single owner of a module's section label (the title row above a module):
--   • descriptor — what the label shows: text, right-aligned text, page state
--   • PageState  — per-module pagination state stored in the screen ctx
--   • rendering  — label widget construction and a per-screen widget cache
--   • height     — vertical space the label reserves
--
-- Descriptor: { text, right_text, page, npages }. A module supplies it through
-- an optional M.getLabel(ctx); without one it is derived from M.label and
-- M.label_right_func (see M.describe). A nil descriptor means "no label"
-- (the module declares none, or the user hid it).
--
-- Widgets reference nothing but the descriptor and the callbacks handed to
-- M.get, so a cache owned by one screen instance never outlives the callbacks
-- it holds.

local CenterContainer = require("ui/widget/container/centercontainer")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local LeftContainer   = require("ui/widget/container/leftcontainer")

local Config    = require("infra/sui_config")
local PageNav   = require("engines/sui_page_nav")
local SUIStyle  = require("features/sui_style")
local UI        = require("infra/sui_core")

local PAD = UI.PAD

local M = {}

-- ---------------------------------------------------------------------------
-- Pagination state
-- ---------------------------------------------------------------------------

-- Page and page count per module id, stored in the screen ctx so it lives as
-- long as that ctx does. A module that was never paged reads as 1 of 1.
local PageState = {}
M.PageState = PageState

local function pageEntry(ctx, id)
    local pages = ctx._pages
    if not pages then
        pages = {}
        ctx._pages = pages
    end
    local entry = pages[id]
    if not entry then
        entry = { page = 1, npages = 1 }
        pages[id] = entry
    end
    return entry
end

-- Returns page, npages.
function PageState.get(ctx, id)
    local entry = ctx and ctx._pages and ctx._pages[id]
    if not entry then return 1, 1 end
    return entry.page, entry.npages
end

function PageState.setPage(ctx, id, page)
    pageEntry(ctx, id).page = page
end

function PageState.setCount(ctx, id, npages)
    pageEntry(ctx, id).npages = npages
end

-- ---------------------------------------------------------------------------
-- Descriptor
-- ---------------------------------------------------------------------------

-- Builds the descriptor for module `id`. Returns nil when `text` is nil or
-- the user hid the label. `right_text` defaults to the "page/npages"
-- indicator when the module has more than one page.
function M.makeDescriptor(id, text, ctx, right_text)
    if not text or Config.isLabelHidden(id) then return nil end
    local page, npages = PageState.get(ctx, id)
    if not right_text and npages > 1 then
        right_text = string.format("%d/%d", page, npages)
    end
    return { text = text, right_text = right_text, page = page, npages = npages }
end

-- Descriptor for `mod`: its own getLabel(ctx) when defined, otherwise derived
-- from the declared M.label and optional M.label_right_func(ctx).
function M.describe(mod, ctx)
    if type(mod.getLabel) == "function" then return mod.getLabel(ctx) end
    local right_text = type(mod.label_right_func) == "function" and mod.label_right_func(ctx) or nil
    return M.makeDescriptor(mod.id, mod.label, ctx, right_text)
end

-- ---------------------------------------------------------------------------
-- Height
-- ---------------------------------------------------------------------------

-- Vertical space reserved for the label of module `id`: 0 when hidden.
function M.height(id, landscape_factor)
    if Config.isLabelHidden(id) then return 0 end
    return Config.getScaledLabelH(landscape_factor)
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

-- Title row with the right-aligned text and, when `turn_page` is given,
-- chevrons on both sides of it. All three share one row height so they
-- centre on a single line.
local function buildTitleRow(desc, avail_w, face, scale, turn_page, has_wallpaper)
    local face_right = Font:getFace(SUIStyle.FACE_REGULAR, math.max(8, math.floor(SUIStyle.FS_DETAIL * scale)))
    local right_widget = UI.makeColoredText{ text = desc.right_text, face = face_right, bold = false }
    local title_widget = UI.makeColoredText{ text = desc.text, face = face, bold = true }
    local row_h = math.max(title_widget:getSize().h, right_widget:getSize().h)
    local gap   = PAD

    local right
    if turn_page then
        right = PageNav.buildPager(desc.page, desc.npages, row_h, right_widget, gap, turn_page, has_wallpaper)
    else
        right = CenterContainer:new{
            dimen = Geom:new{ w = right_widget:getSize().w, h = row_h },
            right_widget,
        }
    end

    -- The title gets a real-width slot so the right side stays at the row's
    -- right edge (a TextWidget only reports its glyph width).
    local row = HorizontalGroup:new{ align = "center" }
    row[#row + 1] = LeftContainer:new{
        dimen = Geom:new{ w = math.max(1, avail_w - right:getSize().w - gap), h = row_h },
        title_widget,
    }
    row[#row + 1] = HorizontalSpan:new{ width = gap }
    row[#row + 1] = right
    return row
end

local function buildWidget(desc, w, scale, turn_page, has_wallpaper)
    local face    = Font:getFace(SUIStyle.FACE_REGULAR, math.max(8, math.floor(SUIStyle.FS_BODY * scale)))
    local avail_w = w - PAD * 2
    local content
    if desc.right_text then
        content = buildTitleRow(desc, avail_w, face, scale,
            desc.npages > 1 and turn_page or nil, has_wallpaper)
    else
        content = UI.makeColoredText{ text = desc.text, face = face, bold = true, width = avail_w }
    end
    return FrameContainer:new{
        bordersize = 0, padding = 0,
        padding_left = PAD, padding_right = PAD,
        padding_bottom = UI.LABEL_PAD_BOT,
        content,
    }
end

-- Returns the label widget for module `id`, reusing the one in `cache` while
-- everything it shows is unchanged (same widget identity = nothing to
-- repaint). `cache` is a table owned by one screen instance.
--   desc             descriptor (see M.describe)
--   w                column width the label spans
--   landscape_factor label scale multiplier (default 1)
--   has_wallpaper    chevrons paint transparently over the wallpaper
--   turn_page        function(id, delta) invoked by the chevrons
function M.get(cache, id, desc, w, landscape_factor, has_wallpaper, turn_page)
    local scale  = Config.getLabelScale() * (landscape_factor or 1)
    local paged  = desc.right_text ~= nil and desc.npages > 1
    local key = table.concat({
        desc.text, w, scale, desc.right_text or "",
        paged and desc.page or 0, paged and desc.npages or 0,
        paged and tostring(has_wallpaper) or "",
    }, "|")

    local entry = cache[id]
    if entry and entry.key == key then return entry.widget end

    local nav = paged and turn_page and function(delta) turn_page(id, delta) end or nil
    local widget = buildWidget(desc, w, scale, nav, has_wallpaper)
    cache[id] = { key = key, widget = widget }
    return widget
end

return M
