# Rift Raiders: Egg Multiverse (Roblox)

Original tycoon + steal-an-egg + PvP raid + speed-progression game, built on the map of the earlier
"Steal the Multiverse" place (multiverse hub, rift portals, 8 bases, the Rift Run lane — now 8 biomes).

* **Design doc (all deliverables, balance, checklists, MVP/roadmap):** [docs/GDD.md](docs/GDD.md)
* **Runtime contract (profile schema, attributes, tags, effects):** [docs/CONTRACT.md](docs/CONTRACT.md)
* **Remotes:** [src/shared/Net.lua](src/shared/Net.lua) · **All tunables:** [src/shared/GameConfig](src/shared/GameConfig)

## Play it

Option A — ready place file:
```bash
python3 tools/build_place.py --source StealMultiverse_v7_fixed.rbxlx --out RiftRaiders.rbxlx
```
Open `RiftRaiders.rbxlx` in Roblox Studio → **Game Settings → Security → Enable Studio Access to API Services** (for saving) → Play / Test with several clients. Set *Max Players* to 7 in Game Settings → Places when publishing.

Option B — live sync with [Rojo](https://rojo.space): open the built place (or the original place) in Studio and run `rojo serve`. Missing zones are generated at runtime, but the build script gives the nicer re-themed map.

Admin chat commands (Studio, or UserIds in `Progression.Admins`): `/event RiftStorm|GoldenHour|Stampede`, `/coins 100000`, `/speed 5000`, `/divine`.

## Develop

```
src/shared   -> ReplicatedStorage.Shared          (GameConfig, Net, Util, ModelFactory)
src/server   -> ServerScriptService.Server        (Main + Services + World)
src/client   -> StarterPlayerScripts.Client       (Main + Data + UI + Controllers)
tools/       -> build_place.py (map re-theme + code injection)
```
Type-check against the Roblox API: `./check.sh` (needs `rojo`, `luau-lsp` and luau-lsp's `globalTypes.d.luau`; see the script header).

Add content by adding data rows: biomes (`Biomes.lua`), species (`Pets.lua`), mutations/sizes (`Rarities.lua`), prices/tracks/trails/items (`Economy.lua`), quests/achievements/codes/events (`Progression.lua`). Never rename an `Id` that is already live — saves reference them.
