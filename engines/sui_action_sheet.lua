-- sui_action_sheet.lua — Simple UI
-- Modal sheet of actions built on SUIWindow: a header with a centred title,
-- an optional icon and a separator below it, followed by sections of actions.
--
--   ActionSheet.show{
--       name     = "sui_win_example",   -- window name (optional)
--       title    = "Title",
--       icon     = "book_open",         -- SUIStyle.icon key (optional)
--       message  = "Longer text",       -- wrapped text below the separator (optional)
--       on_close = function() end,      -- optional; whenever the sheet closes
--       on_dismiss = function() end,    -- optional; only when the user dismisses it
--       footer   = { item, ... },       -- optional; segments pinned below the sections
--       auto_close = false,             -- close the sheet before any callback runs
--       fit_width  = false,             -- narrow the sheet to its widest row (rows sections only)
--       width      = nil,               -- explicit width, in portrait pixels (overrides fit_width)
--       sections = {
--           { type = "tiles",    items = { item, ... } },
--           { type = "segments", items = { item, ... } },
--           { type = "rows",     rows = { { item, item }, { item } } },
--       },
--   }
--
-- Section types
--   tiles     One row of equal-width cells, each with the icon above the
--             label.
--   segments  One row of equal-width buttons. An item flagged `selected` is
--             drawn inverted, in bold, and its label ends with a tick.
--   rows      Rows of icon + label cells. The icon slot is only reserved when
--             an item of the section has an icon, so sections without icons
--             keep their labels flush left. Consecutive `rows` sections are
--             regrouped by shape, so every group is one of:
--               list  one item per row; rows are divided by horizontal lines.
--               grid  several items per row, in equal-width columns; no lines.
--
-- Where a list meets a grid, the same line divides them as divides the rows of
-- a list. Any other pair of sections is separated by the same spacing.
--
-- Item
--   text           string
--   sui_icon       string    SUIStyle.icon key (optional)
--   callback       function  called on tap; the sheet closes itself first only
--                            when `auto_close` is set
--   hold_callback  function  called on long press (optional)
--   enabled        bool      false draws the item dimmed and ignores taps
--   selected       bool      segments only
--   checked        bool      rows only; draws a tick after the label
--
-- ActionSheet.pick(opts) shows a one-column chooser: `title`, `icon`, `name`,
-- `fit_width` as in show, plus `items` and `on_cancel`. Tapping an item closes
-- the sheet and then runs its callback; dismissing the sheet (tap outside,
-- Back key) runs `on_cancel`, so a chooser needs no Cancel item.
--
-- ActionSheet.list(items) builds a `rows` section with one item per row.
--
-- Items follow the button format of ButtonDialog, so button generators can be
-- passed through unchanged.
--
-- ActionSheet.show returns the SUIWindow; close it with window:close().
-- window:update(fields) replaces any of `title`, `message`, `icon` and
-- `sections` of the open sheet and redraws it; the width stays as it was.

local CenterContainer = require("ui/widget/container/centercontainer")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local Screen          = require("device").screen

local SUIStyle  = require("features/sui_style")
local SUIWindow = require("engines/sui_window")

local COLOR = SUIStyle.COLOR

local ActionSheet = {}

-- Metrics in base pixels; scaled by px() when a screen is built.
local METRICS = {
    header_pad_top    = 14,
    header_pad_bottom = 12,
    segment_h         = 44,
    segment_gap       = 10,
    segment_radius    = 10,
    row_h             = 46,
    cell_pad          = 10,
    cell_gap          = 12,
    cell_icon         = 24,
    cell_tick         = 18,
    section_gap       = 8,
    tile_h            = 76,
    tile_gap          = 6,
}

-- Scales a base-pixel metric with the window's landscape-aware factor.
local function px(ctx, base)
    return ctx.SZ(Screen:scaleBySize(base))
end

local function isEnabled(item)
    return item.enabled ~= false
end

-- Wraps `widget` so a tap runs the item's callback and a long press its hold
-- callback. Items that are disabled or have neither are returned as they are.
local function makeTappable(widget, item, w, h)
    if not isEnabled(item) or not (item.callback or item.hold_callback) then
        return widget
    end
    return SUIWindow.Input.tapable(widget,
        { on_tap = item.callback, on_hold = item.hold_callback },
        Geom:new{ w = w, h = h })
end

local function buildLine(width, height, color)
    return LineWidget:new{
        dimen      = Geom:new{ w = width, h = height },
        background = color,
    }
