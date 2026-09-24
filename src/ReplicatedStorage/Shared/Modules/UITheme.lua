-- One visual language for every screen UI: dark translucent "glass"
-- panels, rounded corners, a hairline stroke, one accent colour per
-- meaning (oxygen cyan, gold for loot, red for danger), and small helpers
-- so each script builds its widgets the same way.

local Workspace = game:GetService("Workspace")

local UITheme = {}

UITheme.Colors = {
	Glass = Color3.fromRGB(8, 20, 30),
	GlassLight = Color3.fromRGB(18, 38, 52),
	Stroke = Color3.fromRGB(150, 220, 255),
	Text = Color3.fromRGB(236, 246, 252),
	TextDim = Color3.fromRGB(150, 180, 196),
	Oxygen = Color3.fromRGB(70, 214, 255),
	OxygenDeep = Color3.fromRGB(40, 140, 255),
	Danger = Color3.fromRGB(255, 76, 88),
	Gold = Color3.fromRGB(255, 202, 90),
	Success = Color3.fromRGB(110, 236, 160),
}

UITheme.Rarity = {
	Commune = Color3.fromRGB(200, 208, 214),
	["Peu commune"] = Color3.fromRGB(90, 220, 130),
	Rare = Color3.fromRGB(80, 160, 255),
	["Très rare"] = Color3.fromRGB(190, 110, 255),
	["Légendaire"] = Color3.fromRGB(255, 190, 50),
}

UITheme.Fonts = {
	Title = Enum.Font.GothamBlack,
	Bold = Enum.Font.GothamBold,
	Medium = Enum.Font.GothamMedium,
	Body = Enum.Font.Gotham,
}

function UITheme.Corner(parent: Instance, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius and UDim.new(0, radius) or UDim.new(1, 0)
	corner.Parent = parent
	return corner
end

function UITheme.Stroke(parent: Instance, transparency: number?, color: Color3?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or UITheme.Colors.Stroke
	stroke.Transparency = transparency or 0.82
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function UITheme.Padding(parent: Instance, x: number, y: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, x)
	padding.PaddingRight = UDim.new(0, x)
	padding.PaddingTop = UDim.new(0, y)
	padding.PaddingBottom = UDim.new(0, y)
	padding.Parent = parent
	return padding
end

-- A glass panel: translucent dark fill with a soft vertical sheen.
function UITheme.Panel(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor or Vector2.zero
	frame.BackgroundColor3 = UITheme.Colors.Glass
	frame.BackgroundTransparency = 0.28
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local sheen = Instance.new("UIGradient")
	sheen.Rotation = 90
	sheen.Color = ColorSequence.new(UITheme.Colors.GlassLight, UITheme.Colors.Glass)
	sheen.Parent = frame
	UITheme.Corner(frame, 14)
	UITheme.Stroke(frame)
	return frame
end

function UITheme.Label(parent: Instance, name: string, text: string, font: Enum.Font, size: number, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = font
	label.TextSize = size
	label.TextColor3 = color or UITheme.Colors.Text
	label.Size = UDim2.new(1, 0, 0, size + 4)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

-- Scales a ScreenGui with the viewport so it reads the same on a phone
-- and a 4K monitor.
function UITheme.AutoScale(screenGui: ScreenGui)
	local scale = Instance.new("UIScale")
	scale.Parent = screenGui
	local function update()
		local camera = Workspace.CurrentCamera
		if camera then
			scale.Scale = math.clamp(camera.ViewportSize.Y / 900, 0.7, 1.25)
		end
	end
	update()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return scale
end

-- Upper case that also handles French accents: Luau's string.upper only
-- knows ASCII ("Récif" would come out "RéCIF").
local ACCENTS = {
	["à"] = "À", ["â"] = "Â", ["ä"] = "Ä", ["ç"] = "Ç", ["é"] = "É", ["è"] = "È", ["ê"] = "Ê", ["ë"] = "Ë",
	["î"] = "Î", ["ï"] = "Ï", ["ô"] = "Ô", ["ö"] = "Ö", ["ù"] = "Ù", ["û"] = "Û", ["ü"] = "Ü", ["œ"] = "Œ", ["æ"] = "Æ",
}
function UITheme.Upper(text: string): string
	local upper = string.upper(text)
	for lower, capital in pairs(ACCENTS) do
		upper = string.gsub(upper, lower, capital)
	end
	return upper
end

-- "12 480" style thousands separator.
function UITheme.FormatNumber(value: number): string
	local text = tostring(math.floor(value + 0.5))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

return UITheme
