--InventoryClient.lua
--by DrZeph

--[[
	This module script manages the client side of the inventory ui.
	
	Features:
	- Hotbar slot swapping and visibility
	- Item equipping/unequipping
	- Drag and drop for moving item slots
	
]]

local Inventory = {}
Inventory.__index = Inventory

--Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local GuiService = game:GetService('GuiService')
local SoundService = game:GetService("SoundService")
local HotbarSlot = require(script:WaitForChild("HotbarSlot"))
local InventorySlot = require(script:WaitForChild("InventorySlot"))
local Keybinds = require(script:WaitForChild('Keybinds'))

--Misc
local plr = Players.LocalPlayer
local InventoryEvent = ReplicatedStorage:WaitForChild("InventoryEvent")

--UI
local PlayerGui = plr.PlayerGui
local UI = PlayerGui:WaitForChild("UI")
local InventoryUI = UI:WaitForChild('Inventory')
local Header = InventoryUI:WaitForChild('Header')
local Main = InventoryUI:WaitForChild('Main')
local DragBounds = UI:WaitForChild('Drag Bounds')
local DragTemplate = DragBounds:WaitForChild('Template')

--SFX
local ClickSound = SoundService:WaitForChild("ui_click")
local HoverSound = SoundService:WaitForChild("ui_hover")

--Colors
local Black = Color3.fromRGB(0, 0, 0)
local Grey = Color3.fromRGB(125, 125, 125)

--[[
	This function is called when the client first loads in for a player.
	
	The slot table variables are made to keep track of the slots throughout the script.
	I make a for loop to produce all of the hotbar slot objects with an assigned index.
	Next are the keybinds, which I setup in callbacks for easier use. The first one for general inventory 
	keybinds, which is currently only used for toggling the inventory, and the second one for all the 
	hotbar slots, solely for equipping the individual slots.
]]
function Inventory.Init()
	local self = setmetatable({}, Inventory)
	self.HotbarSlots = {}
	self.InventorySlots = {}
	
	self.IsOpen = false --Used for toggling the UI and keeping track of its state
	
	for i = 1,9 do
		local slot = HotbarSlot.new(i)
		self.HotbarSlots[i] = slot
		
		self:SetupHover(slot)
	end
	
	Keybinds.BindInventory(function(input)
		if input == "ToggleInventory" then
			self.IsOpen = not self.IsOpen
			InventoryUI.Visible = self.IsOpen
			
			for index, slot in ipairs(self.HotbarSlots) do
				if slot.Item or self.IsOpen then
					slot:SetVisible(true)
				else
					slot:SetVisible(false)
				end
			end
		end
	end)
	
	Keybinds.BindHotbarInputs(function(input)
		self:Equip(input)
	end)
	
	return self
end

--[[
	This method is for updating all the inventory and hotbar slots, which is called
	from the server every time a change is made in the inventory.
	
	The first loop goes through the hotbar slots, filling and emptying the slot whether the new inventory
	has an item or not.
	The second and third loops are for the inventory, the second one making all new slots for each new item
	in the new inventory, and the third one removing all slots that no longer exist in the new inventory.
]]
function Inventory:Update(Inv)
	--Hotbar Slots
	for index, slot in ipairs(Inv.Hotbar) do
		if slot.Item then
			self.HotbarSlots[index]:Fill(slot)
		else
			self.HotbarSlots[index]:Empty()
		end
	end
	--Inventory Slots
	for id, item in pairs(Inv.Inventory) do
		if not self.InventorySlots[id] then
			self.InventorySlots[id] = InventorySlot.new(item, id)
			self:SetupHover(self.InventorySlots[id])
		end
	end
	for id, slot in pairs(self.InventorySlots) do
		if Inv.Inventory[id] then continue end
		slot:Destroy()
		self.InventorySlots[id] = nil
	end
end

