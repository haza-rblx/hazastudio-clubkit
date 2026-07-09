--!strict
-- Non-blocking task queue: heavy work masuk queue dan dieksekusi satu per satu.

local Logger = require(script.Parent.Logger)

type TaskFn = () -> ()

type TaskQueueImpl = {
	_queue: {TaskFn},
	_running: boolean,
	enqueue: (self: TaskQueueImpl, fn: TaskFn) -> (),
	size: (self: TaskQueueImpl) -> number,
}

local TaskQueue = {}
TaskQueue.__index = TaskQueue

local log = Logger.new("TaskQueue")

function TaskQueue.new(): TaskQueueImpl
	local self = setmetatable({}, TaskQueue) :: any
	self._queue = {} :: {TaskFn}
	self._running = false
	return self
end

function TaskQueue:enqueue(fn: TaskFn)
	table.insert(self._queue, fn)
	if not self._running then
		self._running = true
		task.spawn(function()
			while #self._queue > 0 do
				local nextTask = table.remove(self._queue, 1)
				if nextTask then
					local ok, err = pcall(function(): boolean
						nextTask()
						return true
					end)
					if not ok then
						log:error("Task failed", {
							error = tostring(err),
						})
					end
				end
				task.wait()
			end
			self._running = false
		end)
	end
end

function TaskQueue:size(): number
	return #self._queue
end

return TaskQueue
