-- sui_arrange.lua — Simple UI
-- Editable ordered list for the settings menus: reorder entries, remove them
-- and, optionally, add new ones from a picker. One implementation serves the
-- native menu and the SUIWindow settings.
--
-- Two entry points:
--
--   Arrange.makeMenuItem{ ... }   entries with their own identity and an
--                                 optional tree of choices to add from
--   Arrange.makeListItem{ ... }   ordered list of ids drawn from a flat pool
--
-- makeMenuItem opts
--   ctx_menu    menu context (`_`, `refresh`, `is_sui`, `UIManager`, `SortWidget`)
--   title       translated row and page title (default "Arrange")
--   text_func   optional native row text, evaluated on every draw
--   labels      already translated
--     action      title of the reorder action and of its widget
--     header      caption above the per-entry removal list
--     empty       text shown when there are no entries
--     too_few     toast shown when there are fewer than two entries to reorder
--     add         title of the add button and of the picker (default "Add Item")
--     full        function(max) -> toast when the list is full
--     at_min      function(min) -> toast when entries cannot be removed
--     settings    header of the per-entry settings in the native menu
--                 (default "Settings")
--   getEntries  function() -> { { value = v, title = "...", settings = f }, ... }
--               `settings` is optional: function() -> { menu item, ... }, the
--               settings of that entry. The SUIWindow page opens them when the
--               entry is tapped, the native menu lists them under a header.
--   count       optional function() -> number of entries, when cheaper than
--               building them
--   saveOrder   function(values)   values of the entries in their new order
--   removeEntry function(value)
--   max, min    optional limits, a number or a function() -> number
--   add         optional
--     choices     function() -> { node, ... } with node being either
--                   { title = "...", value = v }              a leaf, or
--                   { title = "...", children = function() -> { node, ... } }
--                 Branches without any leaf are left out.
--     onAdd       function(value)
--   isEnabled   function() -> bool, default true
--   isMember    function(value) -> bool; removal rows are shown checked
--               while true
--
--   `value` is the stable identity of an entry (never a position): callbacks
--   receive values, so they stay valid while the list changes under an open
--   widget.
--
-- makeListItem opts: ctx_menu, title, text_func, labels, max, min, isEnabled
--   as above, plus
--   getIds      function() -> { id, ... }   current ids, in order
--   setIds      function(ids)               persists the ids; the menu is
--                                           refreshed after every change
--   pool        function() -> { { id = id, label = "..." }, ... }
--   label       optional function(id) -> string for ids missing from the pool
--   The native menu lists the whole pool as checkable rows next to the
--   reorder action; the SUIWindow settings add from a picker.

local UI = require("infra/sui_core")

local M = {}

local SUMMARY_SEPARATOR = "  ·  "

local function resolve(value)
    if type(value) == "function" then return value() end
    return value
end

local function isEnabled(opts)
    return not opts.isEnabled or opts.isEnabled()
end

local function translate(opts)
    return opts.ctx_menu._
end

local function entryCount(opts)
    if opts.count then return opts.count() end
    return #opts.getEntries()
end

-- ---------------------------------------------------------------------------
-- Limits
-- ---------------------------------------------------------------------------

local function toast(text)
    UI.Notify.toast(text, 2)
end

-- Adds `value` unless the list is full; says why when it is.
local function addEntry(opts, value)
    local max = resolve(opts.max)
    if max and entryCount(opts) >= max then
        local full = opts.labels.full
        toast(full and full(max)
            or string.format(translate(opts)("The maximum of %d items has been reached. Remove one first."), max))
        return false
    end
    opts.add.onAdd(value)
    return true
end

-- Removes `value` unless the list is at its minimum; says why when it is.
local function removeEntry(opts, value)
    local min = resolve(opts.min) or 0
    if entryCount(opts) <= min then
        local at_min = opts.labels.at_min
        toast(at_min and at_min(min)
            or string.format(translate(opts)("At least %d items are required."), min))
        return false
    end
    opts.removeEntry(value)
    return true
