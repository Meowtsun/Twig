--!optimize 2

local Connection = { }
local Signal = { }
Signal.__index = Signal
Connection.__index = Connection

export type connection = {
	Connected: boolean,
	Disconnect: (self: connection) -> (),
}


export type signal<T> =  {
	Fire: (self: signal<T>, ...any) -> (),

	Connect: (self: signal<T>, handler: T) -> (connection),
	Once: (self: signal<T>, handler: T) -> (connection),

	DisconnectAll: (self: signal<T>) -> (),
	Destroy: (self: signal<T>) -> (),
}



function Signal.new(...): signal<(...any) -> ()>
	return setmetatable({
		head = false,
		tail = false,
		count = 0,
	}, Signal)
end


function Connection.new(property)
	return setmetatable(property,
		Connection
	)
end


function Connection:Disconnect()
	if not self.Connected then
		return -- been disconnected
	end

	local head = self.head
	local tail = self.tail
	self.Connected = false


	if head then
		head.tail = tail
	end

	if tail then
		tail.head = head
	end

	local signal = self.parent
	signal.count -= 1

	if signal.head == self then
		signal.head = head
	end

	if signal.tail == self then
		signal.tail = tail
	end
end

function Signal:Connect(fn)
	local head = self.head

	local connection = Connection.new({
		Connected = true,
		callback = fn,
		parent = self,
		head = head,
		tail = false,
	})

	self.head = connection
	self.count += 1

	if head then
		head.tail = connection
	else
		self.tail = connection
	end

	return connection
end


function Signal:Once(fn)
	local connection
	self.count += 1
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)

	return connection
end


local cachedThreads: {thread} = {}
local localThread: thread?


local function callAndCacheThread(callback, thread, ...)
	callback(...)

	if localThread then
		table.insert(cachedThreads, thread)
	else
		localThread = thread
	end
end


local function loopedCallAndCacheThread(...)
	callAndCacheThread(...)
	while true do
		callAndCacheThread(coroutine.yield())
	end
end


local function getThread(): thread
	local thread = localThread
	if thread then
		localThread = nil

	else -- get one from cached threads
		local len = #cachedThreads
		thread = cachedThreads[len]
		cachedThreads[len] = nil
	end

	if thread and coroutine.status(thread) == 'suspended' then
		return thread
	else
		return coroutine.create(loopedCallAndCacheThread)
	end
end


function Signal:Fire(...)
	local connection = self.tail
	local count = self.count

	while connection and count > 0 do
		local thread = getThread()

		local ok, message: string? = coroutine.resume(
			thread, connection.callback, thread, ...
		)

		if not ok then
			task.defer(error, message, 2)
		end

		connection = connection.tail
		count -= 1
	end
end


function Signal:Wait(timeout: number?)
	local thread = coroutine.running()
	local connection

	local function callback(...)
		if coroutine.status(thread) == "suspended" then
			coroutine.resume(thread, ...)
		end
	end

	self:Once(callback)
	return coroutine.yield()
end


function Signal:DisconnectAll()
	local connection = self.tail
	local count = self.count

	while connection and count > 0 do
		connection:Disconnect()
		connection = connection.tail
		count -= 1
	end
end


function Signal:Destroy()
	self:DisconnectAll()
	setmetatable(self, nil)
end


do -- initialize
	localThread = coroutine.create(loopedCallAndCacheThread)
end


return { new = Signal.new }