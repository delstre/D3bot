local meta = FindMetaTable("Player")

function meta:D3bot_GetAttackPosOrNil(fraction)
	local mem = self.D3bot_Mem
	local tgt = mem.TgtOrNil
	if not IsValid(tgt) then return end
	return tgt:IsPlayer() and LerpVector(fraction or 0.75, tgt:GetPos(), tgt:EyePos()) or tgt:WorldSpaceCenter()
end

function meta:D3bot_GetAttackPosOrNil(fraction)
	local mem = self.D3bot_Mem
	local tgt = mem.TgtOrNil
	if not IsValid(tgt) then return end
	return tgt:IsPlayer() and LerpVector(fraction or 0.75, tgt:GetPos(), tgt:EyePos()) or tgt:WorldSpaceCenter()
end

-- Linear extrapolated position of the player entity
function meta:D3bot_GetAttackPosOrNilFuture(fraction, t)
	local mem = self.D3bot_Mem
	local tgt = mem.TgtOrNil
	if not IsValid(tgt) then return end
	return tgt:IsPlayer() and LerpVector(fraction or 0.75, tgt:GetPos(), tgt:EyePos()) + tgt:GetVelocity()*t or tgt:WorldSpaceCenter()
end

-- Linear extrapolated position of the player entity. (Works with platform physics)
function meta:D3bot_GetAttackPosOrNilFuturePlatforms(fraction, t)
	local mem = self.D3bot_Mem
	local tgt = mem.TgtOrNil
	if not IsValid(tgt) then return end
	local phys = tgt:GetPhysicsObject()
	if not IsValid(phys) then return end
	return tgt:IsPlayer() and LerpVector(fraction or 0.75, tgt:GetPos(), tgt:EyePos()) + phys:GetVelocity()*t or tgt:WorldSpaceCenter()
end

function meta:D3bot_GetViewCenter()
	return self:GetPos() + (self:Crouching() and self:GetViewOffsetDucked() or self:GetViewOffset())
end

function meta:D3bot_CanPounceToPos(pos)
	if not pos then return end
	
	local initVel
	if self:GetActiveWeapon() and self:GetActiveWeapon().PounceVelocity then
		initVel = (1 - 0.5 * (self:GetLegDamage() / GAMEMODE.MaxLegDamage)) * self:GetActiveWeapon().PounceVelocity
	else
		return
	end
	
	local selfPos = self:GetPos()--LerpVector(0.75, self:GetPos(), self:EyePos())
	local trajectories = D3bot.GetTrajectories(initVel, selfPos, pos, 8)
	local resultTrajectories = {}
	for _, trajectory in ipairs(trajectories) do
		local lastPoint = nil
		local hit = false
		for _, point in ipairs(trajectory.points) do
			if lastPoint then
				local tr = util.TraceEntity({start = point, endpos = lastPoint, filter = player.GetAll()}, self)
				if tr.Hit then
					hit = true
					break
				end
			end
			lastPoint = point
		end
		if not hit then
			table.insert(resultTrajectories, trajectory)
		end
	end
	if #resultTrajectories == 0 then resultTrajectories = nil end
	return resultTrajectories
end

function meta:D3bot_CanSeeTarget()
	local attackPos = self:D3bot_GetAttackPosOrNil()
	if not attackPos then return false end
	local mem = self.D3bot_Mem
	if mem.TgtNodeOrNil and mem.NodeOrNil ~= mem.TgtNodeOrNil and mem.TgtNodeOrNil.Params.See == "Disabled" then return false end
	local tr = D3bot.BotSeeTr
	tr.start = self:D3bot_GetViewCenter()
	tr.endpos = attackPos
	tr.filter = player.GetAll()
	return attackPos and not util.TraceHull(tr).Hit
end

function meta:D3bot_FaceTo(pos, origin, lerpFactor, offshootFactor)
	local mem = self.D3bot_Mem
	mem.Angs = LerpAngle(lerpFactor, mem.Angs, (pos - origin):Angle() + mem.AngsOffshoot * (offshootFactor or 1))
end

