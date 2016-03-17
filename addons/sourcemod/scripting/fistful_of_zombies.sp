/**
 * vim: set ts=4 :
 * =============================================================================
 * Fistful Of Zombies
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
#include <smlib>
#undef REQUIRE_EXTENSIONS
#tryinclude <steamworks>

#define PLUGIN_VERSION		"1.0.1"
#define PLUGIN_NAME         "[FoF] Fistful Of Zombies"
#define DEBUG				true

#define MAX_KEY_LENGTH	    128
#define MAX_TABLE   	    128
#define INFECTION_LIMIT     100.0
#define VOICE_SCALE         12.0

#define GAME_DESCRIPTION    "Fistful Of Zombies"
#define SOUND_ROUNDSTART    "music/standoff1.mp3"
#define SOUND_STINGER       "music/kill1.wav"
#define SOUND_NOPE          "player/voice/no_no1.wav"

#define TEAM_ZOMBIE         3   //Desperados
#define TEAM_HUMAN          2   //Vigilantes

new Handle:g_Cvar_Enabled = INVALID_HANDLE;
new Handle:g_Cvar_Config = INVALID_HANDLE;
new Handle:g_Cvar_RoundTime = INVALID_HANDLE;
new Handle:g_Cvar_RespawnTime = INVALID_HANDLE;
new Handle:g_Cvar_Ratio = INVALID_HANDLE;

new Handle:g_Cvar_TeambalanceAllowed = INVALID_HANDLE;
new Handle:g_Cvar_TeamsUnbalanceLimit = INVALID_HANDLE;
new Handle:g_Cvar_Autoteambalance = INVALID_HANDLE;

new Handle:g_GearPrimaryTable = INVALID_HANDLE;
new g_GearPrimaryTotalWeight;

new Handle:g_GearSecondaryTable = INVALID_HANDLE;
new g_GearSecondaryTotalWeight;

new Handle:g_LootTable = INVALID_HANDLE;
new g_LootTotalWeight;

new g_Teamplay = INVALID_ENT_REFERENCE;


new g_Model_Vigilante;
new g_Model_Desperado;
new g_Model_Bandido;
new g_Model_Ranger;
new g_Model_Ghost;
new g_Model_Skeleton;
new g_Model_FistsGhost;

new g_PredictedViewModel[MAXPLAYERS];


enum FoZRoundState
{
  RoundPre,
  RoundGrace,
  RoundActive,
  RoundEnd
}
new FoZRoundState:g_RoundState = RoundPre;

public Plugin:myinfo =
{
    name = PLUGIN_NAME,
    author = "CrimsonTautology",
    description = "Zombie Survival for Fistful of Frags",
    version = PLUGIN_VERSION,
    url = "https://github.com/CrimsonTautology/sm_fistful_of_zombies"
};

public OnPluginStart()
{
    CreateConVar("foz_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);

    g_Cvar_Enabled = CreateConVar(
            "foz_enabled",
            "1",
            "Whether or not Fistful of Zombies is enabled");

    g_Cvar_Config = CreateConVar(
            "foz_config",
            "fistful_of_zombies.txt",
            "Location of the Fistful of Zombies configuration file",
            FCVAR_PLUGIN);

    g_Cvar_RoundTime = CreateConVar(
            "foz_round_time",
            "120",
            "How long surviors have to survive in seconds to win a round in Fistful of Zombies",
            FCVAR_PLUGIN);

    g_Cvar_RespawnTime = CreateConVar(
            "foz_respawn_time",
            "15",
            "How long zombies have to wait before respawning in Fistful of Zombies",
            FCVAR_PLUGIN);

    g_Cvar_Ratio = CreateConVar(
            "foz_ratio",
            "0.65",
            "Percentage of players that start as human.",
            FCVAR_PLUGIN,
            true, 0.01,
            true, 1.0);


    HookEvent("player_activate", Event_PlayerActivate);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_start", Event_RoundStart);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);

    RegAdminCmd("sm_zombie", Command_Zombie, ADMFLAG_ROOT, "TEST command");//TODO
    RegAdminCmd("foz_dump", Command_Dump, ADMFLAG_ROOT, "TEST command");//TODO

    AddCommandListener(Command_JoinTeam, "jointeam");
    //AddCommandListener(Command_JoinTeam, "equipmenu");
    //AddCommandListener(Command_JoinTeam, "chooseteam");

    g_Cvar_TeambalanceAllowed = FindConVar("fof_sv_teambalance_allowed");
    g_Cvar_TeamsUnbalanceLimit = FindConVar("mp_teams_unbalance_limit");
    g_Cvar_Autoteambalance = FindConVar("mp_autoteambalance");

    //AutoExecConfig();

    AddNormalSoundHook(SoundCallback);
}

public OnClientPostAdminCheck(client)
{
    if(!IsEnabled()) return;

    SDKHook(client, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
    //SDKHook(client, SDKHook_WeaponSwitchPost, Hook_OnWeaponSwitchPost);//TODO
}
public OnClientDisconnect(client)
{
    if(!IsEnabled()) return;
}

public OnMapStart()
{
    if(!IsEnabled()) return;

    //Load configuration
    decl String:file[PLATFORM_MAX_PATH];
    GetConVarString(g_Cvar_Config, file, sizeof(file));
    LoadFOZFile(file,
            g_GearPrimaryTable, g_GearPrimaryTotalWeight,
            g_GearSecondaryTable, g_GearSecondaryTotalWeight,
            g_LootTable, g_LootTotalWeight
            );

    //Cache materials
    PrecacheSound(SOUND_ROUNDSTART, true);
    PrecacheSound(SOUND_STINGER, true);
    PrecacheSound(SOUND_NOPE, true);

    g_Model_Vigilante = PrecacheModel("models/playermodels/player1.mdl");
    g_Model_Desperado = PrecacheModel("models/playermodels/player2.mdl");
    g_Model_Bandido = PrecacheModel("models/playermodels/bandito.mdl");
    g_Model_Ranger = PrecacheModel("models/playermodels/frank.mdl");
    g_Model_Ghost = PrecacheModel("models/npc/ghost.mdl");
    g_Model_Skeleton = PrecacheModel("models/skeleton.mdl");
    g_Model_FistsGhost = PrecacheModel("models/weapons/v_fists_ghost.mdl");

    //Initial setup
    ConvertSpawns();
    ConvertWhiskey(g_LootTable, g_LootTotalWeight);
    g_Teamplay = SpawnZombieTeamplay();
    Team_SetName(TEAM_ZOMBIE, "Zombies");
    Team_SetName(TEAM_HUMAN, "Humans");

    WriteLog("Hit MapStart");
    SetRoundState(RoundPre);

    CreateTimer(1.0, Timer_Repeat, .flags = TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

}

public OnConfigsExecuted()
{
    if(!IsEnabled()) return;

    SetGameDescription(GAME_DESCRIPTION);
    SetDefaultConVars();
}

public Event_PlayerActivate(Handle:event, const String:name[], bool:dontBroadcast)
{
    if(!IsEnabled()) return;
}

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
    if(!IsEnabled()) return;

    new userid = GetEventInt(event, "userid");
    new client = GetClientOfUserId(userid);

    //g_PredictedViewModel[client] = GetViewModelIndex(client);

    RequestFrame(PlayerSpawnDelay, userid);
}

public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
    if(!IsEnabled()) return;

    new userid = GetEventInt(event, "userid");
    new client = GetClientOfUserId(userid);


    //A dead human becomes a zombie
    if(IsHuman(client))
    {
        //Announce the death
        PrintCenterTextAll("%N has turned...", client);
        EmitSoundToAll(SOUND_STINGER, .flags = SND_CHANGEPITCH, .pitch = 80);

        RequestFrame(BecomeZombieDelay, userid);
    }
}

public Event_RoundStart(Event:event, const String:name[], bool:dontBroadcast)
{
    if(!IsEnabled()) return;

    WriteLog("Hit RoundStart");
    SetRoundState(RoundGrace);
    CreateTimer(10.0, Timer_EndGrace, TIMER_FLAG_NO_MAPCHANGE);  

    ConvertWhiskey(g_LootTable, g_LootTotalWeight);
    RemoveCrates();
    RandomizeTeams();
    SetDefaultConVars();
}


public Event_RoundEnd(Event:event, const String:name[], bool:dontBroadcast)
{
    if(!IsEnabled()) return;

    WriteLog("Hit RoundEnd");
    SetRoundState(RoundEnd);
}

public Action:Event_PlayerTeam(Event:event, const String:name[], bool:dontBroadcast)
{
    if(!IsEnabled()) return Plugin_Continue;

    new userid = GetEventInt(event, "userid");
    new client = GetClientOfUserId(userid);
    new team   = GetEventInt(event, "team");
    new oldteam   = GetEventInt(event, "oldteam");

    //If A player joins in late as a human force them to be a zombie
    if(team == TEAM_HUMAN && GetRoundState() == RoundActive)
    {
        WriteLog("-------------blocked %L from joining %d (was %d)", client, team, oldteam);
        RequestFrame(BecomeZombieDelay, userid);

        return Plugin_Handled;
    }

    return Plugin_Continue;

}

public PlayerSpawnDelay(any:userid)
{
    new client = GetClientOfUserId(userid);

    if(!IsEnabled()) return;
    if(!Client_IsIngame(client)) return;
    if(!IsPlayerAlive(client)) return;

    if(IsHuman(client))
    {
        //If a player spawns as human give them their primary and secondary gear
        CreateTimer(0.2, Timer_GiveSecondaryWeapon, userid, TIMER_FLAG_NO_MAPCHANGE);  
        CreateTimer(0.3, Timer_GivePrimaryWeapon, userid, TIMER_FLAG_NO_MAPCHANGE);  

        PrintCenterText(client, "Survive the zombie plague!"); 
    } else if(IsZombie(client))
    {
        //Force client model
        Entity_SetModelIndex(client, g_Model_Skeleton);
        StripWeapons(client);

        PrintCenterText(client, "Ughhhh..... BRAINNNSSSS"); 
    }
}

public BecomeZombieDelay(any:userid)
{
    new client = GetClientOfUserId(userid);

    if(!IsEnabled()) return;
    if(!Client_IsIngame(client)) return;

    JoinZombieTeam(client);
}

public Action:Timer_GivePrimaryWeapon(Handle:timer, any:userid)
{
    new client = GetClientOfUserId(userid);

    if(!IsEnabled()) return Plugin_Handled;
    if(!Client_IsIngame(client)) return Plugin_Handled;
    if(IsZombie(client)) return Plugin_Handled;
    new String:weapon[MAX_KEY_LENGTH];

    GetRandomValueFromTable(g_GearPrimaryTable, g_GearPrimaryTotalWeight, weapon, sizeof(weapon));
    GivePlayerItem(client, weapon);
    PrintToChat(client, "Given %s", weapon);
    UseWeapon(client, weapon);

    return Plugin_Handled;
}

public Action:Timer_GiveSecondaryWeapon(Handle:timer, any:userid)
{
    new client = GetClientOfUserId(userid);

    if(!IsEnabled()) return Plugin_Handled;
    if(!Client_IsIngame(client)) return Plugin_Handled;
    if(IsZombie(client)) return Plugin_Handled;

    new String:weapon[MAX_KEY_LENGTH];

    GetRandomValueFromTable(g_GearSecondaryTable, g_GearSecondaryTotalWeight, weapon, sizeof(weapon));
    GivePlayerItem(client, weapon);
    PrintToChat(client, "Given %s", weapon);
    UseWeapon(client, weapon, true);

    return Plugin_Handled;
}

public Action:Timer_EndGrace(Handle:timer)
{
    WriteLog("Hit EndGrace");
    SetRoundState(RoundActive);
}

public Action:Timer_Repeat(Handle:timer)
{
    if(!IsEnabled()) return Plugin_Continue;

    RoundEndCheck();

    for (new client=1; client <= MaxClients; client++)
    {
        if(!IsClientInGame(client)) continue;


        if(IsHuman(client))
        {
            //No-op

        }else if(IsZombie(client))
        {
            //No-op
        }
    }


    return Plugin_Handled;
}

public Action:Hook_OnWeaponCanUse(client, weapon)
{
    if(!IsEnabled()) return Plugin_Continue;

    //Block zombies from picking up guns
    if (IsZombie(client))
    {
        decl String:class[MAX_KEY_LENGTH];
        GetEntityClassname(weapon, class, sizeof(class));

        if (!StrEqual(class, "weapon_fists"))
        {
            EmitSoundToClient(client, SOUND_NOPE);
            PrintCenterText(client, "Zombies Can Not Use Guns"); 
            PrintToChat(client, "Zombies Can Not Use Guns"); 

            return Plugin_Handled;
        }
    }

    return Plugin_Continue;
}

public Action:Hook_OnWeaponSwitchPost(client, weapon)
{
    //TODO
    //Change zombie fists to ghost fists
    if(IsZombie(client))
    {
        decl String:class[MAX_KEY_LENGTH];
        GetEntityClassname(weapon, class, sizeof(class));
        if(StrEqual(class, "weapon_fists"))
        {
            SetEntProp(weapon, Prop_Send, "m_nModelIndex", 0);
            SetEntProp(g_PredictedViewModel[client], Prop_Send, "m_nModelIndex", g_Model_FistsGhost);
        }
    }

    return Plugin_Continue;
}


public Action:Command_JoinTeam(client, const String:command[], args) 
{ 
    if(!IsEnabled()) return Plugin_Continue;
    if(!Client_IsIngame(client)) return Plugin_Continue; 

    decl String:cmd[32];
    GetCmdArg(1, cmd, sizeof(cmd));

    WriteLog("Hit JoinTeam (%N -> %s)", client, cmd);

    if(GetRoundState() == RoundActive)
    {
        //If attempting to join human team or random then join zombie team
        if(StrEqual(cmd, "3", false) || StrEqual(cmd, "auto", false))
        {
            JoinZombieTeam(client);
            return Plugin_Handled;
        }
        //If attempting to join zombie team or spectator, let them
        else if(StrEqual(cmd, "2", false) || StrEqual(cmd, "spectate", false))
        {
            return Plugin_Continue;
        }
        //Prevent joining any other team
        else
        {
            return Plugin_Handled;
        }
    }

    return Plugin_Continue;
}  

public Action:SoundCallback(clients[64], &numClients, String:sample[PLATFORM_MAX_PATH], &entity, &channel, &Float:volume, &level, &pitch, &flags)
{
    if (entity > 0 && entity <= MaxClients)
    {
        //Change the voice of zombie players
        if(IsZombie(entity))
        {
            if(StrContains(sample, "player/voice") == 0 || StrContains(sample, "npc/mexican") == 0)
            {
                pitch = 40;
                flags |= SND_CHANGEPITCH;
                return Plugin_Changed;
            }
        }
    }
    return Plugin_Continue;
}


public Action:Command_Zombie(client, args)
{
    if(!IsEnabled())
    {
        ReplyToCommand(client, "not_enabled");
        return Plugin_Handled;
    }

    new String:tmp[512];
    Team_GetName(TEAM_ZOMBIE, tmp, sizeof(tmp));
    WriteLog("TEAM_ZOMBIE = %s", tmp);
    Team_GetName(TEAM_HUMAN, tmp, sizeof(tmp));
    WriteLog("TEAM_HUMAN  = %s", tmp);

    Entity_ChangeOverTime(client, 0.1, InfectionStep);
    return Plugin_Handled;
}

public bool:InfectionStep(&client, &Float:interval, &currentCall)
{
    if(!IsEnabled())
    if(!Client_IsIngame(client)) return false;
    if(!IsPlayerAlive(client)) return false;
    if(!IsHuman(client)) return false;
    if(GetRoundState() != RoundActive) return false;

    new Float:drunkness = GetEntPropFloat(client, Prop_Send, "m_flDrunkness");
    drunkness = currentCall * 1.0;
    SetEntPropFloat(client, Prop_Send, "m_flDrunkness", drunkness);

    WriteLog("%N at %d -> %f", client, currentCall, drunkness);

    return true;
}


public Action:Command_Dump(caller, args)
{
    new String:tmp[32], team, health;
    PrintToConsole(caller, "---------------------------------");
    PrintToConsole(caller, "RoundState: %d", g_RoundState);
    PrintToConsole(caller, "TEAM_ZOMBIE: %d, TEAM_HUMAN: %d", TEAM_ZOMBIE, TEAM_HUMAN);
    PrintToConsole(caller, "---------------------------------");
    PrintToConsole(caller, "team          health user");
    for (new client=1; client <= MaxClients; client++)
    {
        if(!IsClientInGame(client) || IsFakeClient(client))
            continue;

        team = GetClientTeam(client);
        health = Entity_GetHealth(client);
        Team_GetName(team, tmp, sizeof(tmp));
        
        PrintToConsole(caller, "%13s %6d %L",
                tmp,
                health,
                client
                );
    }
    PrintToConsole(caller, "---------------------------------");
    return Plugin_Handled;
}

LoadFOZFile(String:file[],
        &Handle:gear_primary_table, &gear_primary_total_weight,
        &Handle:gear_secondary_table, &gear_secondary_total_weight,
        &Handle:loot_table, &loot_total_weight)
{
    decl String:path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/%s", file);

    new Handle:config = CreateKeyValues("fistful_of_zombies");
    if(!FileToKeyValues(config, path))
    {
        LogError("Could not read map rotation file \"%s\"", file);
        SetFailState("Could not read map rotation file \"%s\"", file);
        return;
    }

    //Read the default "loot" key and build the loot table
    BuildWeightTable(config, "loot", loot_table, loot_total_weight);
    BuildWeightTable(config, "gear_primary", gear_primary_table, gear_primary_total_weight);
    BuildWeightTable(config, "gear_secondary", gear_secondary_table, gear_secondary_total_weight);

    CloseHandle(config);
}

//Build a table for randomly selecting a weighted value
BuildWeightTable(Handle:kv, const String:name[], &Handle:table, &total_weight)
{
    decl String:key[MAX_KEY_LENGTH];
    new weight;

    if(table != INVALID_HANDLE) CloseHandle(table);
    total_weight = 0;

    KvRewind(kv);

    if(KvJumpToKey(kv, name))
    {
        table = CreateKeyValues(name);
        KvCopySubkeys(kv, table);

        KvGotoFirstSubKey(kv);
        do
        {
            KvGetSectionName(kv, key, sizeof(key));
            weight = KvGetNum(kv, "weight", 0);


            //Ignore values that do not have a weight or 0 weight
            if(weight > 0)
            {
                total_weight += weight;

                WriteLog("Add[%s]: %s (%d) (%d)", name, key, weight, total_weight);
            }
        }
        while(KvGotoNextKey(kv));

    }else{
        LogError("A valid \"%s\" key was not defined", name);
        SetFailState("A valid \"%s\" key was not defined", name);
    }

    KvRewind(kv);
}

SetDefaultConVars()
{
    SetConVarInt(g_Cvar_TeambalanceAllowed, 0, false, false);
    SetConVarInt(g_Cvar_TeamsUnbalanceLimit, 0, false, false);
    SetConVarInt(g_Cvar_Autoteambalance, 0, false, false);
}

RemoveCrates()
{
    Entity_KillAllByClassName("fof_crate*");
}

RemoveWeapons()
{
    Entity_KillAllByClassName("weapon*");
    Entity_KillAllByClassName("dynamite*");
}

//Change all info_player_fof spawn points to a round robin
//info_player_desperado and info_player_vigilante.
ConvertSpawns()
{
    new count = 0;
    new spawn  = INVALID_ENT_REFERENCE;
    new converted = INVALID_ENT_REFERENCE;
    new Float:origin[3], Float:angles[3];

    while((spawn = FindEntityByClassname(spawn, "info_player_fof")) != INVALID_ENT_REFERENCE)
    {
        //Get original's position and remove it
        Entity_GetAbsOrigin(spawn, origin);
        Entity_GetAbsAngles(spawn, angles);
        Entity_Kill(spawn);

        //Spawn a replacement at the same position
        converted = count % 2 == 0
            ? Entity_Create("info_player_vigilante")
            : Entity_Create("info_player_desperado")
            ;
        if(IsValidEntity(converted))
        {
            Entity_SetAbsOrigin(converted, origin);
            Entity_SetAbsAngles(converted, angles);
            DispatchKeyValue(converted, "StartDisabled", "0");
            DispatchSpawn(converted);
            ActivateEntity(converted);
        }

        count++;
    }

}

//Whiskey is used as the spawn points for the random loot accross the map.
//Every whiskey entity is removed and replaced with a random item/weapon.
ConvertWhiskey(Handle:loot_table, loot_total_weight)
{
    decl String:loot[MAX_KEY_LENGTH];
    new count = 0;
    new whiskey  = INVALID_ENT_REFERENCE;
    new converted = INVALID_ENT_REFERENCE;
    new Float:origin[3], Float:angles[3];

    while((whiskey = FindEntityByClassname(whiskey, "item_whiskey")) != INVALID_ENT_REFERENCE)
    {
        //Get original's position and remove it
        Entity_GetAbsOrigin(whiskey, origin);
        Entity_GetAbsAngles(whiskey, angles);
        Entity_Kill(whiskey);

        //Spawn a replacement at the same position
        GetRandomValueFromTable(loot_table, loot_total_weight, loot, sizeof(loot));
        if(StrEqual(loot, "nothing", false)) continue;

        converted = Weapon_Create(loot, origin, angles);
        Entity_AddEFlags(converted, EFL_NO_GAME_PHYSICS_SIMULATION | EFL_DONTBLOCKLOS);

        WriteLog("Whiskey[%d] to %s", count, loot);//TODO

        count++;
    }
}

//Spawn the fof_teamplay entity that will control the game's logic.
SpawnZombieTeamplay()
{
    new String:tmp[512];


    new ent = CreateEntityByName("fof_teamplay");
    if(IsValidEntity(ent))
    {
        DispatchKeyValue(ent, "targetname", "tpzombie");

        DispatchKeyValue(ent, "RoundBased", "1");
        DispatchKeyValue(ent, "RespawnSystem", "1");
        DispatchKeyValue(ent, "SwitchTeams", "1");

        //Todo, cvar ExtraTime and RoundTime
        Format(tmp, sizeof(tmp),                 "!self,RoundTime,%d,0,-1", GetRoundTime());
        DispatchKeyValue(ent, "OnNewRound",      tmp);
        DispatchKeyValue(ent, "OnNewRound",      "!self,ExtraTime,15,0.1,-1");

        Format(tmp, sizeof(tmp),                 "!self,ExtraTime,%d,0,-1", GetRespawnTime());
        DispatchKeyValue(ent, "OnTimerEnd",      tmp);
        DispatchKeyValue(ent, "OnTimerEnd",      "!self,InputRespawnPlayers,-2,0,-1");

        DispatchKeyValue(ent, "OnRoundTimeEnd",  "!self,InputVigVictory,,0,-1");
        DispatchKeyValue(ent, "OnNoDespAlive",   "!self,InputRespawnPlayers,-2,0,-1");
        DispatchKeyValue(ent, "OnNoVigAlive",    "!self,InputDespVictory,,0,-1");

        DispatchSpawn(ent);
        ActivateEntity(ent);
    }

    return ent;
}

stock bool:IsEnabled()
{
    return GetConVarBool(g_Cvar_Enabled);
}

stock bool:IsHuman(client)
{
    return GetClientTeam(client) == TEAM_HUMAN;
}

stock bool:IsZombie(client)
{
    return GetClientTeam(client) == TEAM_ZOMBIE;
}

stock JoinHumanTeam(client)
{
    ChangeClientTeam(client, TEAM_HUMAN);
}

stock JoinZombieTeam(client)
{
    ChangeClientTeam(client, TEAM_ZOMBIE);
}

stock RandomizeTeams()
{
    decl clients[MAXPLAYERS];
    new client_count = 0, human_count;
    new Float:ratio = GetConVarFloat(g_Cvar_Ratio);

    for(new client = 1; client <= MaxClients; client++)
    {
        if(!IsClientInGame(client)) continue;
        if(!( IsZombie(client) || IsHuman(client) )) continue;

        clients[client_count] = client;
        client_count++;
    }

    SortIntegers(clients, client_count, Sort_Random);

    //Calculate number of humans;  need at least one
    human_count = RoundToFloor(client_count * ratio);
    if(human_count == 0 && client_count > 0) human_count = 1;

    //Assign teams
    for(new i = 0; i < human_count; i++)
    {
        JoinHumanTeam(clients[i]);
    }
    for(new i = human_count; i < client_count; i++)
    {
        JoinZombieTeam(clients[i]);
    }
}

stock bool:GetRandomValueFromTable(Handle:table, total_weight, String:value[], length)
{
    new weight;
    new rand = GetRandomInt(0, total_weight - 1);

    KvRewind(table);
    KvGotoFirstSubKey(table);
    do
    {
        KvGetSectionName(table, value, length);
        weight = KvGetNum(table, "weight", 0);
        if(weight <= 0) continue;

        if(rand < weight){
            KvRewind(table);
            return true;
        }
        rand -= weight;
    }
    while(KvGotoNextKey(table));
    KvRewind(table);

    return false;
}

stock GiveInitialGear(client)
{
    new String:weapon[MAX_KEY_LENGTH];

    GetRandomValueFromTable(g_GearSecondaryTable, g_GearSecondaryTotalWeight, weapon, sizeof(weapon));
    GivePlayerItem(client, weapon);
    PrintToChat(client, "Given %s", weapon);
    //UseWeapon(client, weapon, true);

    GetRandomValueFromTable(g_GearPrimaryTable, g_GearPrimaryTotalWeight, weapon, sizeof(weapon));
    GivePlayerItem(client, weapon);
    PrintToChat(client, "Given %s", weapon);
    UseWeapon(client, weapon);
}

stock UseWeapon(client, const String:weapon[], bool second=false)
{
    new String:tmp[MAX_KEY_LENGTH];
    Format(tmp, sizeof(tmp), "use %s%s", weapon, second ? "2" : "");
    ClientCommand(client, tmp);
}

stock StripWeapons(client)
{
    new weapon_ent;
    decl String:class_name[MAX_KEY_LENGTH];
    new offs = FindSendPropInfo("CBasePlayer","m_hMyWeapons");

    for(new i = 0; i <= 47; i++)
    {
        weapon_ent = GetEntDataEnt2(client,offs + (i * 4));
        if(weapon_ent == -1) continue;

        GetEdictClassname(weapon_ent, class_name, sizeof(class_name));
        if(StrEqual(class_name, "weapon_fists")) continue;

        RemovePlayerItem(client, weapon_ent);
        RemoveEdict(weapon_ent);
    }
}

stock RandomizeModel(client)
{
    new model;

    if(IsZombie(client))
    {
        model = GetRandomInt(0, 3);
        switch (model)
        {
            case 0: { Entity_SetModelIndex(client, g_Model_Vigilante); }
            case 1: { Entity_SetModelIndex(client, g_Model_Desperado); }
            case 2: { Entity_SetModelIndex(client, g_Model_Bandido); }
            case 3: { Entity_SetModelIndex(client, g_Model_Ranger); }
        }

    } else if(IsZombie(client))
    {
        model = GetRandomInt(0, 1);
        switch (model)
        {
            case 0: { Entity_SetModelIndex(client, g_Model_Ghost); }
            case 1: { Entity_SetModelIndex(client, g_Model_Skeleton); }
        }
    }
}

stock GetViewModelIndex(client)
{
    new ent;
    while ((ent = FindEntityByClassname(ent, "predicted_viewmodel")) != -1)
    {
        new owner = GetEntPropEnt(ent, Prop_Send, "m_hOwner");

        if (owner != client) continue;

        return ent;
    }
    return INVALID_ENT_REFERENCE;
}

stock GetRoundTime()
{
    return GetConVarInt(g_Cvar_RoundTime);
}

stock GetRespawnTime()
{
    return GetConVarInt(g_Cvar_RespawnTime);
}

stock SetRoundState(FoZRoundState:round_state)
{
    WriteLog("Set RoundState: %d", round_state);
    g_RoundState = round_state;
}

stock FoZRoundState:GetRoundState()
{
    return g_RoundState;
}

stock RoundEndCheck()
{
    //Check if any Humans are alive and if not force zombies to win
    //NOTE:  The fof_teamplay entity should be handling this but there are some
    //cases where it does not work.
    if(Team_GetClientCount(TEAM_HUMAN, CLIENTFILTER_ALIVE) <= 0
        && GetRoundState() == RoundActive)
    {
        AcceptEntityInput(g_Teamplay, "InputDespVictory");
    }
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
        PrintToServer("---FoZ: %s", buf);
    }
#endif
}
