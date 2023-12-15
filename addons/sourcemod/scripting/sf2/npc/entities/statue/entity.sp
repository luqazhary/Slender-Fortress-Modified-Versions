#pragma semicolon 1

#include "actions/mainlayer.sp"
#include "actions/idle.sp"
#include "actions/chase.sp"

static CEntityFactory g_Factory;

methodmap SF2_StatueEntity < SF2_BaseBoss
{
	public SF2_StatueEntity(int entity)
	{
		return view_as<SF2_StatueEntity>(entity);
	}

	public bool IsValid()
	{
		if (!CBaseCombatCharacter(this.index).IsValid())
		{
			return false;
		}

		return CEntityFactory.GetFactoryOfEntity(this.index) == g_Factory;
	}

	public static void Initialize()
	{
		g_Factory = new CEntityFactory("sf2_npc_boss_statue", OnCreate);
		g_Factory.DeriveFromFactory(SF2_BaseBoss.GetFactory());
		g_Factory.SetInitialActionFactory(SF2_StatueBaseAction.GetFactory());
		g_Factory.BeginDataMapDesc()
			.DefineBoolField("m_IsMoving")
			.DefineFloatField("m_LastKillTime")
		.EndDataMapDesc();
		g_Factory.Install();
	}

	property SF2NPC_Statue Controller
	{
		public get()
		{
			return view_as<SF2NPC_Statue>(view_as<SF2_BaseBoss>(this).Controller);
		}

		public set(SF2NPC_Statue controller)
		{
			view_as<SF2_BaseBoss>(this).Controller = controller;
		}
	}

	property bool IsMoving
	{
		public get()
		{
			return view_as<bool>(this.GetProp(Prop_Data, "m_IsMoving"));
		}

		public set(bool value)
		{
			this.SetProp(Prop_Data, "m_IsMoving", value);
		}
	}
	property float LastKillTime
	{
		public get()
		{
			return this.GetPropFloat(Prop_Data, "m_LastKillTime");
		}

		public set(float value)
		{
			this.SetPropFloat(Prop_Data, "m_LastKillTime", value);
		}
	}

	public void DoAlwaysLookAt(CBaseEntity target)
	{
		if (!target.IsValid())
		{
			return;
		}

		SF2_BasePlayer player = SF2_BasePlayer(target.index);
		if (player.IsValid && !player.IsAlive)
		{
			return;
		}

		INextBot bot = this.MyNextBotPointer();
		ILocomotion loco = bot.GetLocomotionInterface();
		if (!this.GetIsVisible(player))
		{
			return;
		}

		float pos[3];
		target.GetAbsOrigin(pos);
		loco.FaceTowards(pos);
	}

	public static SF2_StatueEntity Create(SF2NPC_BaseNPC controller, const float pos[3], const float ang[3])
	{
		SF2_StatueEntity statue = SF2_StatueEntity(CreateEntityByName("sf2_npc_boss_statue"));
		if (!statue.IsValid())
		{
			return SF2_StatueEntity(-1);
		}
		if (controller == SF2_INVALID_NPC)
		{
			return SF2_StatueEntity(-1);
		}
		char profile[SF2_MAX_PROFILE_NAME_LENGTH];

		controller.GetProfile(profile, sizeof(profile));
		statue.Controller = view_as<SF2NPC_Statue>(controller);

		SF2BossProfileData originalData;
		originalData = view_as<SF2NPC_BaseNPC>(statue.Controller).GetProfileData();

		char buffer[PLATFORM_MAX_PATH];

		GetSlenderModel(controller.Index, _, buffer, sizeof(buffer));
		statue.SetModel(buffer);
		statue.SetRenderMode(view_as<RenderMode>(g_SlenderRenderMode[controller.Index]));
		statue.SetRenderFx(view_as<RenderFx>(g_SlenderRenderFX[controller.Index]));
		statue.SetRenderColor(g_SlenderRenderColor[controller.Index][0], g_SlenderRenderColor[controller.Index][1],
								g_SlenderRenderColor[controller.Index][2], g_SlenderRenderColor[controller.Index][3]);

		if (SF_SpecialRound(SPECIALROUND_TINYBOSSES))
		{
			float scaleModel = controller.ModelScale * 0.5;
			statue.SetPropFloat(Prop_Send, "m_flModelScale", scaleModel);
		}
		else
		{
			statue.SetPropFloat(Prop_Send, "m_flModelScale", controller.ModelScale);
		}

		CBaseNPC npc = TheNPCs.FindNPCByEntIndex(statue.index);
		CBaseNPC_Locomotion loco = npc.GetLocomotion();

		npc.flMaxYawRate = 0.0;
		npc.flStepSize = 18.0;
		npc.flGravity = g_Gravity;
		npc.flDeathDropHeight = 99999.0;
		npc.flJumpHeight = 512.0;
		npc.flMaxYawRate = originalData.TurnRate;
		loco.SetCallback(LocomotionCallback_ClimbUpToLedge, ClimbUpCBase);

		statue.SetPropVector(Prop_Send, "m_vecMins", HULL_HUMAN_MINS);
		statue.SetPropVector(Prop_Send, "m_vecMaxs", HULL_HUMAN_MAXS);

		statue.SetPropVector(Prop_Send, "m_vecMinsPreScaled", HULL_HUMAN_MINS);
		statue.SetPropVector(Prop_Send, "m_vecMaxsPreScaled", HULL_HUMAN_MAXS);

		npc.SetBodyMins(HULL_HUMAN_MINS);
		npc.SetBodyMaxs(HULL_HUMAN_MAXS);

		statue.SetProp(Prop_Data, "m_nSolidType", SOLID_BBOX);
		SetEntityCollisionGroup(statue.index, COLLISION_GROUP_DEBRIS_TRIGGER);

		statue.Teleport(pos, ang, NULL_VECTOR);

		statue.Spawn();
		statue.Activate();

		return statue;
	}

	public static void SetupAPI()
	{
		CreateNative("SF2_StatueBossEntity.IsValid.get", Native_GetIsValid);
		CreateNative("SF2_StatueBossEntity.IsMoving.get", Native_GetIsMoving);
		CreateNative("SF2_StatueBossEntity.LastKillTime.get", Native_GetLastKillTime);
		CreateNative("SF2_StatueBossEntity.ProfileData", Native_GetProfileData);
	}
}