function meta:D3bot_RerollClass()
	if not GAMEMODE:GetWaveActive() then return end
	if self:GetZombieClassTable().Name == "Zombie Torso" then return end
	if GAMEMODE.ZombieEscape then return end
	local zombieClasses = {}
	for _, class in ipairs(D3bot.BotClasses) do
		local zombieClass = GAMEMODE.ZombieClasses[class]
		if zombieClass then
			if not zombieClass.Locked and (zombieClass.Unlocked or zombieClass.Wave <= GAMEMODE:GetWave()) then
				table.insert(zombieClasses, zombieClass)
			end
		end
	end
	local zombieClass = table.Random(zombieClasses)
	if not zombieClass then zombieClass = GAMEMODE.ZombieClasses[GAMEMODE.DefaultZombieClass] end
	--self:SetZombieClass(zombieClass.Index)
	self.DeathClass = zombieClass.Index
end

function meta:D3bot_ResetTgt() -- Reset all kind of targets
	local mem = self.D3bot_Mem
	mem.TgtOrNil = nil
	mem.PosTgtOrNil, mem.PosTgtProximity = nil, nil
	mem.NodeTgtOrNil = nil
	mem.NodeOrNil = nil
	mem.NextNodeOrNil = nil
	mem.RemainingNodes = {}
end

function meta:D3bot_SetTgtOrNil(target) -- Set the entity or player as target, bot will move to and attack. TODO: Add "should attack" and proximity parameter.
	local mem = self.D3bot_Mem
	mem.TgtOrNil = target
	mem.PosTgtOrNil, mem.PosTgtProximity = nil, nil
	mem.NodeTgtOrNil = nil
end

function meta:D3bot_SetPosTgtOrNil(targetPos, proximity) -- Set the position as target, bot will then move to it
	local mem = self.D3bot_Mem
	mem.TgtOrNil = nil
	mem.PosTgtOrNil, mem.PosTgtProximity = targetPos, proximity
	mem.NodeTgtOrNil = nil
end

function meta:D3bot_SetNodeTgtOrNil(targetNode) -- Set the node as target, bot will then move to it
	local mem = self.D3bot_Mem
	mem.TgtOrNil = nil
	mem.PosTgtOrNil, mem.PosTgtProximity = nil, nil
	mem.NodeTgtOrNil = targetNode
end

function meta:D3bot_Initialize()
	if D3bot.MaintainBotRolesAutomatically then
		--GAMEMODE.PreviouslyDied[self:UniqueID()] = CurTime()
		--GAMEMODE:PlayerInitialSpawn(self)
		-- TODO: Make bots spawn as zombie when round started and there is need for more zombies
	end
	
	self.D3bot_Mem = {
		TgtOrNil = nil,					-- Target entity to walk to and attack
		PosTgtOrNil = nil,				-- Target position to walk to
		NodeTgtOrNil = nil,				-- Target node
		TgtNodeOrNil = nil,				-- Node of the target entity or position
		NodeOrNil = nil,				-- The node the bot is inside of (or nearest to)
		NextNodeOrNil = nil,			-- Next node of the current path
		RemainingNodes = {},			-- All remaining nodes of the current path
		ConsidersPathLethality = false,
		Angs = Angle(),					-- Current angle, used to smooth out movement
		AngsOffshoot = Angle()			-- Offshoot angle, to make bots movement more random
	}
end

function meta:D3bot_SetUp()
	local mem = self.D3bot_Mem
	mem.TgtOrNil = nil
	mem.PosTgtOrNil = nil
	mem.NodeTgtOrNil = nil
	mem.NextNodeOrNil = nil
	mem.RemainingNodes = {}
	mem.ConsidersPathLethality = math.random(1, D3bot.BotConsideringDeathCostAntichance) == 1
	mem.Angs = self:EyeAngles()
end

function meta:D3bot_UpdateAngsOffshoot()
	local mem = self.D3bot_Mem
	local nodeOrNil = mem.NodeOrNil
	local nextNodeOrNil = mem.NextNodeOrNil
	if (nodeOrNil and nodeOrNil.Params.Aim == "Straight") or (nextNodeOrNil and nextNodeOrNil.Params.AimTo == "Straight") then
		mem.AngsOffshoot = Angle()
		return
	end
	local angOffshoot = D3bot.BotAngOffshoot
	mem.AngsOffshoot = Angle(math.random(-angOffshoot, angOffshoot), math.random(-angOffshoot, angOffshoot), 0)
