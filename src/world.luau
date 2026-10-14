--!optimize 2
--!native
--!strict
--[[
	This is my approach to preserving type information internally-
	definitely is unconventional
]]

const COMPONENT_CAPACITY = 256 -- Must be a multiple of 32
const ARCHETYPES_COMPARE_LENGTH = 32 -- Must be 32
const MAX_CACHED_ARCHETYPES = 32
const ENTITY_MAX_BYTES = 4
const GENERATION_MAX_BYTES = 4
-- ------ --
const GENERATION_CAPACITY = math.pow(2, GENERATION_MAX_BYTES * 8) - 1
const ENTITY_CAPACITY = math.pow(2, ENTITY_MAX_BYTES * 8) - 1
const COMPONENT_MAX_BYTES = (COMPONENT_CAPACITY / 8)
const ANY_COMPONENT = buffer.create(COMPONENT_MAX_BYTES)
-- ------ --

const Component = require(script.Parent.component)
const World = { }

local CachedArchetypes = { } :: { archetype }


const function isEffect(component: any): boolean
	return type(component.token) ~= 'number'
end


const function emptyqueries()
	return nil
end


const function allocateArchetype(): archetype
	local archetype = table.remove(CachedArchetypes)
	if archetype then -- reusable
		return archetype
	end

	return buffer.create(COMPONENT_MAX_BYTES)
end


const function releaseArchetype(archetype: archetype)
	buffer.fill(archetype, 0, 0, COMPONENT_MAX_BYTES)

	if #CachedArchetypes < MAX_CACHED_ARCHETYPES then
		table.insert(CachedArchetypes, archetype)
	end
end


const function newArchetype(components: { anytoken }): (archetype, archetype?)
	local whitelist = allocateArchetype()
	local blacklist = nil

	for _, stored in components do
		if stored.blacklist == true then
			if blacklist == nil then
				blacklist = allocateArchetype()
			end

			buffer.writebits(blacklist :: archetype, stored.token - 1, 1, 1)
		else
			buffer.writebits(whitelist, stored.token - 1, 1, 1)
		end
	end

	return whitelist, blacklist
end


const function buildArchetypeOf(this: class, entity: entity, components: { anytoken })
	local archetype = newArchetype(components)
	this.archetypesOf[entity] = archetype
end


const function addArchetypeOf(this: class, entity: entity, component: Component.class)
	local archetype = this.archetypesOf[entity]
	buffer.writebits(archetype, component.token - 1, 1, 1)
end


const function removeArchetypeOf(this: class, entity: entity, component: Component.class)
	local archetype = this.archetypesOf[entity]
	buffer.writebits(archetype, component.token - 1, 1, 0)
end


const function hasArchtypeOf(this: class, entity: entity, component: anytoken)
	local archetype = this.archetypesOf[entity]
	const bit = buffer.readbits(archetype, component.token - 1, 1)
	return bit == 1
end


const function identify(entity: entity): (number, number)
	const generation = buffer.readbits(entity, 8 * ENTITY_MAX_BYTES, 8 * GENERATION_MAX_BYTES)
	const id = buffer.readbits(entity, 0, 8 * ENTITY_MAX_BYTES)
	return id, generation
end


const function incrementGenerationOf(entity: entity): entity
	const id, generation = identify(entity)
	if generation >= GENERATION_CAPACITY then
		error(`[Twig]: generation limit reached for "{id}"!`, 4)
	end

	buffer.writebits(entity, 8 * ENTITY_MAX_BYTES, 8 * GENERATION_MAX_BYTES,generation + 1)
	return entity
end


const function newEntity(id: number): entity
	local entity = buffer.create(ENTITY_MAX_BYTES + GENERATION_MAX_BYTES)
	buffer.writebits(entity, 8 * ENTITY_MAX_BYTES, 8 * GENERATION_MAX_BYTES, 1)
	buffer.writebits(entity, 0, 8 * ENTITY_MAX_BYTES, id)
	return entity
end


const function allocateEntity(this: class)
	local entity = table.remove(this.releasedEntities)
	if entity ~= nil then
		return incrementGenerationOf(entity)
	end

	if this.nextID > ENTITY_CAPACITY then
		error(`[Twig]: entity limit reached!`, 3)
	end

	const id = this.nextID
	this.nextID += 1
	return newEntity(id)
end


const function releaseEntity(this: class, entity: entity)
	this.componentsOf[entity] = nil
	this.archetypesOf[entity] = nil
	table.insert(this.releasedEntities, entity)
end


const function buildStoreOf(component: Component.class): store
	local this = { }

	this.token = component.token
	this.commits = { }

	if not isEffect(component) then
		this.components = { }
		this.rowOf = { }
		this.entityOf = { }
	end

	return this
end


