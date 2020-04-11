-- -------------------------------------------------------------------------------------------------------------------------------------------------------------
-- RAILUALIB MIGRATION MODULE
-- Migration handling for different versions.

-- object
local migration = {}

-- locals
local string_split = require("__core__.lualib.util").split

-- returns true if v2 is newer than v1, false if otherwise
function migration.compare_versions(v1, v2)
  local v1_split = string_split(v1, ".")
  local v2_split = string_split(v2, ".")
  for i=1,#v1_split do
    if v1_split[i] < v2_split[i] then
      return true
    elseif v1_split[i] > v2_split[i] then
      return false
    end
  end
  return false
end

-- run migrations
function migration.run(old, migrations, ...)
  local migrate = false
  for v,f in pairs(migrations) do
    if migrate or migration.compare_versions(old, v) then
      migrate = true
      f(...)
    end
  end
end

-- handle version migrations in on_configuration_changed
function migration.on_config_changed(e, migrations, ...)
  local changes = e.mod_changes[script.mod_name]
  if changes then
    local old = changes.old_version
    if old then
      migration.run(old, migrations, ...)
    else
      return false -- don't do generic migrations, because we just initialized
    end
  end
  return true
end

return migration