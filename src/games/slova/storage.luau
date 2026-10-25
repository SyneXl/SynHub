-- By SyneX
local Storage = {}
Storage.__index = Storage

function Storage.new(http, files)
    return setmetatable({http = http, files = files, path = "SynHub/slova/state.json"}, Storage)
end

function Storage:load()
    if type(self.files.readfile) ~= "function" then return {} end
    for _, path in ipairs({self.path, "Slova/state.json"}) do
        local ok, value = pcall(function()
            return self.http:JSONDecode(self.files.readfile(path))
        end)
        if ok and type(value) == "table" then return value end
    end
    return {}
end

function Storage:save(state)
    if type(self.files.writefile) ~= "function" then return false, "Сохранение недоступно" end
    return pcall(function()
        if type(self.files.makefolder) == "function" then
            for _, path in ipairs({"SynHub", "SynHub/slova"}) do
                if type(self.files.isfolder) ~= "function" or not self.files.isfolder(path) then
                    pcall(self.files.makefolder, path)
                end
            end
        end
        self.files.writefile(self.path, self.http:JSONEncode(state))
    end)
end

return Storage
