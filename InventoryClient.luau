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
local ClickSound = game.SoundService:WaitForChild("ui_click")
local HoverSound = game.SoundService:WaitForChild("ui_hover")

--[[
	This function initializes the inventory (called when player joins).
	It creates all the hotbar slots and indexes them in a table.
	
	Keybinds are also defined here (callbacks from Keybinds module) and currently allows inventory UI toggle
	with [Tab] and equipping hotbar slots with keys 1-9.
]]
function Inventory.new()
	local self = setmetatable({}, Inventory)
	self.HotbarSlots = {}
	self.InventorySlots = {}
	
	self.IsOpen = false
	
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
	This method is for updating all the inventory slots, which is called
	from the server every time a change is made in the inventory.
	
	To summarize, it loops through the passed inventory from the server
	and updates the ui accordingly.
	
	Hotbar visibility is also handled here, which just hides a slot if its empty.
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
	
	for index, slot in ipairs(self.HotbarSlots) do
		if slot.Item or self.IsOpen then
			slot:SetVisible(true)
		else
			slot:SetVisible(false)
		end
	end
end

--[[
	This method is for equipping an item from the hotbar, called when a player presses
	the matching key.
	
	It grabs the hotbar slot from the key that was pressed, setting up the new equipped item
	by putting it in the character (the objects are tools), and updating the ui to visualize the change.
	
	When called on a slot thats already equipped, it unequips it instead.
]]
function Inventory:Equip(index)
	InventoryEvent:FireServer("Equip", index)
	
	local slot = self.HotbarSlots[index]
	if not slot then return end
	if not slot.Visible then return end
	
	local item = slot.Item
	if not item then return end
	
	local oldSlot = self.HotbarSlots[self.EquippedIndex]

	if self.EquippedItem then
		if self.EquippedIndex == index then
			
			self.EquippedItem.Parent = plr.Backpack
			self.EquippedItem = nil
			self.EquippedIndex = nil

			slot.UI:WaitForChild("Fade").ImageColor3 = Color3.fromRGB(0, 0, 0)
		else
			self.EquippedItem.Parent = plr.Backpack
			self.EquippedItem = nil 

			self.EquippedItem = plr.Backpack:FindFirstChild(item)
			if not self.EquippedItem then return end
			self.EquippedItem.Parent = plr.Character
			self.EquippedIndex = index
			
			if oldSlot then
				oldSlot.UI:WaitForChild("Fade").ImageColor3 = Color3.fromRGB(0, 0, 0)
			end
			slot.UI:WaitForChild("Fade").ImageColor3 = Color3.fromRGB(125, 125, 125)
		end
	else
		self.EquippedItem = plr.Backpack:FindFirstChild(item)
		if not self.EquippedItem then return end
		self.EquippedItem.Parent = plr.Character
		self.EquippedIndex = index

		if oldSlot then
			oldSlot.UI:WaitForChild("Fade").ImageColor3 = Color3.fromRGB(0, 0, 0)
		end
		slot.UI:WaitForChild("Fade").ImageColor3 = Color3.fromRGB(125, 125, 125)
	end
end

--[[
	This method handles setup for slot dragging (called when a slot is made).
	Hovering/Dehovering gives some visual feedback, and also creates/destroys a ghost ui for dragging.
]]
function Inventory:SetupHover(slot)
	slot.UI.MouseEnter:Connect(function()
		if not self.IsOpen then return end
		if not slot.Item then return end
		if self.Dragging then return end
		if slot.Index then
			if slot.Index == self.EquippedIndex then return end
		end
		slot.UI:WaitForChild('Fade').ImageColor3 = Color3.fromRGB(125, 125, 125)
		HoverSound:Play()
		slot.Hovering = true
		self:CreateDragUI(slot)
	end)

	slot.UI.MouseLeave:Connect(function()
		if not self.IsOpen then return end
		if self.Dragging then return end
		if not slot.Hovering then return end
		slot.UI:WaitForChild('Fade').ImageColor3 = Color3.fromRGB(0,0,0)
		slot.Hovering = false
		if self.DragUI then self.DragUI:Destroy() end
	end)
end

--[[
	This is the main method for setting up the ghost UI for dragging slots.
	It creates a seamless copy over the hovered slot in a separate frame specifically for dragging.
	A UI Drag Detector is also made inside the ghost UI and hooked up to functions
	for initially dragging and releasing the drag.
]]
function Inventory:CreateDragUI(slot)
	self.DragUI = DragTemplate:Clone()
	self.DragUI.Name = "Drag"

	local dragBox = self.DragUI:WaitForChild("Box")
	dragBox:WaitForChild("ItemName").Text = slot.Item or ""
	dragBox:WaitForChild("SlotNumber").Text = slot.Index or ""
	
	self.DragUI.Parent = DragBounds

	local abs = slot.UI.AbsolutePosition
	local parentAbs = self.DragUI.Parent.AbsolutePosition

	self.DragUI.Position = UDim2.fromOffset(abs.X - parentAbs.X, abs.Y - parentAbs.Y)

	self.DragUI:WaitForChild("Fade").ImageColor3 = Color3.fromRGB(125, 125, 125)
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
	Sets some status values and updates the UI to simulate dragging a slot.
]]
function Inventory:DragStart(slot)
	self.Dragging = true
	slot.Hovering = false

	local dragBox = self.DragUI:WaitForChild("Box")
	local dragItemName = dragBox:WaitForChild("ItemName")
	local dragSlotNumber = dragBox:WaitForChild("SlotNumber")
	local dragFade = self.DragUI:WaitForChild("Fade")
	
	local slotItemName = slot.UI:WaitForChild("Box"):WaitForChild("ItemName")
	local slotFade = slot.UI:WaitForChild("Fade")
	
	dragItemName.Text = slot.Item or ""
	dragSlotNumber.Text = slot.Index or ""

	ClickSound:Play()

	if slot.Index then
		dragSlotNumber.Text = ""
		slotItemName.Text = ""
	else
		slot.UI.Visible = false
	end
	slotFade.ImageColor3 = Color3.fromRGB(0,0,0)
end

--[[
	This method handles the logic when the player stops dragging the ghost UI.
	
	The released position is taken and calculated to find where the slot is being dragged to,
	which can either be the inventory, a hotbar slot, or an invalid zone.
	
	Based on where its dropped, the slot either reverts back to its original state or
	the new position is fired to the server to validate and update the slots (which fires the update method).
]]
function Inventory:DragEnd(slot, inputPosition)
	self.Dragging = false

	local EndPoint

	local dragBox = self.DragUI:WaitForChild("Box")
	local dragItemName = dragBox:WaitForChild("ItemName")
	local dragSlotNumber = dragBox:WaitForChild("SlotNumber")
	local dragFade = self.DragUI:WaitForChild("Fade")

	local slotItemName = slot.UI:WaitForChild("Box"):WaitForChild("ItemName")
	local slotFade = slot.UI:WaitForChild("Fade")

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