static void OnCreate(SF2_StatueEntity ent)
{
	ent.LastKillTime = 0.0;
	SDKHook(ent.index, SDKHook_Think, Think);
	SDKHook(ent.index, SDKHook_ThinkPost, ThinkPost);
}

static Action Think(int entIndex)
{
	SF2_StatueEntity statue = SF2_StatueEntity(entIndex);
	statue.Target = ProcessVision(statue);

	if (statue.IsMoving)
	{
		statue.DoAlwaysLookAt(statue.Target);
	}

	statue.CheckVelocityCancel();

	return Plugin_Continue;
}

static void ThinkPost(int entIndex)
{
	SF2_StatueEntity statue = SF2_StatueEntity(entIndex);

	ProcessSpeed(statue);

	if (NPCGetCustomOutlinesState(statue.Controller.Index) && NPCGetRainbowOutlineState(statue.Controller.Index))
	{
		statue.ProcessRainbowOutline();
	}

	if (statue.IsMoving)
	{
		statue.DoAlwaysLookAt(statue.Target);
	}

	statue.SetNextThink(GetGameTime());
}

static CBaseEntity ProcessVision(SF2_StatueEntity statue)
{
	SF2NPC_Statue controller = statue.Controller;
	bool attackEliminated = (controller.Flags & SFF_ATTACKWAITERS) != 0;
	SF2StatueBossProfileData data;
	data = controller.GetProfileData();
	SF2BossProfileData originalData;
	originalData = view_as<SF2NPC_BaseNPC>(controller).GetProfileData();
	int difficulty = controller.Difficulty;

	float playerDists[MAXTF2PLAYERS];

	float traceMins[3] = { -16.0, ... };
	traceMins[2] = 0.0;
	float traceMaxs[3] = { 16.0, ... };
	traceMaxs[2] = 0.0;

	int oldTarget = statue.OldTarget.index;
	if (!IsTargetValidForSlender(SF2_BasePlayer(oldTarget), attackEliminated))
	{
		statue.OldTarget = CBaseEntity(INVALID_ENT_REFERENCE);
		oldTarget = INVALID_ENT_REFERENCE;
	}
	if (originalData.IsPvEBoss && !IsPvETargetValid(SF2_BasePlayer(oldTarget)))
	{
		statue.OldTarget = CBaseEntity(INVALID_ENT_REFERENCE);
		oldTarget = INVALID_ENT_REFERENCE;
	}
	int bestNewTarget = oldTarget;
	float searchRange = originalData.SearchRange[difficulty];
	float bestNewTargetDist = Pow(searchRange, 2.0);

	for (int i = 1; i <= MaxClients; i++)
	{
		SF2_BasePlayer client = SF2_BasePlayer(i);
		if (!IsTargetValidForSlender(client, attackEliminated) && !originalData.IsPvEBoss)
		{
			continue;
		}

		statue.SetIsVisible(client, false);
		statue.SetInFOV(client, false);
		statue.SetIsNear(client, false);

		float traceStartPos[3], traceEndPos[3];
		controller.GetEyePosition(traceStartPos);
		client.GetEyePosition(traceEndPos);

		float dist = 99999999999.9;

		bool isVisible;
		int traceHitEntity;

		Handle trace = TR_TraceRayFilterEx(traceStartPos,
		traceEndPos,
		CONTENTS_SOLID | CONTENTS_MOVEABLE | CONTENTS_MIST | CONTENTS_MONSTERCLIP,
		RayType_EndPoint,
		TraceRayBossVisibility,
		statue.index);
		isVisible = !TR_DidHit(trace);
		traceHitEntity = TR_GetEntityIndex(trace);

		delete trace;

		if (!isVisible && traceHitEntity == client.index)
		{
			isVisible = true;
		}

		if (isVisible)
		{
			isVisible = NPCShouldSeeEntity(controller.Index, client.index);
		}

		dist = GetVectorSquareMagnitude(traceStartPos, traceEndPos);

		if (g_PlayerFogCtrlOffset != -1 && g_FogCtrlEnableOffset != -1 && g_FogCtrlEndOffset != -1)
		{
			int fogEntity = client.GetDataEnt(g_PlayerFogCtrlOffset);
			if (IsValidEdict(fogEntity))
			{
				if (GetEntData(fogEntity, g_FogCtrlEnableOffset) &&
					dist >= SquareFloat(GetEntDataFloat(fogEntity, g_FogCtrlEndOffset)))
				{
					isVisible = false;
				}
			}
		}

		statue.SetIsVisible(client, isVisible);

		if (statue.GetIsVisible(client) && SF_SpecialRound(SPECIALROUND_BOO) && GetVectorSquareMagnitude(traceEndPos, traceStartPos) < SquareFloat(SPECIALROUND_BOO_DISTANCE))
		{
			TF2_StunPlayer(client.index, SPECIALROUND_BOO_DURATION, _, TF_STUNFLAGS_GHOSTSCARE);
		}

		if (client.ShouldBeForceChased(controller))
		{
			bestNewTarget = client.index;
		}

		playerDists[client.index] = dist;

		if (statue.GetIsVisible(client))
		{
			float targetPos[3];
			client.GetAbsOrigin(targetPos);
			if (dist <= SquareFloat(searchRange))
			{
				if (dist < bestNewTargetDist)
				{
					bestNewTarget = client.index;
					bestNewTargetDist = dist;
				}
			}
		}
	}

	if (bestNewTarget != INVALID_ENT_REFERENCE)
	{
		statue.OldTarget = CBaseEntity(bestNewTarget);
	}

	if (SF_IsRaidMap() || SF_BossesChaseEndlessly() || SF_IsProxyMap() || SF_IsBoxingMap() || SF_IsSlaughterRunMap())
	{
		if (!IsTargetValidForSlender(SF2_BasePlayer(bestNewTarget), attackEliminated))
		{
			if (statue.State != STATE_CHASE && NPCAreAvailablePlayersAlive())
			{
				ArrayList arrayRaidTargets = new ArrayList();

				for (int i = 1; i <= MaxClients; i++)
				{
					if (!IsValidClient(i) ||
						!IsPlayerAlive(i) ||
						g_PlayerEliminated[i] ||
						IsClientInGhostMode(i) ||
						DidClientEscape(i))
					{
						continue;
					}
					arrayRaidTargets.Push(i);
				}
				if (arrayRaidTargets.Length > 0)
				{
					int raidTarget = arrayRaidTargets.Get(GetRandomInt(0, arrayRaidTargets.Length - 1));
					if (IsValidClient(raidTarget) && !g_PlayerEliminated[raidTarget])
					{
						bestNewTarget = raidTarget;
						SF2_BasePlayer(bestNewTarget).SetForceChaseState(controller, true);
					}
				}
				delete arrayRaidTargets;
			}
		}
		statue.CurrentChaseDuration = data.ChaseDuration[difficulty];
	}

	return CBaseEntity(bestNewTarget);
}

