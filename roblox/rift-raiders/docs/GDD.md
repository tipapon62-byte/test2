# Rift Raiders: Egg Multiverse — Game Design Document

> Original tycoon + collection + PvP-raid + speed-progression game for Roblox (PC, mobile, tablet, console), up to 7 players per server.
> It keeps the **multiverse concept** of the original "Steal the Multiverse" place (hub plaza, rift portals, the Rift Run lane, 8 personal bases), but all game code, names, creatures, biomes and balance are new and original.

Contents: [1 GDD](#1-game-design) · [2 Systems](#2-systems-and-dependencies) · [3 Structure](#3-roblox-studio-structure) · [4 Remotes](#4-remotes) · [5 DataStore](#5-datastore-schema) · [6 Scripts](#6-script-reference) · [7 Code](#7-code) · [8 UI](#8-ui-structure) · [9 Balance](#9-balance) · [10 Testing](#10-multiplayer--exploit-checklist) · [11 MVP](#11-mvp-plan) · [12 Post-MVP](#12-post-mvp-roadmap)

---

## 1. Game design

### Pitch
A lab accident tore the multiverse open. Eight shard-universes now hang off the Rift Lab like beads on a string, each one full of nests guarded by their furious mothers. You are a **Rift Raider**: sprint into a universe, snatch an egg, outrun its guardian (and rival raiders), and hatch it at home. Your **Riftlings** earn coins every second; coins buy a faster treadmill, a bigger enclosure and the keys to deeper, deadlier universes.

### Core loop
1. Spawn in your personal base (enclosure, incubators, treadmill, shop terminal, fuse machine).
2. Leave through your base barrier and run down the **Rift Run** lane.
3. Pass a biome gate (needs **Speed** and that biome's **Rift Key**).
4. Find a nest, press **E / ButtonX / tap** (ProximityPrompt) to steal the egg.
5. The **nest guardian** wakes ("!") and chases you. Carrying slows you (Normal ×0.88, Large ×0.80, Huge ×0.72).
6. Run home. Rivals can bonk you with a **foam bat** or catch you in a **bear trap**; guardians and hazards knock you down. A knockdown drops the egg — anyone can grab it.
7. Cross your own base barrier → the egg is **delivered** (only now permanently yours) → incubator pad (or the egg shelf queue).
8. Timer ends → the egg hatches into a pet; it's placed in a free enclosure slot and earns coins/sec.
9. Spend coins on upgrades; train Speed on the treadmill (AFK works, actively running works better).
10. More Speed + keys → farther biomes → rarer eggs → more income. Late game: fuse, collect, rebirth.

### Setting: the 8 shard-universes (Rift Run zones, +X from the hub)
| # | Biome | Kind | Look | Hazards | Weather |
|---|---|---|---|---|---|
| 1 | Rift Lab Grounds | Starting Zone | the original sci-fi lab yard | goo puddles (slow) | — |
| 2 | Mosswood | Forest | chunky trees, glowing mushrooms, hollow-tree landmark | mud pits, rolling logs | falling leaves |
| 3 | Glimmer Lake | Lake | drowned glowing lake (original kelp/coral decor) | shallows (slow), geysers (launch) | bubbles |
| 4 | Sunscorch Dunes | Desert | dunes, cacti, sandstone arches, obelisk | quicksand, tumbleweeds | sandstorm |
| 5 | Vinewild Jungle | Jungle | bamboo + giant leaves, vines, stone-head landmark | swinging logs, thorn bushes | rain |
| 6 | Emberpeak Caldera | Volcano | basalt columns, lava pools, volcano cone | lava cracks, eruption vents | ash |
| 7 | Frostveil Tundra | Frozen Lands | ice spikes, frozen pines, aurora | ice sheets (slippery), falling icicles | snow |
| 8 | Astral Ruins | Space / Ancient World | broken temple, floating islands, planets | void pits, meteor strikes | star motes |

Biomes are physically separated by force-field **gates** (server-enforced: under-speed or key-less players are bounced back with a message).

### Eggs
* Rarities: **Common, Uncommon, Rare, Epic, Legendary, Mythic, Divine** (each biome spawns a 4–5 rarity window).
* Higher rarity ⇒ rarer spawn, longer hatch, stronger pet, faster guardian.
* Modifiers rolled at spawn and visible on the egg: **size** (Normal / Large / Huge) and **mutation** (Silver, Gold, Rainbow, Neon, Galaxy; event-only **Rift**). Eggs without a mutation get one more roll on hatch.
* Special spawns: **Divine eggs** (random biome ≥ 6, 4-minute lifetime, server-wide + cross-server announcement), event eggs during **Rift Storm** (Rift mutation, chance of the event-only *Rift Sovereign*).
* States (replicated as attributes on the egg model): `Nest` → `Carried` → `Dropped` → (back to `Nest` after 25 s) / delivered → `Incubating` (pad model) → hatched.

### Guardians
One per `GuardianHome` (up to 4 per zone). Stats per biome in [§9](#9-balance). Behaviour: Patrol (wander near home) → Alert "!" (0.35 s) → Chase (speed = biome speed × rarity multiplier × size bonus × event multiplier) → Attack (range, cooldown, knockback, ragdoll, egg drop) → Stunned 2.5 s → Return "?" → Patrol. Detection radius + line of sight (map walls/decor block sight); gives up after 3 s without sight, when the thief leaves the aggression (leash) zone, or enters any base. Guardians are clamped inside their zone, so they physically can't reach a base.

### Pets
38 original species (5 per early biome, 4 in later ones + an event-only Divine). Each pet has species, rarity, size, mutation, fusion tier (★), weight (kg), name (optional, filtered), procedural model and income.
`income = biome.IncomeBase × rarity.IncomeMult × size.IncomeMult × mutation.IncomeMult × tierMult` then × base bonus × rebirth bonus.
The **Index** shows every species per biome; first discovery pays Rift Shards (1–50 by rarity), completing a biome pays 40.

### Fuse Machine
3 identical pets (same species **and** tier) → 1 pet of tier +1 (income ×3.3 / ×11 / ×36 / ×120 vs tier 1). Keeps the best size and mutation; 15 % mutation upgrade, 10 % size upgrade, 5 % bonus egg (+1 rarity). Coin cost by tier. Irreversible. Safety: two-step preview → token → confirm, locked pets excluded, warnings list everything you lose, valuable fusions need a second "hold to confirm".

### Competition (non-lethal)
* **Foam bat** (F / R1 / mobile button): 9-stud cone, 1.5 s cooldown, ragdoll 2 s, drops the egg, victim immune 6 s. Can't tag from or into a base.
* **Bear traps** (T / ButtonY): buy (250), place at your feet; snaps on the next rival → rooted 4 s, then 8 s trap immunity. Max 2 active, 90 s lifetime, 12-stud spacing, **not within 30 studs of any base** (incubators/exits). Disarmed safely by walking over it while holding a **Decoy Chicken Egg** (Q / DPadUp).
* Anti-griefing: new-player shield 5 min (eggs can't be knocked loose; tagging someone ends your own shield), max 2 egg steals from the same victim per 10 min, players don't collide with each other (no body-blocking base exits), base interiors are safe zones.

### Base protection
Each base's front laser is a collision-group barrier (the owner walks through, others bump into it). The server also teleports any non-owner found inside to the porch (catches no-clip exploits). Carriers can still be tagged on the porch right up to the barrier line.

### Economy
Coins (main) and **Rift Shards** (rare: daily rewards, quests, index, achievements, rebirth). Coin sinks: enclosure slots, treadmill, incubator, trails, traps/decoys, hatch speed-ups, biome keys, fuse. Shard sinks: special eggs (Rift Crate / Prism), mutation potions, premium trails, hatch skips. Offline income: 25 % for up to 2 h.

### Retention
Daily rewards (7-day streak), 3 daily + 3 weekly quests (UTC reset), 11 achievements, global leaderboards (Speed, Income, Rare pets, Egg retrievals), timed events every 20–30 min (Rift Storm, Golden Hour, Egg Stampede), Divine spawns, global chat announcements for Mythic/Divine/Galaxy hatches, bonus codes, **Rebirth** (from 1 M coins + Emberpeak key; resets progress track, keeps pets/index/trails; +25 % income and training per rebirth).

---

## 2. Systems and dependencies

```
                ┌────────────┐
                │ GameConfig │  (shared data + formulas, used by everything)
                └─────┬──────┘
 SaveService ◄── DataService ──► (ProfileUpdated / attributes → client)
                      ▲
   ┌──────────────────┼──────────────────────────────────────────────┐
 BaseService   SpeedService   BiomeService ──► BiomeDecor, HazardBuilder
   ▲   ▲            ▲            ▲   ▲
   │   │            │            │   └──── EggService ◄──► GuardianService
   │   └── PetService ◄── EggService (hatch)   │  ▲
   │          ▲   ▲                            │  └── CombatService (knockdowns drop eggs)
   │   FuseService  EconomyService (income, purchases, rebirth)
   │                    QuestService (Track/SetStat from all gameplay services)
   │                    EventService (rarity/mutation/guardian modifiers, Divine spawns)
   │                    LeaderboardService, AntiCheatService (Grace from teleports/knockbacks)
 ModelFactory (shared) ← used by Base/Egg/Pet/Guardian/Combat/Speed + client UI previews
```

| System | Depends on | Provides |
|---|---|---|
| GameConfig | — | all tunables, lookups, income/speed/hatch formulas |
| Net | — | remote definitions |
| SaveService | DataStoreService | session-locked load/save |
| DataService | SaveService | profiles, replication, currency ops, Notify/Effect/Announce |
| BaseService | DataService, ModelFactory | base assignment, barrier, pads, coordinates, shop range |
| SpeedService | DataService, BaseService, ModelFactory | treadmill, walk speed modifiers, trails |
| BiomeService | BiomeDecor, HazardBuilder, Speed/Combat/Egg (hazard ctx) | zones, gates, BiomeIndex |
| EggService | Biome, Base, Speed, Guardian, Pet, Event, Quest | nests, carry, drop, delivery, incubators |
| GuardianService | Biome, Egg, Combat, Event, Base | guardian AI |
| PetService | Data, Base, Event, Quest | pets, income, index, base pet models |
| FuseService | Data, Pet, Egg, Quest | fusion |
| CombatService | Data, Egg, Speed, Base, Quest, AntiCheat | bat, ragdoll, traps, shield |
| EconomyService | Data, Base, Speed, Pet, Egg, Quest | income tick, offline income, purchases, rebirth |
| QuestService | Data, Egg, Speed, Event | daily/weekly/achievements/codes/admin |
| EventService | Data, Biome, Egg | events, Divine spawns, cross-server announcements |
| LeaderboardService | Data, Pet | global boards |
| AntiCheatService | — | movement validation |

---

## 3. Roblox Studio structure

```
ReplicatedStorage
  Shared/                     (src/shared)
    GameConfig  (ModuleScript)  + Rarities, Biomes, Pets, Economy, Progression
    Net         (ModuleScript)  remote names + helpers
    Util        (ModuleScript)  ids, weighted rolls, deep copy, reconcile
    ModelFactory(ModuleScript)  procedural stylised pets/eggs/guardians/props (+ child modules)
  Remotes/      (created at runtime by Net.Init)
ServerScriptService
  Server/                     (src/server)
    Main        (Script)        bootstrap
    Services/   SaveService DataService BaseService SpeedService BiomeService EggService
                GuardianService PetService FuseService CombatService EconomyService QuestService
                EventService LeaderboardService AntiCheatService SignService
    World/      BiomeDecor HazardBuilder
    Util/       RateLimiter
StarterPlayer.StarterPlayerScripts
  Client/                     (src/client)
    Main        (LocalScript)   bootstrap
    Data/ClientData             profile mirror
    UI/Theme, UI/Components     look + widgets
    Controllers/ HUD Shop Inventory Index Fuse Daily Leaderboard Rebirth Settings
                 Notification Input Effects Animation Weather
ServerStorage   (prefab overrides / future hand-made models)
Workspace
  Bases/Base1..8  (map)  + runtime folder RiftRaiders/{Incubators, Pets, FuseMachine, ShopTerminal}
  RiftRun/Zones/Zone1..8 (map) + Eggs, Guardians, Hazards, Traps (runtime)
  Hub, Portals, Scenery (map)
```
Pets, eggs and guardians are generated by `ModelFactory` on demand (on the server for the world, on the client for UI previews). To hand-author a model, build it in Studio, then make `ModelFactory` return a clone from `ServerStorage`/`ReplicatedStorage` for that id (same Root/joint rules, see the module header).

---

## 4. Remotes

All remotes live in `ReplicatedStorage.Remotes` (source of truth: `src/shared/Net.lua`). Every client→server handler is rate-limited and fully validated on the server.

| Remote | Type | Direction | Arguments | Notes |
|---|---|---|---|---|
| Purchase | Event | C→S | category, id | BaseUpgrade / TreadmillUpgrade / IncubatorUpgrade / Trail / Item / BiomeKey / ShardEgg; must be in own base or ≤40 studs from hub shop |
| EquipTrail | Event | C→S | trailId | owned only |
| Tag | Event | C→S | — | server picks the target |
| DropEgg | Event | C→S | — | |
| UseItem | Event | C→S | itemId | BearTrap places; DecoyEgg toggles |
| PetAction | Event | C→S | action, uids, arg? | Place/Store/Sell/SellDuplicates/Lock/Unlock/Rename/MutationPotion |
| Fuse | Event | C→S | uids, token | token from PreviewFuse, 60 s, single use |
| SpeedUpHatch | Event | C→S | pad, "Coins"/"Shards" | |
| ClaimDaily | Event | C→S | — | |
| ClaimQuest | Event | C→S | kind, questId | |
| RedeemCode | Event | C→S | code | |
| Rebirth | Event | C→S | — | |
| SaveSettings | Event | C→S | settings | whitelisted keys, clamped |
| TreadmillActive | Event | C→S | running | only selects AFK vs active gain; position checked on server |
| ProfileUpdated | Event | S→C | partial profile | top-level keys |
| Notify | Event | S→C | text, kind | |
| Announce | Event | S→all | text, color | |
| Effect | Event | S→C | name, data | Hatch, Fuse, Discovery, Tagged, Trapped, Unlock, Coins, Event, Rebirth |
| Ragdoll | Event | S→C | on, duration | |
| Knockback | Event | S→C | velocity | |
| GetProfile | Function | C→S | — | snapshot |
| GetLeaderboard | Function | C→S | statId | top 25 |
| PreviewFuse | Function | C→S | uids | preview + token |

---

## 5. DataStore schema

DataStore `RiftRaiders_Profiles_v1`, key `P_<UserId>`:
```lua
{ Data = Profile, Meta = { Lock = { JobId, Time }?, SaveCount, LastSaved } }
```
`Profile` (full field list in [CONTRACT.md](CONTRACT.md#profile-what-getprofile-returns-profileupdated-sends-changed-top-level-keys)):

| Field | Format |
|---|---|
| Version | int (migrations in `DataService.migrate`) |
| Coins, Shards, SpeedStat | numbers |
| TreadmillLevel, BaseLevel, IncubatorLevel, Rebirths | ints |
| Biomes | `{ [biomeId] = true }` |
| Trails | `{ Owned = { [id] = true }, Equipped = id }` |
| Items | `{ BearTrap, DecoyEgg, MutationPotion }` counts |
| Pets | `{ [uid] = { Uid, Species, Size, Mutation?, Tier, Kg, Name?, Slot?, Locked?, Obtained } }` |
| Incubators | `{ ["1".."4"] = { Uid, Biome, Rarity, Size, Mutation?, Species?, HatchAt (unix), Duration } }` |
| EggStorage | array of egg records waiting for a pad (max 8) |
| Index / IndexBiomesDone | `{ [speciesId] = { First, Count } }`, `{ [biomeId] = true }` |
| Stats | EggsDelivered, EggsRetrieved, PetsHatched, RareHatches, Tags, TrapsSprung, Fuses, CoinsEarned, TreadmillSeconds, TimePlayed, BestIncome |
| Daily / Quests / Achievements / Codes | streak + last claim; `{Daily/Weekly = {Period, List = {Id, Progress, Claimed}}}`; sets |
| Settings | Music, Sfx, LowGraphics, ShowTrails, Notifications, ConfirmFuse |
| FirstJoin, LastOnline | unix |

Leaderboards: OrderedDataStores `RR_LB_Speed`, `RR_LB_Income`, `RR_LB_RarePets`, `RR_LB_Retrievals` (key = UserId).

Duplication protection: session lock (a server only writes records it holds the lock for; another server waits/kicks), pets and owned eggs get fresh unique ids, fusion consumes inputs before creating the result, all transfers happen in one server.

---

## 6. Script reference

| Script | Receives | Does | Returns / exposes |
|---|---|---|---|
| **Main** (server) | — | `Net.Init()`, requires all services, `Init(services)` then `Start()` in dependency order | — |
| **SaveService** | userId, data | `Load` (UpdateAsync + session lock, retries, Studio fallback), `Save(release)` | `"ok"/"locked"/"error"`, data |
| **DataService** | players, mutations from services | template + migration, replication batching (5 Hz), leaderstats, autosave 120 s, BindToClose, GetProfile/SaveSettings | `Get, Changed, AddCoins, AddShards, Spend, Notify, Effect, Announce, OnLoaded, OnRemoving, RegisterDerived` |
| **BaseService** | player join/leave | assigns bases, builds pads/fuse/shop, barrier collision groups, intruder push-out, spawn | `GetBase, IsInside, IsNear, FindBaseAt, GetSlotCFrame, GetPad, CanShop, ApplyLevels, LocalToWorld` |
| **SpeedService** | TreadmillActive, EquipTrail | treadmill gain (server position check), walk speed with modifiers, trails, slippery | `GetEffective, SetModifier, Apply, ApplyTrail, SetSlippery` |
| **BiomeService** | — | finds/creates zones, gates + labels, decor + hazards, gate enforcement, BiomeIndex | `GetZone, Zones, ZoneIndexAt, CanEnter` |
| **EggService** | GrabPrompt, DropEgg, SpeedUpHatch | nest spawning (event-aware), carry/drop/return, delivery, egg shelf, pads + timers, hatching | `Grab, Drop, ReturnCarriedEgg, GiveEgg, HasFreeStorage, IsCarrying, GetCarriers, SpawnSpecial, BestBiome` |
| **GuardianService** | OnEggTaken | guardian state machine, LOS, leash, zone clamp | `OnEggTaken` |
| **PetService** | PetAction | hatch rolls, slots/storage, income cache, selling, locking, filtered rename, potions, index rewards, pet models | `HatchEgg, AddPet, GetIncome, RefreshBase, StoreOverflow` |
| **FuseService** | PreviewFuse, Fuse | validation, preview + token, fusion rolls, bonus egg | preview table |
| **CombatService** | Tag, UseItem | cone tag, ragdoll, shield, steal limit, traps, decoy | `Knockdown, IsCrowdControlled, IsShielded` |
| **EconomyService** | Purchase, Rebirth | income tick, offline income, every purchase, rebirth | `Purchase, Rebirth` |
| **QuestService** | ClaimDaily, ClaimQuest, RedeemCode, chat | daily streak, quest rotation, achievements, codes, admin commands (`/event`, `/coins`, `/speed`, `/divine`) | `Track, SetStat, Grant` |
| **EventService** | — | event rotation, Divine spawns, MessagingService announcements | `GetActive, StartEvent, SpawnDivine, GlobalAnnounce` |
| **LeaderboardService** | GetLeaderboard | OrderedDataStore writes/reads every 120 s | lists |
| **AntiCheatService** | — | 4 Hz movement validation, rubber-band, kick after strikes | `Grace` |
| **SignService** | — | renders `SignText` labels | — |
| **BiomeDecor / HazardBuilder** | zone, biome, bounds | procedural scenery / hazards + detection loop | folders |
| **ModelFactory** (shared) | species/biome/rarity/opts | stylised part-built models with Motor6D rigs | Models |
| **Client Main** | — | requires ClientData then every controller, calls `Start()` | — |
| **ClientData** | GetProfile, ProfileUpdated | local profile mirror + Changed signal | `Get, Changed, WaitReady` |
| **Controllers** | remotes/attributes | HUD, windows, input, effects, animation, weather (see §8) | — |

---

## 7. Code

All Luau sources are in `src/` (commented where intent isn't obvious). `tools/build_place.py` produces the ready-to-open place from the original map; `check.sh` type-checks everything against the Roblox API with luau-lsp.

---

## 8. UI structure

| Screen | Contents | Talks to |
|---|---|---|
| HUD | coins, shards, Speed (effective + trained), income/s, carried egg ("RUN HOME!"), incubator timers with speed-up buttons, shield timer, event banner, biome indicator (required/recommended Speed vs yours), menu buttons | ClientData, player attributes, SpeedUpHatch |
| Shop | Upgrades (enclosure, treadmill, incubator), Biome Keys, Trails (buy/equip), Items, Shard Eggs | Purchase, EquipTrail |
| Pets | grid with 3D previews, filters/sort, detail panel (place/store, lock, sell, rename, potion), sell duplicates | PetAction |
| Index | per-biome species grid, silhouettes for undiscovered, progress + rewards | ClientData |
| Fuse | pick 3 identical pets (auto-select), exact input list, result, chances, warnings, double confirm | PreviewFuse, Fuse |
| Daily | 7-day track + claim, daily/weekly quests, achievements, codes | ClaimDaily, ClaimQuest, RedeemCode |
| Leaderboards | 4 tabs | GetLeaderboard |
| Rebirth | cost, requirements, kept/reset lists | Rebirth |
| Settings | music, SFX, low graphics, trails, notifications, fuse confirm | SaveSettings |
| Notifications | toasts, banners, chat system messages, hatch/fuse/discovery reveals | Notify, Announce, Effect |
| Mobile buttons | Tag, Drop (when carrying), Trap (count), Decoy (count) + ProximityPrompt tap for interact | Tag, DropEgg, UseItem |

Input: PC F tag / G drop / T trap / Q decoy / E interact; gamepad R1 / L1 / Y / DPadUp / X interact, B closes windows; touch buttons. All layouts are scale-based with UIScale for phones → TVs.

---

## 9. Balance

### Starting values
| Value | Start |
|---|---|
| Starting coins | 100 |
| Common pet income (Rift Lab) | 2 coins/s |
| First enclosure upgrade | 250 (6 → 8 slots, +5 % income) |
| First treadmill upgrade | 150 (gain 1 → 2 Speed/s, +10 base Speed) |
| Base walk speed | 16 (Speed 0); walk = 16 + 5.5·log2(1 + Speed/30), cap 85 |
| Treadmill gain | 1 Speed/s AFK, ×1.5 while actively running (level 1) |
| Hatch timers | Common 20 s · Uncommon 45 s · Rare 1:30 · Epic 3:00 · Legendary 6:00 · Mythic 12:00 · Divine 25:00 (× size: Large 1.25, Huge 1.5; incubator upgrades −5…−30 %) |
| Mutations (per roll) | Silver 6 % ×1.5 · Gold 2.5 % ×2.5 · Rainbow 0.8 % ×4 · Neon 0.4 % ×6 · Galaxy 0.1 % ×10 · Rift (event) 1 % ×7 |
| Sizes | Normal 85 % ×1 · Large 12 % ×1.75 · Huge 3 % ×3 |
| New-player shield | 5 min |

### Biomes and guardians (all 8)
| # | Biome | Gate Speed | Recommended | Key price | Common-pet base income | Guardian speed (Common egg) | Detect / Leash | Knockback |
|---|---|---|---|---|---|---|---|---|
| 1 | Rift Lab Grounds | 0 | 0 | free | 2 | 13 | 45 / 110 | 45 |
| 2 | Mosswood | 60 | 120 | 300 | 6 | 22 | 55 / 130 | 55 |
| 3 | Glimmer Lake | 250 | 450 | 2,500 | 18 | 30 | 60 / 140 | 60 |
| 4 | Sunscorch Dunes | 900 | 1,500 | 15K | 50 | 39 | 65 / 150 | 65 |
| 5 | Vinewild Jungle | 3,000 | 5,000 | 80K | 140 | 47 | 70 / 160 | 70 |
| 6 | Emberpeak Caldera | 9,000 | 15,000 | 400K | 400 | 55 | 75 / 170 | 80 |
| 7 | Frostveil Tundra | 25,000 | 40,000 | 2M | 1,100 | 62 | 80 / 180 | 85 |
| 8 | Astral Ruins | 70,000 | 110,000 | 10M | 3,000 | 70 | 85 / 190 | 95 |

Guardian speed × rarity: Common 1.00, Uncommon 1.03, Rare 1.06, Epic 1.10, Legendary 1.14, Mythic 1.18, Divine 1.25 (Large +2 %, Huge +5 %, Rift Storm +10 %).
Design rule: at the **recommended** Speed, carrying a Normal Common egg is ~5–15 % faster than the guardian; at the **gate** Speed it is slightly slower, so you need a head start, terrain or a lucky dodge — rare eggs "require preparation".

### Detailed table: first 3 biomes
| | Rift Lab Grounds | Mosswood | Glimmer Lake |
|---|---|---|---|
| Walk speed at gate / recommended | 16.0 / 16.0 | 24.7 / 28.8 | 33.7 / 38.0 |
| Carrying (Normal ×0.88) at recommended | 14.1 | 25.3 | 33.4 |
| Egg spawn weights | C 70 · U 22 · R 6.5 · E 1.4 · L 0.1 | C 55 · U 28 · R 12 · E 4.3 · L 0.7 | U 55 · R 28 · E 12.5 · L 4 · M 0.5 |
| Guardian speed by egg rarity | C 13 · U 13.4 · R 13.8 · E 14.3 · L 14.8 | C 22 · U 22.7 · R 23.3 · E 24.2 · L 25.1 | U 30.9 · R 31.8 · E 33 · L 34.2 · M 35.4 |
| Pet income (coins/s, Normal ★1) | C 2 · U 3.2 · R 5.2 · E 9 · L 16 | C 6 · U 9.6 · R 15.6 · E 27 · L 48 | U 28.8 · R 46.8 · E 81 · L 144 · M 270 |
| Species | Sproutpup, Bolt Chick, Goo Nibbler, Gearback Raptor, Flaskwing Owl | Acorn Hopper, Fernfawn, Mushcap Toad, Barkhide Rex, Elder Oakwing | Puddle Paddler, Ripple Newt, Shellback Turtle, Tidefin Serpent, Pearl Leviathan |
| Nest respawn | 20 s | 22 s | 24 s |
| Hazards | goo puddles ×0.75 | mud pits ×0.6, rolling logs (knockdown) | shallows ×0.7, geysers (launch) |

### First 10 minutes (expected)
0:00 spawn with 100 coins, Speed 0 (walk 16) → run to Rift Lab (~25 s) → steal a Common egg (guardian 13 < carry 14.1, safe) → home → 20 s hatch → 2 coins/s. Treadmill AFK between runs (+1–1.5 Speed/s). ~2–3 min: treadmill Lv2 (150). ~4–6 min: Speed 60, enclosure Lv2 (250), Mosswood key (300). ~8–10 min: first Mosswood eggs (6–15 coins/s each), ~20–40 coins/s total, first Rare/Epic attempts.

### Upgrade tracks
| Lv | Enclosure slots / income / price | Treadmill gain / active× / base Speed / price | Incubator pads / hatch −% / price |
|---|---|---|---|
| 1 | 6 / +0 % / 0 | 1 / 1.5 / 0 / 0 | 1 / 0 / 0 |
| 2 | 8 / +5 % / 250 | 2 / 1.55 / 10 / 150 | 2 / 5 / 500 |
| 3 | 10 / +10 % / 900 | 3.5 / 1.6 / 25 / 600 | 2 / 10 / 4K |
| 4 | 12 / +15 % / 3K | 6 / 1.65 / 50 / 2.5K | 3 / 15 / 25K |
| 5 | 15 / +20 % / 10K | 10 / 1.7 / 100 / 9K | 3 / 20 / 150K |
| 6 | 18 / +25 % / 35K | 16 / 1.75 / 200 / 30K | 4 / 30 / 900K |
| 7–10 | 21–36 / +30–65 % / 120K–5M | 25–100 / 1.8–2.0 / 400–3000 / 100K–4M | — |

Trails (Speed ×): Sparkle 1.1 (500), Leafy 1.2 (3K), Bubble 1.35 (15K), Ember 1.5 (75K), Frost 1.75 (350K), Comet 2 (1.5M), Aurora 2.5 (8M); shard trails Prism 1.6 (150), Void 3 (800).

---

## 10. Multiplayer & exploit checklist

Run with **Test → Clients and Servers → 3–7 players** plus one exploit-test client.

Egg flow
- [ ] Two players trigger the same nest prompt in the same frame → exactly one carries it.
- [ ] Carrier tagged → egg on the ground → a third player picks it up and delivers it → `EggsRetrieved` +1 for them only.
- [ ] Dropped egg returns to its nest after 25 s; the dropper can't instantly re-grab (0.6 s).
- [ ] Carrier leaves the game → egg drops where they stood; carrier resets/dies → egg drops.
- [ ] Carrier enters someone else's base → pushed out, keeps carrying; enters own base → delivered.
- [ ] Incubators + shelf full → egg is not lost, player keeps carrying with a warning.
- [ ] Egg models show correct `State` / `CarrierId` on every client.
Guardians
- [ ] The closest guardian of that zone reacts; others keep patrolling.
- [ ] Guardian gives up at leash, without LOS for 3 s, or at a base; never leaves its zone.
- [ ] Higher rarity / Huge eggs → visibly faster chase; at recommended Speed a Common egg escapes.
Combat
- [ ] Tag cooldown, 6 s immunity, no tagging inside bases, shielded victims keep their egg, attacker loses own shield.
- [ ] Third steal from the same victim within 10 min is refused.
- [ ] Traps: not placeable within 30 studs of any base, max 2, spacing, owner immune, decoy disarms, single use.
Economy / data
- [ ] Purchases rejected outside base / far from hub shop; insufficient funds can't go negative.
- [ ] Fuse with a stale/forged token, with 2 identical uids, with a locked pet, or with someone else's uid → rejected.
- [ ] Rejoin quickly on another server → old server releases lock; no rollback or duplicate pets.
- [ ] Shutdown (BindToClose) saves everyone; Studio without API access plays unsaved with a warning.
Exploits (from an executor test client)
- [ ] Setting WalkSpeed locally / teleporting → rubber-banded; 6 strikes in 30 s → kick.
- [ ] No-clipping through a base barrier → teleported to the porch.
- [ ] Spamming any remote → rate limiter drops excess; server CPU stable.
- [ ] Firing `Purchase` with negative/NaN/huge ids, `PetAction` with 10 000 uids, `SaveSettings` with junk → ignored/clamped.
- [ ] Triggering a GrabPrompt from across the map → distance re-check rejects.
- [ ] Renaming a pet with inappropriate text → filtered by TextService.
Platforms
- [ ] Phone (small screen), tablet, console (gamepad only, 10-foot UI), PC; mobile buttons don't overlap thumbstick/jump.

---

## 11. MVP plan

Build/verify in this order (each step is playable):
1. **World + bases**: place file from `build_place.py`, base assignment, barrier, spawn. *(done)*
2. **Data**: SaveService + DataService, coins/Speed attributes, autosave. *(done)*
3. **Speed**: treadmill training, walk speed, gates for biomes 1–3. *(done)*
4. **Eggs**: nests in biomes 1–3, carry, drop, delivery, 1 incubator pad, hatching. *(done)*
5. **Pets**: enclosure slots, income tick, sell. *(done)*
6. **Guardians** with chase/attack/return. *(done)*
7. **HUD + Shop** (upgrades, keys). *(done)*
8. **Foam bat** + ragdoll + shield. *(done)*
MVP test goal: 3–7 testers can complete the loop in biomes 1–3 for 30 minutes without data loss or exploits.
Everything else in this repo (biomes 4–8, fusion, traps, quests, events, leaderboards, rebirth, index) is already implemented behind the same architecture; for an MVP-only test you can hide those windows and gate biomes 4–8 with a very high `RequiredSpeed`.

---

## 12. Post-MVP roadmap

| Update | Content | Where to extend |
|---|---|---|
| 1. Polish | sounds/music (SoundGroups exist), hand-made hero models for Legendary+, hatch cutscene camera | ModelFactory overrides, NotificationController |
| 2. Rift Market | revive the hub conveyor as a rotating egg market (coins/shards) | new MarketService + Economy.ShardEggs-like table |
| 3. Trading | secure two-sided trade window (both confirm, server swaps atomically, trade lock in profile) | TradeService, PetService |
| 4. New biome pack | biome 9+ (e.g. "Clockwork Canyon") | append to Biomes.lua + Pets.lua; zones auto-build if the map lacks ZoneN |
| 5. Seasonal events | event eggs/mutations, limited species (`EventOnly`), event currency | Progression.Events, Rarities.Mutations |
| 6. Clans / team raids | shared base wing, clan leaderboard (MemoryStore sorted maps for weekly boards) | new services |
| 7. Monetisation (optional) | gamepasses (extra pad, auto-collect, trail), developer products (shards) via MarketplaceService ProcessReceipt with idempotent receipt log in the profile | new MonetizationService |
| 8. Weekly MemoryStore boards | weekly retrievals/speed with expiring sorted maps | LeaderboardService |

Adding content never requires engine changes: new species/biomes/mutations/events/quests are data rows in `GameConfig`; new mechanics are new services registered by `Main`.