--[[
	This method is for equipping an item from the hotbar, called when a player presses
	the matching key, sent with the index of that key.
	
	I first check if theres already an item equipped to handle any old slots. If there is, I check whether or
	not the new slot being entered is the same as the old slot, which I simply unequip if it is (so the player
	can unequip items by pressing the same button), and if it isn't I unequip the old slot and equip the 
	new slot.
	
	If there isn't already an item equipped, I only equip the new item.
]]
function Inventory:Equip(index)
	InventoryEvent:FireServer("Equip", index)
	
	local slot = self.HotbarSlots[index]
	if not slot then return end
	
	local item = slot.Item
	if not item then return end
	
	local oldSlot = self.HotbarSlots[self.EquippedIndex]
	
	local slotFade = slot.UI.Fade
	local oldSlotFade = oldSlot and oldSlot.UI.Fade

	if self.EquippedItem then
		if self.EquippedIndex == index then
			
			self.EquippedItem.Parent = plr.Backpack
			self.EquippedItem = nil
			self.EquippedIndex = nil

			slotFade.ImageColor3 = Black
		else
			self.EquippedItem.Parent = plr.Backpack
			self.EquippedItem = nil 

			self.EquippedItem = plr.Backpack:FindFirstChild(item)
			if not self.EquippedItem then return end
			self.EquippedItem.Parent = plr.Character
			self.EquippedIndex = index
			
			if oldSlotFade then
				oldSlotFade.ImageColor3 = Black
			end
			slotFade.ImageColor3 = Grey
		end
	else
		self.EquippedItem = plr.Backpack:FindFirstChild(item)
		if not self.EquippedItem then return end
		self.EquippedItem.Parent = plr.Character
		self.EquippedIndex = index

		if oldSlotFade then
			oldSlotFade.ImageColor3 = Black
		end
		slotFade.ImageColor3 = Grey
	end
end

--[[
	This method handles setup for slot dragging (called when a slot is made).
	
	The callbacks trigger whenever a player's mouse enters or leaves any slot in the inventory and hotbar, to
	setup drag detection.
	
	When it enters, it makes sure the slot is allowed to be dragged, then it updates the visuals to make the ui
	look responsive, and creates a drag ui (so the player can drag it if they need to) identical to the slot 
	and positions it perfectly over it to mask it as the original.
	When it leaves, it does similar checks, and reverts the slots visuals back to normal and cleans up the 
	drag ui.
]]
function Inventory:SetupHover(slot)
	local fade = slot.UI.Fade
	
	slot.UI.MouseEnter:Connect(function()
		if not self.IsOpen then return end
		if not slot.Item then return end
		if self.Dragging then return end
		if slot.Index then
			if slot.Index == self.EquippedIndex then return end
		end
		fade.ImageColor3 = Grey
		HoverSound:Play()
		slot.Hovering = true
		self:CreateDragUI(slot)
	end)

	slot.UI.MouseLeave:Connect(function()
		if not self.IsOpen then return end
		if self.Dragging then return end
		if not slot.Hovering then return end
		fade.ImageColor3 = Black
		slot.Hovering = false
		if self.DragUI then self.DragUI:Destroy() end
	end)
end

--[[
	This is the main method for setting up the ghost UI for dragging slots.
	
	A template is cloned to make a ghost UI and customized to match to slot. The ghost UI is positioned
	seamlessly over the target slot by calculating its offset relative to the drag bounds, to disguise it 
	as the target. A UI Drag Detector is attached to the ghost UI and linked up to 2 methods to handle 
	when the drag starts and ends.
]]
function Inventory:CreateDragUI(slot)
	self.DragUI = DragTemplate:Clone()
	self.DragUI.Name = "Drag"

	local dragBox = self.DragUI:WaitForChild("Box")
	dragBox.ItemName.Text = slot.Item or ""
	dragBox.SlotNumber.Text = slot.Index or ""
	
	self.DragUI.Parent = DragBounds

	local abs = slot.UI.AbsolutePosition
	local parentAbs = self.DragUI.Parent.AbsolutePosition

	self.DragUI.Position = UDim2.fromOffset(abs.X - parentAbs.X, abs.Y - parentAbs.Y)

	self.DragUI.Fade.ImageColor3 = Color3.fromRGB(125, 125, 125)
	self.DragUI.Visible = true

	local UDD = Instance.new("UIDragDetector", self.DragUI)
	UDD.BoundingUI = DragBounds
	UDD.BoundingBehavior = Enum.UIDragDetectorBoundingBehavior.HitPoint
	UDD.ReferenceUIInstance = DragBounds
	UDD.Parent = self.DragUI

	UDD.DragStart:Connect(function()
		self:DragStart(slot)
	end)

	UDD.DragEnd:Connect(function(inputPosition)
		self:DragEnd(slot, inputPosition)
	end)