static void ProcessSpeed(SF2_StatueEntity statue)
{
	SF2NPC_Statue controller = statue.Controller;
	SF2NPC_BaseNPC baseController = view_as<SF2NPC_BaseNPC>(controller);
	int difficulty = controller.Difficulty;
	CBaseNPC npc = TheNPCs.FindNPCByEntIndex(statue.index);
	SF2BossProfileData originalData;
	originalData = baseController.GetProfileData();

	float speed, acceleration;

	acceleration = originalData.Acceleration[difficulty];
	if (controller.HasAttribute(SF2Attribute_ReducedAccelerationOnLook) && controller.CanBeSeen(_, true))
	{
		acceleration *= controller.GetAttributeValue(SF2Attribute_ReducedAccelerationOnLook);
	}
	acceleration += controller.GetAddAcceleration();

	speed = originalData.RunSpeed[difficulty];
	if (controller.HasAttribute(SF2Attribute_ReducedSpeedOnLook) && controller.CanBeSeen(_, true))
	{
		speed *= controller.GetAttributeValue(SF2Attribute_ReducedSpeedOnLook);
	}

	speed += baseController.GetAddSpeed();

	float forwardSpeed = speed;
	Action action = Plugin_Continue;
	Call_StartForward(g_OnBossGetSpeedFwd);
	Call_PushCell(controller.Index);
	Call_PushFloatRef(forwardSpeed);
	Call_Finish(action);
	if (action == Plugin_Changed)
	{
		speed = forwardSpeed;
	}

	if (g_InProxySurvivalRageMode)
	{
		speed *= 1.25;
	}

	speed = (speed + (speed * GetDifficultyModifier(difficulty)) / 15.0);
	acceleration = (acceleration + (acceleration * GetDifficultyModifier(difficulty)) / 15.0);

	if (SF_SpecialRound(SPECIALROUND_RUNNINGINTHE90S))
	{
		if (speed < 520.0)
		{
			speed = 520.0;
		}
		acceleration += 9001.0;
	}
	if (SF_IsSlaughterRunMap())
	{
		if (speed < 580.0)
		{
			speed = 580.0;
		}
		acceleration += 10000.0;
	}

	if (IsBeatBoxBeating(2) || statue.IsKillingSomeone || !statue.IsMoving)
	{
		speed = 0.0;
	}

	npc.flWalkSpeed = speed * 0.9;
	npc.flRunSpeed = speed;
	npc.flAcceleration = acceleration;
}

static any Native_GetIsValid(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);
	SF2_StatueEntity bossEntity = SF2_StatueEntity(entity);
	return bossEntity.IsValid();
}

static any Native_GetIsMoving(Handle plugin, int numParams)
{
	int ent = GetNativeCell(1);
	if (!IsValidEntity(ent))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid entity index %d", ent);
	}

	SF2_StatueEntity boss = SF2_StatueEntity(ent);
	return boss.IsMoving;
}

static any Native_GetLastKillTime(Handle plugin, int numParams)
{
	int ent = GetNativeCell(1);
	if (!IsValidEntity(ent))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid entity index %d", ent);
	}

	SF2_StatueEntity boss = SF2_StatueEntity(ent);
	return boss.LastKillTime;
}

static any Native_GetProfileData(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);
	if (!IsValidEntity(entity))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid entity index %d", entity);
	}

	SF2_StatueEntity bossEntity = SF2_StatueEntity(entity);

	SF2StatueBossProfileData data;
	data = bossEntity.Controller.GetProfileData();
	SetNativeArray(2, data, sizeof(data));
	return 0;
}
