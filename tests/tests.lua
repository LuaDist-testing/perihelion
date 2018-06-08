#!/usr/bin/env lua5.3

require "luarocks.loader"
pcall(require, "luacov")    --measure code coverage, if luacov is present

package.path = "../?.lua;" .. package.path

require 'busted.runner'()
local perihelion = assert(require "perihelion")
local wsapi = assert(require "tests.mock_wsapi")

-- output of most Perihelion functions are a big string, so let's 
-- make those strings machine readable
local json = require "dkjson"


--
-- Finish a Perihelion request. This simulates a templating engine by
-- JSON encoding the variables field.
--
local function finish( web )

	assert.is_table(web.vars)

	return	"200 OK", 
		{ ['Content-type'] = 'text/json' }, 
		
		-- well this proved a bit too complicated.
		coroutine.wrap( function() 
			coroutine.yield(json.encode(web.vars)) 
		end )
		
end


--
-- Create an env object for a request.
--
local function request( req_type, uri, query, name, post_data )

	local ret = {}
	
	ret.REQUEST_METHOD = req_type
	ret.query_string = query or ""
	ret.PATH_INFO = uri or "/"
	ret.SCRIPT_NAME = name or "/test.lua"
	ret.CONTENT_TYPE = ""
	ret.CONTENT_LENGTH = ""
	ret.input = nil

	if req_type == 'POST' then
		assert(post_data, "Must provide data file for post!")
		ret.input = assert(io.open("./post-data/" .. post_data))
		ret.CONTENT_LENGTH = #(ret.input:read("*all"))
		ret.input:seek("set", 0)
	end

	return ret

end



--
-- Check that the rest of a WSAPI response is valid.
--
local function assert_response( code, headers, iter )

	local body = ''

	--
	-- spin the iterator to be sure it doesn't err out.
	--
	local x = iter()
	while x do
		body = body .. x
		x = iter()
	end

	--print(body)
	assert.is_string(body)
	assert.is_not_equal('', body)

	-- for things that need it
	return body

end


--
-- Assert a successful response.
--
local function assert_200( code, headers, iter )

	assert.is_equal("200 OK", code)
	assert.is_string(headers['Content-type'])
	assert_response( code, headers, iter )

end


--
-- Assert a 404 response.
--
local function assert_404( code, headers, iter )

	assert.is_equal("404 Not Found", code)
	assert.is_equal("text/html", headers['Content-type'])
	assert_response( code, headers, iter )
	
end


--
-- Assert a 500 response.
--
local function assert_500( code, headers, iter )

	assert.is_equal("500 Internal Server Error", code)
	assert.is_equal("text/html", headers['Content-type'])
	assert_response( code, headers, iter )
	
end


--
-- Test we can open an object.
--
function test_open()

	local ph = perihelion.new()
	assert.is_table(ph)
	assert.is_function(ph.run)

end


--
-- Test we can call a routed WSAPI subapp.
--
function test_wsapi()

	local ph = perihelion.new()
	local wsapi = wsapi.new()
	
	ph:wsapi( "/test_wsapi", wsapi )
	
	local x, y, z = ph.run( request( "GET", "/test_wsapi/here", ""))
	assert_200(x, y, z)

end


--
-- Test we can call a routed WSAPI subapp, longer path
--
function test_wsapi2()

	local ph = perihelion.new()
	local wsapi = wsapi.new()
	
	ph:wsapi( "/test/wsapi/", wsapi )
	
	local x, y, z = ph.run( request( "GET", "/test/wsapi/below/here", ""))
	assert_200(x, y, z)

end


--
-- Test that multiple slashes are irrelevant in the request.
--
function test_multislash_ignored()

	local ph = perihelion.new()
	local wsapi = wsapi.new()
	
	ph:wsapi( "/test/wsapi/", wsapi )
	
	local x, y, z = ph.run( request( "GET", "/test/wsapi//below/here", ""))
	assert_200(x, y, z)
	
end


--
-- Test that multiple slashes are ignored when placed in the 
-- routing table by the wsapi method.
--
function test_multislash_wsapi()

	local ph = perihelion.new()
	local wsapi = wsapi.new()
	
	ph:wsapi( "/test//wsapi/", wsapi )
	
	local x, y, z = ph.run( request( "GET", "/test/wsapi/below/here", ""))
	assert_200(x, y, z)
	
	-- out of paranoia, how about three in a row?
	
	ph = perihelion.new()
	ph:wsapi( "/test///wsapi/", wsapi )
	
	x, y, z = ph.run( request( "GET", "/test/wsapi/below/here", ""))
	assert_200(x, y, z)
	