function World.spawn(this: class, builds: {Component.build<any>}?): entity
	local entity = allocateEntity(this)
	local components = { } :: { store }

	if builds ~= nil then
		for _, build in builds do
			const component = build.component
			const value = build.value
			const token = component.token

			local stored = this.components[token]
			if stored == nil then
				stored = buildStoreOf(component)
				this.components[token] = stored
				if token > this.archetype_depth then
					this.archetype_depth = token
				end
			end

			const row = #stored.components + 1
			stored.components[row] = value
			stored.rowOf[entity] = row
			stored.entityOf[row] = entity
			table.insert(components, stored)

			const signal = (stored :: any).created
			if signal ~= nil then
				signal:Fire(entity, value)
			end
		end
	end

	this.componentsOf[entity] = components
	buildArchetypeOf(this, entity, components)

	return entity
end


function World.despawn(this: class, entity: entity)
	local components = this.componentsOf[entity]

	for _, stored in components do
		const row = stored.rowOf[entity]
		if row ~= nil then
			const value = stored.components[row]
			const last = #stored.components

			if row ~= last then
				const movingID = stored.entityOf[row]
				stored.components[row] = stored.components[last]
				stored.rowOf[movingID] = row
				stored.entityOf[row] = movingID
			end

			stored.components[last] = nil
			stored.rowOf[entity] = nil
			stored.entityOf[last] = nil

			local signal = (stored :: any).removed
			if signal ~= nil then
				local copy = buffer.create(ENTITY_MAX_BYTES + GENERATION_MAX_BYTES)
				buffer.copy(copy, 0, entity)
				signal:Fire(copy, value)
			end
		end
	end

	releaseEntity(this, entity)
end


function World.add<kind>(this: class, entity: entity, build: Component.build<kind>): (boolean, kind)
	const component = build.component
	const value = build.value
	const token = component.token

	if value == nil then
		const success = World.remove(this, entity, component :: any)
		return success, value
	end

	local stored = this.components[token]
	if stored == nil then
		stored = buildStoreOf(component)
		this.components[token] = stored
		if token > this.archetype_depth then
			this.archetype_depth = token
		end
	end

	const row = stored.rowOf[entity]
	if row ~= nil then
		return false, stored.components[row]
	end

	const row = #stored.components + 1
	stored.components[row] = value
	stored.rowOf[entity] = row
	stored.entityOf[row] = entity
	addArchetypeOf(this, entity, component)

	const signal = (stored :: any).created
	if signal ~= nil then
		signal:Fire(entity, value)
	end

	return true, value
end


function World.remove<kind>(this: class, entity: entity, component: Component.API<kind>): (boolean, kind)
	local stored =  this.components[component.token]

	const row = stored.rowOf[entity]
	if row ~= nil then
		const value = stored.components[row]
		const last = #stored.components

		if row ~= last then
			const movingID = stored.entityOf[last]
			stored.components[row] = stored.components[last]
			stored.rowOf[movingID] = row
			stored.entityOf[row] = movingID
		end

		stored.components[last] = nil
		stored.rowOf[entity] = nil
		stored.entityOf[last] = nil
		removeArchetypeOf(this, entity, component :: any)

		local signal = (stored :: any).removed
		if signal ~= nil then
			signal:Fire(entity, value)
		end

		return true, value
	end

	return false, (nil :: any)
end


function World.set(this: class, entity: entity, builds: { Component.build<any> })
	for _, build in builds do
		const component = build.component
		const value = build.value
		const token = component.token

		if value == nil then
			World.remove(this, entity, component :: any)
			continue
		end

		local stored = this.components[token]
		if stored == nil then
			World.add(this, entity, build)
			continue
		end

		const row = stored.rowOf[entity]
		if row ~= nil then
			stored.components[row] = value
		else
			World.add(this, entity, build)
		end
	end
end


function World.get<kind>(this: class, entity: entity, component: Component.API<kind>): kind?
	const stored = this.components[component.token]
	if stored == nil then
		return nil
	end

	const row = stored.rowOf[entity]
	if row ~= nil then
		return stored.components[row]
	end

	return nil
end


const function isArchetypeCompatible(this: class, archetype: archetype, whitelist: archetype, blacklist: archetype?): boolean
	const total_scan = math.ceil(this.archetype_depth / ARCHETYPES_COMPARE_LENGTH)
	local offset = 0

	if blacklist == nil then
		for index = 1, total_scan do
			const template = buffer.readu32(archetype, offset)
			const required = buffer.readu32(whitelist, offset)
			if bit32.band(template, required) ~= required then
				return false
			end

			offset += (ARCHETYPES_COMPARE_LENGTH / 8)
		end

		return true
	end

	-- blacklist exist, handling things differently
	for index = 1, total_scan do
		const template = buffer.readu32(archetype, offset)
		const required = buffer.readu32(whitelist, offset)
		const excluded = buffer.readu32(blacklist, offset)

		const missing = bit32.band(required, bit32.bnot(template))
		const forbidden = bit32.band(template, excluded)
		if bit32.bor(missing, forbidden) ~= 0 then
			return false
		end

		offset += (ARCHETYPES_COMPARE_LENGTH / 8)
	end

	return true
end


