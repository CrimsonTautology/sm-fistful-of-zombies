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

#define PLUGIN_VERSION		"1.1.2"
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

#define TEAM_HUMAN              2   //Vigilantes
#define TEAM_HUMAN_STR          "2"
#define INFO_PLAYER_HUMAN       "info_player_vigilante"
#define ON_NO_HUMAN_ALIVE       "OnNoVigAlive"
#define INPUT_HUMAN_VICTORY     "InputVigVictory"

#define TEAM_ZOMBIE             3   //Desperados
#define TEAM_ZOMBIE_STR         "3"
#define INFO_PLAYER_ZOMBIE      "info_player_desperado"
#define ON_NO_ZOMBIE_ALIVE      "OnNoDespAlive"
#define INPUT_ZOMBIE_VICTORY    "InputDespVictory"

new Handle:g_Cvar_Enabled = INVALID_HANDLE;
new Handle:g_Cvar_Config = INVALID_HANDLE;
new Handle:g_Cvar_RoundTime = INVALID_HANDLE;
new Handle:g_Cvar_RespawnTime = INVALID_HANDLE;
new Handle:g_Cvar_Ratio = INVALID_HANDLE;
new Handle:g_Cvar_Infection = INVALID_HANDLE;

new Handle:g_Cvar_TeambalanceAllowed = INVALID_HANDLE;
new Handle:g_Cvar_TeamsUnbalanceLimit = INVALID_HANDLE;
new Handle:g_Cvar_Autoteambalance = INVALID_HANDLE;

new Handle:g_GearPrimaryTable = INVALID_HANDLE;
new g_GearPrimaryTotalWeight;
new bool:g_GivenPrimary[MAXPLAYERS] = {false, ...};

new Handle:g_GearSecondaryTable = INVALID_HANDLE;
new g_GearSecondaryTotalWeight;
new bool:g_GivenSecondary[MAXPLAYERS] = {false, ...};

new Handle:g_LootTable = INVALID_HANDLE;
new g_LootTotalWeight;

new g_Teamplay = INVALID_ENT_REFERENCE;
new bool:g_UndoTeamplayDescription = false;

new g_Model_Vigilante;
new g_Model_Desperado;
new g_Model_Bandido;
new g_Model_Ranger;
new g_Model_Ghost;
new g_Model_Skeleton;
new g_Model_Zombie;

//A priority scaling for assigning to the human team;  a higher value has a
//higher priority for joining humans.
new g_HumanPriority[MAXPLAYERS] = {0, ...};

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
    CreateConVar("foz_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);

    g_Cvar_Enabled = CreateConVar(
            "foz_enabled",
            "1",
            "Whether or not Fistful of Zombies is enabled");

    g_Cvar_Config = CreateConVar(
            "foz_config",
            "fistful_of_zombies.txt",
            "Location of the Fistful of Zombies configuration file",
            0);

    g_Cvar_RoundTime = CreateConVar(
            "foz_round_time",
            "120",
            "How long surviors have to survive in seconds to win a round in Fistful of Zombies",
            0);

    g_Cvar_RespawnTime = CreateConVar(
            "foz_respawn_time",
            "15",
            "How long zombies have to wait before respawning in Fistful of Zombies",
            0);

    g_Cvar_Ratio = CreateConVar(
            "foz_ratio",
            "0.65",
            "Percentage of players that start as human.",
            0,
            true, 0.01,
            true, 1.0);

    g_Cvar_Infection = CreateConVar(
            "foz_infection",
            "0.10",
            "Chance that a human will be infected when punched by a zombie.  Value is scaled such that more human players increase the chance",
            0,
            true, 0.01,
            true, 1.0);

    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_start", Event_RoundStart);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);

    RegAdminCmd("foz_dump", Command_Dump, ADMFLAG_ROOT, "TEST: Output information about the current game to console");

    AddCommandListener(Command_JoinTeam, "jointeam");

    g_Cvar_TeambalanceAllowed = FindConVar("fof_sv_teambalance_allowed");
    g_Cvar_TeamsUnbalanceLimit = FindConVar("mp_teams_unbalance_limit");
    g_Cvar_Autoteambalance = FindConVar("mp_autoteambalance");

    AddNormalSoundHook(SoundCallback);
}

