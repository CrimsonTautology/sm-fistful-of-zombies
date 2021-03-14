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

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib/clients>
#include <smlib/teams>
#include <smlib/entities>
#include <smlib/weapons>
#undef REQUIRE_EXTENSIONS
#tryinclude <steamworks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.10.1"
#define PLUGIN_NAME "[FoF] Fistful Of Zombies"

#define MAX_KEY_LENGTH 128
#define MAX_TABLE 128
#define INFECTION_LIMIT 100.0
#define VOICE_SCALE 12.0

#define GAME_DESCRIPTION "Fistful Of Zombies"
#define SOUND_ROUNDSTART "music/standoff1.mp3"
#define SOUND_STINGER "music/kill1.wav"
#define SOUND_NOPE "player/voice/no_no1.wav"

#define TEAM_HUMAN 2  // Vigilantes
#define TEAM_HUMAN_STR "2"
#define INFO_PLAYER_HUMAN "info_player_vigilante"
#define ON_NO_HUMAN_ALIVE "OnNoVigAlive"
#define INPUT_HUMAN_VICTORY "InputVigVictory"

#define TEAM_ZOMBIE 3  // Desperados
#define TEAM_ZOMBIE_STR "3"
#define INFO_PLAYER_ZOMBIE "info_player_desperado"
#define ON_NO_ZOMBIE_ALIVE "OnNoDespAlive"
#define INPUT_ZOMBIE_VICTORY "InputDespVictory"

ConVar g_EnabledCvar;
ConVar g_ConfigFileCvar;
ConVar g_RoundTimeCvar;
ConVar g_RespawnTimeCvar;
ConVar g_RatioCvar;
ConVar g_InfectionCvar;

ConVar g_TeambalanceAllowedCvar;
ConVar g_TeamsUnbalanceLimitCvar;
ConVar g_AutoteambalanceCvar;

KeyValues g_GearPrimaryTable;
int g_GearPrimaryTotalWeight;
bool g_GivenPrimary[MAXPLAYERS+1] = {false, ...};

KeyValues g_GearSecondaryTable;
int g_GearSecondaryTotalWeight;
bool g_GivenSecondary[MAXPLAYERS+1] = {false, ...};

KeyValues g_LootTable;
int g_LootTotalWeight;

int g_TeamplayEntity = INVALID_ENT_REFERENCE;
bool g_AutoSetGameDescription = false;

int g_VigilanteModelIndex;
int g_DesperadoModelIndex;
int g_BandidoModelIndex;
int g_RangerModelIndex;
int g_ZombieModelIndex;

// a priority scaling for assigning to the human team;  a higher value has a
// higher priority for joining humans.
int g_HumanPriority[MAXPLAYERS+1] = {0, ...};

enum FoZRoundState
{
    RoundPre,
    RoundGrace,
    RoundActive,
    RoundEnd
}
FoZRoundState g_RoundState = RoundPre;

public Plugin myinfo =
{
    name = PLUGIN_NAME,
    author = "CrimsonTautology",
    description = "Zombie Survival for Fistful of Frags",
    version = PLUGIN_VERSION,
    url = "https://github.com/CrimsonTautology/sm-fistful-of-zombies"
};

