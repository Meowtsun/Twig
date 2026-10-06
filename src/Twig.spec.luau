
return function()

	const Twig = require(script.Parent)

	local componentA: Twig.component<any>
	local componentB: Twig.component<any>
	local world: Twig.world
	local effect: Twig.effect

	beforeEach(function()
		componentA = Twig.component()
		componentB = Twig.component()
		world = Twig.world()
		effect = Twig.effect()
	end)

	describe('entity', function()
		it('should have different IDs', function()
			local entityA = world:spawn()
			local entityB = world:spawn()

			local idA, genA = world.identity(entityA)
			local idB, genB = world.identity(entityB)

			expect(idA).to.never.equal(idB)
		end)

		it('should be reused and inrecrement generation', function()
			local worldB = Twig.world()
			local entityA = worldB:spawn()
			local idA, genA = worldB.identity(entityA)
			worldB:despawn(entityA)

			entityA = worldB:spawn()
			local idB, genB = worldB.identity(entityA)

			expect(idA).to.equal(idB)
			expect(genA).to.never.equal(genB)
		end)
	end)

	describe('components', function()
		it('should be valid', function()
			expect(componentA).to.be.ok()
			expect(componentB).to.be.ok()
		end)

		it('should have different token', function()
			expect(componentA.token).to.never.equal(componentB.token)
		end)

		it('should make a valid build', function()
			const build = componentA.set(true)
			expect(build.component).to.equal(componentA)
			expect(build.value).to.equal(true)
		end)

	end)

	describe('effects', function()
		it('should be valid', function()
			expect(effect).to.be.ok()
		end)
	end)

	describe('world', function()

		it('should make entity', function()
			local entity = world:spawn()
			expect(entity).to.be.ok()
		end)

		it('should make entity with initial components', function()
			expect(function()
				local entity = world:spawn({
					componentA.set(true),
				})

				local bool = world:get(entity, componentA)
				if bool ~= true then
					error('value invalid')
				end
			end).to.never.throw()
		end)

		it('should be able to set, get and edit component', function()
			expect(function()

				local entity = world:spawn({
					componentB.set(0),
				})

				local n = world:get(entity, componentB)
				if n ~= 0 then
					error('value invalid')
				end

				local nextn = n + 10
				world:set(entity, {
					componentB.set(nextn)
				})

				n = world:get(entity, componentB)
				if n ~= nextn then
					error('value invalid')
				end

			end).to.never.throw()
		end)

		it('should be able to remove component', function()
			expect(function()

				local entity = world:spawn({
					componentB.set(0),
				})

				world:set(entity, {
					componentB.set(nil)
				})

				local n = world:get(entity, componentB)
				if n ~= nil then
					error('value invalid')
				end

			end).to.never.throw()
		end)

		it('should be able to query', function()
			world:spawn({ componentA.set(true) })
			world:spawn({ componentA.set(true) })
			world:spawn({ componentB.set(true) })

			local count = 0
			for entity in world:query(componentA) do
				count += 1
			end

			expect(count).to.equal(2)

			count = 0
			for entity in world:query(componentA, componentB) do
				count += 1
			end

			expect(count).to.equal(0)

		end)

		it('should be able to query with blacklist', function()
			world:spawn({ componentA.set(true) })
			world:spawn({ componentA.set(true) })
			world:spawn({ componentA.set(true), componentB.set(true) })

			local count = 0
			for entity in world:query(componentA, componentB.none) do
				count += 1
			end

			expect(count).to.equal(2)
		end)

		it('should be able to test component', function()
			local entityA = world:spawn({ componentA.set(true), componentB.set(true) })
			local componentC = Twig.component()

			expect(world:withComponent(entityA, componentA)).to.equal(true)
			expect(world:withComponent(entityA, componentC)).to.equal(false)

			expect(world:withComponents(entityA, componentA, componentB)).to.equal(true)
			expect(world:withComponents(entityA, componentA, componentB, componentC)).to.equal(false)
		end)
	end)

	describe('stages', function()

		it('should behave normally with component', function()
			local componentC = Twig.component()
			local entityC = world:spawn()

			local recived = {}

			componentC:publishedIn(world):Connect(function(entity, value)
				recived.entity = entity
				recived.value = value
			end)

			world:set(entityC, {
				componentC.set(10)
			})

			world:stage(entityC, {componentC})
			world:push()
			task.wait()

			expect(recived.entity).to.equal(entityC)
			expect(recived.value).to.equal(10)

		end)

		it('should behave normally with effect', function()
			local componentC = Twig.effect()
			local entityC = world:spawn()

			local recived = {}

			componentC:publishedIn(world):Connect(function(entity, value)
				recived.entity = entity
				recived.value = value
			end)

			world:stage(entityC, {componentC})
			world:push()
			task.wait()

			expect(recived.entity).to.equal(entityC)
			expect(recived.value).to.equal(nil)

		end)
	end)

	describe('added and removed', function()

		it('should be able to detect component creation', function()
			local entityA = world:spawn()

			local received = {}

			componentA:createdIn(world):Connect(function(entity, value)
				received.entity = entity
				received.value = value
			end)

			world:set(entityA, {
				componentA.set(10),
			})

			task.wait()
			expect(received.entity).to.equal(entityA)
			expect(received.value).to.equal(10)
		end)

		it('should detect only creation and not edit', function()
			local entityA = world:spawn()
			local fired = 0

			componentA:createdIn(world):Connect(function(entity, value)
				fired += 1
			end)

			world:set(entityA, {
				componentA.set(10),
			})

			world:set(entityA, {
				componentA.set(20),
			})

			task.wait()
			expect(fired).to.equal(1)
		end)

		it('should be able to detect component removal', function()
			local entityA = world:spawn({
				componentA.set(10),
			})

			local received = {}

			componentA:removedIn(world):Connect(function(entity, value)
				received.entity = entity
				received.value = value
			end)

			world:set(entityA, {
				componentA.set(nil),
			})

			task.wait()
			expect(received.entity).to.equal(entityA)
			expect(received.value).to.equal(10)
			expect(function()
				local value = world:get(entityA, componentA)
				if value ~= nil then
					error('value invalid')
				end
			end).to.never.throw()

		end)

		it('should detect component removal from despawning entity', function()
			local entityA = world:spawn({
				componentA.set(10),
			})

			local idA, genA = world.identity(entityA)
			local received = {}

			componentA:removedIn(world):Connect(function(entity, value)
				received.entity = entity
				received.value = value
			end)

			world:despawn(entityA)

			task.wait()
			expect(received.entity).to.never.equal(entityA)
			expect(received.value).to.equal(10)

			local idB, genB = world.identity(received.entity)
			expect(idA).to.equal(idB)
			expect(genA).to.equal(genB)

			expect(function()
				local value = world:get(entityA, componentA)
				if value ~= nil then
					error('value invalid')
				end
			end).to.never.throw()

		end)
	end)

end