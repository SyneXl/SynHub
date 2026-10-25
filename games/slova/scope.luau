-- By SyneX
local Scope = {}
Scope.__index = Scope

function Scope.new()
    return setmetatable({items = {}, destroyed = false}, Scope)
end

function Scope:add(cleanup)
    assert(not self.destroyed, "Scope is already closed")
    table.insert(self.items, cleanup)
    return cleanup
end

function Scope:Destroy()
    if self.destroyed then return end
    self.destroyed = true
    for index = #self.items, 1, -1 do
        local item = self.items[index]
        local ok, err = pcall(function()
            if type(item) == "function" then item() else item:Disconnect() end
        end)
        if not ok then warn("[SynHub] Не удалось завершить обработчик: " .. tostring(err)) end
    end
    table.clear(self.items)
end

return Scope
