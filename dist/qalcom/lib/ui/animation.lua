local Animation = {}
Animation.__index = Animation
local function clamp(value, minimum, maximum)
return math.max(minimum, math.min(maximum, value))
end
local easing = {
linear = function(value) return value end,
inQuad = function(value) return value * value end,
outQuad = function(value) return value * (2 - value) end,
inOutQuad = function(value)
if value < 0.5 then return 2 * value * value end
return -1 + (4 - 2 * value) * value
end,
smooth = function(value) return value * value * (3 - 2 * value) end,
}
function Animation.new(clock)
return setmetatable({
items = {},
clock = clock or os.clock,
last = nil,
}, Animation)
end
function Animation:to(target, properties, duration, curve, onUpdate, onComplete)
if type(target) ~= "table" or type(properties) ~= "table" then return nil end
duration = math.max(0.001, tonumber(duration) or 0.2)
local starts = {}
local ends = {}
for key, value in pairs(properties) do
if type(value) == "number" and type(target[key]) == "number" then
starts[key] = target[key]
ends[key] = value
end
end
if next(starts) == nil then
if onComplete then onComplete(target) end
return nil
end
local item = {
target = target,
starts = starts,
ends = ends,
duration = duration,
started = self.clock(),
curve = easing[curve or "smooth"] or easing.smooth,
onUpdate = onUpdate,
onComplete = onComplete,
}
self:cancel(target)
self.items[#self.items + 1] = item
self.last = item.started
return item
end
function Animation:cancel(target)
for index = #self.items, 1, -1 do
if not target or self.items[index].target == target then
table.remove(self.items, index)
end
end
end
function Animation:clear()
self:cancel()
end
function Animation:hasActive()
return #self.items > 0
end
function Animation:update(now)
now = tonumber(now) or self.clock()
local changed = false
for index = #self.items, 1, -1 do
local item = self.items[index]
local progress = clamp((now - item.started) / item.duration, 0, 1)
local eased = item.curve(progress)
for key, start in pairs(item.starts) do
item.target[key] = start + (item.ends[key] - start) * eased
end
if item.onUpdate then item.onUpdate(item.target, progress) end
changed = true
if progress >= 1 then
table.remove(self.items, index)
if item.onComplete then item.onComplete(item.target) end
end
end
self.last = now
return changed
end
return Animation