end

function meta:D3bot_SetPath(path)
	local mem = self.D3bot_Mem
	if mem.NextNodeOrNil and mem.NextNodeOrNil == path[1] then table.insert(path, 1, mem.NodeOrNil) end -- Preserve current node if the path starts with the next node
	mem.NodeOrNil = table.remove(path, 1)
	mem.NextNodeOrNil = table.remove(path, 1)
	mem.RemainingNodes = path
end

function meta:D3bot_UpdatePath()
	local mem = self.D3bot_Mem
	if not IsValid(mem.TgtOrNil) and not mem.PosTgtOrNil and not mem.NodeTgtOrNil then return end
	local mapNavMesh = D3bot.MapNavMesh
	local node = mapNavMesh:GetNearestNodeOrNil(self:GetPos())
	mem.TgtNodeOrNil = mem.NodeTgtOrNil or mapNavMesh:GetNearestNodeOrNil(mem.TgtOrNil and mem.TgtOrNil:GetPos() or mem.PosTgtOrNil)
	if not node or not mem.TgtNodeOrNil then return end
	local abilities = {Walk = true}
	if self:GetActiveWeapon() and self:GetActiveWeapon().PounceVelocity then abilities.Pounce = true end
	local path = D3bot.GetBestMeshPathOrNil(node, mem.TgtNodeOrNil, mem.ConsidersPathLethality and D3bot.DeathCostOrNilByLink or {}, abilities) -- TODO: Consider correct death cost
	if not path then
		local handler = findHandler(self:GetZombieClass(), self:Team())
		if handler and handler.RerollTarget then handler.RerollTarget(self) end
		return
	end
	self:D3bot_SetPath(path)
	if mem.NodeOrNil and mem.NodeOrNil.Params.BotMod then
		D3bot.nodeZombiesCountAddition = mem.NodeOrNil.Params.BotMod -- TODO: Trigger noded botmod by human players, not here
	end
end

function meta:D3bot_UpdatePathProgress()
	local mem = self.D3bot_Mem
	while mem.NextNodeOrNil do
		if mem.NextNodeOrNil:GetContains2D(self:GetPos()) then
			mem.NodeOrNil = mem.NextNodeOrNil
			mem.NextNodeOrNil = table.remove(mem.RemainingNodes, 1)
			if mem.NodeOrNil then
				if mem.NodeOrNil.Params.BotMod then
					D3bot.nodeZombiesCountAddition = mem.NodeOrNil.Params.BotMod
					-- TODO: Change node botmod to trigger on human
				end
			end
		else
			break
		end
	end
end

-- Add to last positions list. Used to check bots being stuck, or to determine the current situation (runners, spawnkillers, caders)
function meta:D3bot_StorePos()
	self.D3bot_PosList = self.D3bot_PosList or {}
	local posList = self.D3bot_PosList
	table.insert(posList, 1, self:GetPos())
	while #posList > 30 do
		table.remove(posList)
	end
end

function meta:D3bot_CheckStuck()
	local mem = self.D3bot_Mem
	if mem.nextCheckStuck and mem.nextCheckStuck < CurTime() or not mem.nextCheckStuck then
		mem.nextCheckStuck = CurTime() + 1
	else
		return
	end
	
	local posList = self.D3bot_PosList
	if not posList then return end
	
	local pos_1, pos_2, pos_10 = posList[1], posList[2], posList[10]
	
	local minorStuck = pos_1 and pos_2 and pos_1:Distance(pos_2) < 1		-- Stuck on ladder
	local preMajorStuck = pos_1 and pos_10 and pos_1:Distance(pos_10) < 300	-- Running circles, stuck on object, ...
	local majorStuck
	
	if preMajorStuck and (self.D3bot_LastDamage and self.D3bot_LastDamage < CurTime() - 5 or not self.D3bot_LastDamage) then
		mem.MajorStuckCounter = mem.MajorStuckCounter and mem.MajorStuckCounter + 1 or 1
		if mem.MajorStuckCounter > 15 then
			majorStuck, mem.MajorStuckCounter = true, nil
		end
	else
		mem.MajorStuckCounter = nil
	end
	
	return minorStuck, majorStuck
end