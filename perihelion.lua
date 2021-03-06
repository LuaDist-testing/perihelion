#!/usr/bin/env lua


---
-- The central Perihelion app object. 
--
local _methods = {}


--
-- 5.1 Compatibility
--
if not table.unpack then
	table.unpack = unpack
end


---
--
-- Typical reponse codes, used by a number of functions below
--
local _codes = {

   [200] = "OK",
   [301] = "Moved Permanently",
   [302] = "Found",
   [403] = "Forbidden",
   [404] = "Not Found",
   [500] = "Internal Server Error"
   
}


---
-- Render a server error page.
--
-- This will become obsolete when Perihelion supports error pages.
--
local function wsapi_error( request_env, err )

  	local headers = { ["Content-type"] = "text/html" }

	local function error_text()
		coroutine.yield(  [[
<html>
<head>
	<title>500 Internal Server Error</title>
</head>
<body>
	<h1>Server Error</h1>
	An internal error occured with this application:
]]
.. tostring(err) ..
[[</body>
</html>
		]] )
	end

	return "500 Internal Server Error", headers, coroutine.wrap(error_text)

end


---
-- Render a not found page.
--
-- This will likely become obsolete when Perihelion supports error pages.
--
local function wsapi_404( request_env )

  	local headers = { ["Content-type"] = "text/html" }

	local function error_text()
		coroutine.yield( [[
<html>
<head>
	<title>404 Not Found</title>
</head>
<body>
	<h1>Not Found</h1>
	The requested URL was not mapped:
	<p>
]]
	.. request_env.PATH_INFO ..
[[	</p>
</body>
</html>
		]] )
	end

	return "404 Not Found", headers, coroutine.wrap(error_text)

end


---
-- Simplify URL processing by removing redundant slashes and
-- chopping of variables.
--
local function compress_path( path )

	-- special case: do nothing if merely '/'.
	if path == '/' then
		return path
	end

	-- smoosh multiple slashes together. they cause pain.
	path = path:gsub("%/%/+", "/")
	
	-- chop off the last one, while we are at it
	path = path:gsub("%/$", "")
	
	return path
	
end


---
-- Disconnect GET variables from a request URI.
--
local function parse_uri( uri )

	-- chop variables
	local path, vars = string.match(uri, "([^%?]+)(.*)")

	-- chop the '?' off the variables
	if vars then
		vars = vars:gsub("^%?", "")
	end

	return compress_path( path ), vars

end


---
-- Undo URL encoding.
-- Lifted directly from "Programming In Lua" 5.0 edition
--
local function urldecode(s)

	s = string.gsub(s, "+", " ")
	s = string.gsub(s, "%%(%x%x)", function (h)
		return string.char(tonumber(h, 16))
	end)

	return s

end


---
-- Split the path into components, as an iterator.
--
local function split_string( s, delimit )

	local function f()
	
		while true do
		
			local start, stop = s:find(delimit)
			
			if not start then 
				coroutine.yield(s)
				return
			end
			
			local part = s:sub(1, start - 1)
			local remain = s:sub(start)
			
			coroutine.yield(part, remain)
			s = s:sub(start + 1)
		
		end
	
	end

	return coroutine.wrap(f)

end


---
-- Decodes a GET query string into a table.
-- Mostly lifted from "Programming In Lua" 5.0 edition
--
local function decode_get_variables( vstring )
     
	local ret = {}
	
	-- skip non-sane input
	if not vstring then return {} end
	
	-- 'a=b' is the smallest the query string could possibly be
	if #vstring < 3 then return {} end
	
	for name, value in string.gmatch(vstring, "([^&=]+)=([^&=]+)") do
		name = urldecode(name)
		value = urldecode(value)
		ret[name] = value
	end
			
	return ret
      
end



