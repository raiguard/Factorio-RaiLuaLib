-- -------------------------------------------------------------------------------------------------------------------------------------------------------------
-- RAILUALIB GUI MODULE
-- GUI templating and event registration

-- dependencies
local event = require('__RaiLuaLib__.lualib.event')
local util = require('__core__.lualib.util')

-- locals
local string_gmatch = string.gmatch

local handler_data = {}

-- object
local gui = {}
local handlers = {}
local templates = {}

-- -----------------------------------------------------------------------------
-- TABLE OBJECTS

local function extend_table(self, data, do_return)
  for k, v in pairs(data) do
    if (type(v) == "table") then
      if (type(self[k] or false) == "table") then
        self[k] = extend_table(self[k], v, true)
      else
        self[k] = table.deepcopy(v)
      end
    else
      self[k] = v
    end
  end
  if do_return then return self end
end

handlers.extend = extend_table
templates.extend = extend_table

-- -----------------------------------------------------------------------------
-- EVENTS

-- recursively navigate the handlers table to create the events
local function generate_events(t, event_string, event_groups)
  event_groups[#event_groups+1] = event_string
  for k,v in pairs(t) do
    if k ~= 'extend' then
      local new_string = event_string..'.'..k
      if v.handler then
        v.group = table.deepcopy(event_groups)
        handler_data[new_string] = v
      else
        generate_events(v, new_string, event_groups)
      end
    end
  end
  event_groups[#event_groups] = nil
end

-- register all GUI conditional events
event.register({'on_init_postprocess', 'on_load_postprocess'}, function(e)
  -- create and register conditional handlers for the GUI events
  generate_events(handlers, 'gui', {})
  event.register_conditional(handler_data)
end)

-- -----------------------------------------------------------------------------
-- GUI CONSTRUCTION

local function get_subtable(s, t)
  local o = t
  for key in string_gmatch(s, "([^%.]+)") do
    o = o[key]
  end
  return o
end

-- recursively load a GUI template
local function recursive_load(parent, t, output, player_index)
  -- load template
  if t.template then
    -- use a custom simple merge function to save performance
    local template = get_subtable(t.template, templates)
    for k,v in pairs(template) do
      t[k] = v
    end
  end
  local elem
  -- special logic if this is a tab-and-content
  if t.type == 'tab-and-content' then
    local tab, content
    output, tab = recursive_load(parent, t.tab, output, player_index)
    output, content = recursive_load(parent, t.content, output, player_index)
    parent.add_tab(tab, content)
  else
    -- create element
    elem = parent.add(t)
    -- apply style modifications
    if t.style_mods then
      for k,v in pairs(t.style_mods) do
        elem.style[k] = v
      end
    end
    -- apply modifications
    if t.mods then
      for k,v in pairs(t.mods) do
        elem[k] = v
      end
    end
    -- register handlers
    if t.handlers then
      local id = elem.index
      local name = 'gui.'..t.handlers
      local group = event.conditional_event_groups[name]
      if not group then error('Invalid GUI event group: '..name) end
        -- check if this event group was already enabled
      if event.is_enabled(group[1], player_index) then
        -- append the GUI filters to include this element
        for i=1,#group do
          event.update_gui_filters(group[i], player_index, id, true)
        end
      else
        -- enable the group
        event.enable_group(name, player_index, id)
      end
    end
    -- add to output table
    if t.save_as then
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
    -- add children
    local children = t.children
    if children then
      for i=1,#children do
        output = recursive_load(elem, children[i], output, player_index)
      end
    end
  end
  return output, elem
end

-- -----------------------------------------------------------------------------
-- OBJECT

function gui.build(parent, templates)
  local output = {}
  for i=1,#templates do
    output = recursive_load(parent, templates[i], output, parent.player_index or parent.player.index)
  end
  return output
end

gui.templates = templates
gui.handlers = handlers

return gui