end


--
-- Test that only a single '/' is still routable
--
function test_single_slash()

	local ph = perihelion.new()
	local wsapi = wsapi.new()
	
	ph:wsapi( "/", wsapi )
	
	local x, y, z = ph.run( request( "GET", "/", ""))
	assert_200(x, y, z)
	
end


--
-- Test that we modify SCRIPT_NAME when calling a subapp.
--
function test_wsapi_script_name()

	local ph = perihelion.new()
	local wsapi = wsapi.new()
	
	ph:wsapi( "/test/wsapi/", wsapi )
	
	local x, y, z = ph.run( request( "GET", "/test/wsapi/below/here", ""))
	local response_output = assert_response(x, y, z)
	
	local path_match = response_output:match("PATH_INFO: ([.%w%s%/]+)")
	local name_match = response_output:match("SCRIPT_NAME: ([.%w%s%/]+)")
	
	test.assert_equal('/below/here', path_match)
	test.assert_equal('/test.lua/test/wsapi', name_match)
	
end


--
-- Test that an empty script name still generates sane results.
--
function test_wsapi_empty_script_name()

	local ph = perihelion.new()
	local wsapi = wsapi.new()
	
	ph:wsapi( "/test/wsapi/", wsapi )
	
	local request = request( "GET", "/test/wsapi/below/here", "")
	request.SCRIPT_NAME = nil
	
	local x, y, z = ph.run(request)
	local response_output = assert_response(x, y, z)
	
	local path_match = response_output:match("PATH_INFO: ([.%w%s%/]+)")
	local name_match = response_output:match("SCRIPT_NAME: ([.%w%s%/]+)")
	
	assert.is_equal('/below/here', path_match)
	assert.is_equal('/test/wsapi', name_match)
	
end


--
-- Test that an unset URL hits a 404.
--
function test_404()

	local ph = perihelion.new()
	
	local x, y, z = ph.run( request( "GET", "/not-possibly-a-url", ""))
	assert_404(x, y, z)

end


--
-- Test that a get request is properly handled
--
function test_get_success()

	local ph = perihelion.new()
	
	ph:get "/test/url" { 
		function( web ) 
			assert.is_table(web.GET)
			return	"200 OK", 
				{ ['Content-type'] = 'text/html' }, 
				coroutine.wrap(function() coroutine.yield("Hello world!") end)
		end
	}
	
	local x, y, z = ph.run( request( "GET", "/test/url", "") )
	assert_200(x, y, z)

end


--
-- Prove that an assertation failure or error() causes Perihelion to
-- return a 500 error code.
--
function test_get_error()

	local ph = perihelion.new()
	
	ph:get "/test/url" { 
		function( web ) 
			error("death")
		end
	}
	
	local x, y, z = ph.run( request( "GET", "/test/url", "") )
	assert_500(x, y, z)
	
end



--
-- Prove that a get request fails gracefully when not properly
-- programmed to provide a response.
--
function test_get_noresponse()

	local ph = perihelion.new()

	ph:get "/test/url" { 
		function( web ) 
			return { more = 'vars in it!' }
		end
	}
	
	local x, y, z = ph.run( request( "GET", "/test/url", "") )
	assert_500(x, y, z)
	
end


--
-- Prove a GET request works even when very simple.
--
function test_get_basic()

	local ph = perihelion.new()
	
	ph:get "/get" { function( web )
		return { one = true }
	end, finish }


	local expect = json.encode( { item = true } )
	local x, y, z = ph.run( request( "GET", "/get", "") )
	assert_200(x, y, z)

end

--
-- Prove a GET string returns arguments.
--
function test_get_argument()

	local ph = perihelion.new()
	
	ph:get "/get" { function( web )
		local ret = {}

		assert.is_table(web.GET)
		assert.is_equal("true", web.GET.item)

		return ret
	end, finish }


	local expect = json.encode( { item = true } )
	local x, y, z = ph.run( request( "GET", "/get?item=true", "") )
	assert_200(x, y, z)

end


--
-- Test that GET doesn't get soaked into a subapplication path
-- trap.
--
function test_get_subapp_fails()

	local ph = perihelion.new()
	
	ph:get "/get" { function( web )
		print("AIEEEEEE!")
		error("Shouldn't get here.")
	end, finish }


	local expect = json.encode( { item = true } )
	local x, y, z = ph.run( request( "GET", "/get/item", "") )
	assert_404(x, y, z)

