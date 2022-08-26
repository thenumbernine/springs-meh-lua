#!/usr/bin/env luajit
local class = require 'ext.class'
local table = require 'ext.table'
local sdl = require 'ffi.sdl'
local ig = require 'imgui'
local vec2f = require 'vec-ffi.vec2f'

_G.count = 10
_G.dt = .1
_G.gravForceEnabled = true

-- units: m^3 / (kg s^2)
_G.gravForceConst = 1

-- dumb
_G.doubleCurlForceEnabled = false
_G.doubleCurlForceConst = 1	-- units: m^3 / (kg s^2)

-- dumb
_G.tripleCurlForceEnabled = false
_G.tripleCurlForceConst = .000001

_G.outerWallRadius = 100
_G.outerWallRestitution = .5

-- 1D cross: cross(v)^i = ε^ij v_j
local function left(v)
	return vec2f(-v.y, v.x)
end

-- 1D dot cross , i.e. volume: volume(a,b) = ε^ij a_i b_j
local function determinant(a, b)
	return a.x * b.y - a.y * b.x
end

local Object = class()

--[[
pos units = m
vel units = m/s
force units = kg m/s^2
density units = kg/m^2
scale units = m
volume units = m^2
mass units = kg
--]]
function Object:init(args)
	if args then
		if args.pos then
			self.pos = args.pos.unpack and vec2f(args.pos:unpack()) or vec2f(table.unpack(args.pos))
		end
		if args.vel then
			self.vel = args.vel.unpack and vec2f(args.vel:unpack()) or vec2f(table.unpack(args.vel))
		end
		self.angle = assert(tonumber(args.angle))
		self.scale = assert(tonumber(args.scale))
	end
	if not self.pos then self.pos = vec2f() end
	if not self.vel then self.vel = vec2f() end
	if not self.angle then self.angle = 0 end
	if not self.scale then self.scale = 1 end
	self.force = vec2f()
	self.density = 1
end

function Object:mass()
	return self:volume() * self.density
end

function Object:volume()
	-- using a [-1,1]^n square
	return 4 * self.scale * self.scale
end


local App = require 'imguiapp.withorbit'()

function App:initGL(...)
	App.super.initGL(self, ...)

	self.view.ortho = true
	self.view.orthoSize = 100
	self.running = true

	self:reset()
end

function App:reset()
	self.objs = table()
	for i=1,count do
		local th = math.random() * 2 * math.pi
		local r = 1000 * math.random()
		r = math.sqrt(r)
		self.objs:insert(Object{
			pos = vec2f(r * math.cos(th), r * math.sin(th)),
			angle = math.random() * 2 * math.pi,
			scale = math.random() + .5,
		})
	end
end

local quadvtxs = table{
	vec2f(-1,-1),
	vec2f(1,-1),
	vec2f(1,1),
	vec2f(-1,1),
}