public void OnPluginStart()
{
    CreateConVar("foz_version", PLUGIN_VERSION, PLUGIN_NAME,
            FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);

    g_EnabledCvar = CreateConVar(
            "foz_enabled",
            "1",
            "Whether or not Fistful of Zombies is enabled");

    g_ConfigFileCvar = CreateConVar(
            "foz_config",
            "configs/fistful_of_zombies.txt",
            "Location of the Fistful of Zombies configuration file",
            0);

    g_RoundTimeCvar = CreateConVar(
            "foz_round_time",
            "120",
            "How long survivors have to survive in seconds to win a round in Fistful of Zombies",
            0);

    g_RespawnTimeCvar = CreateConVar(
            "foz_respawn_time",
            "15",
            "How long zombies have to wait before respawning in Fistful of Zombies",
            0);

    g_RatioCvar = CreateConVar(
            "foz_ratio",
            "0.65",
            "Percentage of players that start as human.",
            0,
            true, 0.01,
            true, 1.0);

    g_InfectionCvar = CreateConVar(
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

    RegAdminCmd("foz_dump", Command_Dump, ADMFLAG_ROOT,
            "Debug: Output information about the current game to console");

    RegAdminCmd("foz_reload", Command_Reload, ADMFLAG_ROOT,
            "Force a reload of the configuration file");

    AddCommandListener(Command_JoinTeam, "jointeam");

    g_TeambalanceAllowedCvar = FindConVar("fof_sv_teambalance_allowed");
    g_TeamsUnbalanceLimitCvar = FindConVar("mp_teams_unbalance_limit");
    g_AutoteambalanceCvar = FindConVar("mp_autoteambalance");

    AddNormalSoundHook(SoundCallback);

    InitializeFOZ();
}

public void OnClientPutInServer(int client)
{
    if (!IsEnabled()) return;

    SDKHook(client, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
    SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);

    g_HumanPriority[client] = 0;
}

public void OnMapStart()
{
    if (!IsEnabled()) return;

    char tmp[PLATFORM_MAX_PATH];

    // cache materials
    PrecacheSound(SOUND_ROUNDSTART, true);
    PrecacheSound(SOUND_STINGER, true);
    PrecacheSound(SOUND_NOPE, true);

    // precache zombie sounds
    for (int i = 1; i <= 3; i++)
    {
        Format(tmp, sizeof(tmp), "npc/zombie/foot%d.wav", i);
        PrecacheSound(tmp, true);
    }

    for (int i = 1; i <= 14; i++)
    {
        Format(tmp, sizeof(tmp), "npc/zombie/moan-%02d.wav", i);
        PrecacheSound(tmp, true);
    }

    for (int i = 1; i <= 4; i++)
    {
        Format(tmp, sizeof(tmp), "npc/zombie/zombie_chase-%d.wav", i);
        PrecacheSound(tmp, true);
    }

    for (int i = 1; i <= 4; i++)
    {
        Format(tmp, sizeof(tmp), "npc/zombie/moan_loop%d.wav", i);
        PrecacheSound(tmp, true);
    }

    for (int i = 1; i <= 2; i++)
    {
        Format(tmp, sizeof(tmp), "npc/zombie/claw_miss%d.wav", i);
        PrecacheSound(tmp, true);
    }

    for (int i = 1; i <= 3; i++)
    {
        Format(tmp, sizeof(tmp), "npc/zombie/claw_strike%d.wav", i);
        PrecacheSound(tmp, true);
    }

    for (int i = 1; i <= 3; i++)
    {
        Format(tmp, sizeof(tmp), "npc/zombie/zombie_die%d.wav", i);
        PrecacheSound(tmp, true);
    }

    PrecacheSound("vehicles/train/whistle.wav", true);
    PrecacheSound("player/fallscream1.wav", true);

    g_VigilanteModelIndex = PrecacheModel("models/playermodels/player1.mdl");
    g_DesperadoModelIndex = PrecacheModel("models/playermodels/player2.mdl");
    g_BandidoModelIndex = PrecacheModel("models/playermodels/bandito.mdl");
    g_RangerModelIndex = PrecacheModel("models/playermodels/frank.mdl");
    g_ZombieModelIndex = PrecacheModel("models/zombies/fof_zombie.mdl");

    // initial setup
    ConvertSpawns();
    ConvertWhiskey(g_LootTable, g_LootTotalWeight);
    g_TeamplayEntity = SpawnZombieTeamplayEntity();
    g_AutoSetGameDescription = true;

    SetRoundState(RoundPre);

    CreateTimer(1.0, Timer_Repeat, .flags = TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void OnConfigsExecuted()
{
    if (!IsEnabled()) return;

    SetGameDescription(GAME_DESCRIPTION);
    SetDefaultConVars();
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsEnabled()) return;

    int userid = event.GetInt("userid");
    RequestFrame(PlayerSpawnDelay, userid);
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsEnabled()) return;

    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);

    // a dead human becomes a zombie
    if (IsHuman(client))
    {
        // announce the death
        PrintCenterTextAll("%N has turned...", client);
        EmitSoundToAll(SOUND_STINGER, .flags = SND_CHANGEPITCH, .pitch = 80);

        RequestFrame(BecomeZombieDelay, userid);
    }
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsEnabled()) return;

    SetRoundState(RoundGrace);
    CreateTimer(10.0, Timer_EndGrace, TIMER_FLAG_NO_MAPCHANGE);

    ConvertWhiskey(g_LootTable, g_LootTotalWeight);
    RemoveCrates();
    RemoveTeamplayEntities();
    RandomizeTeams();
    SetDefaultConVars();
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsEnabled()) return;

    SetRoundState(RoundEnd);
    RewardSurvivingHumans();
}

Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsEnabled()) return Plugin_Continue;

    int userid = event.GetInt("userid");
    int team = event.GetInt("team");

    event.BroadcastDisabled = true;

    // if A player joins in late as a human force them to be a zombie
    if (team == TEAM_HUMAN && GetRoundState() == RoundActive)
    {
        RequestFrame(BecomeZombieDelay, userid);
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

void PlayerSpawnDelay(int userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsEnabled()) return;
    if (!IsClientIngame(client)) return;
    if (!IsPlayerAlive(client)) return;

    g_GivenPrimary[client] = false;
    g_GivenSecondary[client] = false;

    if (IsHuman(client))
    {
        RandomizeModel(client);

        // if a player spawns as human give them their primary and secondary
        // gear
        CreateTimer(0.2, Timer_GiveSecondaryWeapon, userid,
                TIMER_FLAG_NO_MAPCHANGE);
        CreateTimer(0.3, Timer_GivePrimaryWeapon, userid,
                TIMER_FLAG_NO_MAPCHANGE);

        PrintCenterText(client, "Survive the zombie plague!");
    }
    else if (IsZombie(client))
    {
        // force client model
        RandomizeModel(client);
        StripWeapons(client);
        EmitZombieYell(client);

        PrintCenterText(client, "Ughhhh..... BRAINNNSSSS");
    }
}

