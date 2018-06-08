#!/usr/bin/env lua5.3

--
-- This is part of the release script.
--
-- See release.sh for more explanation.
--


perihelion = dofile("./perihelion.lua")
print(perihelion._VERSION .. " " .. perihelion._RELEASE)
