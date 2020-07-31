#include <sdktools>
#include <sdkhooks>
#include <dhooks>

#define PLUGIN_VERSION 	"1.0.0"

public Plugin myinfo =
{
	name = "[TF2] Smart Pipes",
	author = "Scag",
	description = "Smarter than the average bar",
	version = PLUGIN_VERSION,
	url = "https://github.com/Scags/"
};

Handle
	hCalcAbsolutePosition,
	hDetonate
;

Handle
	hVPhysicsCollision
;

public void OnPluginStart()
{
	GameData conf = LoadGameConfigFile("tf2.smartpipes");

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(conf, SDKConf_Signature, "CBaseEntity::CalcAbsolutePosition");
	if (!(hCalcAbsolutePosition = EndPrepSDKCall()))
		SetFailState("Could not load call to CBaseEntity::CalcAbsolutePosition");

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(conf, SDKConf_Virtual, "CTFWeaponBaseGrenadeProj::Detonate");
	if (!(hDetonate = EndPrepSDKCall()))
		SetFailState("Could not load call to CTFWeaponBaseGrenadeProj::Detonate");

	hVPhysicsCollision = DHookCreateEx(conf, "CTFGrenadePipebombProjectile::VPhysicsCollision", HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, CTFGrenadePipebombProjectile_VPhysicsCollision)
	DHookAddParam(hVPhysicsCollision, HookParamType_Int);
	DHookAddParam(hVPhysicsCollision, HookParamType_Int);

	delete conf;
}

public void OnEntityCreated(int ent, const char[] classname)
{
	if (!strcmp(classname, "tf_projectile_pipe", false))
		DHookEntity(hVPhysicsCollision, true, ent);
}

#define EF_NODRAW 32
public MRESReturn CTFGrenadePipebombProjectile_VPhysicsCollision(int ent)
{
	// We exploded or fizzled this frame
	if (GetEntProp(ent, Prop_Send, "m_fEffects") & EF_NODRAW)
		return;

	// There's an attribute for this, but fuck it
	float radius = GetEntPropFloat(ent, Prop_Send, "m_DmgRadius");
	float origin[3]; origin = GetAbsOrigin(ent);

	if (CanHurtATarget(ent, origin, radius))
	{	// Have to wait a frame since this is a Physics callback :(
		RequestFrame(Detonate, EntIndexToEntRef(ent));
	}
}

public bool CanHurtATarget(int ent, float origin[3], float radius)
{
	int[] victims = new int[MaxClients];
	int victimcount = GetEntitiesInSphere(victims, origin, radius, FL_CLIENT);

	for (int i = 0; i < victimcount; ++i)
		if (WillHurtTarget(ent, origin, victims[i]))
			return true;
	return false;
}

public bool WillHurtTarget(int ent, float origin[3], int victim)
{
	float spot[3]; GetClientEyePosition(victim, spot);
	return Filter(ent, victim, origin, spot);
}

public bool Filter(int ent, int victim, float start[3], float end[3])
{
	TR_TraceRayFilter(start, end, MASK_SHOT & (~CONTENTS_HITBOX), RayType_EndPoint, ExplosionTrace, ent);
//	PrintToChatAll("%d", TR_GetEntityIndex());
	return TR_GetEntityIndex() == victim;
}

public bool ExplosionTrace(int ent, int mask, any data)
{
	char cls[32]; GetEntityClassname(ent, cls, sizeof(cls));
	int myteam = GetEntProp(data, Prop_Send, "m_iTeamNum");
	int otherteam = GetEntProp(ent, Prop_Send, "m_iTeamNum");

//	PrintToChatAll("%d %d", ent, data);

	if (ent == data)
		return false;

	if (HasEntProp(ent, Prop_Send, "m_nRevives") || !strncmp(cls, "entity_medigun", 14, false))
		return myteam != otherteam;

	if (myteam == otherteam)
		return GetEntPropEnt(data, Prop_Send, "m_hThrower") == ent;
	return true;
}

// This is dumb lmao
public int GetEntitiesInSphere(int[] array, float origin[3], float radius, int entflags)
{
	int count;
	int ent = -1;
	radius = radius * radius;	// I am speed
	while ((ent = FindEntityByClassname(ent, "*")) != -1)
	{
		if (!(GetEntityFlags(ent) & entflags))
			continue;

		float mypos[3]; mypos = GetAbsOrigin(ent);
		if (GetVectorDistance(origin, mypos, true) <= radius)
			array[count++] = ent;
	}
	return count;
}

public void Detonate(int ent)
{
	if (!IsValidEntity(ent))
		return;

	if (GetEntProp(ent, Prop_Send, "m_fEffects") & EF_NODRAW)
		return;

	SDKCall(hDetonate, ent);
}

#define EFL_DIRTY_ABSTRANSFORM 2048
stock float[] GetAbsOrigin(int ent)
{
	int flags = GetEntProp(ent, Prop_Data, "m_iEFlags");
	if (flags & EFL_DIRTY_ABSTRANSFORM)
		SDKCall(hCalcAbsolutePosition, ent);

	float v[3];
	GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", v);
	return v;
}

stock Handle DHookCreateEx(Handle gc, const char[] key, HookType hooktype, ReturnType returntype, ThisPointerType thistype, DHookCallback callback)
{
	int offset = GameConfGetOffset(gc, key);
	if (offset == -1)
	{
		SetFailState("Failed to get offset of %s", key);
		return null;
	}
	
	return DHookCreate(offset, hooktype, returntype, thistype, callback);
}