void BecomeZombieDelay(int userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsEnabled()) return;
    if (!IsClientIngame(client)) return;

    JoinZombieTeam(client);
}

Action Timer_GivePrimaryWeapon(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsEnabled()) return Plugin_Handled;
    if (!IsClientIngame(client)) return Plugin_Handled;
    if (IsZombie(client)) return Plugin_Handled;
    if (g_GivenPrimary[client]) return Plugin_Handled;
    char weapon[MAX_KEY_LENGTH];

    GetRandomValueFromTable(g_GearPrimaryTable, g_GearPrimaryTotalWeight,
            weapon, sizeof(weapon));
    GivePlayerItem(client, weapon);
    UseWeapon(client, weapon);

    g_GivenPrimary[client] = true;

    return Plugin_Handled;
}

Action Timer_GiveSecondaryWeapon(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsEnabled()) return Plugin_Handled;
    if (!IsClientIngame(client)) return Plugin_Handled;
    if (IsZombie(client)) return Plugin_Handled;
    if (g_GivenSecondary[client]) return Plugin_Handled;

    char weapon[MAX_KEY_LENGTH];

    GetRandomValueFromTable(g_GearSecondaryTable, g_GearSecondaryTotalWeight,
            weapon, sizeof(weapon));
    GivePlayerItem(client, weapon);
    UseWeapon(client, weapon, true);

    g_GivenSecondary[client] = true;

    return Plugin_Handled;
}