const function buildIterator(this: class, stored: store, components: { store }, length: number, whitelist: archetype, blacklist: archetype?)
	local row = 1

	return function (): WAS_OVERRIDDEN
		while true do
			if row > length then
				releaseArchetype(whitelist)
				if blacklist ~= nil then
					releaseArchetype(blacklist :: any)
				end

				return nil
			end

			const entity = stored.entityOf[row]
			const archetype = this.archetypesOf[entity]
			row += 1

			if isArchetypeCompatible(this, archetype, whitelist, blacklist) then
				local values = table.create(#components)

				for _, component_stored in components do
					const component_row = component_stored.rowOf[entity]
					table.insert(values,
						component_stored.components[component_row]
					)
				end

				return entity, table.unpack(values)
			end
		end
	end
end


function World.query<kind>(this: class, ...: Component.class): WAS_OVERRIDDEN
	const components = { ... }
	local mapped = { }

	local score = math.huge
	local best: store

	const whitelist, blacklist = newArchetype(components :: any)

	for index, component in components do
		const stored = this.components[component.token]
		if stored == nil then
			return emptyqueries
		end

		if component.blacklist ~= true then
			const total = #stored.components
			mapped[index] = stored :: any
			if total < score then
				score, best = total, stored
			end
		end
	end

	if best == nil then
		error('[Twig]: world:query() requires at least one whitelisted component!')
	end

	return buildIterator(this, best, mapped, score, whitelist, blacklist)
end


function World.withComponent(this: class, entity: entity, component: Component.API<any>): boolean
	return hasArchtypeOf(this, entity, component :: any)
end


function World.withoutComponent(this: class, entity: entity, component: Component.API<any>): boolean
	return not hasArchtypeOf(this, entity, component :: any)
end


function World.withComponents(this: class, entity: entity, ...: Component.API<any>): boolean
	const queries = { ... }

	const archetype = this.archetypesOf[entity]
	const query = newArchetype(queries :: any)
	return isArchetypeCompatible(this, archetype, query)
end


function World.withoutComponents(this: class, entity: entity, ...: Component.API<any>): boolean
	const queries = { ... }

	const archetype = this.archetypesOf[entity]
	const query = newArchetype(queries :: any)
	return isArchetypeCompatible(this, archetype, ANY_COMPONENT, query)
end


function World.hasCommit(this: class): boolean
	return this.wasStaged
end


function World.stage(this: class, entity: entity, components: { Component.API<any> })
	for _, component in components do
		const token = component.token

		local stored = this.components[token]
		if stored == nil then
			stored = buildStoreOf(component :: any)
			this.components[token] = stored
			if token > this.archetype_depth then
				this.archetype_depth = token
			end
		end

		stored.commits[entity] = true
		this.stagedComponents[stored] = true
	end

	this.wasStaged = true
end


function World.push(this: class)
	for stored in this.stagedComponents do
		for entity in stored.commits do
			local value = nil

			if stored.rowOf ~= nil then
				const row = stored.rowOf[entity]
				if row ~= nil then
					value = stored.components[row]
				end
			end

			local signal = (stored :: any).published
			if signal ~= nil then
				task.defer(signal.Fire, signal, entity, value)
			end
		end

		table.clear(stored.commits)
	end

	table.clear(this.stagedComponents)
	this.wasStaged = false
end


export type class = typeof(World.new())

type archetype = buffer
type token = number
type row = number
type entity = buffer
type WAS_OVERRIDDEN = any

type anytoken = {
	[any]: any,
	token: number ,
}

type store = {
	entityOf: { [row]: entity },
	rowOf: { [entity]: row },
	components: { [row]: any },
	commits: { [entity]: true },
	token: number,
}


type query = -- this is depressing is it not?, I'm crying right now
& (<a> (this: class, a: Component.API<a>) -> () -> (entity, a))
& (<a, b> (this: class, a: Component.API<a>, b: Component.API<b>) -> () -> (entity, a, b))
& (<a, b, c> (this: class, a: Component.API<a>, b: Component.API<b>, c: Component.API<c>) -> () -> (entity, a, b, c))
& (<a, b, c, d> (this: class, a: Component.API<a>, b: Component.API<b>, c: Component.API<c>, d: Component.API<d>) -> () -> (entity, a, b, c, d))
& (<a, b, c, d, e> (this: class, a: Component.API<a>, b: Component.API<b>, c: Component.API<c>, d: Component.API<d>, e: Component.API<e>) -> () -> (entity, a, b, c, d, e))


function World.new()
	local this = { }

	this.archetype_depth = 32
	this.nextID = 1
	this.wasStaged = false

	this.stagedComponents = { } :: { [store]: true }
	this.releasedEntities = { } :: { entity }

	this.archetypesOf = { } :: { [entity]: archetype }
	this.components = { } :: { [token]: store }
	this.componentsOf = { } :: {
		[entity]: { store }
	}

	this.despawn = World.despawn
	this.spawn = World.spawn
	this.remove = World.remove
	this.add = World.add

	this.set = World.set
	this.get = World.get

	this.hasCommit = World.hasCommit
	this.stage = World.stage
	this.push = World.push
	this.query = World.query :: query
	this.identity = identify

	this.withoutComponent = World.withoutComponent
	this.withComponent = World.withComponent
	this.withoutComponents = World.withoutComponents
	this.withComponents = World.withComponents

	return this
end


return World.new