function App:update(...)
	local gl = self.gl
	self.view:setup(self.width / self.height)

	gl.glClear(gl.GL_COLOR_BUFFER_BIT)

	if self.running then
		-- update
		for i,o in ipairs(self.objs) do
			o.force:set(0,0)
			o.gravPotEnergy = 0
		end
		-- [[ object-object-object forces
		if tripleCurlForceEnabled then
			for i=1,#self.objs-2 do
				local oi = self.objs[i]
				for j=i+1,#self.objs-1 do
					local oj = self.objs[j]
					for k=j+1,#self.objs do
						local ok = self.objs[k]
						-- determine COM.  units: m
						local com = (oi.pos * oi:mass() + oj.pos * oj:mass() + ok.pos * ok:mass()) / (oi:mass() + oj:mass() + ok:mass())
						-- determine volume of triangle
						local dij = oj.pos - oi.pos
						local djk = ok.pos - oj.pos
						local vol = determinant(dij, djk)
	print('vol', vol)
						-- determine axis of rotation between the three
						local d0i = oi.pos - com
						local d0j = oj.pos - com
						local d0k = ok.pos - com
						local curli = left(d0i):dot(oi.vel) / d0i:lenSq()
						local curlj = left(d0j):dot(oj.vel) / d0j:lenSq()
						local curlk = left(d0k):dot(ok.vel) / d0k:lenSq()
						local curl = vol * tripleCurlForceConst * (curli + curlj + curlk)
						oi.force = oi.force + left(d0i) * curl 
						oj.force = oj.force + left(d0j) * curl 
						ok.force = ok.force + left(d0k) * curl 
					end
				end
			end
		end
		--]]
		-- object-object forces
		for i=1,#self.objs-1 do
			local oi = self.objs[i]
			for j=i+1,#self.objs do
				local oj = self.objs[j]
				local massProd = oi:mass() * oj:mass()
				local delta = oj.pos - oi.pos	-- meters
				local len = delta:length()		-- meters
				local invLen = 1 / len			-- 1/meters
				local invLenSq = invLen * invLen	-- 1/meters^2
				local invLenCubed = invLen * invLenSq	-- 1/meters^3
				-- self.gravitation
				if gravForceEnabled then
					if len > oi.scale + oj.scale then
						local forcemag = gravForceConst * massProd * invLenCubed	-- kg/s^2
						local force = delta * forcemag 	-- kg m / s^2
						oi.force = oi.force + force		-- kg m / s^2
						oj.force = oj.force - force		-- kg m / s^2
					end
				end
				-- while we're here .. sum up potential gravitational force
				-- TODO why isn't it conservative?  
				oi.gravPotEnergy = oi.gravPotEnergy - gravForceConst * massProd * invLen	-- units: kg m^2 / s^2
				oj.gravPotEnergy = oj.gravPotEnergy - gravForceConst * massProd * invLen
				
				if doubleCurlForceEnabled then
					if len > oi.scale + oj.scale then
						local forcemag = doubleCurlForceConst * massProd * invLenCubed	-- kg/s^2
						local force = left(delta) * forcemag	-- kg m / s^2
						oi.force = oi.force + force				-- kg m / s^2
						oj.force = oj.force - force				-- kg m / s^2
					end
				end
			end
		end
		-- per-object forces
		for i,o in ipairs(self.objs) do
			-- hard constraints?
			if o.pos:length() > outerWallRadius then
				o.pos = o.pos * (outerWallRadius / o.pos:length())
				o.vel = o.vel * (-outerWallRestitution) 
			end
		end
		self.totalKineticEnergy = 0
		self.totalPotentialEnergy = 0
		for i,o in ipairs(self.objs) do
			o.pos = o.pos + o.vel * dt
			o.vel = o.vel + o.force * (dt / o:mass())
			local kineticEnergy = .5 * o.vel:lenSq() * o:mass()		-- kg m^2 / s^2
			self.totalKineticEnergy = self.totalKineticEnergy + kineticEnergy 
			self.totalPotentialEnergy = self.totalPotentialEnergy + o.gravPotEnergy
		end
	end

	-- render
	gl.glBegin(gl.GL_QUADS)
	for i,o in ipairs(self.objs) do
		local fwd = vec2f(math.cos(o.angle), math.sin(o.angle))
		local up = left(fwd)
		for _,corner in ipairs(quadvtxs) do
			gl.glVertex2f((o.pos + (fwd * corner.x + up * corner.y) * o.scale):unpack())
		end
	end
	gl.glEnd()

	App.super.super.update(self, ...)
end

function App:event(event, ...)
	App.super.event(self, event, ...)
	if event.type == sdl.SDL_KEYDOWN then
		if event.key.keysym.sym == ('r'):byte() then
			self:reset()
		elseif event.key.keysym.sym == (' '):byte() then
			self.running = not self.running
		end
	end	
end

function App:updateGUI()
	ig.luatableInputInt('count', _G, 'count')
	ig.luatableInputFloat('dt', _G, 'dt')
	ig.luatableCheckbox('gravForceEnabled', _G, 'gravForceEnabled')
	ig.luatableInputFloat('gravForceConst', _G, 'gravForceConst')
	ig.luatableCheckbox('doubleCurlForceEnabled', _G, 'doubleCurlForceEnabled')
	ig.luatableInputFloat('doubleCurlForceConst', _G, 'doubleCurlForceConst')
	ig.luatableCheckbox('tripleCurlForceEnabled', _G, 'tripleCurlForceEnabled')
	ig.luatableInputFloat('tripleCurlForceConst', _G, 'tripleCurlForceConst')
	ig.luatableInputFloat('outerWallRadius', _G, 'outerWallRadius') 
	ig.luatableInputFloat('outerWallRestitution', _G, 'outerWallRestitution') 
	ig.luatableInputFloat('znear', self.view, 'znear')
	ig.luatableInputFloat('zfar', self.view, 'zfar')
	ig.igText('total kin. energy '..self.totalKineticEnergy)
	ig.igText('total grav. pot. energy '..self.totalPotentialEnergy)
	ig.igText('total energy '..(self.totalKineticEnergy + self.totalPotentialEnergy))
end

App():run()