end



--
-- Prove a GET string returns multiple arguments.
--
function test_get_arguments()

	local ph = perihelion.new()
	
	ph:get "/get" { function( web )
		local ret = {}

		assert.is_table(web.GET)
		assert.is_equal("true", web.GET.item)
		assert.is_equal("false", web.GET.bar)

		return ret
	end, finish }

	local x, y, z = ph.run( request( "GET", "/get?item=true&bar=false", "") )
	assert_200(x, y, z)

end

--
-- Prove that a GET handler won't get called when POST is requested.
--
function test_post_doesnt_get()

	local ph = perihelion.new()
	ph:get "/get" { function( web )
		print("AIEEEEEE!")
		error("Shouldn't get here.")
	end }

	local x, y, z = ph.run( request( "POST", "/get", nil, "", "single-var") )
	assert_404(x, y, z)	

end


--
-- Prove that a POST handler won't get called with a GET is requested.
--
function test_get_doesnt_post()

	local ph = perihelion.new()
	ph:post "/post" { function( web )
		print("AIEEEEEE!")
		error("Shouldn't get here.")
	end }

	local x, y, z = ph.run( request( "GET", "/post") )
	assert_404(x, y, z)	

end


--
-- Prove that a POST and a GET handler can exist in the same place,
-- and that the appropriate one is called for the appropriate type
-- of request.
--
function test_get_and_post()

	local ph = perihelion.new()
	
	ph:get "/location" { function( web )
		assert.is_equal(web.REQUEST_METHOD, "GET")
		return {}
	end, finish }
	
	ph:post "/location" { function( web )
		assert.is_equal(web.REQUEST_METHOD, "POST")
		return {}
	end, finish }
	
	local x, y, z = ph.run( request( "GET", "/location") )
	assert_200(x, y, z)
	
	x, y, z = ph.run( request( "POST", "/location", nil, "", "single-var") )
	assert_200(x, y, z)

end


--
-- Prove that a POST handler works even if very basic.
--
function test_post_basic()

	local ph = perihelion.new()

	ph:post "/location" { function( web )
		assert.is_equal(web.REQUEST_METHOD, "POST")
		return {}
	end, finish }
	
	x, y, z = ph.run( request( "POST", "/location", nil, "", "single-var") )
	assert_200(x, y, z)

end


--
-- Test that a post request is properly handled
--
function test_post_urlencoded()

	local ph = perihelion.new()
	
	ph:post "/location" { 
		function( web ) 
		
			assert.is_table(web.POST)
			assert.is_equal('true', web.POST.var1)
			return web.POST
			
	end, finish }
	
	local req = request( "POST", "/location", nil, "", "single-var")
	req.CONTENT_TYPE = 'application/x-www-form-urlencoded'
	
	local x, y, z = ph.run( req )
	assert_200(x, y, z)

end


--
-- Test that a post request is properly handled with multiple vars
--
function test_post_urlencoded_multi()

	local ph = perihelion.new()
	
	ph:post "/location" { 
		function( web ) 
			
			assert.is_table(web.POST)
			assert.is_equal('true', web.POST.item1)
			assert.is_equal('3432', web.POST.secondthing)
			return web.POST
			
	end, finish }
	
	local req = request( "POST", "/location", nil, "", "double-var")
	req.CONTENT_TYPE = 'application/x-www-form-urlencoded'
	
	local x, y, z = ph.run( req )
	assert_200(x, y, z)

end


--
-- Test that a post request is properly handled when type multipart
--
function test_post_multipart()

	local ph = perihelion.new()
	
	ph:post "/location" { 
		function( web ) 
			
			assert.is_table(web.POST)
			assert.is_equal('This is value #1', web.POST.variable1)
			return web.POST
			
	end, finish }
	
	local req = request( "POST", "/location", nil, "", "multipart-single")
	req.CONTENT_TYPE = 'multipart/form-data'
	
	local x, y, z = ph.run( req )
	assert_200(x, y, z)

end