Action Timer_EndGrace(Handle timer)
{
    SetRoundState(RoundActive);
}

Action Timer_Repeat(Handle timer)
{
    if (!IsEnabled()) return Plugin_Continue;

    // NOTE: Spawning a teamplay entity seems to now change game description to
    // Teamplay.  Need to re-set game description back to zombies next
    // iteration.
    if (g_AutoSetGameDescription)
    {
        SetGameDescription(GAME_DESCRIPTION);
        g_AutoSetGameDescription = false;
    }

    RoundEndCheck();

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client)) continue;

        if (IsHuman(client))
        {
            // no-op
        }
        else if (IsZombie(client))
        {
            StripWeapons(client);
        }
    }

    return Plugin_Handled;
}

Action Hook_OnWeaponCanUse(int client, int weapon)
{
    if (!IsEnabled()) return Plugin_Continue;

    // block zombies from picking up guns
    if (IsZombie(client))
    {
        char class[MAX_KEY_LENGTH];
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

Action Hook_OnTakeDamage(int victim, int& attacker, int& inflictor,
        float& damage, int& damagetype, int& weapon, float damageForce[3],
        float damagePosition[3])
{
    if (!IsEnabled()) return Plugin_Continue;
    if (!IsClientIngame(attacker)) return Plugin_Continue;
    if (!IsClientIngame(victim)) return Plugin_Continue;
    if (attacker == victim) return Plugin_Continue;

    if (weapon > 0 && IsHuman(victim) && IsZombie(attacker))
    {
        char class[MAX_KEY_LENGTH];
        GetEntityClassname(weapon, class, sizeof(class));
        if (StrEqual(class, "weapon_fists"))
        {
            // random chance that you can be infected
            if (InfectionChanceRoll())
            {
                BecomeInfected(victim);
            }
        }

    }
    else if (IsHuman(victim) && IsHuman(attacker))
    {
        // reduce the damage of friendly fire
        damage = view_as<float>(RoundToCeil(damage / 10.0));
    }

    return Plugin_Continue;
}

Action Command_JoinTeam(int client, const char[] command, int argc)
{
    if (!IsEnabled()) return Plugin_Continue;
    if (!IsClientIngame(client)) return Plugin_Continue;

    char arg[32];
    GetCmdArg(1, arg, sizeof(arg));

    if (GetRoundState() == RoundGrace)
    {
        // block players switching to humans
        if (StrEqual(arg, TEAM_HUMAN_STR, false) ||
                StrEqual(arg, "auto", false))
        {
            EmitSoundToClient(client, SOUND_NOPE);
            PrintCenterText(client, "You cannot change teams");
            PrintToChat(client, "You cannot change teams");
            return Plugin_Handled;
        }
    }

    if (GetRoundState() == RoundActive)
    {
        // if attempting to join human team or random then join zombie team
        if (StrEqual(arg, TEAM_HUMAN_STR, false) ||
                StrEqual(arg, "auto", false))
        {
            return Plugin_Handled;
        }
        // if attempting to join zombie team or spectator, let them
        else if (StrEqual(arg, TEAM_ZOMBIE_STR, false) ||
                StrEqual(arg, "spectate", false))
        {
            return Plugin_Continue;
        }
        // prevent joining any other team
        else
        {
            return Plugin_Handled;
        }
    }

    return Plugin_Continue;
}

Action SoundCallback(int clients[MAXPLAYERS], int &numClients,
        char sample[PLATFORM_MAX_PATH], int &entity, int &channel,
        float &volume, int &level, int &pitch, int &flags,
        char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
    if (0 < entity <= MaxClients)
    {
        // change the voice of zombie players
        if (IsZombie(entity))
        {
            // change to zombie footsteps
            if (StrContains(sample, "player/footsteps") == 0)
            {
                Format(sample, sizeof(sample), "npc/zombie/foot%d.wav",
                        GetRandomInt(1, 3));
                return Plugin_Changed;
            }

            // change zombie punching
            if (StrContains(sample, "weapons/fists/fists_punch") == 0)
            {
                Format(sample, sizeof(sample), "npc/zombie/claw_strike%d.wav",
                        GetRandomInt(1, 3));
                return Plugin_Changed;
            }

            // change zombie punch missing
            if (StrContains(sample, "weapons/fists/fists_miss") == 0)
            {
                Format(sample, sizeof(sample), "npc/zombie/claw_miss%d.wav",
                        GetRandomInt(1, 2));
                return Plugin_Changed;
            }

            // change zombie death sound
            if (StrContains(sample, "player/voice/pain/pl_death") == 0 ||
                    StrContains(sample, "player/voice2/pain/pl_death") == 0 ||
                    StrContains(sample, "player/voice4/pain/pl_death") == 0 ||
                    StrContains(sample, "npc/mexican/death") == 0)
            {
                Format(sample, sizeof(sample), "npc/zombie/zombie_die%d.wav",
                        GetRandomInt(1, 3));
                return Plugin_Changed;
            }

            if (StrContains(sample, "player/voice") == 0 ||
                    StrContains(sample, "npc/mexican") == 0)
            {
                Format(sample, sizeof(sample), "npc/zombie/moan-%02d.wav",
                        GetRandomInt(1, 14));
                return Plugin_Changed;
            }
        }
    }
    return Plugin_Continue;
}

Action Command_Dump(int caller, int args)
{
    char tmp[32];
    int team, health;
    PrintToConsole(caller, "---------------------------------");
    PrintToConsole(caller, "RoundState: %d", g_RoundState);
    PrintToConsole(caller, "TEAM_ZOMBIE: %d, TEAM_HUMAN: %d", TEAM_ZOMBIE, TEAM_HUMAN);
    PrintToConsole(caller, "---------------------------------");
    PrintToConsole(caller, "team          health pri user");
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client)) continue;

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

Action Command_Reload(int caller, int args)
{
    InitializeFOZ();
    return Plugin_Handled;
}

void InitializeFOZ()
{
    // load configuration
    char file[PLATFORM_MAX_PATH];
    g_ConfigFileCvar.GetString(file, sizeof(file));

    KeyValues config = LoadFOZFile(file);

    delete g_LootTable;
    g_LootTable = BuildWeightTable(
            config, "loot", g_LootTotalWeight);

    delete g_GearPrimaryTable;
    g_GearPrimaryTable = BuildWeightTable(
            config, "gear_primary", g_GearPrimaryTotalWeight);

    delete g_GearSecondaryTable;
    g_GearSecondaryTable = BuildWeightTable(
            config, "gear_secondary", g_GearSecondaryTotalWeight);

    delete config;
}

KeyValues LoadFOZFile(const char[] file)
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), file);
    WriteLog("LoadFOZFile %s", path);

    KeyValues config = new KeyValues("fistful_of_zombies");
    if (!config.ImportFromFile(path))
    {
        LogError("Could not read map rotation file \"%s\"", file);
        SetFailState("Could not read map rotation file \"%s\"", file);
        return null;
    }

    return config;
}

