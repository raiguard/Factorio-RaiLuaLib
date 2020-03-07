-- -------------------------------------------------------------------------------------------------------------------------------------------------------------
-- RAILUALIB GUI MODULE
-- GUI templating and event handling

-- dependencies
local event = require('__RaiLuaLib__.lualib.event')

-- locals
local global_data
local string_find = string.find
local string_gsub = string.gsub
local string_gmatch = string.gmatch

-- settings
local handlers = {}
local templates = {}

-- objects
local self = {}

-- -----------------------------------------------------------------------------
-- LOCAL UTILITIES

local function get_subtable(s, t)
  local o = t
  for key in string_gmatch(s, "([^%.]+)") do
    o = o[key]
  end
  return o
end

local function get_event_name(gui_name, handlers_path, event_name)
  return 'gui.'..gui_name..'.'..handlers_path..'.'..event_name
end

local function register_handlers(gui_name, handlers_path, options)
  local handlers_t = get_subtable(gui_name..'.'..handlers_path, handlers)
  local t = table.deepcopy(options)
  for n,func in pairs(handlers_t) do
    t.name = get_event_name(gui_name, handlers_path, n)
    -- check if the event has already been registered
    if event.is_registered(t.name, t.player_index) then
      -- append the GUI filters with our new element
      event.update_gui_filters(t.name, t.player_index, t.gui_filters, true)
    else
      -- actually register it
      if not global_data[gui_name] then global_data[gui_name] = {} end
      if not global_data[gui_name][t.player_index] then global_data[gui_name][t.player_index] = {} end
      global_data[gui_name][t.player_index][t.name] = true
      if defines.events[n] then n = defines.events[n] end
      event.register(n, func, t)
    end
  end
end

local function deregister_handlers(gui_name, handlers_path, player_index, gui_events)
  local handlers_t = get_subtable(gui_name..'.'..handlers_path, handlers)
  gui_events = gui_events or global_data[gui_name][player_index]
  if type(handlers_t) == 'function' then
    local name = 'gui.'..gui_name..'.'..handlers_path
    event.deregister_conditional(handlers_t, name, player_index)
    gui_events[name] = nil
  else
    for n,func in pairs(handlers_t) do
      event.deregister_conditional(func, n, player_index)
      gui_events[n] = nil
    end
  end
end

-- recursively load a GUI template
local function recursive_load(parent, t, output, build_data, name, player_index)
  -- load template
  if t.template then
    -- use a custom simple merge function to save performance
    local template = get_subtable(t.template, templates)
    for k,v in pairs(template) do
      t[k] = v
    end
  end
  local elem
  -- skip all of this if it's a tab-and-content
  if t.type ~= 'tab-and-content' then
    -- create element
    elem = parent.add(t)
    -- apply style modifications
    if t.style_mods then
      for k,v in pairs(t.style_mods) do
        if k ~= 'name' then
          elem.style[k] = v
        end
      end
    end
    -- apply modifications
    if t.mods then
      for k,v in pairs(t.mods) do
        elem[k] = v
      end
    end
    -- add to output table
    if t.save_as then
      if type(t.save_as) == 'boolean' then
        t.save_as = t.handlers
      end
      -- recursively create tables as needed
      local prev = output
      local prev_key
      local nav
      for key in string_gmatch(t.save_as, "([^%.]+)") do
        prev = prev_key and prev[prev_key] or prev
        nav = prev[key]
        if nav then
          prev = nav
        else
          prev[key] = {}
          prev_key = key
        end
      end
      prev[prev_key] = elem
    end
    -- register handlers
    if t.handlers then
      if name and player_index then
        register_handlers(name, t.handlers, {player_index=player_index, gui_filters=elem.index})
      else
        error('Must specify name and player index to register GUI events!')
      end
    end
    -- add children
    local children = t.children
    if children then
      for i=1,#children do
        output = recursive_load(elem, children[i], output, build_data, name, player_index)
      end
    end
  else -- tab-and-content
    local tab, content
    output, tab = recursive_load(parent, t.tab, output, build_data, name, player_index)
    output, content = recursive_load(parent, t.content, output, build_data, name, player_index)
    parent.add_tab(tab, content)
  end
  return output, elem
end

-- -----------------------------------------------------------------------------
-- SETUP

event.on_init(function()
  global.__lualib.gui = {}
  global_data = global.__lualib.gui
end)

event.on_load(function()
  global_data = global.__lualib.gui
  local con_registry = global.__lualib.event
  for n,t in pairs(con_registry) do
    if string_find(n, '^gui%.') then
      event.register(t.id, get_subtable(string_gsub(n, '^gui%.', ''), handlers), {name=n})
    end
  end
end)

event.on_configuration_changed(function(e)
  if not global.__lualib.gui then
    global.__lualib.gui = {}
    global_data = global.__lualib.gui
  end
end)

-- -----------------------------------------------------------------------------
-- OBJECT

-- name and player_index are only required if we're registering events
function self.build(parent, templates, name, player_index)
  local output = {}
  for i=1,#templates do
    output = recursive_load(parent, templates[i], output, {}, name, player_index)
  end
  return output
end

-- deregisters all handlers for the given GUI
function self.deregister_all(gui_name, player_index)
  -- deregister handlers
  local gui_tables = global_data[gui_name]
  if gui_tables then
    local list = gui_tables[player_index]
    for n,_ in pairs(list) do
      deregister_handlers(gui_name, string_gsub(n, '^gui%.'..gui_name..'%.', ''), player_index, list)
    end
    gui_tables[player_index] = nil
    if table_size(gui_tables) == 0 then
      global_data[gui_name] = nil
    end
  end
end

function self.add_templates(...)
  local arg = {...}
  if #arg == 1 then
    for k,v in pairs(arg[1]) do
      templates[k] = v
    end
  else
    templates[arg[1]] = arg[2]
  end
  return self
end

function self.add_handlers(...)
  local arg = {...}
  if #arg == 1 then
    for k,v in pairs(arg[1]) do
      handlers[k] = v
    end
  else
    handlers[arg[1]] = arg[2]
  end
  return self
end

-- calls a GUI template as a function
function self.call_template(path, ...)
  return get_subtable(path, templates)(...)
end

-- retrieves and returns a GUI template
function self.get_template(path)
  return get_subtable(path, templates)
end

-- calls a GUI handler
function self.call_handler(path, ...)
  return get_subtable(path, handlers)(...)
end

-- retrieves and returns a handler
function self.get_handler(path)
  return get_subtable(path, handlers)
end

self.get_event_name = get_event_name
self.register_handlers = register_handlers
self.deregister_handlers = deregister_handlers

return self