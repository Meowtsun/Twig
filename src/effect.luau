--!optimize 2
--!strict

const Signal = require './internals/signal'
const Effect = { }


const function getStoreOf(this: effect, world)
	return world.components[this.token]
end


const function composeSignal(name: string)
	return function <world> (this: effect, world: world)
		local world = world :: any

		local store = getStoreOf(this, world)
		if store == nil then
			store = Effect.buildStore(this)
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


function Effect.set(this: effect)
	return function (value: any?): build
		return {
			component = this,
			value = value,
		}
	end
end


function Effect.buildStore(this: effect)
	local store = { }

	store.token = this.token
	store.commits = { } :: { [entity]: true }

	return store
end


Effect.publishedIn = composeSignal('published')


export type build = { read component: effect, read value: any }
export type effect = typeof(Effect.new())
export type store = typeof(Effect.buildStore(nil :: any))

export type API = {
	read publishedIn: <world> (this: API, world: world) -> (Signal.signal<(entity: entity) -> ()>),
	read token: any,
}

type blacklist = { read blacklist: boolean, read token: number }
type row = number
type entity = buffer


function Effect.new()
	local this = { }

	this.token = newproxy()
	this.buildStore = Effect.buildStore
	this.publishedIn = Effect.publishedIn

	return this
end


return Effect.new