--
-- Test that a post request is properly handled when type multipart,
-- with multiple vars
--
function test_post_multipart_many()

	local ph = perihelion.new()
	
	ph:post "/location" { 
		function( web ) 
			
			assert.is_table(web.POST)
			assert.is_equal('This is value #1', web.POST.variable1)
			assert.is_equal('This is value #2', web.POST.variable2)
			assert.is_equal('nginx', web.POST.username)
			assert.is_equal('bar', web.POST.foo)
			return web.POST
			
	end, finish }
	
	local req = request( "POST", "/location", nil, "", "multipart-multi")
	req.CONTENT_TYPE = 'multipart/form-data'
	
	local x, y, z = ph.run( req )
	assert_200(x, y, z)

end


--
-- Prove we can route calls via patterns
--
function test_pattern_single()

	local ph = perihelion.new()
	local inputs = { 'one', 'two', 'fifteenis15', 'abc1234ghj567' }
	local val

	ph:get "/test/(%w+)" { function( web, input )
		assert.is_equal(val, input)
		return {}
	end, finish }

	for i, input in ipairs(inputs) do
		val = input
		assert_200(ph.run( request( "GET", "/test/" .. input ) ))
	end

end


--
-- Prove pattern routes still handle GET strings just fine.
--
function test_pattern_querystring()

	local ph = perihelion.new()

	ph:get "/test/(%w+)" { function( web, input )
		assert.is_equal("thingy", input)
		assert.is_equal(web.GET.value, "1")
		return {}
	end, finish }

	assert_200(ph.run( request( "GET", "/test/thingy?value=1") ))

end


--
-- Prove that routing via patterns matches well, and not everything.
--
function test_pattern_failures()

	local ph = perihelion.new()
	local val
	local fail = false

	ph:get "/test/(%w%w%w%-%d%d%d)" { function( web, input )
		if fail then
			print("AIEEEE!")
			error("Shouldn't get here")
		else
			assert.is_equal(val, input)
		end
		
		return {}
	end, finish }

	local inputs = { 'one-111', 'two-222', 'thr-333' }
	for i, input in ipairs(inputs) do
		val = input
		local x, y, z = ph.run( request( "GET", "/test/" .. input ) )
		assert_200(x, y, z)
	end

	local failinputs = { 'one', '3irm3km', 'NOPE@#$%!!' }
	fail = true
	for i, input in ipairs(failinputs) do
		local x, y, z = ph.run( request( "GET", "/test/" .. input ) )
		assert_404(x, y, z)
	end
	
end


--
-- Prove we can route calls via patterns, with multiple captures
--
function test_pattern_multi()

	local ph = perihelion.new()
	local val

	ph:get "/test/(%w%d%d)-(%w+)" { function( web, input1, input2 )
		assert.is_equal(val, input1 .. '-' .. input2)
		return {}
	end, finish }

	local inputs_1 = { 'o11', 't26', 'r32' }
	
	-- Let's make this fair (following command works on Debian)
	-- shuf -n 4 /usr/share/dict/words.pre-dictionaries-common
	local inputs_2 = { 'whole', 'resonator', 'brutality', 'Wolsey' }
	
	for i1, input1 in ipairs(inputs_1) do
		for i2, input2 in ipairs(inputs_2) do
			val = input1 .. '-' .. input2
			local url = "/test/" .. val
			assert_200(ph.run( request( "GET", url) ))
		end
	end
	
end


--
-- Prove a small url doesn't match part of a bigger one.
--
function test_url_submatch()

	local ph = perihelion.new()

	ph:get "/test/one/two" { function( web, input )
		print("AIEEEEEE!")
		error("Shouldn't get here.")
	end, finish }

	assert_404(ph.run( request( "GET", "/one/two") ))

end


--
-- Prove a url doesn't match part of a bigger one, when patterns
-- are involved.
--
function test_pattern_submatch()

	local ph = perihelion.new()

	ph:get "/test/(%w+)/two" { function( web, input )
		print("AIEEEEEE!")
		error("Shouldn't get here.")
	end, finish }

	assert_404(ph.run( request( "GET", "/one/two") ))

end


--
-- Prove a pattern can match almost all the URL.
--
function test_almostall_pattern()

	local ph = perihelion.new()
	local inputs = { "", "one", "3i4n3jk4n3", "three" }
	local val = nil

	ph:get "/(%w*)" { function( web, rinput )
		if not (val == "") then
			assert.is_equal(val, rinput)
		end
		
		return {}
	end, finish }

	for i, input in ipairs(inputs) do
		val = input
		assert_200(ph.run( request( "GET", "/" .. input )))
	end
	
end


