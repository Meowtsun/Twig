
--[[
	Benchmark dependency versions:

	Jecs   = "ukendio/jecs@0.11.0",
	Twig	 = "meowtsun/twig@0.1.0"

	Benchmark intended to be run directly in Roblox Studio.
	sorry I exclusively use studio
]]

const Jecs = require(game.ServerStorage.Packages.Jecs:Clone())
const Twig = require(game.ServerStorage.Packages.Twig:Clone())

const ENTITY_COUNT = 2 ^ 12 - 2
const COMPONENT_COUNT = 32
const QUERY_COUNT = 2

const jecsWorld = Jecs.world()
const twigWorld = Twig.world()

const components = {
	jecs = { },
	twig = { },
}

for cind = 1, COMPONENT_COUNT do
	components.jecs[cind] = jecsWorld:component()
	components.twig[cind] = Twig.component()
end


for eind = 1, ENTITY_COUNT do

	local jecs_entity = jecsWorld:entity()
	local twig_entity = twigWorld:spawn()

	for cind = 1, COMPONENT_COUNT do
		if math.random() > 0.5 then
			continue
		end

		jecsWorld:set(jecs_entity, components.jecs[cind], {value = true})
		twigWorld:set(twig_entity, {
			components.twig[cind]({value = true})
		})
	end
end

const query = {
	jecs = { },
	twig = { },
}

for qind = 1, QUERY_COUNT do
	const index = math.random(1, COMPONENT_COUNT)
	query.jecs[qind] = components.jecs[index]
	query.twig[qind] = components.twig[index]
end


return {

	ParameterGenerator = function()
		return
	end,

	BeforeAll = function()

	end,

	AfterAll = function()

	end,

	Functions = {

		Jecs_query = function(Profiler)
			Profiler.Begin('query')
				for entity in jecsWorld:query(table.unpack(query.jecs)) do
					-- ...
				end
			Profiler.End()
		end,

		Twig_query = function(Profiler)
			Profiler.Begin('query')
				for entity in twigWorld:query(table.unpack(query.twig)) do
					-- ...
				end
			Profiler.End()
		end,

	},
}
