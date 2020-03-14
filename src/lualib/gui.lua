-- -------------------------------------------------------------------------------------------------------------------------------------------------------------
-- RAILUALIB GUI MODULE
-- GUI templating and event handling

-- dependencies
-- local event = require('__RaiLuaLib__.lualib.event')

-- locals
local string_gmatch = string.gmatch

-- settings
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

-- recursively load a GUI template
local function recursive_load(parent, t, output)
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
    output, tab = recursive_load(parent, t.tab, output)
    output, content = recursive_load(parent, t.content, output)
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
        output = recursive_load(elem, children[i], output)
      end
    end
  end
  return output, elem
end

-- -----------------------------------------------------------------------------
-- OBJECT

function self.build(parent, templates)
  local output = {}
  for i=1,#templates do
    output = recursive_load(parent, templates[i], output)
  end
  return output
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

-- calls a GUI template as a function
function self.call_template(path, ...)
  return get_subtable(path, templates)(...)
end

-- retrieves and returns a GUI template
function self.get_template(path)
  return get_subtable(path, templates)
end

return self