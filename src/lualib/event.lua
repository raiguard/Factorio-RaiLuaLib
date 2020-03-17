-- -------------------------------------------------------------------------------------------------------------------------------------------------------------
-- RAILUALIB EVENT MODULE
-- Event registration, conditional event management, GUI event filtering.

-- locals
local string_match = string.match
local table_insert = table.insert
local table_remove = table.remove

-- object
local event = {}

-- -----------------------------------------------------------------------------
-- DISPATCHING

-- holds registered events for dispatch
local events = {}
-- holds conditional event data
local conditional_events = {}
-- conditional events by group
local conditional_event_groups = {}
-- whether or not a certain handler has been registered to a conditional event
local associated_handlers = {}

-- GUI filter matching functions
local gui_filter_matchers = {
  string = function(element, filter) return string_match(element.name, filter) end,
  number = function(element, filter) return element.index == filter end,
  table = function(element, filter) return element == filter end
}

-- calls handler functions tied to an event
-- all non-bootstrap events go through this function
local function dispatch_event(e)
  local global_data = global.__lualib.event.conditional_events
  local id = e.name
  -- set ID for special events
  if e.nth_tick then
    id = -e.nth_tick
  end
  if e.input_name then
    id = e.input_name
  end
  -- error checkingw
  if not events[id] then
    error('Event is registered but has no handlers!')
  end
  for _,t in ipairs(events[id]) do -- for every handler registered to this event
    local options = t.options
    if not options.skip_validation then
      -- check if any userdata has gone invalid since last iteration
      for _,v in pairs(e) do
        if type(v) == 'table' and v.__self and not v.valid then
          return
        end
      end
    end
    -- if we are a conditional event, insert registered players
    local name = t.conditional_name
    local gui_filters
    if name then
      local con_data = global_data[name]
      if not con_data then error('Conditional event has been raised, but has no data!') end
      if con_data ~= true then
        e.registered_players = con_data.players
        -- if there are GUI filters, check them
        gui_filters = con_data.gui_filters[e.player_index]
        if not gui_filters and table_size(con_data.gui_filters) > 0 then
          goto continue
        end
      end
    else
      gui_filters = t.gui_filters
    end
    -- check GUI filters, if any
    if gui_filters then
      -- check GUI filters if they exist
      local elem = e.element
      if not elem then
        -- there is no element to filter, so skip calling the handler
        log('Event '..id..' has GUI filters but no GUI element, skipping!')
        goto continue
      end
      local matchers = gui_filter_matchers
      for i=1,#gui_filters do
        local filter = gui_filters[i]
        if matchers[type(filter)](elem, filter) then
          goto call_handler
        end
      end
      -- if we're here, none of the filters matched, so don't call the handler
      goto continue
    end
    ::call_handler::
    -- call the handler
    t.handler(e)
    ::continue::
    if options.force_crc then
      game.force_crc()
    end
  end
  return
end

-- BOOTSTRAP EVENTS
-- these events are handled specially and do not go through dispatch_event

script.on_init(function()
  global.__lualib = {event={conditional_events={}, players={}}}
  -- dispatch events
  for _,t in ipairs(events.on_init or {}) do
    t.handler()
  end
  -- dispatch postprocess events
  for _,t in ipairs(events.on_init_postprocess or {}) do
    t.handler()
  end
end)

script.on_load(function()
  -- dispatch events
  for _,t in ipairs(events.on_load or {}) do
    t.handler()
  end
  -- dispatch postprocess events
  for _,t in ipairs(events.on_load_postprocess or {}) do
    t.handler()
  end
  -- re-register conditional events
  local registered = global.__lualib.event.conditional_events
  for n,_ in pairs(registered) do
    event.enable(n, nil, nil, true)
  end
end)

script.on_configuration_changed(function(e)
  -- dispatch events
  for _,t in ipairs(events.on_configuration_changed or {}) do
    t.handler(e)
  end
end)

-- -----------------------------------------------------------------------------
-- REGISTRATION

local bootstrap_events = {on_init=true, on_init_postprocess=true, on_load=true, on_load_postprocess=true, on_configuration_changed=true}

