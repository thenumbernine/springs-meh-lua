#!/usr/bin/env luajit
local class = require 'ext.class'
local table = require 'ext.table'
local sdl = require 'ffi.sdl'
local vec2f = require 'vec-ffi.vec2f'

local Object = class()

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
end

local App = require 'imguiapp.withorbit'()

function App:initGL(...)
	App.super.initGL(self, ...)

	self.view.ortho = true

	self:reset()
end

function App:reset()
	self.objs = table()
	for i=1,100 do
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

	-- update
	local dt = .1
	for i,obj in ipairs(self.objs) do
		obj.force = vec2f(0,0)
	end
	-- object-object-object forces
	for i=1,#self.objs-2 do
		local oi = self.objs[i]
		for j=i+1,#self.objs-1 do
			local oj = self.objs[j]
			for k=j+1,#self.objs do
				local ok = self.objs[k]
				-- determine axis of rotation between the three
			end
		end
	end
	-- object-object forces
	for i=1,#self.objs-1 do
		local oi = self.objs[i]
		for j=i+1,#self.objs do
			local oj = self.objs[j]
			local delta = oj.pos - oi.pos
			local len = delta:length()
			-- self.gravitation
			if len > oi.scale + oj.scale then
				local forcemag = 4 * (oi.scale * oi.scale + oj.scale * oj.scale) / (len * len * len)
				local force = delta * forcemag
				oi.force = oi.force + force
				oj.force = oj.force - force
			end
		end
	end
	-- per-object forces
	for i,obj in ipairs(self.objs) do
		-- hard constraints?
		if obj.pos:length() > 100 then
			obj.pos = obj.pos * (100 / obj.pos:length())
			obj.vel = -obj.vel
		end
	end
	for i,obj in ipairs(self.objs) do
		obj.pos = obj.pos + obj.vel * dt
		obj.vel = obj.vel + obj.force * (dt / (4 * obj.scale * obj.scale))
	end

	-- render
	gl.glBegin(gl.GL_QUADS)
	for i,obj in ipairs(self.objs) do
		local fwd = vec2f(math.cos(obj.angle), math.sin(obj.angle))
		local up = vec2f(-fwd.y, fwd.x)
		for _,corner in ipairs(quadvtxs) do
			gl.glVertex2f((obj.pos + (fwd * corner.x + up * corner.y) * obj.scale):unpack())
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
		end
	end	
end

App():run()
