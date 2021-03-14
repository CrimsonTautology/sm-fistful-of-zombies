# sm-fistful-of-zombies

![Build Status](https://github.com/CrimsonTautology/sm-fistful-of-zombies/workflows/Build%20plugins/badge.svg?style=flat-square)
[![GitHub stars](https://img.shields.io/github/stars/CrimsonTautology/sm-fistful-of-zombies?style=flat-square)](https://github.com/CrimsonTautology/sm-fistful-of-zombies/stargazers)
[![GitHub issues](https://img.shields.io/github/issues/CrimsonTautology/sm-fistful-of-zombies.svg?style=flat-square&logo=github&logoColor=white)](https://github.com/CrimsonTautology/sm-fistful-of-zombies/issues)
[![GitHub pull requests](https://img.shields.io/github/issues-pr/CrimsonTautology/sm-fistful-of-zombies.svg?style=flat-square&logo=github&logoColor=white)](https://github.com/CrimsonTautology/sm-fistful-of-zombies/pulls)
[![GitHub All Releases](https://img.shields.io/github/downloads/CrimsonTautology/sm-fistful-of-zombies/total.svg?style=flat-square&logo=github&logoColor=white)](https://github.com/CrimsonTautology/sm-fistful-of-zombies/releases)

Fistful of Zombies; a custom zombie survival game mode for Fistful of Frags.


## Requirements
* [SourceMod](https://www.sourcemod.net/) 1.10 or later
* (optional) [SteamWorks](https://forums.alliedmods.net/showthread.php?t=229556) extension (only used to change the game description in the browser).
* (optional) [MapFix Plugin](https://github.com/CrimsonTautology/sm-mapfix-fof) that fixes a few issues with Fistful of Frags.


## Installation
Make sure your server has SourceMod installed.  See [Installing SourceMod](https://wiki.alliedmods.net/Installing_SourceMod).  If you are new to managing SourceMod on a server be sure to read the '[Installing Plugins](https://wiki.alliedmods.net/Managing_your_sourcemod_installation#Installing_Plugins)' section from the official SourceMod Wiki.

Download the latest [release](https://github.com/CrimsonTautology/sm-fistful-of-zombies/releases/latest) and copy the contents of `addons` to your server's `addons` directory.  It is recommended to restart your server after installing.

To confirm the plugin is installed correctly, on your server's console type:
```
sm plugins list
```

## Usage


### Commands
NOTE: All commands can be run from the in-game chat by replacing `sm_` with `!` or `/`.  For example `sm_rtv` can be called with `!rtv`.

| Command | Accepts | Values | SM Admin Flag | Description |
| --- | --- | --- | --- | --- |
| `foz_dump` | None | None | Root | (debug) Output information about the current game to console |
| `foz_reload` | None | None | Root | Force a reload fo the configuration file |

### Console Variables

| Command | Accepts | Values | Description |
| --- | --- | --- | --- |
| `foz_enabled` | boolean | 0-1 | Whether or not Fistful of Zombies is enabled |
| `foz_config` | string | file path | Location of the Fistful of Zombies configuration file |
| `foz_round_time` | integer | 0-999 | How long survivors have to survive in seconds to win a round in Fistful of Zombies |
| `foz_respawn_time` | integer | 0-999 | How long zombies have to wait before respawning in Fistful of Zombies |
| `foz_ratio` | float | 0-1 | Percentage of players that start as human. |
| `foz_infection` | float | 0-1 | Chance that a human will be infected when punched by a zombie.  Value is scaled such that more human players increase the chance |

## Mapping
The plugin is designed in such a way that it can run on any shootout map.  However due to unintended map exploits they may not be balanced for this game mode.  Some things to keep in mind if you want to build your own maps for this game mode:

* The prefix `foz_` has been adopted for maps designed for this gamemode. e.g. foz_twintowers, foz_undeadwood, foz_greenglacier
* The `item_whiskey` entity is used for the spawn points for random weapons that appear in the map.
* From a gameplay stand point consider the vigilante team to be the human team and the desperado team as the zombie team.  Thus for player spawn points, `info_player_vigilante` are used as the spawn points for humans and `info_player_desperado` are used for the spawn points of zombies.
* If any `info_player_fof` spawn points exists, such as in Shootout maps, they will be randomly replaced with either a `info_player_vigilante` or `info_player_desperado` spawn point with equal distribution.
* All `fof_crate*` and `fof_buyzone` entities are removed from the map.
* If an `fof_teamplay` entity exists on the map it will be modified by the plugin to handle some gamemode events.
* If no `fof_teamplay` entity exists a default one will be added to the map.


## Compiling
If you are new to SourceMod development be sure to read the '[Compiling SourceMod Plugins](https://wiki.alliedmods.net/Compiling_SourceMod_Plugins)' page from the official SourceMod Wiki.

You will need the `spcomp` compiler from the latest stable release of SourceMod.  Download it from [here](https://www.sourcemod.net/downloads.php?branch=stable) and uncompress it to a folder.  The compiler `spcomp` is located in `addons/sourcemod/scripting/`;  you may wish to add this folder to your path.

Once you have SourceMod downloaded you can then compile using the included [Makefile](Makefile).

```sh
cd sm-fistful-of-zombies
make SPCOMP=/path/to/addons/sourcemod/scripting/spcomp
```

Other included Makefile targets that you may find useful for development:

```sh
# compile plugin with DEBUG enabled
make DEBUG=1

# pass additonal flags to spcomp
make SPFLAGS="-E -w207"

# install plugins and required files to local srcds install
make install SRCDS=/path/to/srcds

# uninstall plugins and required files from local srcds install
make uninstall SRCDS=/path/to/srcds
```


## Contributing

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request


## License
[GNU General Public License v3.0](https://choosealicense.com/licenses/gpl-3.0/)


## Acknowledgements

* Resi - Developed the custom map "foz_undeadwood"
* elise - Developed the custom map "foz_undeadwood"
* nbreech - Developed the custom map "foz_greenglacier"
