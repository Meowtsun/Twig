# Twig

The Wicked ecs Inspired by Git

ECS focused on being lightweight and having fast query speed.

---

## Features

- Lightweight ECS architecture
- Archetype-based queries
- Fast component queries
- Strong Luau typing
- Explicit state mutation and publication
- Batched change signals
- Low memory overhead

---

## Benchmark

Twig's compact archetype representation allows unmatched entities to be rejected cheaply, making highly selective queries particularly fast.

![Twig benchmark](test\data\query_16_components.png)
---

## Overview

```lua
local Twig = require(path_to_twig)
local world = Twig.world()

local active = Twig.component() :: Twig.component<boolean>
local name = Twig.component() :: Twig.component<string>
local disabled = Twig.component()

-- this initial component is optional
local entity = world:spawn({
    active.set(true),
    name.set("Dummy"),
})


-- query entities with name and active, but without disabled.
for entity, name, active in world:query(name, active, disabled.none) do
    -- ...
end

-- Or check membership directly.
if world:withoutComponent(entity, disabled) then
    -- ...
end


-- Twig requires you to explicitly stage which component of which entity
-- was changed if you want to observe the change through Twig's signals.
-- You can stage a component even without changing its value.
-- Or, you can simply not stage() at all if you don't need to publish it.
world:stage(entity, {
    name,
    active,
})

-- publishIn will run after you flush everything with world:push()
local connection = name:publishedIn(world):Connect(function(entity, value)
    connection:Disconnect()
end)

-- 2 more but these doesn't require you to flush, It just fires
-- name:createdIn(world) 
-- name:removedIn(world) 

-- you can also have effects, they are also component
-- but you can not add it to any entity
-- you only stage() this component

local recompute_state = Twig.effect()
local same_signal_api = recompute_state:publishedIn(world)

-- and membership doesn't matter, entity does not need to have this component
-- this act like built-in push signal, using the same API
world:stage(entity, {
    recompute_state,
})

-- flush all staged components of this world
world:push()
```

---

## Installation

Install Twig through Wally:

```toml
[dependencies]
twig = "meowtsun/twig@0.1.0"
```