--
-- Prove that a URL doesn't get eaten by a bigger one when
-- patterns and mixed methods involved.
--
function test_pattern_doesnt_swamp()

	local ph = perihelion.new()

	ph:get "/(%w+)" { function( web, input )
		error("Shouldn't get here.")
	end, finish }
	
	ph:post "/foobar" { function( web, input )
		return { one = true }
	end, finish }
	
	--
	-- The GET handler should always throw error.
	--
	assert_500(ph.run( request( "GET", "/fark") ))	
	
	--
	-- The POST handler should succeed.
	--
	local req = request( "POST", "/foobar", nil, "", "double-var")
	req.CONTENT_TYPE = 'x-www-form-urlencoded'
	local x, y, z = ph.run( req )
	assert_200(x, y, z)

end


--
-- Prove that web:result_ok() works
--
function test_return_200()

	local ph = perihelion.new()
	ph:get "/" { function( web ) return web:ok( "done" ) end }
	assert_200( ph.run( request( "GET", "/" ) ))

end


--
-- Prove that web:result_err() works
--
function test_return_500()

	local ph = perihelion.new()
	ph:get "/" { function( web ) return web:err( "not done" ) end }
	assert_500( ph.run( request( "GET", "/" ) ))

end


--
-- Prove that web:result_nope() works
--
function test_return_403()

	local ph = perihelion.new()
	ph:get "/" { function( web ) return web:nope() end }
	local code, headers, iter = ph.run( request( "GET", "/" ) )
	
	assert.is_equal("403 Forbidden", code)
	assert.is_string(headers['Content-type'])
	assert_response( code, headers, iter )

end


--
-- Prove that web:notfound() works
--
function test_return_404()

	local ph = perihelion.new()
	ph:get "/" { function( web ) return web:notfound() end }
	assert_404(ph.run( request( "GET", "/" ) ))
	
end


--
-- Prove that web:redirect() works
--
function test_return_302()

	local ph = perihelion.new()
	ph:get "/" { function( web ) return web:redirect("/somewhere") end }
	local code, headers, iter = ph.run( request( "GET", "/" ) )
	
	assert.is_equal("302 Found", code)
	assert.is_string(headers['Location'])
	assert.is_equal("/somewhere", headers['Location'])
	assert_response( code, headers, iter )

end


--
-- Prove that web:redirect() requires an argument
--
function test_return_302_failure1()

	local ph = perihelion.new()
	ph:get "/" { function( web ) return web:redirect() end }
	assert_500(ph.run( request( "GET", "/" ) ))
	
end

--
-- Prove that web:redirect() requires a string argument
--
function test_return_302_failure2()

	local ph = perihelion.new()
	ph:get "/" { function( web ) return web:redirect( {} ) end }
	assert_500(ph.run( request( "GET", "/" ) ))
	
end


--
-- Prove that web:redirect_perm() works
--
function test_return_301()

	local ph = perihelion.new()
	ph:get "/" { function( web ) return web:redirect_permanent("/somewhere") end }
	local code, headers, iter = ph.run( request( "GET", "/" ) )

	assert.is_equal("301 Moved Permanently", code)
	assert.is_string(headers['Location'])
	assert.is_equal("/somewhere", headers['Location'])
	assert_response( code, headers, iter )

end


--
-- Prove that web:redirect_perm() requires an argument
--
function test_return_301_failure1()

	local ph = perihelion.new()
	ph:get "/" { function( web ) return web:redirect_permanent() end }
	assert_500(ph.run( request( "GET", "/" ) ))
	
end

--
-- Prove that web:redirect() requires a string argument
--
function test_return_301_failure2()

	local ph = perihelion.new()
	ph:get "/" { function( web ) return web:redirect_permanent( {} ) end }
	assert_500(ph.run( request( "GET", "/" ) ))
	
end


--
-- Prove that return values are folded into web.vars.
--
function test_return_values_saved()

	local ph = perihelion.new()
	ph:get "/" {
		function( web ) 
			return { one = 1 } 
		end,
		
		function( web ) 
			assert.is_equal(1, web.vars.one) 
			return { two = 2 }
		end,
		
		function( web)
			assert.is_equal(1, web.vars.one) 
			assert.is_equal(2, web.vars.two)
			return web:ok("done")
		end
	}

	assert_200(ph.run( request( "GET", "/") ))

end


