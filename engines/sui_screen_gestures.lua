-- engines/sui_screen_gestures.lua — selects and runs the file manager touch
-- zones that a fullscreen screen shown over it has to forward.

local M = {}

-- Every gesture type KOReader's gesture detector emits.
M.GESTURE_TYPES = {
    "tap", "double_tap", "touch",
    "hold", "hold_pan", "hold_release",
    "swipe", "pan", "pan_release", "multiswipe", "inward_pan", "outward_pan",
    "two_finger_tap", "two_finger_swipe", "two_finger_pan", "two_finger_pan_release",
    "two_finger_hold", "two_finger_hold_pan",
    "spread", "pinch", "rotate",
}

-- File manager zones registered by KOReader itself; screens provide their own.
local NATIVE = {
    filemanager_tap       = true,
    filemanager_ext_tap   = true,
    filemanager_swipe     = true,
    filemanager_ext_swipe = true,
}

-- Pan placeholders KOReader's gesture actions add for each edge swipe; they
-- never act in the file manager.
local PLACEHOLDERS = { "^one_finger_swipe_.+_pan$", "^one_finger_swipe_.+_pan_release$" }

-- This plugin's own zones; screens register their own copies.
local function isOwn(id)
    return id:find("^navbar_") ~= nil or id:find("^simpleui_") ~= nil
end

--- True when the zone defined by `def` is forwarded to the file manager.
function M.isDelegated(def)
    local id = def and def.id
    if not id or NATIVE[id] or isOwn(id) then return false end
    for _, pattern in ipairs(PLACEHOLDERS) do
        if id:find(pattern) then return false end
    end
    return true
end

--- Set of the gesture types of the delegated zones.
function M.typeSet(zones)
    local set = {}
    for _, tzone in ipairs(zones or {}) do
        if M.isDelegated(tzone.def) then set[tzone.def.ges] = true end
    end
    return set
end

--- Runs the delegated zones that match `ges`, in order, skipping those whose
--- definition `filter` (optional) rejects. Stops, unconsumed, at a matching
--- zone of this plugin, so the screen's own copy of it runs at the same point
--- of the order as in the file manager. Returns true when a zone consumed the
--- gesture.
function M.run(zones, ges, filter)
    for _, tzone in ipairs(zones or {}) do
        local def = tzone.def
        if tzone.gs_range:match(ges) and (not filter or filter(def)) then
            if def.id and isOwn(def.id) then return false end
            if M.isDelegated(def) and tzone.handler(ges) then return true end
        end
    end
    return false
end

--- Id of the screen zone that forwards gesture type `ges`.
function M.zoneId(pfx, ges)
    return pfx .. "fm_" .. ges
end

return M
