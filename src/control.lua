local event = require('__RaiLuaLib__.lualib.event')

local tests = require('tests.tests')
for _,test in pairs(tests) do
  require('tests.'..test..'.control')
end