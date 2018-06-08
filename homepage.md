Perihelion
==========

Perihelion is a Lua web development framework. It runs as a WSAPI
app, and provides a way to route requests to streams of Lua functions
via patterns.

Functions merely return tables of variables for the next part of the
request, or the output to send to the client.

Perihelion is small (0.3 is less than 1,000 lines including whitespace
and comments) and has zero dependancies. An extensive test suite using
[Busted](http://olivinelabs.com/busted/) is provided.


Basic Usage
-----------

First, create a Perihelion object. This will become the app that your
webserver calls:

	local perihelion = require "perihelion"
	local app = perihelion.new()
	
	
Then, create streams that a request will call. The following returns
'Hello World' as a text document:

	local function index( web )
	
		web.headers = { 'Content-type', 'text/plain' }
		return web:ok( "Hello, World!" )
	
	end

	app:get "/index" { index() }
	return app
	
GET and POST requests are supported. PUT and DELETE may be added in a 
future version. The function needs to return with a - in this case, 
web:ok(). See below for the full list of stop methods. If one is not 
called, Perihelion will continue to the next function in the chain. 
This lets you reuse code, ie, your template rendering function:

	local funtion render( web )
	
		local tmpl = find_template()
		tmpl.vars = web.vars
		web:ok( tmpl.render() )
	
	end
	
	app:get "/one" { call_one, render }
	app:get "/two" { call_two, render }
	app:get "/three" { call_three, render }
	
	
Chains can call a stop method at anytime, in which case anything
remaining is skipped. For example, code to check if a user logged in
might look like:

	local function check_authorized( web )
	
		if not web.request['REMOTE_USER'] then
			web:redirect( "/login" )
		end
	
	end

	app:get "/login" { login, render }
	app:get "/private/one" { check_authorized, call_one, render }
	app:get "/private/two" { check_authorized, call_two, render }



You can also use patterns to route output:

	app:get "/.*" { catchall }
	
	
Patterns can also include captures, which will be passed as arguments
to functions in the stream:

	local function get_object( web, object_name )
	
		vars.object = get_from_database( object_name )
		if not vars.object then
			web:notfound()
		end
	
	end
	
	local function render_as_json( web )
	
		return web:ok( json.encode( vars.object ) )
	
	end

	app:get "/objects/(.*)" { get_object, render_as_json }


You can also bring in an entirely different WSAPI app:

	local app = perihelion.new()
	local subapp = other_app.new()
	
	app:wsapi( "/subapp", subapp )



For a more in-depth example, this page you are viewing is generated 
with [this Perihelion app](/code/perihelion/examples/markdowner.lua), 
which generates the site on the fly from 
[Markdown](https://daringfireball.net/projects/markdown/) files.


Provided Environment Variables
------------------------------

The 'web' object in all the above examples allow for access to
all request/response variables. It comes preloaded with WSAPI's
CGI-based server variables, as well as the following:

  * web.headers: A table of headers to be sent to the client. Comes 
  	preloaded with Content-type: text/html.
  * web.GET: A table of variables parsed from the query string, similar 
  	to PHP's $_GET.
  * web.POST: Variables parsed from the body of a POST request, similar 
  	to PHP's $_POST.
  * web.vars: The return value of the previous function in the chain. 
  	If the first function called in a chain, it is set top an empty table.


Stop Methods
------------

Perihelion continues calling every function in a stream until it
reaches one that returns one of the following:

  * web:ok( output ) - Return a 200 OK status
  * web:err( output ) - Return an 500 server error
  * web:nope( output ) - Return a 403 Forbidden error
  * web:notfound( output ) - Return 404 Not Found
  
All of the above take a string argument, which will be returned to the 
client as the response body. A table may also be provided, in which 
case it's values will be concatenated as sent as the response.

The following are also permissible, which take a URL as their sole
argument:
  
  * web:redirect( url ) - Redirects client, using a 302 Found response
  * web:redirect_permanent( url ) - Redirects client using 301

As of version 0.3, reaching the end of a function stream without calling
a stop method will result in undefined behaviour.


Requirements
------------

None! No, really, it has no dependancies!

Though of course, you will need a WSAPI capable web server or 
application server to run it properly. Perihelion has been well tested 
on [uWSGI](https://uwsgi-docs.readthedocs.io/en/latest/) and 
[Xavante](https://keplerproject.github.io/xavante/). Openresty should 
work with an [adapter](https://github.com/ignacio/wsapi-openresty) but 
I personally have not tried this.
  

Installation
------------

The simplest method is via LuaRocks.

However, Perihelion is pure Lua, and can be installed by simply
copying 'perihelion.lua' from the distribution tarball into 
package.path.

You can download the distribution tarball 
[here.](https://zadzmo.org/code/perihelion/downloads/)


Planned Features 
----------------

In no particular order, all the below are planned or under 
consideration:

  * Session support - handle cookies, etc automatically if requested
  * DELETE and PUT verbs
  * Custom error pages
  
  
Features that will NOT be added
-------------------------------

I do not ever intend to add the following - because there are other
projects that do the job just fine:

 * A template engine
 * MVC models or views
 * Anything involving databases
  
  
License
-------

This code is provided without warrenty under the terms of the
[MIT/X11 License](http://opensource.org/licenses/MIT).
    
    
Contact Maintainer
------------------

You can reach me by email at [aaron] [at] [zadzmo.org]. 