// build a table for randomly selecting a weighted value
KeyValues BuildWeightTable(KeyValues config, const char[] name,
        int& total_weight)
{
    char key[MAX_KEY_LENGTH];
    int weight;
    KeyValues table = new KeyValues(name);

    total_weight = 0;

    config.Rewind();
    WriteLog("BuildWeightTable %s start", name);

    if (config.JumpToKey(name))
    {
        table.Import(config);

        config.GotoFirstSubKey();
        do
        {
            config.GetSectionName(key, sizeof(key));
            weight = config.GetNum("weight", 0);

            // ignore values that do not have a weight or 0 weight
            if (weight > 0)
            {
                total_weight += weight;
            }
            WriteLog("BuildWeightTable %s key: %s, weight: %d",
                    name, key, weight);
        }
        while(config.GotoNextKey());

    }
    else
    {
        LogError("A valid \"%s\" key was not defined", name);
        SetFailState("A valid \"%s\" key was not defined", name);
    }
    WriteLog("BuildWeightTable %s end total_weight: %d", name, total_weight);

    return table;
}

void SetDefaultConVars()
{
    g_TeambalanceAllowedCvar.SetInt(0, false, false);
    g_TeamsUnbalanceLimitCvar.SetInt(0, false, false);
    g_AutoteambalanceCvar.SetInt(0, false, false);
}

