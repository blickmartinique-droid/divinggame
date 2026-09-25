-- Dresses a character in its dive gear, server-side so everyone sees it:
-- the tank (or twin set) strapped on the back with its valve and hose, a
-- mask (or, with the abyssal suit, a brass helmet), fins on the feet, a
-- lamp on the head that really lights the way, and the suit itself --
-- the limbs recoloured in neoprene with an accent stripe (clothing is set
-- aside while a suit is worn and put back without one).
-- Works with R15 and R6 rigs. Every piece is welded, massless and
-- non-colliding, in a "DiveGear" folder rebuilt on each call.

local EquipmentVisuals = {}

local SKIN_ATTRIBUTE = "DiveGearSkin"

local LIMBS_R15 = {
	Torso = { "UpperTorso", "LowerTorso" },
	Arms = { "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm" },
	Legs = { "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg" },
	Feet = { "LeftFoot", "RightFoot" },
}
local LIMBS_R6 = {
	Torso = { "Torso" },
	Arms = { "Left Arm", "Right Arm" },
	Legs = { "Left Leg", "Right Leg" },
	Feet = {},
}

local function findPart(character: Model, names: { string }): BasePart?
	for _, name in ipairs(names) do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

local function gear(folder: Instance, attach: BasePart, name: string, size: Vector3, offset: CFrame, material: Enum.Material, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Shape = shape or Enum.PartType.Block
	p.Material = material
	p.Color = color
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.CFrame = attach.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attach
	weld.Part1 = p
	weld.Parent = p
	p.Parent = folder
	return p
end

-- Recolours (or restores) the body under the suit.
local function dressSuit(character: Model, suit)
	local limbs = character:FindFirstChild("UpperTorso") and LIMBS_R15 or LIMBS_R6
	local stash = character:FindFirstChild("StoredClothing")
	local wearing = suit and suit.Color ~= nil
	for _, group in pairs(limbs) do
		for _, name in ipairs(group) do
			local limb = character:FindFirstChild(name)
			if limb and limb:IsA("BasePart") then
				local skin = limb:GetAttribute(SKIN_ATTRIBUTE)
				if wearing then
					if not skin then
						limb:SetAttribute(SKIN_ATTRIBUTE, limb.Color)
					end
					limb.Color = suit.Color
				elseif skin then
					limb.Color = skin
					limb:SetAttribute(SKIN_ATTRIBUTE, nil)
				end
			end
		end
	end
	if wearing then
		if not stash then
			stash = Instance.new("Folder")
			stash.Name = "StoredClothing"
			stash.Parent = character
		end
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") then
				child.Parent = stash
			end
		end
	elseif stash then
		for _, child in ipairs(stash:GetChildren()) do
			child.Parent = character
		end
		stash:Destroy()
	end
end

-- `items`: { Tank = item, Suit = item, Fins = item, Lamp = item } from
-- EquipmentConfig.
function EquipmentVisuals.Apply(character: Model, items)
	local old = character:FindFirstChild("DiveGear")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "DiveGear"
	folder.Parent = character

	local torso = findPart(character, { "UpperTorso", "Torso" })
	local head = findPart(character, { "Head" })
	if not torso or not head then
		return folder
	end
	local suit = items.Suit
	dressSuit(character, suit)

	-- Tank(s) on the back (+Z is the back of a character's torso).
	local tank = items.Tank
	if tank then
		local back = torso.Size.Z / 2 + 0.55
		local xs = tank.Twin and { -0.55, 0.55 } or { 0 }
		for _, x in ipairs(xs) do
			gear(folder, torso, "GearTank", Vector3.new(2.4, 1.05, 1.05), CFrame.new(x, 0.1, back) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Metal, tank.Color, Enum.PartType.Cylinder)
			gear(folder, torso, "GearTankCap", Vector3.new(0.3, 1.1, 1.1), CFrame.new(x, 1.25, back) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Metal, Color3.fromRGB(60, 60, 66), Enum.PartType.Cylinder)
		end
		gear(folder, torso, "GearValve", Vector3.new(0.5, 0.45, 0.45), CFrame.new(0, 1.55, back) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Metal, Color3.fromRGB(190, 190, 196), Enum.PartType.Cylinder)
		-- Harness straps over the shoulders and round the waist.
		for _, x in ipairs({ -0.45, 0.45 }) do
			gear(folder, torso, "GearStrap", Vector3.new(0.25, torso.Size.Y + 0.05, 0.08), CFrame.new(x, 0, -torso.Size.Z / 2 - 0.04), Enum.Material.Fabric, Color3.fromRGB(24, 24, 28))
		end
		gear(folder, torso, "GearBelt", Vector3.new(torso.Size.X + 0.1, 0.3, torso.Size.Z + 0.1), CFrame.new(0, -torso.Size.Y / 2 + 0.2, 0), Enum.Material.Fabric, Color3.fromRGB(24, 24, 28))
		-- Regulator hose from the valve round to the mouth.
		gear(folder, head, "GearHose", Vector3.new(0.18, 0.18, 1.6), CFrame.new(0.55, -0.55, 0.1) * CFrame.Angles(0.5, 0, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(20, 20, 24))
		gear(folder, head, "GearRegulator", Vector3.new(0.45, 0.35, 0.3), CFrame.new(0, -0.4, -head.Size.Z / 2 - 0.1), Enum.Material.SmoothPlastic, Color3.fromRGB(30, 30, 34))
	end

	-- Suit accent stripes along the sides of the torso.
	if suit and suit.Accent then
		for _, x in ipairs({ -1, 1 }) do
			gear(folder, torso, "GearStripe", Vector3.new(0.06, torso.Size.Y * 0.9, 0.3), CFrame.new(x * (torso.Size.X / 2 + 0.03), 0, 0), Enum.Material.SmoothPlastic, suit.Accent)
		end
	end

	-- Mask, or the brass helmet of the abyssal suit.
	if suit and suit.Id == "Abyssal" then
		local helmet = gear(folder, head, "GearHelmet", Vector3.new(2.3, 2.3, 2.3), CFrame.new(0, 0.1, 0), Enum.Material.Metal, suit.Color, Enum.PartType.Ball)
		helmet.Transparency = 0
		local port = gear(folder, head, "GearHelmetPort", Vector3.new(0.2, 1.1, 1.1), CFrame.new(0, 0.1, -1.1) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Glass, Color3.fromRGB(170, 220, 240), Enum.PartType.Cylinder)
		port.Transparency = 0.45
		gear(folder, head, "GearHelmetRing", Vector3.new(0.25, 1.4, 1.4), CFrame.new(0, 0.1, -1.02) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Metal, suit.Accent or suit.Color, Enum.PartType.Cylinder)
		gear(folder, torso, "GearCollar", Vector3.new(0.6, 2.4, 2.4), CFrame.new(0, torso.Size.Y / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Metal, suit.Color, Enum.PartType.Cylinder)
	else
		local visor = gear(folder, head, "GearMask", Vector3.new(1.1, 0.55, 0.2), CFrame.new(0, 0.2, -head.Size.Z / 2 - 0.08), Enum.Material.Glass, Color3.fromRGB(150, 210, 240))
		visor.Transparency = 0.45
		gear(folder, head, "GearMaskFrame", Vector3.new(1.25, 0.7, 0.14), CFrame.new(0, 0.2, -head.Size.Z / 2 - 0.02), Enum.Material.SmoothPlastic, Color3.fromRGB(26, 26, 30))
		gear(folder, head, "GearMaskStrap", Vector3.new(head.Size.X + 0.08, 0.18, head.Size.Z + 0.08), CFrame.new(0, 0.2, 0), Enum.Material.Fabric, Color3.fromRGB(26, 26, 30))
	end

	-- Fins.
	local fins = items.Fins
	if fins and fins.Color then
		local feet = character:FindFirstChild("UpperTorso") and { "LeftFoot", "RightFoot" } or { "Left Leg", "Right Leg" }
		for _, name in ipairs(feet) do
			local foot = character:FindFirstChild(name)
			if foot and foot:IsA("BasePart") then
				local length = 1.6 + (fins.SpeedMultiplier - 1) * 3
				gear(folder, foot, "GearFin", Vector3.new(foot.Size.X + 0.2, 0.12, length), CFrame.new(0, -foot.Size.Y / 2 + 0.05, -length / 2 + 0.2), Enum.Material.SmoothPlastic, fins.Color)
			end
		end
	end

	-- Head lamp with a real beam.
	local lamp = items.Lamp
	if lamp and lamp.LampRange and lamp.LampRange > 0 then
		local body = gear(folder, head, "GearLamp", Vector3.new(0.8, 0.45, 0.45), CFrame.new(head.Size.X / 2 + 0.15, 0.35, -0.2) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Metal, lamp.Color or Color3.fromRGB(40, 40, 46), Enum.PartType.Cylinder)
		local lens = gear(folder, head, "GearLampLens", Vector3.new(0.4, 0.4, 0.1), CFrame.new(head.Size.X / 2 + 0.15, 0.35, -0.62), Enum.Material.Neon, Color3.fromRGB(255, 244, 210))
		local beam = Instance.new("SpotLight")
		beam.Name = "LampBeam"
		beam.Face = Enum.NormalId.Front
		beam.Range = lamp.LampRange
		beam.Brightness = lamp.LampBrightness
		beam.Angle = 55
		beam.Color = Color3.fromRGB(255, 244, 220)
		beam.Shadows = true
		beam.Parent = lens
		local glow = Instance.new("PointLight")
		glow.Name = "LampGlow"
		glow.Range = math.min(14, lamp.LampRange * 0.3)
		glow.Brightness = 0.6
		glow.Color = Color3.fromRGB(255, 244, 220)
		glow.Parent = body
	end
	return folder
end

return EquipmentVisuals
