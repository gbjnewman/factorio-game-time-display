require "constants"

function update_timer(player)
  local base = math.floor(game.tick/60)
  local seconds = math.floor(base) % 60
  local minutes = math.floor(base/60) % 60
  local hours = math.floor(base/3600)

  local caption = string.format("%02d:%02d", minutes, seconds)
  if hours > 0 then
    caption = string.format("%d:%s", hours, caption)
  end
  local label = player.gui.screen[GUI_FRAME_NAME][GUI_LABEL_NAME]
  label.caption = caption
end

function create_gui(player)
    -- Remove any existing timer frame before creating another one.
    -- This prevents duplicate GUI name errors during initialization.
    local existing_frame = player.gui.screen[GUI_FRAME_NAME]

    if existing_frame then
        existing_frame.destroy()
    end

    -- Create the timer frame and its label.
    local frame = player.gui.screen.add{
        type = "frame",
        name = GUI_FRAME_NAME
    }

    frame.style.padding = {0, 6, 0, 6}

    local label = frame.add{
        type = "label",
        name = GUI_LABEL_NAME
    }

    label.drag_target = frame
end

function init_gui(player)
    -- Keep existing player state if it is available.
    local player_state = storage.ptplus[player.name] or {}
    storage.ptplus[player.name] = player_state

    -- Remember the previously saved clock position.
    local saved_location = player_state.loc2

    -- Create the clock GUI.
    create_gui(player)

    if saved_location then
        -- Restore the player's previous position.
        set_gui_location(player, saved_location.x, saved_location.y)
        set_gui_location(player, saved_location.x, saved_location.y)
    else
        -- New players start at their configured position.
        reset_gui_location(player)
    end

    update_timer(player)
end

function destroy_gui(player)
  if player.gui.screen[GUI_FRAME_NAME] then
    player.gui.screen[GUI_FRAME_NAME].destroy()
  end
end

function reset_gui_location(player)
  local x = settings.get_player_settings(player)["ptplus-x"].value
  local y = settings.get_player_settings(player)["ptplus-y"].value
  set_gui_location(player, x, y)
  set_gui_location(player, x, y) -- Call twice to override location buffering
end

function save_gui_location(player)
  local frame = player.gui.screen[GUI_FRAME_NAME]
  -- Buffering gui location to look one previous location due to on_gui_location_changed() is triggerd BEFORE on_player_display_resolution_change()
  storage.ptplus[player.name].loc1 = storage.ptplus[player.name].loc2
  storage.ptplus[player.name].loc2 = {x = frame.location.x, y = frame.location.y}
end

function reposition_gui(event, player)
  if not (storage.ptplus[player.name].loc1) then return end -- Workaround to prevent crash

  local currw = player.display_resolution.width
  local currh = player.display_resolution.height
  local prevw = event.old_resolution.width
  local prevh = event.old_resolution.height

  local scale = player.display_scale
  local w = calc_width(player) * scale
  local x = math.floor(storage.ptplus[player.name].loc1.x / prevw * currw)
  local y = math.floor(storage.ptplus[player.name].loc1.y / prevh * currh)

  set_gui_location(player, x, y)
  set_gui_location(player, x, y) -- Call twice to override location buffering
end

function snap_gui(player)
  local frame = player.gui.screen[GUI_FRAME_NAME]
  local margin = GUI_SNAP_MARGIN -- snap sensitivity

  local x = frame.location.x
  local y = frame.location.y
  if x < margin then x = 0 end
  if y < margin then y = 0 end

  local scale = player.display_scale
  local w = calc_width(player) * scale
  local h = 28 * scale
  if x > player.display_resolution.width - margin - w then x = player.display_resolution.width - w end
  if y > player.display_resolution.height - margin - h then y = player.display_resolution.height - h end

  set_gui_location(player, x, y)
end

function calc_width(player)
  local label = player.gui.screen[GUI_FRAME_NAME][GUI_LABEL_NAME]
  local caption = label.caption
  local WIDTH_CHAR = 8
  local WIDTH_COLON = 2
  local WIDTH_MARGIN = 9
  local n_char = #string.gsub(caption, ":", "")
  local n_colon = #caption - n_char
  return n_char * WIDTH_CHAR + n_colon * WIDTH_COLON + 2 * WIDTH_MARGIN
end

function set_gui_location(player, x, y)
  local frame = player.gui.screen[GUI_FRAME_NAME]
  frame.location = {x, y}
  save_gui_location(player)
end

--------------------------------------------------------------------------------
-- event handlers
local function on_nth_tick_60()
  for _, player in pairs(game.players) do
    if storage.ptplus[player.name] ~= nil then -- Workaround to prevent crash #https://mods.factorio.com/mod/playtime-plus/discussion/64186da0b66cf569cb6e8518
      update_timer(player)
    end
  end
end

local function on_nth_tick_hour()
  for _, player in pairs(game.players) do
    if storage.ptplus[player.name] ~= nil then -- Workaround to prevent crash #https://mods.factorio.com/mod/playtime-plus/discussion/64186da0b66cf569cb6e8518
      snap_gui(player) -- preventing out of edge per hour
    end
  end
end

local function on_configuration_changed(event)
    -- Keep existing player state where possible.
    storage.ptplus = storage.ptplus or {}

    for _, player in pairs(game.players) do
        -- Remember the clock position before rebuilding it.
        local old_frame = player.gui.screen[GUI_FRAME_NAME]
        local old_location = nil

        if old_frame then
            old_location = {
                x = old_frame.location.x,
                y = old_frame.location.y
            }
        end

        -- Recreate the clock safely.
        init_gui(player)

        -- Restore its previous position.
        if old_location then
            set_gui_location(player, old_location.x, old_location.y)
        end
    end
end

local function on_player_created(event)
  local player = game.players[event.player_index]
  init_gui(player)
end

local function on_gui_click(event)
  if event.element.name == GUI_LABEL_NAME and event.button == defines.mouse_button_type.right then
    local player = game.players[event.player_index]
    reset_gui_location(player)
  end
end

local function on_gui_location_changed(event)
  if event.element.name == GUI_FRAME_NAME then
    local player = game.players[event.player_index]
    snap_gui(player)
  end
end

local function on_player_display_resolution_changed(event)
  local player = game.players[event.player_index]
  reposition_gui(event, player)
end

local function on_runtime_mod_setting_changed(event)
  if event.setting == "ptplus-x" or event.setting == "ptplus-y" then
    local player = game.players[event.player_index]
    reset_gui_location(player)
  end
end

script.on_init(function()
  storage.ptplus = {}
end)

script.on_nth_tick(60, on_nth_tick_60)
script.on_nth_tick(60*60*60, on_nth_tick_hour)
script.on_configuration_changed(on_configuration_changed)
script.on_event(defines.events.on_player_created, on_player_created)
script.on_event(defines.events.on_gui_click, on_gui_click)
script.on_event(defines.events.on_gui_location_changed, on_gui_location_changed)
script.on_event(defines.events.on_player_display_resolution_changed, on_player_display_resolution_changed)
script.on_event(defines.events.on_runtime_mod_setting_changed, on_runtime_mod_setting_changed)
