--!optimize 2
--!native
--!strict

const GENERATION_MAX_BYTES = 4
const ENTITY_MAX_BYTES = 4
const COMPONENT_MAX_BYTES = 32
const MAX_CACHED_ARCHETYPES = 32
const ARCHETYPE_COMPARE_LENGTH = 32
-- ------ --
const GENERATION_CAPACITY = math.pow(2, 8 * GENERATION_MAX_BYTES) - 1
const ENTITY_CAPACITY = math.pow(2, 8 * ENTITY_MAX_BYTES) - 1
const COMPONENT_CAPACITY = math.pow(2, 8 * COMPONENT_MAX_BYTES) - 1
-- ------ --

const Component = require(script.Parent.component)
const World = { }
local CachedArchetypes = { } :: { buffer }

export type world = typeof(World.new())


const function allocateArchetype(): archetype
	local archetype = table.remove(CachedArchetypes)
	if archetype then -- reusable, yay
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


const function emptyqueries()
	return nil
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


const function allocateEntity(this: world): entity
	local entity = table.remove(this.releasedEntities)
	if entity then
		return incrementGenerationOf(entity)
	end

	if this.nextID > ENTITY_CAPACITY then
		error(`[Twig]: entity limit reached!`, 3)
	end

	const id = this.nextID
	this.nextID += 1
	return newEntity(id)
end


const function releaseEntity(this: world, entity: entity)
	this.componentsOf[entity] = nil
	this.archetypesOf[entity] = nil
	table.insert(this.releasedEntities, entity)
end


const function newArchetype(components: { Component.withToken }): (archetype, archetype?)
	local whitelist: archetype = allocateArchetype()
	local blacklist: archetype? = nil

	for _, stored in components do
		if stored.blacklist == true
		then
			if blacklist == nil then
				blacklist = allocateArchetype()
			end
			buffer.writebits(blacklist :: any, stored.token - 1, 1, 1)
		else
			buffer.writebits(whitelist, stored.token - 1, 1, 1)
		end
	end

	return whitelist, blacklist
end


const function buildArchetypeOf(this: world, entity: entity, components: { Component.withToken })
	local archetype = newArchetype(components)
	this.archetypesOf[entity] = archetype
end


const function addArchetypeOf(this: world, entity: entity, component: Component.component)
	local archetype = this.archetypesOf[entity]
	buffer.writebits(archetype, component.token - 1, 1, 1)
end


const function removeArchetypeOf(this: world, entity: entity, component: Component.component)
	local archetype = this.archetypesOf[entity]
	buffer.writebits(archetype, component.token - 1, 1, 0)
end


const function isArchetypeCompatible(this: world, archetype: archetype, whitelist: archetype, blacklist: archetype?): boolean
	const total_scan = math.ceil(this.archetypeDepth / ARCHETYPE_COMPARE_LENGTH)
	local offset = 0

	for index = 1, total_scan do
		const template = buffer.readu32(archetype, offset)
		const required = buffer.readu32(whitelist, offset)

		if bit32.band(template, required) ~= required then
			return false
		end

		if blacklist ~= nil then
			const forbidden = buffer.readu32(blacklist, offset)
			if bit32.band(template, forbidden) ~= 0 then
				return false
			end
		end

		offset += (ARCHETYPE_COMPARE_LENGTH / 8)
	end

	return true
end


const function hasArchtypeOf(this: world, entity: entity, component: Component.withToken)
	local archetype = this.archetypesOf[entity]
	const bit = buffer.readbits(archetype, component.token - 1, 1)
	return bit == 1
end


function World.spawn(this: world, builds: { Component.build }): entity
	local entity = allocateEntity(this)
	local components = { } :: { Component.store }

	if builds ~= nil then
		for _, build in builds do
			const component = build.component
			const value = build.value
			const token = component.token

			local stored = this.components[token]
			if stored == nil then
				stored = component:buildStore()
				this.components[token] = stored

				if component.token > this.archetypeDepth then
					this.archetypeDepth = component.token
				end
			end

			const row = #stored.components + 1
			stored.components[row] = value
			stored.rowOf[entity] = row
			stored.entityOf[row] = entity
			table.insert(components, stored)
		end
	end

	this.componentsOf[entity] = components
	buildArchetypeOf(this, entity, components :: any)

	return entity
end


function World.despawn(this: world, entity: entity)
	local components = this.componentsOf[entity]
	local removed = false

	for _, stored in components do
		const row = stored.rowOf[entity]
		if row ~= nil then
			removed = true

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
		end
	end

	if removed == true then
		releaseEntity(this, entity)
	end
end