end

-- ---------------------------------------------------------------------------
-- Choices
-- ---------------------------------------------------------------------------

-- The nodes with their branches resolved; branches left without leaves are
-- dropped.
local function liveChoices(nodes)
    local live = {}
    for _i, node in ipairs(nodes) do
        if node.children then
            local children = liveChoices(node.children())
            if #children > 0 then live[#live + 1] = { title = node.title, children = children } end
        else
            live[#live + 1] = node
        end
    end
    return live
end

local function hasChoices(opts)
    return #liveChoices(opts.add.choices()) > 0
end

-- ---------------------------------------------------------------------------
-- Native menu
-- ---------------------------------------------------------------------------

local function valuesOf(items, field)
    local values = {}
    for _i, item in ipairs(items) do values[#values + 1] = item[field] end
    return values
end

local function arrangeAction(opts)
    local ctx_menu = opts.ctx_menu
    local labels   = opts.labels
    return {
        text           = labels.action,
        enabled_func   = function() return entryCount(opts) > 1 end,
        keep_menu_open = true,
        callback       = function()
            local entries = opts.getEntries()
            if #entries < 2 then
                toast(labels.too_few)
                return
            end
            local sort_items = {}
            for _i, entry in ipairs(entries) do
                sort_items[#sort_items + 1] = { text = entry.title, value = entry.value, mandatory = "" }
            end
            local UIManager  = ctx_menu.UIManager or require("ui/uimanager")
            local SortWidget = ctx_menu.SortWidget or require("ui/widget/sortwidget")
            UIManager:show(SortWidget:new{
                title             = labels.action,
                item_table        = sort_items,
                covers_fullscreen = true,
                callback          = function()
                    opts.saveOrder(valuesOf(sort_items, "value"))
                    ctx_menu.refresh()
                end,
            })
        end,
    }
end

local function nativeChoiceRows(opts, nodes)
    local rows = {}
    for _i, node in ipairs(nodes) do
        if node.children then
            rows[#rows + 1] = { text = node.title, sub_item_table = nativeChoiceRows(opts, node.children) }
        else
            local value = node.value
            rows[#rows + 1] = {
                text           = node.title,
                keep_menu_open = true,
                callback       = function()
                    if addEntry(opts, value) then opts.ctx_menu.refresh() end
                end,
            }
        end
    end
    return rows
end

-- One removal row per entry; a tap removes the entry.
local function removalRows(opts)
    local rows    = {}
    local entries = opts.getEntries()
    if #entries == 0 then
        rows[1] = { text = opts.labels.empty, enabled = false }
        return rows
    end
    for _i, entry in ipairs(entries) do
        local value = entry.value
        rows[#rows + 1] = {
            text           = entry.title,
            checked_func   = opts.isMember and function() return opts.isMember(value) end or nil,
            keep_menu_open = true,
            callback       = function()
                if removeEntry(opts, value) then opts.ctx_menu.refresh() end
            end,
        }
    end
    return rows
end

-- One submenu per entry that has settings.
local function settingsRows(opts)
    local rows = {}
    for _i, entry in ipairs(opts.getEntries()) do
        if entry.settings then
            rows[#rows + 1] = { text = entry.title, sub_item_table_func = entry.settings }
        end
    end
    return rows
end

local function nativeSubItems(opts)
    local items = {}
    if opts.add then
        items[#items + 1] = {
            text                = opts.labels.add,
            enabled_func        = function() return hasChoices(opts) end,
            sub_item_table_func = function()
                return nativeChoiceRows(opts, liveChoices(opts.add.choices()))
            end,
        }
    end
    items[#items + 1] = arrangeAction(opts)
    items[#items + 1] = { text = opts.labels.header, enabled = false, separator = true }
    for _i, row in ipairs(removalRows(opts)) do items[#items + 1] = row end

    local settings_rows = settingsRows(opts)
    if #settings_rows > 0 then
        items[#items].separator = true
        items[#items + 1] = {
            text      = opts.labels.settings or translate(opts)("Settings"),
            enabled   = false,
            separator = true,
        }
        for _i, row in ipairs(settings_rows) do items[#items + 1] = row end
    end
    return items
end

-- ---------------------------------------------------------------------------
-- SUIWindow settings
-- ---------------------------------------------------------------------------

-- Opens the picker for `nodes`; a leaf adds its entry and returns to the
-- arrange page, a branch opens the picker of its children.
local function pushPicker(opts, ctx, nodes, title, depth, onAdded)
    local picker_items = {}
    for _i, node in ipairs(nodes) do
        picker_items[#picker_items + 1] = {
            text         = node.title,
            show_chevron = node.children ~= nil,
            on_tap       = function(picker_ctx)
                if node.children then
                    pushPicker(opts, picker_ctx, node.children, node.title, depth + 1, onAdded)
                elseif addEntry(opts, node.value) then
                    onAdded()
                    for _level = 0, depth do picker_ctx.pop() end
                end
            end,
        }
    end
    ctx.push("item_picker", { title = title, items = picker_items })
end

-- Pushes the arrange page. Its items mirror the entries and are re-filled
-- after every change, so the page also reflects what the callbacks adjusted.
local function pushPage(opts, ctx)
    local ctx_menu = opts.ctx_menu
    local labels   = opts.labels
    local items    = {}

    local sync
    local function changed()
        sync()
        ctx_menu.refresh()
        ctx.repaint()
    end

    function sync()
        for i = #items, 1, -1 do items[i] = nil end
        for _i, entry in ipairs(opts.getEntries()) do
            local item = { text = entry.title, orig_item = entry.value }
            if entry.settings then
                item.show_chevron = true
                item.on_tap = function()
                    ctx.push("nested_menu", { title = entry.title, items = entry.settings() })
                end
            end
            items[#items + 1] = item
        end
        local removable = #items > (resolve(opts.min) or 0)
        for _i, item in ipairs(items) do
            local value = item.orig_item
            item.on_delete = removable and function()
                if removeEntry(opts, value) then changed() end
            end or nil
        end
    end
    sync()

    local function added()
        sync()
        ctx_menu.refresh()
    end

    local page = {
        title      = opts.title,
        items      = items,
        empty_text = labels.empty,
        on_change  = function(arranged)
            opts.saveOrder(valuesOf(arranged, "orig_item"))
            sync()
            ctx_menu.refresh()
        end,
    }
    if opts.add then
        page.footer_text    = labels.add
        page.item_count     = function() return entryCount(opts) end
        page.max_items      = opts.max
        page.footer_enabled = function()
            local max = resolve(opts.max)
            return (not max or entryCount(opts) < max) and hasChoices(opts)
        end
        page.footer_action  = function(page_ctx)
            pushPicker(opts, page_ctx, liveChoices(opts.add.choices()), labels.add, 0, added)
        end
    end
    ctx.push("arrange", page)
end

local function suiRow(opts, ctx)
    local SUIWindow = require("engines/sui_window")
    local row = {
        title        = opts.title,
        subtitle     = function()
            local entries = opts.getEntries()
            if #entries == 0 then return opts.labels.empty end
            local titles = {}
            for _i, entry in ipairs(entries) do titles[#titles + 1] = entry.title end
            return table.concat(titles, SUMMARY_SEPARATOR)
        end,
        inner_w      = ctx.inner_w,
        show_chevron = true,
        enabled      = isEnabled(opts),
        on_tap       = function() pushPage(opts, ctx) end,
    }
    if opts.max then
        row.item_count = function() return entryCount(opts) end
        row.max_items  = opts.max
    end
    return SUIWindow.ListRow(row)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Returns the menu item for an editable list (see the header for `opts`).
function M.makeMenuItem(opts)
    local ctx_menu = opts.ctx_menu
    local _lc      = ctx_menu._
    opts.title            = opts.title or _lc("Arrange")
    opts.labels.add       = opts.labels.add or _lc("Add Item")
    return {
        text                = opts.title,
        text_func           = opts.text_func,
        enabled_func        = function() return isEnabled(opts) end,
        sub_item_table_func = function() return nativeSubItems(opts) end,
        sui_build           = ctx_menu.is_sui and function(ctx) return suiRow(opts, ctx) end or nil,
    }
end

local function sortedByLabel(pool)
    local sorted = {}
    for _i, entry in ipairs(pool) do sorted[#sorted + 1] = entry end
    table.sort(sorted, function(a, b) return a.label:lower() < b.label:lower() end)
    return sorted
end

-- Rows of the native submenu of makeListItem: the reorder action followed by
-- every pool entry as a checkable row. Rows of entries not yet added show how
-- many places are left once the list is close to its maximum.
local function poolToggleRows(opts, list)
    local N_   = require("infra/sui_i18n").ngettext
    local rows = { arrangeAction(opts) }
    rows[1].separator = true

    local function selected(id)
        for _i, v in ipairs(list.getIds()) do
            if v == id then return true end
        end
        return false
    end

    for _i, entry in ipairs(sortedByLabel(list.pool())) do
        local id, label = entry.id, entry.label
        rows[#rows + 1] = {
            text_func = function()
                local max = resolve(opts.max)
                if not max or selected(id) then return label end
                local left = max - entryCount(opts)
                if left > 2 then return label end
                return label .. string.format(N_("  (%d left)", "  (%d left)", left), left)
            end,
            checked_func   = function() return selected(id) end,
            keep_menu_open = true,
            callback       = function()
                local done
                if selected(id) then done = removeEntry(opts, id) else done = addEntry(opts, id) end
                if done then opts.ctx_menu.refresh() end
            end,
        }
    end
    return rows
end

-- Returns the menu item for an ordered list of ids (see the header for `opts`).
function M.makeListItem(opts)
    -- A copy: `opts.getIds` may hand out the stored list.
    local function currentIds()
        local ids = {}
        for i, id in ipairs(opts.getIds()) do ids[i] = id end
        return ids
    end

    local function without(ids, id)
        local kept = {}
        for _i, v in ipairs(ids) do
            if v ~= id then kept[#kept + 1] = v end
        end
        return kept
    end

    local core = {
        ctx_menu  = opts.ctx_menu,
        title     = opts.title,
        text_func = opts.text_func,
        labels    = opts.labels,
        max       = opts.max,
        min       = opts.min,
        isEnabled = opts.isEnabled,
        count      = function() return #opts.getIds() end,
        getEntries = function()
            local labels = {}
            for _i, entry in ipairs(opts.pool()) do labels[entry.id] = entry.label end
            local entries = {}
            for _i, id in ipairs(opts.getIds()) do
                entries[#entries + 1] = { value = id, title = labels[id] or (opts.label and opts.label(id)) or tostring(id) }
            end
            return entries
        end,
        saveOrder   = opts.setIds,
        removeEntry = function(id) opts.setIds(without(opts.getIds(), id)) end,
        add = {
            choices = function()
                local taken = {}
                for _i, id in ipairs(opts.getIds()) do taken[id] = true end
                local nodes = {}
                for _i, entry in ipairs(sortedByLabel(opts.pool())) do
                    if not taken[entry.id] then
                        nodes[#nodes + 1] = { title = entry.label, value = entry.id }
                    end
                end
                return nodes
            end,
            onAdd = function(id)
                local ids = currentIds()
                ids[#ids + 1] = id
                opts.setIds(ids)
            end,
        },
    }

    local item = M.makeMenuItem(core)
    item.sub_item_table_func = function() return poolToggleRows(core, opts) end
    return item
end

return M
