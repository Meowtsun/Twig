--!optimize 2
--!strict

const Signal = require(script.Parent.internals.signal)
const Component = { }
const Metatable = { }
local NextID = 1


const function buildBlacklistOf(this: component): blacklist
	local copy = { }

	copy.token = this.token
	copy.blacklist = true

	return copy
end


const function getStoreOf(this: component, world)
	return world.components[this.token]
end


const function composeSignal(name: string)
	return function <world> (this: component, world: world)
		local world = world :: any

		local store = getStoreOf(this, world)
		if store == nil then
			store = Component.buildStore(this)
			world.components[this.token] = store
		end

		local signal = store[name]
		if signal then -- reusing
			return signal
		end

		signal = Signal.new()
		store[name] = signal

		return signal
	end
end


function Metatable.__call(this: component, value)
	return this:set(value)
end


function Component.set(this: component)
	return function (value: any?): build
		return {
			component = this,
			value = value,
		}
	end
end


function Component.buildStore(this: component)
	local store = { }

	store.entityOf = { } :: { [row]: entity }
	store.rowOf = { } :: { [entity]: row }
	store.components = { } :: { [row]: any }
	store.token = this.token
	store.commits = { } :: { [entity]: true }

	return store
end


Component.publishedIn = composeSignal('published')
Component.createdIn = composeSignal('created')
Component.removedIn = composeSignal('removed')


export type build = { read component: component, read value: any }
export type component = typeof(Component.new())
export type store = typeof(Component.buildStore(nil :: any))
export type withToken = { [any]: any, read token: number }
export type API<kind> = {
	read set: (value: kind) -> (build),
	read none: component,
	read type: kind,
	read token: number,

	read publishedIn: <world> (this: API<kind>, world: world) -> (Signal.signal<(entity: entity, value: kind) -> ()>),
	read createdIn: <world> (this: API<kind>, world: world) -> (Signal.signal<(entity: entity, value: kind) -> ()>),
	read removedIn: <world> (this: API<kind>, world: world) -> (Signal.signal<(entity: entity, value: kind) -> ()>),
}

type blacklist = { read blacklist: boolean, read token: number }
type row = number
type entity = buffer


function Component.new()
	local this = { }

	this.blacklist = false
	this.token = NextID

	this.buildStore = Component.buildStore
	this.set = Component.set(this :: any)
	this.none = buildBlacklistOf(this :: any)

	this.publishedIn = Component.publishedIn
	this.createdIn = Component.createdIn
	this.removedIn = Component.removedIn

	NextID += 1

	return setmetatable(this, Metatable)
end


return Component.new