---
-- Take a chunk of a multipart/form-data POST and turn it into
-- an entry in the POST table.
--
local function decode_mime_part( mime_part )

	--
	-- There are two parts to a MIME message part: headers and data.
	-- Split them.
	--
	local raw_headers = {}
	local data = nil
	--local line_term = "[\n" .. char(0x0D) .. char(0x0A) .. "]"
	
	for v, r in split_string( mime_part, "\n" ) do
	
		if not v or v:match("^%s*$") then
			data = r
			break
		else
			raw_headers[ #raw_headers + 1 ] = v
		end
	
	end
	
	--
	-- Kill the remaining newline at the beginning of the data field.
	--
	if data then
		data = data:gsub('^(%s*)', '')
	end
	
	--
	-- Extract header data
	--
	local decoded = {}
	local function headercheck( headers, field )
		local c = string.match(field, 'Content%-Type: (.*)$')
		if c then
			decoded.content = c:gsub("(%s*)$", "")
		end
		
		local name = string.match(field, 'Content%-Disposition: form%-data; name="([^"]-)"%s*$')
		if name then
			decoded.name = name
			decoded.isfile = false
			return
		end
		
		local m, n = string.match(field, 'Content%-Disposition: form%-data; name="([^"]-)"; filename="([^"]-)"')
		if m then
			decoded.name = m
			decoded.filename = n:gsub("(%s*)$", "")
			decoded.isfile = true
			return
		end
	end
	

	for i, v in ipairs(raw_headers) do
		headercheck( raw_headers, v )
	end
	
	if not decoded.name or decoded.name == '' then
		return nil
	end


	--
	-- Precisely one line terminator at the end.
	--
	decoded.value = data:gsub('(%s?%s)$', "")

	return decoded

end



---
-- Break up a multipart/form-data POST request.
--
local function decode_post_multipart( data, bound )

	local ret = {}
	bound = "--" .. bound
	local escaped_bound = bound:gsub('%-', '%%-')
	
	--
	-- Need to find the first chunk, which will be after the
	-- first delimiter. Advance the iterator once and throw it away.
	--
	for mime_part in split_string( data, escaped_bound ) do
		if mime_part and #mime_part > 1 then
			
			-- cut off the delimiter in the beginning, string_split
			-- leaves it there. Kill beginning new lines.
			mime_part = mime_part:sub( #bound )
			mime_part = mime_part:gsub("^(%s*)", "")
				
			local decoded = decode_mime_part(mime_part)
				
			if decoded then		
				ret[ #ret + 1 ] = decoded
			end
		end
	end
	
	return ret

end


---
-- Decode POST variables.
--
local function decode_post_variables( req )


	assert(req.CONTENT_TYPE, "Content type isn't set - can't POST!")
	assert(req.CONTENT_LENGTH, "Content length isn't set - can't POST!")
	assert(req.input, "No input stream - can't POST!")

	--
	-- There's got to be a better way to handle this than slurping
	-- the entire content into memory. Line endings are making it
	-- a hairy mess to implement, though, and right now I just want
	-- this thing to work.
	--
	local len = tonumber(req.CONTENT_LENGTH) or 0
	local ctype = req.CONTENT_TYPE
	local data = req.input:read(len)
	
	--
	-- Easy, it's the same as GET.
	--
	if ctype == 'application/x-www-form-urlencoded' then
		
		req.POST = decode_get_variables( data )
		req.POST_RAW = nil
		return
	
	end

	--
	-- Much harder. Thanks, HTML4, for causing this pain.
	--
	if string.match(ctype, "^multipart/form%-data;") then
	
		local bound = string.match(ctype, "boundary%=([%w%-]+)")
		local vars = decode_post_multipart( data, bound )
		
		req.POST = {}
		req.POST_RAW = nil
		req.FILE = {}
			
		for i, var in ipairs(vars) do
		
			if not var.isfile then
				req.POST[var.name] = var.value
			else
				req.FILE[var.name] = {
					['CONTENT-TYPE'] = var.content,
					['DATA'] = var.value,
					['FILENAME'] = var.filename
				}
			end
		end
		
		return
		
	end


	--
	-- Fallback: unknown type, leave a big string.
	-- 
	req.POST = {}
	req.POST_RAW = data
	return

end



---
-- Destroy the internal variables we were caching inside the
-- request object.
--
local function sanitize_request( env )

	env._UNMATCHED = nil
	env._GET_VARIABLES = nil
	env._URI = nil

end


---
-- Set a list of handler functions for the given path, to be
-- invoked during an HTTP request.
--
-- This function is where the syntax-hack magic happens, thus the
-- multilayered complexity.
--
local function set_route( app, method, path )

	--
	-- Sanity check - set_route doesn't work on everything yet.
	-- 
	local methods = {
			GET = true,
			POST = true
		}

	assert(methods[method], "Attempting to set unknown method")
	path = compress_path(path)

	--
	-- I can't claim credit for the following madness; it was shown to 
	-- me by someone (I can't recall whom) at Lua Workshop 2012. Said
	-- demonstration immediately spawned the idea for Perihelion.
	--
	--
	-- Let's peel this onion.
	--
	-- First layer: set_route is called by the user of Perihelion to
	-- setup the routing table. It does this by immediately returning
	-- a function.
	--
	-- The returned function is what allows the table of handlers 
	-- immediately after the path in the perihelion app to be valid
	-- Lua syntax.
	-- 
	-- set_route recieves the path, the following anonymous function
	-- gets the handlers.
	--
	return function( handlers )
	
		--
		-- Second layer: inside this anonymous function, Perihelion
		-- now has access to the user's handler functions, in the form
		-- of a table.
		--
		-- This anonymous function runs once, at app startup, and saves
		-- the handler table into the app's routing table.
		--
		if not app.routes[ path ] then app.routes[path] = {} end
		app.routes[ path ][ method ] = function( request_env, ... )
		
			--
			-- Third layer: this function, set inside the routes table,
			-- actually handles requests.
			--
			-- This is called for every request that matches the route,
			-- and steps through the provided handlers until it gets
			-- a valid way to end the HTTP request.
			--
			local uri, get_vars = parse_uri( request_env.PATH_INFO )
			
			request_env.vars = {}
			
			request_env.GET = decode_get_variables(
					request_env._GET_VARIABLES
				)
			
			if method == 'POST' then
				decode_post_variables(request_env)
			end
			
			sanitize_request(request_env)
				
			for i, v in ipairs(handlers) do
					
				local output, headers, iter = v( request_env, ... )
				if type(output) == 'table' then
					vars = output
				elseif type(output) == 'string' 
						or type(output) == 'number' then
					return output, headers, iter
				else
					error("Undefined output")
				end
					
				for k, v in pairs(output) do
					request_env.vars[k] = v
				end
					
			end
				
			return wsapi_error(
				request_env, 
				"Application didn't finish response"
			)
		end
	end

end


---
-- Tells Perihelion that this application is running under
-- a prefix that must be removed before routing a web request.
--
function _methods.prefix( self, path )

	--
	-- Prefix must start with '/' and not end with '/'.
	--
	if path:sub(1, 1) ~= '/' then
		error("Invalid prefix: must start with '/'")
	end
	
	if path:sub(-1) == '/' then
		path = path:sub(1, #path - 1 )
	end

	self._prefix = compress_path( path )

end


---
-- Sets a GET handler in the application routing table.
--
function _methods.get( self, path )

	return set_route( self, "GET", path )

end


---
-- Sets a POST handler in the application routing table.
--
function _methods.post( self, path )

	return set_route( self, "POST", path )

end


--
-- XXX: Add PUT and DELETE support. More a function of 
-- having the unit tests that ensure nothing collides.
--

---
-- Add a subapplication to this Perihelion application. Any path
-- below the path provided will be routed to the application below.
--
function _methods.wsapi( self, path, app )

	path = compress_path(path)
	
	self.routes[ path ] = { }
		
	local f = function( request_env ) 
	
		-- reappend the GET variables, so the underlying WSAPI
		-- application can make use of them.
		local uri = request_env._UNMATCHED
		if request_env.GET then
			uri = uri .. "?" .. request_env.GET
		end
		
		request_env.PATH_INFO = uri
		sanitize_request(request_env)
		
		return app.run( request_env )
	end
		
	local methods = {
			GET = true,
			POST = true,
			PUT = true,
			DELETE = true,
			
			soak = true
		}	
		
	for k, v in pairs(methods) do
		self.routes[path][k] = f
	end
	
end


---
-- Return a basic iterator; used in almost every application.
--
local function request_end( return_code, headers, output )

	if not _codes[ return_code ] then
		error("Requested return code not implemented")
	end
	
	return	tonumber(return_code) .. " " .. _codes[return_code],
			headers,
			coroutine.wrap(function()
			
				if type(output) == 'string' then
					coroutine.yield(output)
					return
				end
			
				if type(output) == 'table' then
					for i, v in pairs(output) do
						coroutine.yield(tostring(v))
					end
				end
				
				error("What do I do with this?!")
				
			end)

end


---
-- Methods called from inside Perihelion app requests
--
local _int_methods = {}


---
-- Web call completed successfully
--
function _int_methods.ok( self, output )

	return request_end( 200, self.headers, output or "" )

end


---
-- Web call failed; explicitly render a 500 page
--
function _int_methods.err( self, output )

	return request_end( 500, self.headers, output or "" )

end


---
-- Web call failed - we have no URL here
--
function _int_methods.notfound( self, output )

	return request_end( 
		404, self.headers, 
		output or "<html><body>Not Found</body></html>" 
	)

end


---
-- Web call failed - you aren't allowed
--
function _int_methods.nope( self, output )

	return request_end( 
		403, self.headers, 
		output or "<html><body>Not Authorized</body></html>" 
	)

end


---
-- Redirect elsewhere
--
function _int_methods.redirect( self, url )

	if (not url) or (type(url) ~= 'string') then
		error("Redirect without destination")
	end
	
	self.headers['Location'] = url
	
	return request_end( 
		302, self.headers, 
		output or "<html><body><a href=" .. url .. "</a></body></html>" 
	)

end


---
-- Redirect elsewhere... forever
--
function _int_methods.redirect_permanent( self, url )

	if (not url) or (type(url) ~= 'string') then
		error("Redirect without destination")
	end
	
	self.headers['Location'] = url
	
	return request_end( 
		301, self.headers, 
		output or "<html><body><a href=" .. url .. "</a></body></html>" 
	)

end



---
-- Sanity tests that a route is viable, called inside handle_request.
--
local function route_viable( route, uri_remain, method )

	-- Route must exist.
	if not route then 
		return false 
	end

	-- Route must support the method.
	if not route[ method ] then 
		return false 
	end
	
	-- The rest depends on the remaining URI. No URL?
	-- then it always can handle it.
	if type(uri_remain) ~= 'string' then
		return true
	end
	
	-- Route must be able to soak the remaining path, if the 
	-- remaining path isn't merely get variables.
	if #uri_remain > 0 then
		return route.soak
	end
	
	return true

end


---
-- Executes a WSAPI request. Called by the web/app server or whatever
-- else is the container for this application.
--
local function handle_request( self, request_env )

	local uri, vars = parse_uri( request_env.PATH_INFO )
	local path = ''
	local ret, headers, iter
	
	
	--
	-- shallow copy the environment, we need to mangle some paths
	--	
	-- XXX: Xavante does some wierd insanity with metamethods. Gotta
	-- explicitly initialize most vars before pairs() will see them.
	--
	-- Maybe Perihelion should detect if this is necessary and optimize
	-- it out otherwise.
	--
	local cgi_vars = {     
			'SERVER_SOFTWARE',
    		'SERVER_NAME',
			'GATEWAY_INTERFACE',
			'SERVER_PROTOCOL',
			'SERVER_PORT',
			'REQUEST_METHOD',
			'DOCUMENT_ROOT',
			'PATH_INFO',
			'PATH_TRANSLATED',
			'SCRIPT_NAME',
			'QUERY_STRING',
			'REMOTE_ADDR',
			'REMOTE_USER',
			'CONTENT_TYPE',
			'CONTENT_LENGTH',
			'APP_PATH',
			'input',
			'error'
		}
		
	local env = {}
	for i, variable in ipairs(cgi_vars) do 
		env[variable] = request_env[variable]
	end
			
	--
	-- Now build the rest of the request object, including default
	-- headers.
	--
	env.headers = { ['Content-type'] = 'text/html' }
	setmetatable(env, { __index = _int_methods })
	
	
	--
	-- How does SCRIPT_NAME look? Make sure it's set, uWSGI
	-- isn't a fan of it.
	--
	env.SCRIPT_NAME = request_env.SCRIPT_NAME or ''
	
	
	--
	-- How does PATH_INFO look? Needs to start with a '/'.
	--
	if env.PATH_INFO:sub(1, 1) ~= '/' then
		env.PATH_INFO = '/' .. env.PATH_INFO
	end
	
	
	--
	-- Remove any specified prefix.
	--
	if self._prefix ~= '/' then

		local prefix_test = string.sub( uri, 1, #(self._prefix) )

		if prefix_test == self._prefix then
			uri = string.sub( uri, #(self._prefix) + 1 )
		end
		
	end
	
	
	--
	-- Let's go find a path.
	--
	success, err = pcall( function()
			
		----
		---- Attempt one: see if anything hits with string.match().
		----
		---- This is a rather unintelligent algorithm, and likely
		---- a performance bottleneck especially in large apps.
		---- We'll deal with that later.
		----
		for path, route in pairs(self.routes) do
			local xm = { string.match(uri, "^" .. path .. "$") }
			
			
			if #xm > 0 then			
				--
				-- Getting captures implies we have a pattern hit.
				-- However, we now need to ensure we aren't matching
				-- too much. Cut the matched part off of the URI and
				-- see if there's anything left.
				--
				local xpath = path
				local xuri = uri
				
				--
				-- This integer controls how deep Perihelion will look
				-- into a URL. 25 seems reasonable to me...
				--
				local i = 25 
				repeat 
					local ustart, uend = string.find(xuri, xpath)
					local pstart, pend = string.find(xpath, "%b()")
					
					uend = uend or 1
					pend = pend or 1

					xpath = xpath:sub(pend + 1) or ""
					xuri = xuri:sub(uend + 1) or ""

					--
					-- Prevent infinite loops.
					--
					i = i - 1
					if i <= 0 then 
						error("Excessive route complexity") 
					end
					
				until (#xuri == 0) or (xuri == "/")
				
				if #xuri == 0 then
					xuri = "/"
				end
				
				env._UNMATCHED = xuri
				
			
				
				--
				-- If there is an unmatched subpath at this point,
				-- the hander must be able to use it. Otherwise,
				-- continue looking.
				-- 
				if xuri  == '/' or route.soak then
					env.SCRIPT_NAME = env.SCRIPT_NAME .. path
					env._GET_VARIABLES = vars
					env._URI = uri
					
					local handler = route[ env.REQUEST_METHOD ]
					
					if handler then	
						ret, headers, iter = handler(env, table.unpack(xm))
						return
					end
				else
					print("Pattern failed for", path)
					
				end
			end
		end
			
			
		--
		-- Attempt two: split the path apart, and go looking for 
		-- anything that will take it in pieces.
		--
		-- This is the original way Perihelion worked. Pattern
		-- base request routing was too powerful of a feature for the
		-- first go around and, thus this was implemented as the first 
		-- shot.
		--
		-- You'd think you could kill this code; however I expect it
		-- would outperform the pattern matcher above.
		--
		-- There has to be a way to merge the two into a fairly complex,
		-- but efficient, algorithm. I just haven't found that yet and
		-- Perihelion is performing nicely so far.
		--
		uri = compress_path(uri)
	
		for path_part, remain in split_string( uri, '/' ) do
		
			if path ~= '/' then
				path = path .. '/' .. (path_part or '')
			else
				path = path .. (path_part or '')
			end
				
			local route = self.routes[path]
				
			--
			-- Tests to ensure the handler is viable.
			--
			if route_viable( route, remain, env.REQUEST_METHOD ) then 
				env._UNMATCHED = remain or '/'
				env._GET_VARIABLES = vars
				env._URI = uri
				env.SCRIPT_NAME = env.SCRIPT_NAME .. path
				ret, headers, iter = route[ env.REQUEST_METHOD ](env)
				return 
			end
			
		end 
		
		--
		-- Nothing. Fire the 404.
		--
		ret, headers, iter = wsapi_404( request_env )
		return true, nil
	end)
		
	if success then 
		return ret, headers, iter
	end
	
	return wsapi_error( request_env, err ) 

end


---
-- The returned namespace just contains the 'new' function
-- for API calls and some versioning info.
--
local _M = {}


---
-- Version number of this copy of Perihelion.
--
_M._VERSION = "0.5"


---
-- Release date of this copy of Perihelion.
--
_M._RELEASE = "2017.0909"


---
-- Creates a new Perihelion application.
--
function _M.new( )

	local ret = {
		routes = {},
		_prefix = "/"
	}
	
	for k, v in pairs( _methods ) do
		ret[k] = v
	end
		
	--
	-- This is an ugly hack: WSAPI applications are called as
	-- functions in namespaces, not as objects. Thus we don't get
	-- a unique state per instantiated application.
	--
	-- We work around this with a closure. It should tail-call 
	-- optimize away.
	--
	ret.run = function( ... ) return handle_request( ret, ... ) end
	
	return ret
	
end

return _M
