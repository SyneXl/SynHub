-- By SyneX
local require = ...
local Analysis = require("analysis")
local Overlay = {}
Overlay.__index = Overlay

local function make(kind, values, parent)
    local object = Instance.new(kind)
    for key, value in pairs(values) do object[key] = value end
    object.Parent = parent
    return object
end

function Overlay.new(palette)
    local self = setmetatable({objects = {}, arrows = {}, palette = palette}, Overlay)
    self:build()
    return self
end

function Overlay:build()
    if self.root then self.root:Destroy() end
    table.clear(self.objects)
    table.clear(self.arrows)
    self.root = make("Frame", {Name = "MoveHints", BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), Active = false, ClipsDescendants = true, Visible = false, ZIndex = 100})
    self.host, self.geometry, self.visible = nil, nil, false
    local colors = self.palette.moves
    local function part(kind, values)
        values.Visible = false
        values.Active = false
        values.BorderSizePixel = 0
        values.AnchorPoint = Vector2.new(0.5, 0.5)
        local object = make(kind, values, self.root)
        table.insert(self.objects, object)
        return object
    end
    for rank = 3, 1, -1 do
        local color = colors[rank]
        local line = part("Frame", {BackgroundColor3 = color, BackgroundTransparency = 0.18, ZIndex = 110 - rank})
        make("UICorner", {CornerRadius = UDim.new(1, 0)}, line)
        local head = part("TextLabel", {BackgroundTransparency = 1, Text = "▲", TextColor3 = color,
            TextTransparency = 0.08, Font = Enum.Font.Arial, TextScaled = true, ZIndex = 114 - rank})
        local badge = part("Frame", {BackgroundColor3 = self.palette.badge,
            BackgroundTransparency = 0.05, ZIndex = 120})
        make("UICorner", {CornerRadius = UDim.new(1, 0)}, badge)
        local label = part("TextLabel", {BackgroundTransparency = 1, Text = tostring(rank), Font = Enum.Font.SourceSansSemibold,
            TextColor3 = color, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 121})
        self.arrows[rank] = {line = line, head = head, badge = badge, label = label}
    end
end

function Overlay:hide()
    if self.root then self.root.Visible = false end
    self.visible, self.geometry = false, nil
end

function Overlay:draw(snapshot, rows, config, selected)
    if not self.root then return end
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
    if size.X <= 0 or size.Y <= 0 then self:hide(); return end
    if self.host and not self.root.Parent then self:build() end
    if self.root.Parent ~= board.frame then
        self.root.Parent, self.host, self.geometry = board.frame, board.frame, nil
    end
    local geometry = tostring(position) .. tostring(size) .. tostring(board.flipped) .. selected .. tostring(config.allArrows)
    if self.visible and self.geometry == geometry and self.rows == rows then return end
    self.geometry, self.rows, self.visible = geometry, rows, true
    self.root.Visible = true
    local function point(value) return UDim2.fromScale(value.X / size.X, value.Y / size.Y) end
    local function dimensions(width, height) return UDim2.fromScale(width / size.X, height / size.Y) end
    for rank, arrow in ipairs(self.arrows) do
        local row = rows[rank]
        local from = row and board.squares[Analysis.square(row.from)]
        local to = row and board.squares[Analysis.square(row.to)]
        local visible = from ~= nil and to ~= nil and (config.allArrows or selected == rank)
        for _, object in pairs(arrow) do object.Visible = visible end
        if visible then
            local start = from.AbsolutePosition - position + from.AbsoluteSize / 2
            local finish = to.AbsolutePosition - position + to.AbsoluteSize / 2
            local delta = finish - start
            if delta.Magnitude > 0 then
                local unit = delta.Unit
                local normal = Vector2.new(-unit.Y, unit.X)
                local cell = math.min(size.X, size.Y) / 8
                local tip = finish - unit * cell * 0.12
                local headLength = cell * 0.24
                local base = tip - unit * headLength
                local stemStart = start + unit * cell * 0.12
                local stemEnd = base + unit * 2
                local rotation = math.deg(math.atan2(delta.Y, delta.X))
                arrow.line.Position = point((stemStart + stemEnd) / 2)
                arrow.line.Size = dimensions((stemEnd - stemStart).Magnitude, math.max(4, cell * (rank == selected and 0.085 or 0.06)))
                arrow.line.Rotation = rotation
                arrow.line.BackgroundTransparency = rank == selected and 0.02 or 0.32
                arrow.head.Position = point((tip + base) / 2)
                arrow.head.Size = dimensions(cell * 0.30, headLength * 1.15)
                arrow.head.Rotation = rotation + 90
                local badge = finish + normal * cell * 0.24
                arrow.badge.Position, arrow.label.Position = point(badge), point(badge)
                arrow.badge.Size, arrow.label.Size = dimensions(24, 24), dimensions(24, 24)
            else
                for _, object in pairs(arrow) do object.Visible = false end
            end
        end
    end
end

function Overlay:Destroy()
    if self.root then self.root:Destroy(); self.root = nil end
    table.clear(self.objects)
    table.clear(self.arrows)
    self.visible = false
end

return Overlay