-- register static (non-conditional) events
-- used by register_conditional to insert the handler
-- conditional name is not to be used by the modder - it is internal only!
function event.register(id, handler, gui_filters, options, conditional_name)
  options = options or {}
  -- register handler
  if type(id) ~= 'table' then id = {id} end
  for _,n in pairs(id) do
    -- create event registry if it doesn't exist
    if not events[n] then
      events[n] = {}
    end
    local registry = events[n]
    -- create master handler if not already created
    if not bootstrap_events[n] then
      if #registry == 0 then
        if type(n) == 'number' and n < 0 then
          script.on_nth_tick(-n, dispatch_event)
        else
          script.on_event(n, dispatch_event)
        end
      end
    end
    -- make sure the handler has not already been registered
    for i,t in ipairs(registry) do
      if t.handler == handler then
        -- remove handler for re-insertion at the bottom
        if not options.suppress_logging then
          log('Re-registering existing event \''..n..'\', moving to bottom')
        end
        table_remove(registry, i)
      end
    end
    -- nest GUI filters into an array if they're not already
    if gui_filters then
      if type(gui_filters) ~= 'table' or gui_filters.gui then
        gui_filters = {gui_filters}
      end
    end
    -- insert handler
    local data = {handler=handler, gui_filters=gui_filters, options=options, conditional_name=conditional_name}
    if options.insert_at then
      table_insert(registry, options.insert_at, data)
    else
      table_insert(registry, data)
    end
  end
  return
end

