-- Copyright (C) 2020 David Vogel
--
-- This file is part of D3bot.
--
-- D3bot is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- D3bot is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with D3bot.  If not, see <http://www.gnu.org/licenses/>.

local D3bot = D3bot
local UTIL = D3bot.Util
local LOCOMOTION_HANDLERS = D3bot.LocomotionHandlers

-- Add new locomotion handler class.
LOCOMOTION_HANDLERS.JUMP_AND_FALL = LOCOMOTION_HANDLERS.JUMP_AND_FALL or {}
local THIS_LOCO_HANDLER = LOCOMOTION_HANDLERS.JUMP_AND_FALL

------------------------------------------------------
--		Static
------------------------------------------------------

-- Make all methods and properties of the class available to its objects.
THIS_LOCO_HANDLER.__index = THIS_LOCO_HANDLER

---Creates a new instance of a general locomotion handler for bots that handles controlled falling from edges/walls and jumping onto edges.
---Works best with locomotion types: "Wall".
---@param maxJumpHeight number
---@param maxFallHeight number
---@return table
function THIS_LOCO_HANDLER:New(maxJumpHeight, maxFallHeight)
	local handler = setmetatable({
		MaxJumpHeight = maxJumpHeight, -- Max. jump height that a bot can achieve by crouch jumping.
		MaxFallHeight = maxFallHeight, -- Max. height that the bot is allowed to fall down.
	}, self)

	return handler
end

------------------------------------------------------
--		Methods
------------------------------------------------------

---Returns the cache for the given pathElement (from pathElements at index), if needed this will regenerate the cache.
---The cache contains all values to easily control the bot through the pathElement.
---@param index integer @pathElements index
---@param pathElements D3botPATH_ELEMENT[]
---@return table
function THIS_LOCO_HANDLER:GetPathElementCache(index, pathElements)
	local pathElement = pathElements[index]
	local cache = pathElement.Cache
	if cache then return cache end

	-- Regenerate cache.
	local cache = {}
	pathElement.Cache = cache

	-- A flag indicating if the cache contains correct or malformed data.
	-- Changing this to false will not cause the cache to be rebuilt.
	cache.IsValid = true

	return cache
end

---Overrides the base pathfinding cost (in engine units) for the given path fragment.
---If no method is defined, the distance of the path fragment will be used as metric.
---Any time based cost would need to be transformed into a distance based cost in here (Relative to normal walking speed).
---This is used in pathfinding and should be as fast as possible.
---@param pathFragment D3botPATH_FRAGMENT
---@return number cost
function THIS_LOCO_HANDLER:CostOverride(pathFragment)
	-- Assume near 0 cost for falling or jumping, which is somewhat realistic.
	return 0
end

---Returns whether the bot can move on the path fragment described by pathFragment.
---entityData is a map that contains pathfinding metadata (Parent entity, gScore, ...).
---Leaving this undefined has the same result as returning true.
---This is used in pathfinding and should be as fast as possible.
---@param pathFragment D3botPATH_FRAGMENT
---@param entityData table
---@return boolean
function THIS_LOCO_HANDLER:CanNavigate(pathFragment, entityData)
	-- Start navmesh entity of the path fragment.
	local entityA = pathFragment.From

	-- TODO: Get max diff for non parallel edges
	local posA, posB = pathFragment.FromPos, pathFragment.ToPos
	local zDiff = posB[3] - posA[3]
	local sideLengthSqr = (posB - posA):Length2DSqr()

	-- Check if the nodes are somewhat aligned vertically.
	if sideLengthSqr > zDiff * zDiff then
		return false
	end

	-- Get zDiff of the previous element, or nil.
	-- A positive zDiff means that the current part is just a fraction of the total jump path.
	-- A negative zDiff means that the current part is just a fraction of the total fall path.
	-- nil means that this is the only or initial jump/fall path.
	local previousEntity = entityData[entityA].From
	local previousZDiff = previousEntity and entityData[previousEntity].ZDiff or nil

	-- A bot can either fall or jump in one go, a mix isn't allowed.
	if previousZDiff and UTIL.PositiveNumber(zDiff) ~= UTIL.PositiveNumber(previousZDiff) then return false end

	-- Check if bot is in the possible and or safe zone.
	local totalZDiff = zDiff + (previousZDiff or 0)
	if totalZDiff > -self.MaxFallHeight and totalZDiff < self.MaxJumpHeight then
		-- Store total vertical diff for the next node that may use it.
		entityData[entityA].ZDiff = totalZDiff
		return true
	end

	-- Bot can neither jump up that edge, nor can it safely fall down.
	return false
end

---Draw the pathElement (from pathElements at index) into a 3D rendering context.
---@param index integer @pathElements index
---@param pathElements D3botPATH_ELEMENT[]
function THIS_LOCO_HANDLER:Render3D(index, pathElements)
	local pathElement = pathElements[index]
	local pathFragment = pathElement.PathFragment
	local fromPos, toPos = pathFragment.FromPos, pathFragment.ToPos
	render.DrawBeam(fromPos, toPos, 5, 0, 1, Color(0, 255, 0, 255))

	-- Draw end condition planes
	render.DrawQuadEasy(toPos, -pathFragment.OrthogonalOutside, 50, 50, Color(255, 0, 255, 128))
end