end

--[[
	This method handles the logic when the player first starts to drag the ghost UI.
	
	It sets the dragging state, then hides part of the original slot to simulate it being picked up.
	If its from the inventory, the actual slot is hidden. If its from the hotbar, the slot is visually cleared
	out to look temporarily empty. The original slot's fade is reset regardless.
]]
function Inventory:DragStart(slot)
	self.Dragging = true
	slot.Hovering = false

	local dragBox = self.DragUI.Box
	local dragSlotNumber = dragBox.SlotNumber
	
	local slotItemName = slot.UI:WaitForChild("Box"):WaitForChild("ItemName")
	local slotFade = slot.UI:WaitForChild("Fade")

	ClickSound:Play()

	if slot.Index then
		dragSlotNumber.Text = ""
		slotItemName.Text = ""
	else
		slot.UI.Visible = false
	end
	slotFade.ImageColor3 = Black
end

--[[
	This method handles the logic when the player stops dragging the ghost UI.
	
	Taking the position provided by the ui drag detector, I find all the gui there and identify if one of them
	is a hotbar slot the inventory.
	
	If it's the inventory, I check whether the original was from the hotbar or not, alerting the server to 
	update if so, or otherwise bringing back the original slot, and finally getting rid of the ghost UI.
	
	If its a hotbar slot, I see if the original was also a hotbar slot. If it is, I check if both slots are 
	matching (if the player dragged the slot into itself) and revert it back to normal or alert the server to
	update it if the slot is a different one. If the original isn't a hotbar slot, I just alert the server to
	update. Finally, I destroy the ghost UI.
	
	If its neither a hotbar slot or the inventory (no valid ui), I just revert the original UI back to normal
	and destroy the ghost UI.
]]
function Inventory:DragEnd(slot, inputPosition)
	self.Dragging = false

	local EndPoint
	local slotItemName = slot.UI:WaitForChild("Box"):WaitForChild("ItemName")

	local inset = GuiService:GetGuiInset()
	local uiX = inputPosition.X - inset.X
	local uiY = inputPosition.Y - inset.Y

	local objects = PlayerGui:GetGuiObjectsAtPosition(uiX, uiY)
	for _, gui in pairs(objects) do
		if gui:HasTag("InventoryDropoff") then
			EndPoint = "Inventory"
			break
		elseif gui:GetAttribute("Slot") then
			EndPoint = gui:GetAttribute("Slot")
			break
		end
	end

	if EndPoint == "Inventory" then
		if slot.Index then
			InventoryEvent:FireServer("Move", slot, "Inventory")
		else
			slot.UI.Visible = true
		end
		self.DragUI:Destroy()
	elseif type(EndPoint) == "number" then
		if slot.Index then
			if slot.Index == EndPoint then
				slotItemName.Text = slot.Item
			else
				InventoryEvent:FireServer("Move", slot, "Hotbar", EndPoint)
			end
		else
			InventoryEvent:FireServer("Move", slot, "Hotbar", EndPoint)
		end
		self.DragUI:Destroy()
	else
		slotItemName.Text = slot.Item
		slot.UI.Visible = true
		self.DragUI:Destroy()
	end
end

return Inventory