function World.add(this: world, entity: entity, build: Component.build): overrided
	const component = build.component
	const value = build.value

	if value == nil then
		const success = World.remove(this, entity, component)
		return success, nil
	end

	local stored = this.components[component.token]
	if stored == nil then
		stored = component:buildStore()
		this.components[component.token] = stored
		if component.token > this.archetypeDepth then
			this.archetypeDepth = component.token
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

	local signal = (stored :: any).created
	if signal ~= nil then
		signal:Fire(entity, value)
	end

	return true, value
end


function World.remove(this: world, entity: entity, component: Component.component): overrided
	local stored = this.components[component.token]

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
		removeArchetypeOf(this, entity, component)

		local signal = (stored :: any).removed
		if signal ~= nil then
			signal:Fire(entity, value)
		end

		return true, value
	end

	return false, nil
end


function World.set(this: world, entity: entity, builds: { Component.build })
	for _, build in builds do
		const component = build.component
		const value = build.value

		if value == nil then
			World.remove(this, entity, component)
			return
		end

		local stored = this.components[component.token]
		if stored == nil then
			World.add(this, entity, build)
			return
		end

		const row = stored.rowOf[entity]
		if row ~= nil then
			stored.components[row] = value
		else
			World.add(this, entity, build)
		end
	end
end


function World.get(this: world, entity: entity, component:Component.component): overrided
	local stored = this.components[component.token]
	if stored == nil then
		return nil
	end

	const row = stored.rowOf[entity]
	if row ~= nil then
		return stored.components[row]
	end

	return nil
end


const function buildIterator(this: world, stored: Component.store, components: { Component.store }, length: number, whitelist: archetype, blacklist: archetype?)
	local row = 1

	return function (): overrided
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


function World.query(this: world, ...: Component.component): overrided
	const components = { ... }
	local mapped = { }

	local best: Component.store
	local score = math.huge

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

	return buildIterator(this, best, mapped :: any, score, whitelist, blacklist)
end


function World.withComponent(this: world, entity: entity, component: Component.component): boolean
	return hasArchtypeOf(this, entity, component :: any)
end


function World.withoutComponent(this: world, entity: entity, component: Component.component): boolean
	return not hasArchtypeOf(this, entity, component :: any)
end


function World.withComponents(this: world, entity: entity, ...: Component.component): boolean
	const archetype = this.archetypesOf[entity]
	const query = newArchetype({...:: any})
	return isArchetypeCompatible(this, archetype, query)
end


function World.withoutComponents(this: world, entity: entity, ...: Component.component): boolean
	const archetype = this.archetypesOf[entity]
	const query = newArchetype({...:: any})
	return not isArchetypeCompatible(this, archetype, query)
end


function World.stage(this: world, entity: entity, components: { Component.component })
	for _, component in components do
		local stored = this.components[component.token]
		if stored == nil then
			stored = component:buildStore()
			this.components[component.token] = stored

			if type(component.token) == 'number' then
				if component.token > this.archetypeDepth then
					this.archetypeDepth = component.token
				end
			end
		end

		stored.commits[entity] = true
		this.stagedComponents[stored] = true
	end

	this.wasStaged = true
end


function World.push(this: world)

	for stored in this.stagedComponents do
		for entity in stored.commits do
			local value = nil

			const row = stored.rowOf[entity]
			if row ~= nil then
				value = stored.components[row]
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


function World.hasCommit(this: world): boolean
	return this.wasStaged
end


type overrided = any
type archetype = buffer
type token = number
type row = number
type entity = buffer

type component<a> = Component.API<a>
type get = (<a> (this: world, component<a>) -> (a))

type query = -- this is depressing is it not?, I'm crying right now
& (<a> (this: world, a: component<a>) -> () -> (entity, a))
& (<a, b> (this: world, a: component<a>, b: component<b>) -> () -> (entity, a, b))
& (<a, b, c> (this: world, a: component<a>, b: component<b>, c: component<c>) -> () -> (entity, a, b, c))
& (<a, b, c, d> (this: world, a: component<a>, b: component<b>, c: component<c>, d: component<d>) -> () -> (entity, a, b, c, d))
& (<a, b, c, d, e> (this: world, a: component<a>, b: component<b>, c: component<c>, d: component<d>, e: component<e>) -> () -> (entity, a, b, c, d, e))


function World.new()
	local this = { }

	this.archetypeDepth = 32
	this.nextID = 1
	this.wasStaged = false

	this.components = { } :: { [token]: Component.store }
	this.archetypesOf = { } :: { [entity]: archetype }
	this.componentsOf = { } :: {
		[entity]: { Component.store }
	}

	this.stagedComponents = { } :: { [Component.store]: true }
	this.releasedEntities = { } :: { entity }

	this.despawn = World.despawn
	this.spawn = World.spawn
	this.remove = World.remove
	this.add = World.add

	this.set = World.set
	this.get = World.get :: get

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