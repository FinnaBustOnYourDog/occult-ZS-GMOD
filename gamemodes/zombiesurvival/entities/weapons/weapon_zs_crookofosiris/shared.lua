SWEP.PrintName = "'Osiris' Sharp Melee"
SWEP.Description = "Revelation 16:4"

SWEP.Base = "weapon_zs_basemelee"

SWEP.HoldType = "melee2"

SWEP.DamageType = DMG_CLUB

SWEP.ViewModel = "models/aether_gazer/v_osiris.mdl"
SWEP.WorldModel = "models/aether_gazer/w_osiris.mdl"
SWEP.ViewModelFOV = 70
SWEP.UseHands = true

if CLIENT then 
	SWEP.Offset = {
		Pos = {
			Up = -4.5,
			Right = 1,
			Forward = 4,
		},
			
		Ang = {
		Up = 90,
			Right = -5,
			Forward = -180
		},
		Scale = 1
	}
end

SWEP.MeleeDamage = 0
SWEP.MeleeRange = 160
SWEP.MeleeSize = 3.0
SWEP.MeleeKnockBack = 0

SWEP.Primary.Delay = 0.6

SWEP.WalkSpeed = SPEED_SLOWER

SWEP.SwingRotation = Angle(0, -120, -70)
SWEP.SwingOffset = Vector(0, 30, -40)
SWEP.SwingTime = 0.35
SWEP.SwingHoldType = "melee"

SWEP.Tier = 6
SWEP.MaxStock = 1

SWEP.AllowQualityWeapons = true
GAMEMODE:AttachWeaponModifier(SWEP, WEAPON_MODIFIER_FIRE_DELAY, -0.08, 1)
GAMEMODE:AttachWeaponModifier(SWEP, WEAPON_MODIFIER_MELEE_RANGE, 3, 1)

function SWEP:PlaySwingSound()
	self:EmitSound("weapons/osiris/axe_swing_miss"..math.random(1, 2)..".wav", 90, 135)
end

function SWEP:PlayHitSound()
	self:EmitSound("weapons/osiris/melee_axe_0"..math.random(1, 3)..".wav", 90, 135)
	self:EmitSound("physics/metal/metal_computer_impact_hard2.wav", 65, 90, 0.5, CHAN_WEAPON + 1)
end

function SWEP:GetTracesNumPlayers(traces)
	local numplayers = 0

	local ent
	for _, trace in pairs(traces) do
		ent = trace.Entity
		if ent and ent:IsValidPlayer() then
			numplayers = numplayers + 1
		end
	end

	return numplayers
end

function SWEP:GetDamage(numplayers, basedamage)
	basedamage = basedamage or self.MeleeDamage

	if numplayers then
		return basedamage * math.Clamp(1.25 - numplayers * 0.25, 0.5, 1)
	end

	return basedamage
end

function SWEP:MeleeSwing()
	local owner = self:GetOwner()
	local combo = self:GetDTInt(10)

	owner:DoAttackEvent()
	self:SendWeaponAnim(ACT_VM_SWINGHARD)
	--self:SendViewModelAnim(ACT_VM_BLOWBACK)
	self.IdleAnimation = CurTime() + self:SequenceDuration()

	local hit = false
	local tr = owner:CompensatedPenetratingMeleeTrace(self.MeleeRange * (owner.MeleeRangeMul or 1), self.MeleeSize)
	local damage = self:GetDamage(self:GetTracesNumPlayers(tr))
	local ent

	local damagemultiplier = owner:Team() == TEAM_HUMAN and owner.MeleeDamageMultiplier or 1 --(owner.BuffMuscular and owner:Team()==TEAM_HUMAN) and 1.2 or 1
	if owner:IsSkillActive(SKILL_LASTSTAND) then
		if owner:Health() <= owner:GetMaxHealth() * 0.25 then
			damagemultiplier = damagemultiplier * 2
		else
			damagemultiplier = damagemultiplier * 0.85
		end
	end

	if combo == 2 then
		damagemultiplier = damagemultiplier * 1.35
	end

	for _, trace in ipairs(tr) do
		if not trace.Hit then continue end

		ent = trace.Entity

		hit = true

		local hitflesh = trace.MatType == MAT_FLESH or trace.MatType == MAT_BLOODYFLESH or trace.MatType == MAT_ANTLION or trace.MatType == MAT_ALIENFLESH

		if hitflesh then
			util.Decal(self.BloodDecal, trace.HitPos + trace.HitNormal, trace.HitPos - trace.HitNormal)

			if SERVER then
				self:ServerHitFleshEffects(ent, trace, damagemultiplier)
			end

		end

		if ent and ent:IsValid() then
			if SERVER then
				self:ServerMeleeHitEntity(trace, ent, damagemultiplier)
			end

			self:MeleeHitEntity(trace, ent, damagemultiplier, damage)

			if SERVER then
				self:ServerMeleePostHitEntity(trace, ent, damagemultiplier)
			end

			if owner.GlassWeaponShouldBreak then break end
		end
	end

	if hit then
		self:PlayHitSound()
	else
		self:PlaySwingSound()

		if owner.MeleePowerAttackMul and owner.MeleePowerAttackMul > 1 then
			self:SetPowerCombo(0)
		end
	end

	local armdelay = owner:GetMeleeSpeedMul()
	self:SetNextPrimaryFire(CurTime() +
		self.Primary.Delay * (combo < 2 and 0.36 or 1.25) * armdelay
	)

	self:SetDTInt(10, combo >= 2 and 0 or combo + 1)
