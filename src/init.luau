
const component = require(script.component)
const world = require(script.world)
const effect = require(script.effect)

export type component<a> = component.API<a>
export type effect = effect.API
export type entity = buffer
export type world = world.class

return {
	component = component :: () -> (component.API<any>),
	effect = effect :: () -> (effect.API),
	world = world,
}