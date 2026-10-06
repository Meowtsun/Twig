
const component = require(script.component)
const world = require(script.world)
const effect = require(script.effect)

export type component<a> = component.API<a>
export type effect = effect.effect
export type entity = buffer
export type world = world.world

return {
	component = component :: () -> component.API<any>,
	effect = effect :: () -> effect.API,
	world = world,
}