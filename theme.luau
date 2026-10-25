-- By SyneX
local blue = Color3.fromRGB(102, 184, 255)
local background = Color3.fromRGB(16, 21, 28)
local panel = Color3.fromRGB(22, 29, 38)
local muted = Color3.fromRGB(151, 168, 188)

return {
    accent = blue,
    moves = {Color3.fromRGB(116, 235, 171), Color3.fromRGB(119, 182, 255), Color3.fromRGB(255, 202, 113)},
    moveHex = {"#74ebab", "#77b6ff", "#ffca71"},
    badge = Color3.fromRGB(13, 21, 32),
    windui = {
        Name = "Sky", Accent = background, Primary = blue,
        Background = background, WindowBackground = Color3.fromRGB(12, 17, 24),
        Text = Color3.fromRGB(232, 240, 249), Outline = Color3.fromRGB(42, 55, 70),
        Placeholder = Color3.fromRGB(119, 137, 157), ElementDesc = muted, WindowTopbarAuthor = muted,
        Button = blue, Icon = blue, Hover = blue, Toggle = blue, Slider = blue,
        SliderThumb = Color3.fromRGB(236, 246, 255),
        ElementBackground = panel, ElementBackgroundTransparency = 0,
        PanelBackground = background, PanelBackgroundTransparency = 0,
        SectionBox = panel, SectionBoxTransparency = 0,
        SectionBoxBackground = Color3.fromRGB(18, 25, 34), SectionBoxBackgroundTransparency = 0,
        TabBackgroundActive = blue, TabBackgroundActiveTransparency = 0.88,
    },
}
