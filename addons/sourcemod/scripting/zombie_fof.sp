/**
 * vim: set ts=4 :
 * =============================================================================
 * zombie_fof
 * Zombie survival for Fistful of Frags
 *
 * Copyright 2016 CrimsonTautology
 * =============================================================================
 *
 */

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#undef REQUIRE_EXTENSIONS
#tryinclude <steamworks>

#define PLUGIN_VERSION		"1.0.0"
#define PLUGIN_NAME         "[FoF] Zombie Survival"
#define DEBUG				false

#define GAME_DESCRIPTION    "Zombie Survival"
#define SOUND_ROUNDSTART    "music/standoff1.mp3"

new Handle:g_Cvar_Enabled = INVALID_HANDLE;

new Handle:g_Cvar_TeambalanceAllowed = INVALID_HANDLE;
new Handle:g_Cvar_TeamsUnbalanceLimit = INVALID_HANDLE;
new Handle:g_Cvar_Autoteambalance = INVALID_HANDLE;

new g_Teamplay = INVALID_ENT_REFERENCE;

public Plugin:myinfo =
{
	name = PLUGIN_NAME,
	author = "CrimsonTautology",
	description = "Zombie Survival for Fistful of Frags",
	version = PLUGIN_VERSION,
	url = "https://github.com/CrimsonTautology/sm_zombie_fof"
};

public OnPluginStart()
{
    CreateConVar("fof_zombie_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);

    g_Cvar_Enabled = CreateConVar("fof_zombie", "1", "Whether or not zombie mode is enabled");

    HookEvent("player_activate", Event_PlayerActivate);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_start", Event_RoundStart);

    RegAdminCmd("sm_zombie", Command_Zombie, ADMFLAG_ROOT, "TEST command");//TODO

    g_Cvar_TeambalanceAllowed = FindConVar("fof_sv_teambalance_allowed");
    g_Cvar_TeamsUnbalanceLimit = FindConVar("mp_teams_unbalance_limit");
    g_Cvar_Autoteambalance = FindConVar("mp_autoteambalance");

    SetDefaultConVars();

    AutoExecConfig();
}

public OnClientDisconnect_Post(client)
{
}

public OnMapStart()
{
    PrecacheSound(SOUND_ROUNDSTART, true);

    g_Teamplay = SpawnZombieTeamplay();
}

public OnConfigsExecuted()
{
	SetGameDescription(GAME_DESCRIPTION);
}

public Event_PlayerActivate(Handle:event, const String:name[], bool:dontBroadcast)
{
}

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
}

public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
}

public Event_RoundStart(Event:event, const String:name[], bool:dontBroadcast)
{
    ConvertSpawns();
    RemoveCrates();
}

public Action:Command_Zombie(client, args)
{
    if(!IsEnabled())
    {
        ReplyToCommand(client, "not_enabled");
        return Plugin_Handled;
    }

    ServerCommand("round_restart");

    return Plugin_Handled;
}

SetDefaultConVars()
{
    SetConVarBool(g_Cvar_TeambalanceAllowed, false, false, false);
    SetConVarInt(g_Cvar_TeamsUnbalanceLimit, 30, false, false);
    SetConVarBool(g_Cvar_Autoteambalance, false, false, false);
}


RemoveCrates()
{
    new ent = INVALID_ENT_REFERENCE;
    while((ent = FindEntityByClassname(ent, "fof_crate*")) != INVALID_ENT_REFERENCE)
    {
		AcceptEntityInput(ent, "Kill" );
    }
}

//Change all info_player_fof spawn points to a round robin
//info_player_desperado and info_player_vigilante.
ConvertSpawns()
{
    new count = 0;
    new original  = INVALID_ENT_REFERENCE;
    new converted = INVALID_ENT_REFERENCE;
    new Float:position[3];

    while((original = FindEntityByClassname(original, "info_player_fof")) != INVALID_ENT_REFERENCE)
    {
        //Get original's position and remove it
        GetEntPropVector(original, Prop_Send, "m_vecOrigin", position);
        AcceptEntityInput(original, "Kill" );

        //Spawn a replacement at the same position
        converted = count % 2 == 0
            ? CreateEntityByName("info_player_vigilante")
            : CreateEntityByName("info_player_desperado")
            ;
        if(IsValidEntity(converted))
        {
            SetEntPropVector(converted, Prop_Send, "m_vecOrigin", position);
            DispatchSpawn(converted);
            ActivateEntity(converted);
        }

        count++;
    }

}

SpawnZombieTeamplay()
{
    new ent = CreateEntityByName("fof_teamplay");
    if(IsValidEntity(ent))
    {
        SetEntProp(ent, Prop_Data, "m_bRoundBased", 1);
        SetEntProp(ent, Prop_Data, "m_nRespawnSystem", 1);
        SetEntProp(ent, Prop_Data, "m_bSwitchTeams", 0);
        DispatchSpawn(ent);
        ActivateEntity(ent);

        //OnRoundTimeEnd //Winner is Humans(vig)
        //OnNoDespAlive  //Respawn Zombies(desp)
        //OnNoVigAlive   //Winner is Zombies(desp)
        //OnNewBuyRound  //Block or remove cash
    }

    return ent;
}

//Human Spawn
ConvertInfoPlayerDesperado(old)
{
    new ent = CreateEntityByName("info_player_desperado");
    if(IsValidEntity(ent))
    {
        DispatchSpawn(ent);
        ActivateEntity(ent);
    }
}

bool:IsEnabled()
{
    return GetConVarBool(g_Cvar_Enabled);
}

stock bool:SetGameDescription(String:description[], bool:override = true)
{
#if defined _SteamWorks_Included
    if(override) return SteamWorks_SetGameDescription(description);
#endif
    return false;
}

stock WriteLog(const String:format[], any:... )
{
#if defined DEBUG
    if(format[0] != '\0')
    {
        decl String:buf[2048];
        VFormat(buf, sizeof(buf), format, 2 );
        //LogToFileEx("log_zombie.txt", "[%.3f] %s", GetGameTime(), buf);
        PrintToServer("[%.3f] %s", GetGameTime(), buf);
    }
#endif
}
