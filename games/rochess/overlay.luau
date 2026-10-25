-- By SyneX
local require = ...
local Analysis = require("analysis")
local Overlay = {}
Overlay.__index = Overlay

function Overlay.new(drawing)
    local self = setmetatable({objects = {}, arrows = {}, drawing = drawing}, Overlay)
    if not drawing then return self end
    local colors = {Color3.fromRGB(116, 235, 171), Color3.fromRGB(119, 182, 255), Color3.fromRGB(255, 202, 113)}
    local function make(kind, values)
        local object = drawing.new(kind)
        table.insert(self.objects, object)
        for key, value in pairs(values) do object[key] = value end
        object.Visible = false
        return object
    end
    for rank = 3, 1, -1 do
        local color = colors[rank]
        self.arrows[rank] = {
            line = make("Line", {Color = color, Thickness = 7, Transparency = 0.82, ZIndex = 10 - rank}),
            head = make("Triangle", {Color = color, Filled = true, Transparency = 0.92, ZIndex = 14 - rank}),
            badge = make("Circle", {Color = Color3.fromRGB(19, 26, 30), Radius = 12, Filled = true, Transparency = 0.95, ZIndex = 20}),
            label = make("Text", {Text = tostring(rank), Size = 17, Center = true, Outline = true,
                Color = color, Transparency = 1, ZIndex = 21}),
        }
    end
    return self
end

function Overlay:hide()
    if not self.visible then return end
    for _, object in ipairs(self.objects) do object.Visible = false end
    self.visible = false
    self.geometry = nil
end

function Overlay:draw(snapshot, rows, config, selected)
    if not self.drawing then return end
    local session = snapshot and snapshot.session
    local board = snapshot and snapshot.board
    if not config.enabled or not config.arrows or #rows == 0 or not session or session.over
        or session.version ~= snapshot.version or session.viewPly ~= #session.ucis
        or config.onlyOwn and session.engine.side ~= session.myColor
        or not board or not board.frame.Parent then self:hide(); return end
    local ancestor = board.frame
    while ancestor and not ancestor:IsA("ScreenGui") do
        if ancestor:IsA("GuiObject") and not ancestor.Visible then self:hide(); return end
        ancestor = ancestor.Parent
    end
    if ancestor and not ancestor.Enabled then self:hide(); return end
    local position, size = board.frame.AbsolutePosition, board.frame.AbsoluteSize
    local inset = game:GetService("GuiService"):GetGuiInset()
    if size.X <= 0 or size.Y <= 0 then self:hide(); return end
    local geometry = tostring(position) .. tostring(size) .. tostring(inset) .. tostring(board.flipped) .. selected .. tostring(config.allArrows)
    if self.visible and self.geometry == geometry and self.rows == rows then return end
    self.geometry, self.rows, self.visible = geometry, rows, true
    for rank, arrow in ipairs(self.arrows) do
        local row = rows[rank]
        local visible = row ~= nil and (config.allArrows or selected == rank)
        for _, object in pairs(arrow) do object.Visible = visible end
        if visible then
            local from = board.squares[Analysis.square(row.from)]
            local to = board.squares[Analysis.square(row.to)]
            if from and to then
                local start = from.AbsolutePosition + inset + from.AbsoluteSize / 2
                local finish = to.AbsolutePosition + inset + to.AbsoluteSize / 2
                local delta = finish - start
                if delta.Magnitude > 0 then
                    local unit = delta.Unit
                    local normal = Vector2.new(-unit.Y, unit.X)
                    local cell = math.min(size.X, size.Y) / 8
                    local tip = finish - unit * cell * 0.12
                    local base = tip - unit * cell * 0.22
                    arrow.line.From = start + unit * cell * 0.12
                    arrow.line.To = base + unit * 2
                    arrow.line.Thickness = math.max(4, cell * (rank == selected and 0.085 or 0.06))
                    arrow.line.Transparency = rank == selected and 0.98 or 0.68
                    arrow.head.PointA, arrow.head.PointB, arrow.head.PointC = tip, base + normal * cell * 0.13, base - normal * cell * 0.13
                    local badge = finish + normal * cell * 0.24
                    arrow.badge.Position = badge
                    arrow.label.Position = badge - Vector2.new(0, 10)
                end
            else
                for _, object in pairs(arrow) do object.Visible = false end
            end
        end
    end
end

function Overlay:Destroy()
    for _, object in ipairs(self.objects) do pcall(object.Remove, object) end
    table.clear(self.objects)
    self.visible = false
end

return Overlay