public OnClientPostAdminCheck(client)
{
    if(!IsEnabled()) return;

    SDKHook(client, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
    SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);

    g_HumanPriority[client] = 0;
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
    decl String:tmp[PLATFORM_MAX_PATH];
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

    //Precache zombie sounds
    for (new i=1; i<=3; i++) {
        Format(tmp, sizeof(tmp), "npc/zombie/foot%d.wav", i);
        PrecacheSound(tmp, true);
    }

    for (new i=1; i<=14; i++) {
        Format(tmp, sizeof(tmp), "npc/zombie/moan-%02d.wav", i);
        PrecacheSound(tmp, true);
    }

    for (new i=1; i<=4; i++) {
        Format(tmp, sizeof(tmp), "npc/zombie/zombie_chase-%d.wav", i);
        PrecacheSound(tmp, true);
    }

    for (new i=1; i<=4; i++) {
        Format(tmp, sizeof(tmp), "npc/zombie/moan_loop%d.wav", i);
        PrecacheSound(tmp, true);
    }

    for (new i=1; i<=2; i++) {
        Format(tmp, sizeof(tmp), "npc/zombie/claw_miss%d.wav", i);
        PrecacheSound(tmp, true);
    }

    for (new i=1; i<=3; i++) {
        Format(tmp, sizeof(tmp), "npc/zombie/claw_strike%d.wav", i);
        PrecacheSound(tmp, true);
    }

    for (new i=1; i<=3; i++) {
        Format(tmp, sizeof(tmp), "npc/zombie/zombie_die%d.wav", i);
        PrecacheSound(tmp, true);
    }

    g_Model_Vigilante = PrecacheModel("models/playermodels/player1.mdl");
    g_Model_Desperado = PrecacheModel("models/playermodels/player2.mdl");
    g_Model_Bandido = PrecacheModel("models/playermodels/bandito.mdl");
    g_Model_Ranger = PrecacheModel("models/playermodels/frank.mdl");
    g_Model_Ghost = PrecacheModel("models/npc/ghost.mdl");
    g_Model_Skeleton = PrecacheModel("models/skeleton.mdl");
    g_Model_Zombie = PrecacheModel("models/zombies/fof_zombie.mdl");

    //Initial setup
    ConvertSpawns();
    ConvertWhiskey(g_LootTable, g_LootTotalWeight);
    g_Teamplay = SpawnZombieTeamplay();
    g_UndoTeamplayDescription = true;

    SetRoundState(RoundPre);

    CreateTimer(1.0, Timer_Repeat, .flags = TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public OnConfigsExecuted()
{
    if(!IsEnabled()) return;

    SetGameDescription(GAME_DESCRIPTION);
    SetDefaultConVars();
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
    if(!IsEnabled()) return Plugin_Continue;

    new userid = GetEventInt(event, "userid");
    RequestFrame(PlayerSpawnDelay, userid);

    return Plugin_Continue;
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

    SetRoundState(RoundGrace);
    CreateTimer(10.0, Timer_EndGrace, TIMER_FLAG_NO_MAPCHANGE);  

    ConvertWhiskey(g_LootTable, g_LootTotalWeight);
    RemoveCrates();
    RemoveTeamplayEntities();
    RandomizeTeams();
    SetDefaultConVars();
}


public Event_RoundEnd(Event:event, const String:name[], bool:dontBroadcast)
{
    if(!IsEnabled()) return;

    SetRoundState(RoundEnd);
    RewardSurvivingHumans();
}

public Action:Event_PlayerTeam(Event:event, const String:name[], bool:dontBroadcast)
{
    if(!IsEnabled()) return Plugin_Continue;

    new userid = GetEventInt(event, "userid");
    new team   = GetEventInt(event, "team");

    SetEventBroadcast(event, true);

    //If A player joins in late as a human force them to be a zombie
    if(team == TEAM_HUMAN && GetRoundState() == RoundActive)
    {
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

    g_GivenPrimary[client] = false;
    g_GivenSecondary[client] = false;

    if(IsHuman(client))
    {
        RandomizeModel(client);

        //If a player spawns as human give them their primary and secondary gear
        CreateTimer(0.2, Timer_GiveSecondaryWeapon, userid, TIMER_FLAG_NO_MAPCHANGE);  
        CreateTimer(0.3, Timer_GivePrimaryWeapon, userid, TIMER_FLAG_NO_MAPCHANGE);  

        PrintCenterText(client, "Survive the zombie plague!"); 

    } else if(IsZombie(client))
    {
        //Force client model
        Entity_SetModelIndex(client, g_Model_Zombie);
        StripWeapons(client);
        EmitZombieYell(client);

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
    if(g_GivenPrimary[client]) return Plugin_Handled;
    new String:weapon[MAX_KEY_LENGTH];

    GetRandomValueFromTable(g_GearPrimaryTable, g_GearPrimaryTotalWeight, weapon, sizeof(weapon));
    GivePlayerItem(client, weapon);
    UseWeapon(client, weapon);

    g_GivenPrimary[client] = true;

    return Plugin_Handled;
}

public Action:Timer_GiveSecondaryWeapon(Handle:timer, any:userid)
{
    new client = GetClientOfUserId(userid);

    if(!IsEnabled()) return Plugin_Handled;
    if(!Client_IsIngame(client)) return Plugin_Handled;
    if(IsZombie(client)) return Plugin_Handled;
    if(g_GivenSecondary[client]) return Plugin_Handled;

    new String:weapon[MAX_KEY_LENGTH];

    GetRandomValueFromTable(g_GearSecondaryTable, g_GearSecondaryTotalWeight, weapon, sizeof(weapon));
    GivePlayerItem(client, weapon);
    UseWeapon(client, weapon, true);

    g_GivenSecondary[client] = true;

    return Plugin_Handled;
}

public Action:Timer_EndGrace(Handle:timer)
{
    SetRoundState(RoundActive);
}

public Action:Timer_Repeat(Handle:timer)
{
    if(!IsEnabled()) return Plugin_Continue;

    //NOTE: Spawning a teamplay entity seems to now change game description to
    //Teamplay.  Need to re-set game description back to zombies next iteration.
    if (g_UndoTeamplayDescription)
    {
         SetGameDescription(GAME_DESCRIPTION);
         g_UndoTeamplayDescription = false;
    }

    RoundEndCheck();

    for (new client=1; client <= MaxClients; client++)
    {
        if(!IsClientInGame(client)) continue;


        if(IsHuman(client))
        {
            //No-op

        }else if(IsZombie(client))
        {
            StripWeapons(client);
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

public Action:Hook_OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3], damagecustom)
{
    if(!IsEnabled()) return Plugin_Continue;
    if(!Client_IsIngame(attacker)) return Plugin_Continue;
    if(!Client_IsIngame(victim)) return Plugin_Continue;
    if(attacker == victim) return Plugin_Continue;

    if(weapon > 0 && IsHuman(victim) && IsZombie(attacker))
    {
        decl String:class[MAX_KEY_LENGTH];
        GetEntityClassname(weapon, class, sizeof(class));
        if(StrEqual(class, "weapon_fists"))
        {
            //Random chance that you can be infected
            if(InfectionChanceRoll())
            {
                BecomeInfected(victim);
            }
        }

    } else if(IsHuman(victim) && IsHuman(attacker))
    {
        //Reduce the damage of friendly fire
        damage = Float:RoundToCeil(damage / 10.0);
    }

    return Plugin_Continue;
}

public Action:Command_JoinTeam(client, const String:command[], args) 
{ 
    if(!IsEnabled()) return Plugin_Continue;
    if(!Client_IsIngame(client)) return Plugin_Continue; 

    decl String:cmd[32];
    GetCmdArg(1, cmd, sizeof(cmd));

    if(GetRoundState() == RoundGrace)
    {
        //Block players switching to humans
        if(StrEqual(cmd, TEAM_HUMAN_STR, false) || StrEqual(cmd, "auto", false))
        {
            EmitSoundToClient(client, SOUND_NOPE);
            PrintCenterText(client, "I can't let you do that, starfox!"); 
            PrintToChat(client, "I can't let you do that, starfox!"); 
            return Plugin_Handled;
        }
    }

    if(GetRoundState() == RoundActive)
    {
        //If attempting to join human team or random then join zombie team
        if(StrEqual(cmd, TEAM_HUMAN_STR, false) || StrEqual(cmd, "auto", false))
        {
            return Plugin_Handled;
        }
        //If attempting to join zombie team or spectator, let them
        else if(StrEqual(cmd, TEAM_ZOMBIE_STR, false) || StrEqual(cmd, "spectate", false))
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
            //Change to zombie footsteps
            if(StrContains(sample, "player/footsteps") == 0)
            {
                Format(sample, sizeof(sample), "npc/zombie/foot%d.wav", GetRandomInt(1, 3));
                return Plugin_Changed;
            }

            //Change zombie punching
            if(StrContains(sample, "weapons/fists/fists_punch") == 0)
            {
                Format(sample, sizeof(sample), "npc/zombie/claw_strike%d.wav", GetRandomInt(1, 3));
                return Plugin_Changed;
            }
            
            //Change zombie punch missing
            if(StrContains(sample, "weapons/fists/fists_miss") == 0)
            {
                Format(sample, sizeof(sample), "npc/zombie/claw_miss%d.wav", GetRandomInt(1, 2));
                return Plugin_Changed;
            }

            //Change zombie death sound
            if(StrContains(sample, "player/voice/pain/pl_death") == 0 || StrContains(sample, "player/voice2/pain/pl_death") == 0 || StrContains(sample, "player/voice4/pain/pl_death") == 0 || StrContains(sample, "npc/mexican/death") == 0)
            {
                Format(sample, sizeof(sample), "npc/zombie/zombie_die%d.wav", GetRandomInt(1, 3));
                return Plugin_Changed;
            }

            if(StrContains(sample, "player/voice") == 0 || StrContains(sample, "npc/mexican") == 0)
            {
                Format(sample, sizeof(sample), "npc/zombie/moan-%02d.wav", GetRandomInt(1, 14));
                return Plugin_Changed;
            }
        }
    }
    return Plugin_Continue;
}

public Action:Command_Dump(caller, args)
{
    new String:tmp[32], team, health;
    PrintToConsole(caller, "---------------------------------");
    PrintToConsole(caller, "RoundState: %d", g_RoundState);
    PrintToConsole(caller, "TEAM_ZOMBIE: %d, TEAM_HUMAN: %d", TEAM_ZOMBIE, TEAM_HUMAN);
    PrintToConsole(caller, "---------------------------------");
    PrintToConsole(caller, "team          health pri user");
    for (new client=1; client <= MaxClients; client++)
    {
        if(!IsClientInGame(client)) continue;

        team = GetClientTeam(client);
        health = Entity_GetHealth(client);
        Team_GetName(team, tmp, sizeof(tmp));
        
        PrintToConsole(caller, "%13s %6d %3d %L",
                tmp,
                health,
                g_HumanPriority[client],
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

RemoveTeamplayEntities()
{
    Entity_KillAllByClassName("fof_buyzone");
}

//Change all info_player_fof spawn points to a round robin
//info_player_desperado and info_player_vigilante.
ConvertSpawns()
{
    new count = GetRandomInt(0, 1);
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
            ? Entity_Create(INFO_PLAYER_HUMAN)
            : Entity_Create(INFO_PLAYER_ZOMBIE)
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

        count++;
    }
}

//Spawn the fof_teamplay entity that will control the game's logic.
SpawnZombieTeamplay()
{
    new String:tmp[512];

    //First check if an fof_teamplay already exists
    new ent = FindEntityByClassname(INVALID_ENT_REFERENCE, "fof_teamplay");
    if(IsValidEntity(ent))
    {
        DispatchKeyValue(ent, "RespawnSystem", "1");

        //Todo, cvar ExtraTime and RoundTime
        Format(tmp, sizeof(tmp),                 "!self,RoundTime,%d,0,-1", GetRoundTime());
        DispatchKeyValue(ent, "OnNewRound",      tmp);
        DispatchKeyValue(ent, "OnNewRound",      "!self,ExtraTime,15,0.1,-1");

        Format(tmp, sizeof(tmp),                 "!self,ExtraTime,%d,0,-1", GetRespawnTime());
        DispatchKeyValue(ent, "OnTimerEnd",      tmp);
        DispatchKeyValue(ent, "OnTimerEnd",      "!self,InputRespawnPlayers,-2,0,-1");

        Format(tmp, sizeof(tmp),                 "!self,%s,,0,-1", INPUT_HUMAN_VICTORY);
        DispatchKeyValue(ent, "OnRoundTimeEnd",  tmp);
        DispatchKeyValue(ent, ON_NO_ZOMBIE_ALIVE,   "!self,InputRespawnPlayers,-2,0,-1");
        Format(tmp, sizeof(tmp),                 "!self,%s,,0,-1", INPUT_ZOMBIE_VICTORY);
        DispatchKeyValue(ent, ON_NO_HUMAN_ALIVE, tmp);

    }

    //If not create one
    else if(!IsValidEntity(ent))
    {
        ent = CreateEntityByName("fof_teamplay");
        DispatchKeyValue(ent, "targetname", "tpzombie");

        DispatchKeyValue(ent, "RoundBased", "1");
        DispatchKeyValue(ent, "RespawnSystem", "1");

        Format(tmp, sizeof(tmp),                 "!self,RoundTime,%d,0,-1", GetRoundTime());
        DispatchKeyValue(ent, "OnNewRound",      tmp);
        DispatchKeyValue(ent, "OnNewRound",      "!self,ExtraTime,15,0.1,-1");

        Format(tmp, sizeof(tmp),                 "!self,ExtraTime,%d,0,-1", GetRespawnTime());
        DispatchKeyValue(ent, "OnTimerEnd",      tmp);
        DispatchKeyValue(ent, "OnTimerEnd",      "!self,InputRespawnPlayers,-2,0,-1");

        Format(tmp, sizeof(tmp),                 "!self,%s,,0,-1", INPUT_HUMAN_VICTORY);
        DispatchKeyValue(ent, "OnRoundTimeEnd",  tmp);
        DispatchKeyValue(ent, ON_NO_ZOMBIE_ALIVE,   "!self,InputRespawnPlayers,-2,0,-1");
        Format(tmp, sizeof(tmp),                 "!self,%s,,0,-1", INPUT_ZOMBIE_VICTORY);
        DispatchKeyValue(ent, ON_NO_HUMAN_ALIVE, tmp);

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
    new client_count = 0, human_count, client;
    new Float:ratio = GetConVarFloat(g_Cvar_Ratio);

    for(client = 1; client <= MaxClients; client++)
    {
        if(!IsClientInGame(client)) continue;
        if(!( IsZombie(client) || IsHuman(client) )) continue;

        clients[client_count] = client;
        client_count++;
    }

    SortCustom1D(clients, client_count, Sort_HumanPriority);

    //Calculate number of humans;  need at least one
    human_count = RoundToFloor(client_count * ratio);
    if(human_count == 0 && client_count > 0) human_count = 1;

    //Assign teams; modify priority for next round
    for(new i = 0; i < human_count; i++)
    {
        client = clients[i];
        JoinHumanTeam(client);
        g_HumanPriority[client]--;
    }
    for(new i = human_count; i < client_count; i++)
    {
        client = clients[i];
        JoinZombieTeam(clients[i]);
        g_HumanPriority[client]++;
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

stock EmitZombieYell(client)
{
    decl String:tmp[PLATFORM_MAX_PATH];
    Format(tmp, sizeof(tmp), "npc/zombie/zombie_chase-%d.wav", GetRandomInt(1, 4));
    EmitSoundToAll(tmp, client, SNDCHAN_AUTO, SNDLEVEL_SCREAMING, SND_CHANGEPITCH, SNDVOL_NORMAL, GetRandomInt(85, 110));
}

stock RandomizeModel(client)
{
    new model;

    if(IsHuman(client))
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
        model = GetRandomInt(0, 2);
        switch (model)
        {
            case 0: { Entity_SetModelIndex(client, g_Model_Ghost); }
            case 1: { Entity_SetModelIndex(client, g_Model_Skeleton); }
            case 2: { Entity_SetModelIndex(client, g_Model_Zombie); }
        }
    }
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

stock bool:InfectionChanceRoll()
{
    new humans = Team_GetClientCount(TEAM_HUMAN, CLIENTFILTER_ALIVE);
    //Last human can't be infected
    if(humans <= 1) return false;

    new Float:chance = GetConVarFloat(g_Cvar_Infection);

    return GetURandomFloat() < chance;
}

stock BecomeInfected(client)
{
    Entity_ChangeOverTime(client, 0.1, InfectionStep);
}

stock InfectedToZombie(client)
{
    StripWeapons(client);
    UseWeapon(client, "weapon_fists");

    JoinZombieTeam(client);
    Entity_SetModelIndex(client, g_Model_Zombie);

    EmitZombieYell(client);
    SetEntPropFloat(client, Prop_Send, "m_flDrunkness", 0.0);

    PrintCenterTextAll("%N has succumbed to the infection...", client);
    EmitSoundToAll(SOUND_STINGER, .flags = SND_CHANGEPITCH, .pitch = 80);
}

public bool:InfectionStep(&client, &Float:interval, &currentCall)
{
    //This steps through the process of an infected human to a zombie
    //Takes 300 steps or 30 seconds
    if(!IsEnabled()) return false;
    if(!Client_IsIngame(client)) return false;
    if(!IsPlayerAlive(client)) return false;
    if(!IsHuman(client)) return false;
    if(GetRoundState() != RoundActive) return false;
    if(Team_GetClientCount(TEAM_HUMAN, CLIENTFILTER_ALIVE) <= 1) return false;

    //Become drunk 2/3 of the way through
    if(currentCall > 200)
    {
        new Float:drunkness = GetEntPropFloat(client, Prop_Send, "m_flDrunkness");
        drunkness = currentCall * 1.0;
        SetEntPropFloat(client, Prop_Send, "m_flDrunkness", drunkness);
    }

    //All the way through, change client into a zombie
    if(currentCall > 300)
    {
        InfectedToZombie(client);
        return false;
    }

    if(currentCall > 250 && (2 * GetURandomFloat()) < (currentCall / 300.0))
    {
        FakeClientCommand(client, "vc 15");
    }

    return true;
}

stock RoundEndCheck()
{
    //Check if any Humans are alive and if not force zombies to win
    //NOTE:  The fof_teamplay entity should be handling this but there are some
    //cases where it does not work.
    if(GetRoundState() == RoundActive
            && Team_GetClientCount(TEAM_HUMAN, CLIENTFILTER_ALIVE) <= 0)
    {
        AcceptEntityInput(g_Teamplay, INPUT_ZOMBIE_VICTORY);
    }
}

stock BecomeGhost(client)
{
    Entity_SetModelIndex(client, g_Model_Ghost);
    StripWeapons(client);
    SetEntityMoveType(client, MOVETYPE_FLY);
    SetEntProp(client, Prop_Data, "m_MoveCollide", 1);
    Entity_SetMaxHealth(client, 25);
    ChangeEdictState(client);
}

public Sort_HumanPriority(elem1, elem2, const array[], Handle:hndl)
{
    if(g_HumanPriority[elem1] < g_HumanPriority[elem2]) return  1;
    if(g_HumanPriority[elem1] > g_HumanPriority[elem2]) return  -1;

    return GetURandomFloat() < 0.5 ? 1 : -1;  
}

public RewardSurvivingHumans()
{
    //Called at round end to give rewards to surviving humans.  Currently used
    //to pump their priority by one so they have a better chance to be human
    //next round.

    for(new client = 0; client < MaxClients; client++)
    {
        if(!Client_IsIngame(client)) continue;
        if(!IsPlayerAlive(client)) continue;
        if(!IsHuman(client)) continue;

        g_HumanPriority[client]++;
    }
}

stock bool:SetGameDescription(String:description[])
{
#if defined _SteamWorks_Included
    return SteamWorks_SetGameDescription(description);
#else
    return false;
#endif
}

stock WriteLog(const String:format[], any:... )
{
#if defined DEBUG
    if(format[0] != '\0')
    {
        decl String:buf[2048];
        VFormat(buf, sizeof(buf), format, 2 );
        PrintToServer("[FoZ] %s", buf);
    }
#endif
}