end

-- Width of one of `count` equal columns.
local function columnWidth(ctx, count)
    return math.floor(ctx.inner_w / count)
end

-- Horizontal group of `count` columns of `cell_w`: `cells`, then empty space
-- for the missing ones.
local function buildColumns(cells, count, cell_w)
    local group = HorizontalGroup:new{ align = "center" }
    for i = 1, count do
        group[#group + 1] = cells[i] or HorizontalSpan:new{ width = cell_w }
    end
    return group
end

-- ---------------------------------------------------------------------------
-- Header
-- ---------------------------------------------------------------------------

local function buildMessage(ctx, text)
    return TextBoxWidget:new{
        text      = text,
        face      = Font:getFace(SUIStyle.FACE_REGULAR, ctx.SZ(SUIStyle.FS_DETAIL)),
        fgcolor   = COLOR.text_secondary,
        width     = ctx.inner_w,
        alignment = "left",
    }
end

-- Centred title row above a separator, and message, each optional, between the
-- header padding. Without either, the header is only the window's own bottom
-- padding, so the content sits evenly between top and bottom.
local function buildHeader(ctx, opts)
    local has_title   = opts.title and opts.title ~= ""
    local has_message = opts.message and opts.message ~= ""
    if not has_title and not has_message then
        return VerticalSpan:new{ width = ctx.SZ(Size.padding.large) }
    end

    local header = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = px(ctx, METRICS.header_pad_top) },
    }
    if has_title then
        local heading = SUIWindow.TitleRow{
            width = ctx.inner_w,
            title = opts.title,
            icon  = opts.icon,
        }
        header[#header + 1] = CenterContainer:new{
            dimen = Geom:new{ w = ctx.inner_w, h = heading:getSize().h },
            heading,
        }
        header[#header + 1] = VerticalSpan:new{ width = px(ctx, METRICS.header_pad_bottom) }
        header[#header + 1] = buildLine(ctx.inner_w, Size.line.medium, COLOR.text_primary)
    end
    if has_message then
        if has_title then
            header[#header + 1] = VerticalSpan:new{ width = px(ctx, METRICS.header_pad_bottom) }
        end
        header[#header + 1] = buildMessage(ctx, opts.message)
    end
    header[#header + 1] = VerticalSpan:new{ width = px(ctx, METRICS.header_pad_bottom) }
    return header
end

-- ---------------------------------------------------------------------------
-- Segments section
-- ---------------------------------------------------------------------------

local SEGMENT_TICK = "\u{2713}"

-- Label of a segment. A selected segment ends with a tick; a tick already in
-- the text is replaced, never doubled.
local function segmentLabel(item, selected)
    local label = (item.text or ""):gsub("%s*" .. SEGMENT_TICK .. "%s*$", "")
    if selected then label = label .. "  " .. SEGMENT_TICK end
    return label
end

local function buildSegment(ctx, item, w, h, face)
    local selected = item.selected == true
    local fgcolor
    if selected then
        fgcolor = COLOR.surface
    else
        fgcolor = isEnabled(item) and COLOR.text_primary or COLOR.text_dim
    end

    local frame = FrameContainer:new{
        bordersize = 0,
        padding    = 0,
        radius     = px(ctx, METRICS.segment_radius),
        background = selected and COLOR.text_primary or COLOR.surface_flat,
        CenterContainer:new{
            dimen = Geom:new{ w = w, h = h },
            TextWidget:new{
                text                   = segmentLabel(item, selected),
                face                   = face,
                fgcolor                = fgcolor,
                bold                   = selected,
                padding                = 0,
                max_width              = math.max(1, w - 2 * px(ctx, METRICS.cell_pad)),
                truncate_with_ellipsis = true,
            },
        },
    }
    return makeTappable(frame, item, w, h)
end

local function buildSegments(ctx, section)
    local items = section.items
    local count = #items
    if count == 0 then return {} end
    local gap   = px(ctx, METRICS.segment_gap)
    local h     = px(ctx, METRICS.segment_h)
    local w     = math.floor((ctx.inner_w - gap * (count - 1)) / count)
    local face  = Font:getFace(SUIStyle.FACE_REGULAR, ctx.SZ(SUIStyle.FS_BODY))

    local group = HorizontalGroup:new{ align = "center" }
    for i, item in ipairs(items) do
        if i > 1 then group[#group + 1] = HorizontalSpan:new{ width = gap } end
        group[#group + 1] = buildSegment(ctx, item, w, h, face)
    end
    return { group }
end

-- ---------------------------------------------------------------------------
-- Tiles section
-- ---------------------------------------------------------------------------

-- Icon above the label, centred in a cell of `w` x `h`.
local function buildTile(ctx, item, w, h)
    local fgcolor = isEnabled(item) and COLOR.text_primary or COLOR.text_dim
    local icon_w  = px(ctx, METRICS.cell_icon)

    local content = VerticalGroup:new{ align = "center" }
    if item.sui_icon then
        content[#content + 1] = TextWidget:new{
            text    = SUIStyle.icon(item.sui_icon),
            face    = SUIStyle.glyphFace(icon_w),
            fgcolor = fgcolor,
            padding = 0,
        }
        content[#content + 1] = VerticalSpan:new{ width = px(ctx, METRICS.tile_gap) }
    end
    content[#content + 1] = TextWidget:new{
        text                   = item.text or "",
        face                   = Font:getFace(SUIStyle.FACE_REGULAR, ctx.SZ(SUIStyle.FS_BODY)),
        fgcolor                = fgcolor,
        padding                = 0,
        max_width              = math.max(1, w - 2 * px(ctx, METRICS.cell_pad)),
        truncate_with_ellipsis = true,
    }

    return makeTappable(CenterContainer:new{
        dimen = Geom:new{ w = w, h = h },
        content,
    }, item, w, h)
end

local function buildTiles(ctx, section)
    local count = #section.items
    if count == 0 then return {} end
    local w = columnWidth(ctx, count)
    local h = px(ctx, METRICS.tile_h)

    local tiles = {}
    for i, item in ipairs(section.items) do tiles[i] = buildTile(ctx, item, w, h) end
    return { buildColumns(tiles, count, w) }
end

-- ---------------------------------------------------------------------------
-- Rows section
-- ---------------------------------------------------------------------------

-- Optional icon slot, the label and, for a checked item, a tick. The slot is
-- left empty for items without an icon when `slot` is set, so labels stay
-- aligned across the rows of a section.
local function buildCellContent(ctx, item, cell_w, row_h, fgcolor, slot)
    local pad      = px(ctx, METRICS.cell_pad)
    local gap      = px(ctx, METRICS.cell_gap)
    local icon_w   = slot and px(ctx, METRICS.cell_icon) or 0
    local tick_w   = item.checked and px(ctx, METRICS.cell_tick) or 0
    local content  = HorizontalGroup:new{ align = "center" }
    local used     = 2 * pad + tick_w

    if slot then
        if item.sui_icon then
            content[#content + 1] = CenterContainer:new{
                dimen = Geom:new{ w = icon_w, h = row_h },
                TextWidget:new{
                    text    = SUIStyle.icon(item.sui_icon),
                    face    = SUIStyle.glyphFace(icon_w),
                    fgcolor = fgcolor,
                    padding = 0,
                },
            }
        else
            content[#content + 1] = HorizontalSpan:new{ width = icon_w }
        end
        content[#content + 1] = HorizontalSpan:new{ width = gap }
        used = used + icon_w + gap
    end

    content[#content + 1] = TextWidget:new{
        text                   = item.text or "",
        face                   = Font:getFace(SUIStyle.FACE_REGULAR, ctx.SZ(SUIStyle.FS_BODY)),
        fgcolor                = fgcolor,
        padding                = 0,
        max_width              = math.max(1, cell_w - used - (item.checked and gap or 0)),
        truncate_with_ellipsis = true,
    }

    if item.checked then
        content[#content + 1] = HorizontalSpan:new{ width = gap }
        content[#content + 1] = TextWidget:new{
            text    = SUIStyle.icon("tick"),
            face    = SUIStyle.glyphFace(tick_w),
            fgcolor = fgcolor,
            padding = 0,
        }
    end

    return HorizontalGroup:new{
        HorizontalSpan:new{ width = pad },
        content,
    }
end

local function buildCell(ctx, item, cell_w, row_h, slot)
    local fgcolor = isEnabled(item) and COLOR.text_primary or COLOR.text_dim
    local cell = LeftContainer:new{
        dimen = Geom:new{ w = cell_w, h = row_h },
        buildCellContent(ctx, item, cell_w, row_h, fgcolor, slot),
    }
    return makeTappable(cell, item, cell_w, row_h)
end

-- One row of a section with `columns` columns.
local function buildRow(ctx, items, slot, columns)
    local row_h  = px(ctx, METRICS.row_h)
    local cell_w = columnWidth(ctx, columns)
    local cells  = {}
    for i, item in ipairs(items) do
        cells[i] = buildCell(ctx, item, cell_w, row_h, slot)
    end
    return buildColumns(cells, columns, cell_w)
end

-- A row followed by a separator line. The window drops that line when the
-- row ends up last on a page.
local function withSeparator(ctx, row)
    local group = VerticalGroup:new{
        align = "left",
        row,
        buildLine(ctx.inner_w, Size.line.thin, COLOR.gray_strong),
    }
    group.is_list_row_with_sep = true
    return group
end

-- Number of columns of a section: the item count of its widest row.
local function columnCount(rows)
    local count = 1
    for _i, items in ipairs(rows) do count = math.max(count, #items) end
    return count
end

-- True when any item of the rows has an icon.
local function hasIcons(rows)
    for _i, items in ipairs(rows) do
        for _j, item in ipairs(items) do
            if item.sui_icon then return true end
        end
    end
    return false
end

local function buildRows(ctx, section)
    local filled = {}
    for _i, items in ipairs(section.rows) do
        if #items > 0 then filled[#filled + 1] = items end
    end

    local slot    = hasIcons(filled)
    local columns = columnCount(filled)
    local widgets = {}
    for i, items in ipairs(filled) do
        local row = buildRow(ctx, items, slot, columns)
        if columns == 1 and i < #filled then row = withSeparator(ctx, row) end
        widgets[#widgets + 1] = row
    end
    return widgets
end

-- ---------------------------------------------------------------------------
-- Screen
-- ---------------------------------------------------------------------------

local SECTION_BUILDERS = {
    tiles    = buildTiles,
    segments = buildSegments,
    rows     = buildRows,
}

-- The sections with consecutive `rows` sections regrouped by shape: each
-- list or grid is one section, whatever sections its rows came from.
local function regroupRows(sections)
    local result, run = {}, nil
    for _i, section in ipairs(sections) do
        if section.type == "rows" then
            for _j, items in ipairs(section.rows) do
                if #items > 0 then
                    local multi = #items > 1
                    if not run or run.multi ~= multi then
                        run = { multi = multi, section = { type = "rows", rows = {} } }
                        result[#result + 1] = run.section
                    end
                    run.section.rows[#run.section.rows + 1] = items
                end
            end
        else
            result[#result + 1] = section
            run = nil
        end
    end
    return result
end

local function buildScreen(ctx, sections)
    local widgets = {}
    local previous
    for _i, section in ipairs(regroupRows(sections)) do
        local build = SECTION_BUILDERS[section.type]
        local built = build and build(ctx, section) or {}
        if #built > 0 then
            if previous == "rows" and section.type == "rows" then
                widgets[#widgets] = withSeparator(ctx, widgets[#widgets])
            elseif previous then
                widgets[#widgets + 1] = VerticalSpan:new{ width = px(ctx, METRICS.section_gap) }
            end
            previous = section.type
            for _j, widget in ipairs(built) do
                widgets[#widgets + 1] = widget
            end
        end
    end
    return widgets
end

-- Makes every item close the sheet before running its callback.
local function closeBeforeCallbacks(sections, close)
    for _i, section in ipairs(sections) do
        local rows = section.rows or { section.items or {} }
        for _j, items in ipairs(rows) do
            for _k, item in ipairs(items) do
                local callback = item.callback
                if callback then
                    item.callback = function()
                        close()
                        callback()
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Width fitting
-- ---------------------------------------------------------------------------

local FIT_MAX_ITEMS = 12    -- longer lists keep the default width, unmeasured
local FIT_MIN_RATIO = 0.4   -- narrowest sheet, as a fraction of the portrait width
local FIT_MAX_RATIO = 5 / 6 -- widest sheet: the window's default width

-- Width in portrait pixels of the sheet that just holds the title and the
-- `sections` of `opts`, or nil when they are not all `rows` sections or hold
-- more than FIT_MAX_ITEMS items (measuring a long list costs more than it
-- saves: such a sheet is wide anyway). Mirrors the metrics of buildCell:
-- the widest cell of a section sets the width of every column.
local function fitWidth(opts)
    local count = 0
    for _i, section in ipairs(opts.sections) do
        if section.type ~= "rows" then return nil end
        for _j, items in ipairs(section.rows) do count = count + #items end
    end
    if count > FIT_MAX_ITEMS then return nil end

    local face     = Font:getFace(SUIStyle.FACE_REGULAR, SUIStyle.FS_BODY)
    local pad      = Screen:scaleBySize(METRICS.cell_pad)
    local gap      = Screen:scaleBySize(METRICS.cell_gap)
    local icon_w   = Screen:scaleBySize(METRICS.cell_icon)
    local tick_w   = Screen:scaleBySize(METRICS.cell_tick)
    local widest   = 0

    for _i, section in ipairs(opts.sections) do
        local slot = hasIcons(section.rows)
        local cell_w, columns = 0, 1
        for _j, items in ipairs(section.rows) do
            columns = math.max(columns, #items)
            for _k, item in ipairs(items) do
                local label = TextWidget:new{ text = item.text or "", face = face, padding = 0 }
                local w = 2 * pad + label:getWidth()
                label:free()
                if slot then w = w + icon_w + gap end
                if item.checked then w = w + gap + tick_w end
                cell_w = math.max(cell_w, w)
            end
        end
        widest = math.max(widest, cell_w * columns)
    end

    -- The centred title, with its optional icon (mirrors SUIWindow.TitleRow).
    if opts.title and opts.title ~= "" then
        local heading = TextWidget:new{
            text    = opts.title,
            face    = Font:getFace(SUIStyle.FACE_BOLD, SUIStyle.FS_TITLE),
            padding = 0,
        }
        local title_w = heading:getWidth()
        heading:free()
        if opts.icon then title_w = title_w + Screen:scaleBySize(26 + 12) end
        widest = math.max(widest, title_w)
    end

    local portrait_w = require("infra/sui_core").getPortraitDims()
    local width = widest + 2 * Screen:scaleBySize(20)   -- the window's horizontal padding
    return math.min(math.max(width, math.floor(portrait_w * FIT_MIN_RATIO)),
                    math.floor(portrait_w * FIT_MAX_RATIO))
end

-- Segments pinned under the sections, so they stay visible on every page.
local function buildFooter(ctx, items)
    local gap = px(ctx, METRICS.section_gap)
    local footer = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = gap } }
    for _i, widget in ipairs(buildSegments(ctx, { items = items })) do
        footer[#footer + 1] = widget
    end
    footer[#footer + 1] = VerticalSpan:new{ width = gap }
    return footer
end

--- A `rows` section with one item per row.
function ActionSheet.list(items)
    local rows = {}
    for _i, item in ipairs(items) do rows[#rows + 1] = { item } end
    return { type = "rows", rows = rows }
end

function ActionSheet.show(opts)
    local window
    local function arm(sections)
        if opts.auto_close then
            closeBeforeCallbacks(sections, function() window:close() end)
        end
    end
    arm(opts.sections)
    window = SUIWindow:new{
        name           = opts.name or "sui_win_action_sheet",
        no_titlebar    = true,
        auto_height    = true,
        width          = opts.width or (opts.fit_width and fitWidth(opts)) or nil,
        position       = "center",
        navpager_mode  = require("infra/sui_config").isNavpagerEnabled(),
        on_close       = opts.on_close,
        on_dismiss     = opts.on_dismiss,
        screens        = { __root__ = function(ctx) return buildScreen(ctx, opts.sections) end },
        screen_headers = { __root__ = function(ctx) return buildHeader(ctx, opts) end },
        screen_footers = opts.footer and {
            __root__ = function(ctx) return buildFooter(ctx, opts.footer) end,
        } or nil,
    }

    function window:update(fields)
        if fields.sections then arm(fields.sections) end
        for key, value in pairs(fields) do opts[key] = value end
        self:repaint()
    end

    window:show()
    return window
end

--- Shows `opts.items` as a chooser (see the header). Returns the SUIWindow.
function ActionSheet.pick(opts)
    local window
    -- Copies, so the caller's items keep their own callbacks.
    local items = {}
    for i, source in ipairs(opts.items) do
        local item, callback = {}, source.callback
        for key, value in pairs(source) do item[key] = value end
        item.callback = function()
            window:close()
            if callback then callback() end
        end
        items[i] = item
    end
    window = ActionSheet.show{
        name      = opts.name,
        title     = opts.title,
        icon      = opts.icon,
        fit_width = opts.fit_width ~= false,
        on_dismiss = opts.on_cancel,
        sections  = { ActionSheet.list(items) },
    }
    return window
end

return ActionSheet