void RemoveCrates()
{
    Entity_KillAllByClassName("fof_crate*");
}

void RemoveTeamplayEntities()
{
    Entity_KillAllByClassName("fof_buyzone");
}

// change all info_player_fof spawn points to a round robin
// info_player_desperado and info_player_vigilante.
void ConvertSpawns()
{
    int count = GetRandomInt(0, 1);
    int spawn = INVALID_ENT_REFERENCE;
    int converted = INVALID_ENT_REFERENCE;
    float origin[3], angles[3];

    while((spawn = FindEntityByClassname(spawn, "info_player_fof")) != INVALID_ENT_REFERENCE)
    {
        // get original's position and remove it
        Entity_GetAbsOrigin(spawn, origin);
        Entity_GetAbsAngles(spawn, angles);
        Entity_Kill(spawn);

        // spawn a replacement at the same position
        converted = count % 2 == 0
            ? Entity_Create(INFO_PLAYER_HUMAN)
            : Entity_Create(INFO_PLAYER_ZOMBIE)
            ;
        if (IsValidEntity(converted))
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

// whiskey is used as the spawn points for the random loot accross the map,
// every whiskey entity is removed and replaced with a random item/weapon.
void ConvertWhiskey(KeyValues loot_table, int loot_total_weight)
{
    char loot[MAX_KEY_LENGTH];
    int count = 0;
    int whiskey = INVALID_ENT_REFERENCE;
    int converted = INVALID_ENT_REFERENCE;
    float origin[3], angles[3];

    while((whiskey = FindEntityByClassname(whiskey, "item_whiskey")) != INVALID_ENT_REFERENCE)
    {
        // get original's position and remove it
        Entity_GetAbsOrigin(whiskey, origin);
        Entity_GetAbsAngles(whiskey, angles);
        Entity_Kill(whiskey);

        // spawn a replacement at the same position
        GetRandomValueFromTable(loot_table, loot_total_weight, loot,
                sizeof(loot));
        if (StrEqual(loot, "nothing", false)) continue;

        converted = Weapon_Create(loot, origin, angles);
        Entity_AddEFlags(converted, EFL_NO_GAME_PHYSICS_SIMULATION | EFL_DONTBLOCKLOS);

        count++;
    }
}

// spawn the fof_teamplay entity that will control the game's logic.
int SpawnZombieTeamplayEntity()
{
    char tmp[512];

    // first check if an fof_teamplay already exists
    int ent = FindEntityByClassname(INVALID_ENT_REFERENCE, "fof_teamplay");
    if (IsValidEntity(ent))
    {
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

    }

    // if not create one
    else if (!IsValidEntity(ent))
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

bool IsEnabled()
{
    return g_EnabledCvar.BoolValue;
}

bool IsHuman(int client)
{
    return GetClientTeam(client) == TEAM_HUMAN;
}

bool IsZombie(int client)
{
    return GetClientTeam(client) == TEAM_ZOMBIE;
}

void JoinHumanTeam(int client)
{
    ChangeClientTeam(client, TEAM_HUMAN);
}

void JoinZombieTeam(int client)
{
    ChangeClientTeam(client, TEAM_ZOMBIE);
}

void RandomizeTeams()
{
    int clients[MAXPLAYERS+1];
    int client_count = 0, human_count, client;
    float ratio = g_RatioCvar.FloatValue;

    for (client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client)) continue;
        if (!(IsZombie(client) || IsHuman(client))) continue;

        clients[client_count] = client;
        client_count++;
    }

    SortCustom1D(clients, client_count, Sort_HumanPriority);

    // calculate number of humans;  need at least one
    human_count = RoundToFloor(client_count * ratio);
    if (human_count == 0 && client_count > 0) human_count = 1;

    // assign teams; modify priority for next round
    for (int i = 0; i < human_count; i++)
    {
        client = clients[i];
        JoinHumanTeam(client);
        g_HumanPriority[client]--;
    }
    for (int i = human_count; i < client_count; i++)
    {
        client = clients[i];
        JoinZombieTeam(clients[i]);
        g_HumanPriority[client]++;
    }
}

bool GetRandomValueFromTable(KeyValues table, int total_weight, char[] value,
        int length)
{
    int weight;
    int rand = GetRandomInt(0, total_weight - 1);

    table.Rewind();
    table.GotoFirstSubKey();
    WriteLog("GetRandomValueFromTable total_weight: %d, rand: %d",
            total_weight, rand);
    do
    {
        table.GetSectionName(value, length);
        weight = table.GetNum("weight", 0);
        WriteLog("GetRandomValueFromTable value: %s, weight: %d",
                value, weight);
        if (weight <= 0) continue;

        if (rand < weight)
        {
            return true;
        }
        rand -= weight;
    }
    while(table.GotoNextKey());

    return false;
}

void UseWeapon(int client, const char[] weapon, bool second=false)
{
    char tmp[MAX_KEY_LENGTH];
    Format(tmp, sizeof(tmp), "use %s%s", weapon, second ? "2" : "");
    ClientCommand(client, tmp);
}

void StripWeapons(int client)
{
    int weapon_ent;
    char class_name[MAX_KEY_LENGTH];
    int offs = FindSendPropInfo("CBasePlayer","m_hMyWeapons");

    for (int i = 0; i <= 47; i++)
    {
        weapon_ent = GetEntDataEnt2(client,offs + (i * 4));
        if (weapon_ent == -1) continue;

        GetEdictClassname(weapon_ent, class_name, sizeof(class_name));
        if (StrEqual(class_name, "weapon_fists")) continue;

        RemovePlayerItem(client, weapon_ent);
        RemoveEdict(weapon_ent);
    }
}

void EmitZombieYell(int client)
{
    char tmp[PLATFORM_MAX_PATH];
    Format(tmp, sizeof(tmp), "npc/zombie/zombie_chase-%d.wav",
            GetRandomInt(1, 4));
    EmitSoundToAll(tmp, client, SNDCHAN_AUTO, SNDLEVEL_SCREAMING,
            SND_CHANGEPITCH, SNDVOL_NORMAL, GetRandomInt(85, 110));
}

void RandomizeModel(int client)
{
    int model;

    if (IsHuman(client))
    {
        model = GetRandomInt(0, 3);
        switch (model)
        {
            case 0: { Entity_SetModelIndex(client, g_VigilanteModelIndex); }
            case 1: { Entity_SetModelIndex(client, g_DesperadoModelIndex); }
            case 2: { Entity_SetModelIndex(client, g_BandidoModelIndex); }
            case 3: { Entity_SetModelIndex(client, g_RangerModelIndex); }
        }

    }
    else if (IsZombie(client))
    {
        model = GetRandomInt(0, 0);
        switch (model)
        {
            case 0: { Entity_SetModelIndex(client, g_ZombieModelIndex); }
        }
    }
}

int GetRoundTime()
{
    return g_RoundTimeCvar.IntValue;
}

int GetRespawnTime()
{
    return g_RespawnTimeCvar.IntValue;
}

void SetRoundState(FoZRoundState round_state)
{
    WriteLog("Set RoundState: %d", round_state);
    g_RoundState = round_state;
}

FoZRoundState GetRoundState()
{
    return g_RoundState;
}

bool InfectionChanceRoll()
{
    int humans = Team_GetClientCount(TEAM_HUMAN, CLIENTFILTER_ALIVE);
    // last human can't be infected
    if (humans <= 1) return false;

    float chance = g_InfectionCvar.FloatValue;

    return GetURandomFloat() < chance;
}

void BecomeInfected(int client)
{
    Entity_ChangeOverTime(client, 0.1, InfectionStep);
}

void InfectedToZombie(int client)
{
    StripWeapons(client);
    UseWeapon(client, "weapon_fists");

    JoinZombieTeam(client);
    Entity_SetModelIndex(client, g_ZombieModelIndex);

    EmitZombieYell(client);
    SetEntPropFloat(client, Prop_Send, "m_flDrunkness", 0.0);

    PrintCenterTextAll("%N has succumbed to the infection...", client);
    EmitSoundToAll(SOUND_STINGER, .flags = SND_CHANGEPITCH, .pitch = 80);
}

bool InfectionStep(int& client, float& interval, int& currentCall)
{
    // this steps through the process of an infected human to a zombie takes
    // 300 steps or 30 seconds
    if (!IsEnabled()) return false;
    if (!IsClientIngame(client)) return false;
    if (!IsPlayerAlive(client)) return false;
    if (!IsHuman(client)) return false;
    if (GetRoundState() != RoundActive) return false;
    if (Team_GetClientCount(TEAM_HUMAN, CLIENTFILTER_ALIVE) <= 1) return false;

    // become drunk 2/3 of the way through
    if (currentCall > 200)
    {
        float drunkness = GetEntPropFloat(client, Prop_Send, "m_flDrunkness");
        drunkness = currentCall * 1.0;
        SetEntPropFloat(client, Prop_Send, "m_flDrunkness", drunkness);
    }

    // all the way through, change client into a zombie
    if (currentCall > 300)
    {
        InfectedToZombie(client);
        return false;
    }

    if (currentCall > 250 && (2 * GetURandomFloat()) < (currentCall / 300.0))
    {
        FakeClientCommand(client, "vc 15");
    }

    return true;
}

void RoundEndCheck()
{
    // check if any Humans are alive and if not force zombies to win
    // NOTE:  The fof_teamplay entity should be handling this but there are
    // some cases where it does not work.
    if (GetRoundState() == RoundActive
            && Team_GetClientCount(TEAM_HUMAN, CLIENTFILTER_ALIVE) <= 0)
    {
        AcceptEntityInput(g_TeamplayEntity, INPUT_ZOMBIE_VICTORY);
    }
}

int Sort_HumanPriority(int elem1, int elem2, const array[], Handle hndl)
{
    if (g_HumanPriority[elem1] < g_HumanPriority[elem2]) return 1;
    if (g_HumanPriority[elem1] > g_HumanPriority[elem2]) return -1;

    return GetURandomFloat() < 0.5 ? 1 : -1;
}

void RewardSurvivingHumans()
{
    // Called at round end to give rewards to surviving humans.  Currently used
    // to pump their priority by one so they have a better chance to be human
    // next round.

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientIngame(client)) continue;
        if (!IsPlayerAlive(client)) continue;
        if (!IsHuman(client)) continue;

        g_HumanPriority[client]++;
    }
}

bool SetGameDescription(const char[] description)
{
#if defined _SteamWorks_Included
    return SteamWorks_SetGameDescription(description);
#else
    return false;
#endif
}

stock bool IsClientIngame(int client)
{
	if (client > 4096) {
		client = EntRefToEntIndex(client);
	}

	if (client < 1 || client > MaxClients) {
		return false;
	}

	return IsClientInGame(client);
}

stock void WriteLog(const char[] format, any ...)
{
#if defined DEBUG
    char buf[2048];
    VFormat(buf, sizeof(buf), format, 2);
    PrintToServer("[FOZ - %.3f] %s", GetGameTime(), buf);
#endif
}