--
-- Test that a 500 error is thrown if a proper ending function
-- isn't called.
--
function test_end_correctness()

	local ph = perihelion.new()
	ph:get "/" {
		function( web ) 
			return { one = 1 } 
		end
	}
	
	assert_500(ph.run( request( "GET", "/") ))
	
end


--
-- Test prefix stripping.
--
function test_prefix_strip()

	local ph = perihelion.new()
	ph:get "/" {
		function( web ) 
			return web:ok("Done!")	
		end 
	}

	ph:prefix("/testprefix")
	assert_200(ph.run( request( "GET", "/testprefix/" ) ))

end


--
-- Test prefix that a prefix is properly truncated, if need be
--
function test_prefix_strip_withslash()

	local ph = perihelion.new()
	ph:get "/" {
		function( web ) 
			return web:ok("Done!")	
		end 
	}

	ph:prefix("/testprefix/")
	assert_200(ph.run( request( "GET", "/testprefix/" ) ))

end


--
-- Prove prefixes are enforced to be sane.
--
function test_prefix_sanity()

	local ph = perihelion.new()
	assert.is_error(function()
		ph:prefix("emfkemkef")
	end)
	
end


--
-- Run the tests
--
describe("Perihelion", function()

	it( "can open an object", test_open )
	it( "can call a routed WSAPI subapp", test_wsapi )
	it( "can call a routed WSAPI subapp, longer path", test_wsapi2 )
	it( "multiple slashes are irrelevant in the request", test_multislash_ignored )
	it( "multiple slashes are ignored when placed in the routing table by the wsapi method", test_multislash_wsapi)
	it( "still works with a single '/'", test_only_slash )
	it( "modify SCRIPT_NAME when calling a subapp", test_wsapi_empty_script_name )
	it( "empty script name still generates sane results", test_wsapi_empty_script_name )
	it( "unset URL hits a 404", test_404 )
	it( "GET request is properly handled", test_get_success )
	it( "Very simple GET request works", test_get_basic )
	it( "an assertation failure or error() returns a 500 error code", test_get_error )
	it( "GET request fails gracefully when not properly programmed to provide a response", test_get_noresponse )
	it( "GET string returns arguments", test_get_argument )
	it( "GET doesn't get soaked into a subapplication path trap", test_get_subapp_fails )
	it( "GET string returns multiple arguments", test_get_arguments )
	it( "Very simple POST request works", test_post_basic )
	it( "GET handler won't get called when POST is requested", test_post_doesnt_get )
	it( "POST handler won't get called when a GET is requested", test_get_doesnt_post )
	it( "a POST and a GET handler can exist in the same place", test_get_and_post )
	it( "urlencoded POST is properly handled", test_post_urlencoded )
	it( "urlencoded POST with multiple arguments is properly handled", test_post_urlencoded_multi )
	it( "multipart encoded POST is properly handled", test_post_multipart )
	it( "multipart encoded POST works, multiple vars", test_post_multipart_many )
	it( "can route calls via patterns", test_pattern_single )
	it( "pattern routes still handle GET strings just fine", test_pattern_querystring )
	it( "routing via patterns matches well, and not everything", test_pattern_failures )
	it( "can route calls via patterns, with multiple captures", test_pattern_multi )
	it( "small urls don't match part of a bigger one", test_url_submatch )
	it( "small pattern urls don't match part of a bigger one", test_pattern_submatch )
	it( "can match a URL that is almost all pattern", test_almostall_pattern )
	it( "doesn't let a small pattern eat a large URI", test_pattern_doesnt_swamp )
	it( "Has a function to send 200 ok", test_return_200 )
	it( "Has a function to send 500 error", test_return_500 )
	it( "Has a function to send 403 responses", test_return_403 )
	it( "Has a function to send a 404 response", test_return_404 )
	it( "Has a function to redirect", test_return_302 )
	it( "Has a function to redirect permanently", test_return_301 )
	it( "Requires an argument for 301 redirects", test_return_301_failure1 )
	it( "Requires an argument for 302 redirects", test_return_302_failure1 )
	it( "Requres a string for 301 redirects", test_return_301_failure2 )
	it( "Requres a string for 302 redirects", test_return_302_failure2 )
	it( "Folds return values into web.vars", test_return_values_saved )
	it( "Returns 500 if a request doesn't end right", test_end_correctness )
	it( "Can strip off a prefix if need be", test_prefix_strip )
	it( "Can strip off a prefix if need be", test_prefix_strip_withslash )
	it( "Can check prefix sanity", test_prefix_sanity )
	
end)
