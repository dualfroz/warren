-- Rolling message log. Keeps a bounded tail of lines so the panel and the save
-- file stay small while still reflecting recent events in order.

local MessageLog = {}
MessageLog.__index = MessageLog

function MessageLog.new(capacity)
  return setmetatable({ lines = {}, capacity = capacity or 32 }, MessageLog)
end

function MessageLog:add(line)
  self.lines[#self.lines + 1] = line
  while #self.lines > self.capacity do
    table.remove(self.lines, 1)
  end
end

function MessageLog:addAll(lines)
  for _, line in ipairs(lines) do
    self:add(line)
  end
end

function MessageLog:last()
  return self.lines[#self.lines]
end

function MessageLog:recent(count)
  local out = {}
  local from = math.max(1, #self.lines - count + 1)
  for i = from, #self.lines do
    out[#out + 1] = self.lines[i]
  end
  return out
end

function MessageLog:toData()
  return { lines = self.lines, capacity = self.capacity }
end

function MessageLog.fromData(snapshot)
  return setmetatable({ lines = snapshot.lines, capacity = snapshot.capacity }, MessageLog)
end

return MessageLog
