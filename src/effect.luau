--!strict

const Signal = require(script.Parent.internals.signal)
const Component = require(script.Parent.component)
const Effect = { }


const function buildStoreOf(component: class)
	local this = { }

	this.token = component.token
	this.commits = { }

	return this
end


const function buildSignal(label: string)
	return function<world> (this: class, world: world)
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


Effect.publishedIn = buildSignal('published')


export type class = typeof(Effect.new())

type build = Component.build<any>
type entity = buffer

export type API = {
	read publishedIn: <world> (this: API, world: world) -> (Signal.signal<(entity: entity) -> ()>),
	read token: any,
}


function Effect.new()
	local this = { }

	this.publishedIn = Effect.publishedIn
	this.token = newproxy()

	return this
end


return Effect.new