-- register conditional (non-static) events
-- called in on_init and on_load ONLY
function event.register_conditional(data)
  for n,t in pairs(data) do
    if conditional_events[n] then
      error('Duplicate conditional event: '..n)
    end
    if associated_handlers[t.handler] then
      error('Every conditional event must have a unique handler.')
    end
    associated_handlers[t.handler] = n
    t.options = t.options or {}
    -- add to conditional events table
    conditional_events[n] = t
    -- add to group lookup
    local groups = t.group
    if groups then
      if type(groups) ~= 'table' then groups = {groups} end
      for i=1,#groups do
        local group = conditional_event_groups[groups[i]]
        if group then
          group[#group+1] = n
        else
          conditional_event_groups[groups[i]] = {n}
        end
      end
    end
  end
end

-- enables a conditional event
function event.enable(name, player_index, gui_filters, reregister)
  local data = conditional_events[name]
  if not data then
    error('Conditional event \''..name..'\' was not registered and has no data!')
  end
  local global_data = global.__lualib.event
  local saved_data = global_data.conditional_events[name]
  local add_player_data = false
  -- nest GUI filters into an array if they're not already
  if gui_filters then
    if type(gui_filters) ~= 'table' or gui_filters.gui then
      gui_filters = {gui_filters}
    end
  end
  if saved_data then
    -- update existing data / add this player
    if player_index then
      if saved_data == true then error('Tried to add a player to a global conditional event!') end
      local player_lookup = global_data.players[player_index]
      -- check if they're already registered
      if player_lookup and player_lookup[name] then
        -- don't do anything
        if not data.options.suppress_logging then
          log('Tried to re-register conditional event \''..name..'\' for player '..player_index..', skipping!')
        end
        return
      else
        add_player_data = true
      end
    elseif not reregister then
      if not data.options.suppress_logging then
        log('Conditional event \''..name..'\' was already registered, skipping!')
      end
      return
    end
  else
    -- add to global
    if player_index then
      global_data.conditional_events[name] = {gui_filters={}, players={}}
      add_player_data = true
    else
      global_data.conditional_events[name] = true
    end
    saved_data = global_data.conditional_events[name]
  end
  -- add to player lookup table
  if add_player_data then
    local player_lookup = global_data.players[player_index]
    -- add the player to the event
    saved_data.gui_filters[player_index] = gui_filters
    table_insert(saved_data.players, player_index)
    -- add to player lookup table
    if not player_lookup then
      global_data.players[player_index] = {[name]=true}
    else
      player_lookup[name] = true
    end
  end
  -- register handler
  event.register(data.id, data.handler, data.gui_filters, data.options, name)
end

-- disables a conditional event
function event.disable(name, player_index)
  local data = conditional_events[name]
  if not data then
    error('Tried to disable conditional event \''..name..'\', which does not exist!')
  end
  local global_data = global.__lualib.event
  local saved_data = global_data.conditional_events[name]
  if not saved_data then
    log('Tried to disable conditional event \''..name..'\', which is not enabled!')
    return
  end
  -- remove player from / manipulate global data
  if player_index then
    -- check if the player is actually registered to this event
    if global_data.players[player_index][name] then
      -- remove from players subtable
      for i,pi in ipairs(saved_data.players) do
        if pi == player_index then
          table.remove(saved_data.players, i)
          break
        end
      end
      -- remove GUI filters
      saved_data.gui_filters[player_index] = nil
      -- remove from lookup table
      global_data.players[player_index][name] = nil
      -- remove lookup table if it's empty
      if table_size(global_data.players[player_index]) == 0 then
        global_data.players[player_index] = nil
      end
    else
      log('Tried to disable conditional event \''..name..'\' from player #'..player_index..' when it wasn\'t enabled for them!')
      return
    end
    if #saved_data.players == 0 then
      global_data.conditional_events[name] = nil
    else
      -- don't do anything else
      return
    end
  else
    if type(saved_data) == 'table' then
      -- remove from all player lookup tables
      local players = global_data.players
      for i=1,#saved_data.players do
        players[saved_data.players[i]][name] = nil
      end
    end
    global_data.conditional_events[name] = nil
  end
  -- deregister handler
  local id = data.id
  if type(id) ~= 'table' then id = {id} end
  for _,n in pairs(id) do
    local registry = events[n]
    -- error checking
    if not registry or #registry == 0 then
      log('Tried to deregister an unregistered event of id: '..n)
      return
    end
    -- remove the handler from the events tables
    for i,t in ipairs(registry) do
      if t.handler == data.handler then
        table.remove(registry, i)
      end
    end
    -- de-register the master handler if it's no longer needed
    if #registry == 0 then
      if type(n) == 'number' and n < 0 then
        script.on_nth_tick(math.abs(n), nil)
      else
        script.on_event(n, nil)
      end
      events[n] = nil
    end
  end
end

-- enables a group of conditional events
function event.enable_group(group, player_index, gui_filters)
  local group_events = conditional_event_groups[group]
  if not group_events then error('Group \''..group..'\' has no handlers!') end
  for i=1,#group_events do
    event.enable(group_events[i], player_index, gui_filters)
  end
end

-- disables a group of conditional events
function event.disable_group(group, player_index)
  local group_events = conditional_event_groups[group]
  if not group_events then error('Group \''..group..'\' has no handlers!') end
  for i=1,#group_events do
    event.disable(group_events[i], player_index)
  end
end

-- -------------------------------------
-- SHORTCUT FUNCTIONS

-- bootstrap events
function event.on_init(handler, options)
  return event.register('on_init', handler, nil, options)
end

function event.on_load(handler, options)
  return event.register('on_load', handler, nil, options)
end

function event.on_configuration_changed(handler, options)
  return event.register('on_configuration_changed', handler, nil, options)
end

function event.on_nth_tick(nthTick, handler, options)
  return event.register(-nthTick, handler, nil, options)
end

-- defines.events
for n,id in pairs(defines.events) do
  event[n] = function(handler, options)
    event.register(id, handler, options)
  end
end

-- -----------------------------------------------------------------------------
-- EVENT MANIPULATION

-- raises an event as if it were actually called
function event.raise(id, table)
  script.raise_event(id, table)
  return
end

-- set or remove event filters
function event.set_filters(id, filters)
  if type(id) ~= 'table' then id = {id} end
  for _,n in pairs(id) do
    script.set_event_filter(n, filters)
  end
  return
end

-- holds custom event IDs
local custom_id_registry = {}

-- generates or retrieves a custom event ID
function event.get_id(name)
  if not custom_id_registry[name] then
    custom_id_registry[name] = script.generate_event_name()
  end
  return custom_id_registry[name]
end

-- saves a custom event ID
function event.save_id(name, id)
  if custom_id_registry[name] then
    log('Overwriting entry in custom event registry: '..name)
  end
  custom_id_registry[name] = id
end

-- appends an array with the elements in the second array
local function append_array(t1, t2)
  local t1_len = #t1
  for i=1,#t2 do
    t1[t1_len+i] = t2[i]
  end
  return t1
end
-- updates the GUI filters for the given conditional event
function event.update_gui_filters(name, player_index, filters, append_mode)
  if type(filters) ~= 'table' or filters.gui then
    filters = {filters}
  end
  local event_data = global.__lualib.event.conditional_events[name]
  if not event_data then error('Cannot update GUI filters for a non-existent event!') end
  if append_mode then
    local filters_t = event_data.gui_filters
    filters_t[player_index] = append_array(filters_t[player_index], filters)
  else
    event_data.gui_filters[player_index] = filters
  end
end

-- retrieves and returns the global data for the given conditional event
function event.get_event_data(name)
  return global.__lualib.event.conditional_events[name]
end

-- returns true if the conditional event is registered
function event.is_enabled(name, player_index)
  local global_data = global.__lualib.event
  local registry = global_data.conditional_events[name]
  if registry then
    if player_index then
      for _,i in ipairs(registry.players) do
        if i == player_index then
          return true
        end
      end
      return false
    end
    return true
  end
  return false
end

-- -----------------------------------------------------------------------------

event.events = events
event.conditional_events = conditional_events
event.conditional_event_groups = conditional_event_groups

return event