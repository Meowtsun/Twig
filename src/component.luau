--!strict

const Signal = require(script.Parent.internals.signal)
const Component = { }
local nextID = 1


const function buildStoreOf(component: class)
	local this = { }

	this.token = component.token
	this.commits = { }
	this.components = { }
	this.rowOf = { }
	this.entityOf = { }

	return this
end


const function buildSignal(label: string)
	return function <world> (this: class, world: world)
		world = world :: any

		local store = world.components[this.token]
		if store == nil then
			store = buildStoreOf(this)
			world.components[this.token] = store
		end

		local signal = store[label]
		if signal ~= nil then
			return signal
		end

		signal = Signal.new()
		store[label] = signal

		return signal
	end
end


const function buildBlacklistOf(this: class)
	return {
		token = this.token,
		blacklist = true,
	}
end


function Component.set(this: class)
	return function <kind>
	(value: kind): build<kind>
		return {
			component = this,
			value = value,
		}
	end
end


Component.publishedIn = buildSignal('published')
Component.createdIn = buildSignal('created')
Component.removedIn = buildSignal('removed')


export type class = typeof(Component.new())
export type build<kind> = {
	read component: class,
	read value: kind,
}

type entity = buffer
type row = number

type componentSignalOf<kind> = Signal.signal<(entity: entity, value: kind) -> ()>
type blacklist<kind> = { type: nil }

export type API<kind> = {
	read none: blacklist<nil>,
	read type: kind,
	read token: number,

	read publishedIn: <world> (this: API<kind>, world: world) -> (componentSignalOf<kind>),
	read createdIn: <world> (this: API<kind>, world: world) -> (componentSignalOf<kind>),
	read removedIn: <world> (this: API<kind>, world: world) -> (componentSignalOf<kind>),
	read set: (value: kind) -> (build<kind>),
}


function Component.new()
	local this = { }

	this.blacklist = false
	this.token = nextID
	nextID += 1

	this.publishedIn = Component.publishedIn
	this.createdIn = Component.createdIn
	this.removedIn = Component.removedIn
	this.set = Component.set(this)
	this.none = buildBlacklistOf(this)

	return this
end


return Component.new
