#!/usr/bin/env lua

---
-- A mock WSAPI app, for testing the WSAPI-to-WSAPI routing
-- feature in Perihelion.
--
-- A lot of this file was taken from WSAPI's website, and is not
-- my own. See here: http://keplerproject.github.com/wsapi/manual.html
--
local _methods = {}


---
-- Run the app.
--
function _methods.run( wsapi_env )

  local headers = { ["Content-type"] = "text/html" }
 
  local function hello_text()
    coroutine.yield("<html><body>")
    coroutine.yield("<p>Hello Wsapi!</p>")
    coroutine.yield("<p>PATH_INFO: " .. wsapi_env.PATH_INFO .. "</p>")
    coroutine.yield("<p>SCRIPT_NAME: " .. wsapi_env.SCRIPT_NAME .. "</p>")
    coroutine.yield("</body></html>")
  end

  return "200 OK", headers, coroutine.wrap(hello_text)

end



---
-- Exposed namespace, mostly a 'new' function
--
local _M = {}

function _M.new()
	local ret = {}
	
	for k, v in pairs(_methods) do
		ret[k] = v
	end
	
	return ret
end

return _M
