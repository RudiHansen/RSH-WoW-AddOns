# RSH Profession Tracker Export

Generates one text file per character from the SavedVariables database created
by the `RSH_ProfessionTracker` World of Warcraft addon.

WoW writes SavedVariables to disk during logout or `/reload`. Do that before
running the exporter when the newest in-game data is required.

## Usage

```bash
lua5.4 tools/RSH_ProfessionTrackerExport/RSH_ProfessionTrackerExport.lua
```

The defaults are configured for the repository owner's Faugus installation:

- Input: `~/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_retail_/WTF/Account/RUDIHANSEN2/SavedVariables/RSH_ProfessionTracker.lua`
- Output: `~/Nextcloud/06_Spil/Wow/Profession`

Supply another SavedVariables path as the positional argument when needed:

```bash
lua5.4 tools/RSH_ProfessionTrackerExport/RSH_ProfessionTrackerExport.lua \
    "/path with spaces/RSH_ProfessionTracker.lua"
```

Override the output directory with `--output`:

```bash
lua5.4 tools/RSH_ProfessionTrackerExport/RSH_ProfessionTrackerExport.lua \
    --output "/another/output directory"
```

Existing character files are replaced atomically. Filenames use the format
`Character-Realm.txt` to prevent characters with the same name on different
realms from overwriting each other.
