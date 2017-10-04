# Fistful of Zombies

Custom zombie survival gamemode for Fistful of Frags.

##Installation
* Compile plugin with spcomp (e.g.)
> spcomp fistful_of_zombies.sp
* Move compiled .smx files into your `fof/addons/sourcemod/plugins` directory.
* Move `configs/fistful_of_zombies.txt` configuration file into your `fof/addons/sourcemod/configs` directory.
* (optional) Install the [SteamWorks](https://forums.alliedmods.net/showthread.php?t=229556) extension (only used to change the game description in the browser).
* (optional) Install the [MapFix Plugin](https://github.com/CrimsonTautology/sm_mapfix_fof) that fixes a few issues with Fistful of Frags.

    
# CVARs

* `foz_enabled` - Default: "1"; Whether or not Fistful of Zombies is enabled.

* `foz_config` - Default: "fistful_of_zombies.txt"; Location of the Fistful of Zombies configuration file.

* `foz_round_time` - Default: "120"; How long surviors have to survive in seconds to win a round in Fistful of Zombies.

* `foz_respawn_time` - Default: "15"; How long zombies have to wait before respawning in Fistful of Zombies.

* `foz_ratio` - Default: "0.65"; Percentage of players that start as human..

* `foz_infection` - Default: "0.10"; Chance that a human will be infected when punched by a zombie.  Value is scaled such that more human players increase the chance.

# Mapping
The plugin is designed in such a way that it can run on any shootout map.  However due to unintended map exploits they may not be balanced for this game mode.  Some things to keep in mind if you want to build your own maps for this game mode:

* The prefix `foz_` has been adopted for maps designed for this gamemode. e.g. foz_twintowers, foz_undeadwood, foz_greenglacier
* The `item_whiskey` entity is used for the spawn points for random weapons that appear in the map.
* From a gameplay stand point consider the vigilante team to be the human team and the desperado team as the zombie team.  Thus for player spawn points, `info_player_vigilante` are used as the spawn points for humans and `info_player_desperado` are used for the spawn points of zombies.
* If any `info_player_fof` spawn points exists, such as in Shootout maps, they will be randomly replaced with either a `info_player_vigilante` or `info_player_desperado` spawn point with equal distribution.
* All `fof_crate*` and `fof_buyzone` entities are removed from the map.
* If an `fof_teamplay` entity exists on the map it will be modified by the plugin to handle some gamemode events.
* If no `fof_teamplay` entity exists a default one will be added to the map.
