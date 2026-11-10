# Runtime contract (server ⇄ client ⇄ world)

This file is the interface every module codes against. Change it deliberately.

## Instance layout at runtime

| Location | Contents |
|---|---|
| `ReplicatedStorage.Shared` | `GameConfig` (+ children), `Net`, `ModelFactory`, `Util` |
| `ReplicatedStorage.Remotes` | created by the server at boot (`Net.Init`) |
| `ServerScriptService.Server` | `Main` (Script) + `Services/*` + `World/*` |
| `StarterPlayer.StarterPlayerScripts.Client` | `Main` (LocalScript) + `Controllers/*` + `UI/*` |
| `ServerStorage.Prefabs` | models cached by the server from `ModelFactory` (Pets/Eggs/Guardians/Props) |
| `workspace.Bases.Base1..8` | player bases (map) — attribute `OwnerId` (number, 0 = free), `OwnerName` |
| `workspace.Bases.BaseN.RiftRaiders` | runtime folder per base: `Incubators/Pad1..4`, `Pets/<uid>`, `FuseMachine`, `ShopTerminal` |
| `workspace.RiftRun.Zones.Zone1..8` | biome zones (map); `Floor`, `Nests/Nest*`, `GuardianHome*`, `Gate` |
| `workspace.RiftRun.Eggs` | all world eggs (in nests, carried, dropped) |
| `workspace.RiftRun.Guardians` | guardian models |
| `workspace.RiftRun.Hazards` | hazard parts/models |
| `workspace.RiftRun.Traps` | placed bear traps |

## Player attributes (replicated, read-only for clients)

| Attribute | Type | Meaning |
|---|---|---|
| `Coins`, `Shards` | number | currencies |
| `SpeedStat` | number | trained Speed |
| `EffectiveSpeed` | number | Speed after treadmill base bonus and trail multiplier (used for gates) |
| `Income` | number | coins/sec with all multipliers |
| `BaseName` | string | name of the player's base model (`Base3`) |
| `CarryingEgg` | string | display name of the carried egg, `""` when not carrying |
| `CarryingRarity` | string | rarity of the carried egg, `""` when not carrying |
| `ShieldUntil` | number | `workspace:GetServerTimeNow()` until which the new-player shield is active |
| `TagReadyAt` | number | server time when the foam bat can be swung again |
| `Ragdolled`, `Trapped` | boolean | crowd-control states |
| `HoldingDecoy` | boolean | decoy chicken egg in hand (disarms traps) |
| `BiomeIndex` | number | biome index the player stands in (0 = hub/base) |

## Tagged models (CollectionService)

| Tag | Model | Attributes |
|---|---|---|
| `RR_Egg` | world egg | `Uid, Biome, Rarity, Size, Mutation, State ("Nest"/"Carried"/"Dropped"), CarrierId` |
| `RR_IncubatorEgg` | egg hatching on an enclosure slot (workspace.Bases.BaseN.RiftRaiders.Eggs) | `Uid, Biome, Rarity, Size, Mutation, HatchAt (unix, compare with workspace:GetServerTimeNow())` |
| `RR_Pet` | pet placed in an enclosure | `Uid, Species, Rarity, Size, Mutation, Tier, Income, OwnerId` |
| `RR_Guardian` | nest guardian | `Biome, State ("Idle"/"Patrol"/"Alert"/"Chase"/"Attack"/"Return"/"Stunned"), Speed` |
| `RR_Trap` | bear trap | `OwnerId, Armed` |
| `RR_Hazard` | hazard part | `HazardType`, see BiomeService |

## Profile (what `GetProfile` returns; `ProfileUpdated` sends changed top-level keys)

```lua
{
  Version = 1,
  Coins = 100, Shards = 0, SpeedStat = 0,
  TreadmillLevel = 1, BaseLevel = 1, IncubatorLevel = 1, Rebirths = 0,
  Biomes = { RiftLab = true },                    -- unlocked biome keys
  Trails = { Owned = { None = true }, Equipped = "None" },
  Items = { BearTrap = 0, DecoyEgg = 0, MutationPotion = 0 },
  Pets = { [uid] = PetData },                     -- PetData.Slot = enclosure slot or nil (storage)
  Incubators = { ["7"] = EggData, ... },          -- eggs hatching ON enclosure slots, keyed by slot number as string; HatchAt = unix time.
                                                  -- A slot holds either a pet or an egg. Derived.Pads = max eggs hatching at once.
  EggStorage = { EggData, ... },                  -- delivered eggs waiting for a free slot / hatch capacity (max 8)
  Index = { [speciesId] = { First = unix, Count = n } },
  IndexBiomesDone = { [biomeId] = true },
  Stats = { EggsDelivered, EggsRetrieved, PetsHatched, RareHatches, Tags, TrapsSprung,
            Fuses, CoinsEarned, TreadmillSeconds, TimePlayed, BestIncome },
  Daily = { Streak = 0, LastClaim = 0 },
  Quests = { Daily = { Period = n, List = { {Id, Progress, Claimed} } }, Weekly = { ... } },
  Achievements = { [id] = true },
  Codes = { [CODE] = true },
  Settings = { Music = 0.5, Sfx = 0.8, LowGraphics = false, ShowTrails = true,
               Notifications = true, ConfirmFuse = true },
  FirstJoin = unix, LastOnline = unix,
  -- not saved, computed by the server and included in snapshots/updates:
  Derived = { Income, EffectiveSpeed, WalkSpeed, Slots, Pads, ActiveEvent = {Id, Name, EndsAt}?,
              ShieldUntil, RebirthCost, CanRebirth },
}
```

`PetData = { Uid, Species, Size, Mutation?, Tier, Kg, Name?, Slot?, Locked?, Obtained }`
`EggData = { Uid, Biome, Rarity, Size, Mutation?, Species?, HatchAt?, Duration? }`

## Effect payloads (`Effect(name, data)`)

| name | data |
|---|---|
| `Hatch` | `{ Pet = PetData, New = boolean }` |
| `Fuse` | `{ Pet = PetData, MutationUp = bool, SizeUp = bool, BonusEgg = EggData? }` |
| `Discovery` | `{ Species = id, Shards = n }` |
| `Tagged` | `{ By = displayName }` |
| `Trapped` | `{ Duration = seconds }` |
| `Unlock` | `{ Biome = id }` |
| `Coins` | `{ Amount = n }` |
| `Event` | `{ Id = id?, Name = string?, EndsAt = serverTime? }` (Id nil = event ended) |
| `Rebirth` | `{ Rebirths = n }` |

## PreviewFuse result

```lua
{ Ok = bool, Error = string?, Inputs = { PetData, PetData, PetData },
  Result = { Species, Tier, IncomeBefore, IncomeAfter, Cost },
  Chances = { Mutation = 0.15, Size = 0.10, BonusEgg = 0.05 },
  Warnings = { "..." }, NeedsDoubleConfirm = bool, Token = string? }
```