end

function SWEP:MeleeHitEntity(tr, hitent, damagemultiplier, damage)
	if not IsFirstTimePredicted() then return end

	local owner = self:GetOwner()

	if SERVER and hitent:IsPlayer() and owner:IsSkillActive(SKILL_GLASSWEAPONS) then
		damagemultiplier = damagemultiplier * 3.5
		owner.GlassWeaponShouldBreak = not owner.GlassWeaponShouldBreak
	end

	damage = damage * damagemultiplier

	local dmginfo = DamageInfo()
	dmginfo:SetDamagePosition(tr.HitPos)
	dmginfo:SetAttacker(owner)
	dmginfo:SetInflictor(self)
	dmginfo:SetDamageType(self.DamageType)
	dmginfo:SetDamage(damage)
	dmginfo:SetDamageForce(math.min(self.MeleeDamage, 50) * 50 * owner:GetAimVector())

	local vel
	if hitent:IsPlayer() then
		local bleed = hitent:GiveStatus("bleed")
		if bleed then
			bleed:AddDamage(616)
			bleed.DamPerTick = 66
			bleed.Damager = self:GetOwner()
		end

		if owner.MeleePowerAttackMul and owner.MeleePowerAttackMul > 1 then
			self:SetPowerCombo(self:GetPowerCombo() + 1)

			damage = damage + damage * (owner.MeleePowerAttackMul - 1) * (self:GetPowerCombo()/4)
			dmginfo:SetDamage(damage)

			if self:GetPowerCombo() >= 4 then
				self:SetPowerCombo(0)
				if SERVER then
					local pitch = math.Clamp(math.random(90, 110) + 15 * (1 - damage/45), 50 , 200)
					owner:EmitSound("npc/strider/strider_skewer1.wav", 75, pitch)
				end
			end
		end

		hitent:MeleeViewPunch(damage)
		if hitent:IsHeadcrab() then
			damage = damage * 2
			dmginfo:SetDamage(damage)
		end

		if SERVER then
			hitent:SetLastHitGroup(tr.HitGroup)
			if tr.HitGroup == HITGROUP_HEAD then
				hitent:SetWasHitInHead()
			end

			if hitent:WouldDieFrom(damage, tr.HitPos) then
				dmginfo:SetDamageForce(math.min(self.MeleeDamage, 50) * 400 * owner:GetAimVector())
			end
		end

		vel = hitent:GetVelocity()
	else
		if owner.MeleePowerAttackMul and owner.MeleePowerAttackMul > 1 then
			self:SetPowerCombo(0)
		end
	end

	--if not hitent.LastHeld or CurTime() >= hitent.LastHeld + 0.1 then -- Don't allow people to shoot props out of their hands
		if self.PointsMultiplier then
			POINTSMULTIPLIER = self.PointsMultiplier
		end

		hitent:DispatchTraceAttack(dmginfo, tr, owner:GetAimVector())

		if self.PointsMultiplier then
			POINTSMULTIPLIER = nil
		end

		-- Invalidate the engine knockback vs. players
		if vel then
			hitent:SetLocalVelocity(vel)
		end
	--end

	-- Perform our own knockback vs. players
	if hitent:IsPlayer() then
		local knockback = self.MeleeKnockBack * (owner.MeleeKnockbackMultiplier or 1)
		if knockback > 0 then
			hitent:ThrowFromPositionSetZ(tr.StartPos, knockback, nil, true)
		end

		if owner.MeleeLegDamageAdd and owner.MeleeLegDamageAdd > 0 then
			hitent:AddLegDamage(owner.MeleeLegDamageAdd)
		end
	end

	local effectdata = EffectData()
	effectdata:SetOrigin(tr.HitPos)
	effectdata:SetStart(tr.StartPos)
	effectdata:SetNormal(tr.HitNormal)
	util.Effect("RagdollImpact", effectdata)
	if not tr.HitSky then
		effectdata:SetSurfaceProp(tr.SurfaceProps)
		effectdata:SetDamageType(self.DamageType)
		effectdata:SetHitBox(tr.HitBox)
		effectdata:SetEntity(hitent)
		util.Effect("Impact", effectdata)
	end
end

if CLIENT then
	local WorldModel = ClientsideModel(SWEP.WorldModel)

	-- Settings...
	WorldModel:SetSkin(1)
	WorldModel:SetNoDraw(true)

	function SWEP:DrawWorldModel()
		local _Owner = self:GetOwner()

		if (IsValid(_Owner)) then
            -- Specify a good position
			local offsetVec = Vector(3, -1, -15)
			local offsetAng = Angle(0, 0, 180)
			
			local boneid = _Owner:LookupBone("ValveBiped.Bip01_R_Hand") -- Right Hand
			if !boneid then return end

			local matrix = _Owner:GetBoneMatrix(boneid)
			if !matrix then return end

			local newPos, newAng = LocalToWorld(offsetVec, offsetAng, matrix:GetTranslation(), matrix:GetAngles())

			WorldModel:SetPos(newPos)
			WorldModel:SetAngles(newAng)

            WorldModel:SetupBones()
		else
			WorldModel:SetPos(self:GetPos())
			WorldModel:SetAngles(self:GetAngles())
		end

		WorldModel:DrawModel()
	end
end
