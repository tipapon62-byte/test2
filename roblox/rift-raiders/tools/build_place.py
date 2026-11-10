#!/usr/bin/env python3
"""Builds the playable Rift Raiders place from the original "Steal the Multiverse" map.

  python3 tools/build_place.py --source StealMultiverse_v7_fixed.rbxlx --out RiftRaiders.rbxlx

What it does (the map is kept; only gameplay code and off-theme content change):
  1. `rojo build` the scripts in src/ and injects them (ReplicatedStorage.Shared,
     ServerScriptService.Server, StarterPlayerScripts.Client).
  2. Removes the old scripts, remotes, config and the parody character/guardian models.
  3. Re-themes the Rift Run into 8 biomes:
       Zone1 lab (kept)          -> Rift Lab Grounds   Zone5 <- old Zone4 bamboo decor -> Vinewild Jungle
       Zone2 town decor removed  -> Mosswood           Zone6 decor removed             -> Emberpeak Caldera
       Zone3 underwater (kept)   -> Glimmer Lake       Zone7 new (cloned structure)    -> Frostveil Tundra
       Zone4 decor removed       -> Sunscorch Dunes    Zone8 new <- old Zone6 crystals -> Astral Ruins
     BiomeDecor (Luau) dresses the emptied zones procedurally at server start.
  4. Extends the lane barriers / end wall and renames hub signs.
Requires: rojo on PATH (or $ROJO).
"""
import argparse
import copy
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ET.register_namespace("xmime", "http://www.w3.org/2005/05/xmlmime")
ET.register_namespace("xsi", "http://www.w3.org/2001/XMLSchema-instance")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZONE_LEN = 542.0
BASEPARTS = {"Part", "WedgePart", "CornerWedgePart", "TrussPart", "MeshPart", "UnionOperation",
             "NegateOperation", "SpawnLocation", "Seat", "VehicleSeat"}

SIGN_TEXT = {
    "⭐ STEAL THE MULTIVERSE ⭐": "⭐ RIFT RAIDERS: EGG MULTIVERSE ⭐",
    "👟 SPEED SHOP · Warp Boots & Treadmills": "✨ RIFT SHOP · Trails & Upgrades",
    "🧪 Mad Science · no Speed needed": "🧪 Rift Lab Grounds · no Speed needed",
    "🌀 MULTIVERSE PLAZA": "🌀 RIFT PLAZA",
    "Mad Science": "Rift Lab Grounds", "Yellow Town": "Mosswood", "Bikini Deep": "Glimmer Lake",
    "Anime Dimension": "Sunscorch Dunes", "Meme Universe": "Vinewild Jungle", "Multiverse Core": "Astral Ruins",
    "🧪 MAD SCIENCE": "🧪 RIFT LAB GROUNDS", "🍩 YELLOW TOWN": "🌲 MOSSWOOD", "🌊 BIKINI DEEP": "🌊 GLIMMER LAKE",
    "⚔️ ANIME DIMENSION": "🏜️ SUNSCORCH DUNES", "🤪 MEME UNIVERSE": "🌿 VINEWILD JUNGLE",
    "🌌 MULTIVERSE CORE": "🌋 EMBERPEAK CALDERA",
}
# culture-specific / off-theme props dropped when the bamboo decor becomes a jungle
JUNGLE_DROP = {"Torii", "ToriiLanterns", "Shrine", "Pagoda", "Fuji", "Landmark_SwordShrine", "SkyLanterns"}

_ref_counter = [0]


def items(parent):
    return [c for c in parent if c.tag == "Item"]


def props(item):
    return item.find("Properties")


def name(item):
    p = props(item)
    if p is None:
        return ""
    for c in p:
        if c.get("name") == "Name":
            return c.text or ""
    return ""


def child(parent, n, cls=None):
    for c in items(parent):
        if name(c) == n and (cls is None or c.get("class") == cls):
            return c
    return None


def path(root, *names):
    node = root
    for i, n in enumerate(names):
        nxt = None
        for c in items(node):
            if (i == 0 and c.get("class") == n) or (i > 0 and name(c) == n):
                nxt = c
                break
        if nxt is None:
            return None
        node = nxt
    return node


def remove_children(parent, keep=None):
    for c in items(parent):
        if keep is None or name(c) not in keep:
            parent.remove(c)


def shift(item, dx):
    """Moves every part / model pivot in the subtree by dx along X (world-space CFrames only)."""
    for it in item.iter("Item"):
        p = props(it)
        if p is None:
            continue
        cls = it.get("class")
        for prop in p:
            if prop.tag == "CoordinateFrame" and prop.get("name") == "CFrame" and cls in BASEPARTS:
                x = prop.find("X")
                x.text = repr(float(x.text) + dx)
            elif prop.tag == "OptionalCoordinateFrame" and prop.get("name") == "WorldPivotData":
                cf = prop.find("CFrame")
                if cf is not None and cf.find("X") is not None:
                    cf.find("X").text = repr(float(cf.find("X").text) + dx)


def pivot_x_z(item):
    for it in item.iter("Item"):
        p = props(it)
        if p is None:
            continue
        for prop in p:
            if (prop.tag == "CoordinateFrame" and prop.get("name") == "CFrame" and it.get("class") in BASEPARTS) or \
                    (prop.tag == "OptionalCoordinateFrame" and prop.get("name") == "WorldPivotData"):
                cf = prop.find("CFrame") if prop.tag == "OptionalCoordinateFrame" else prop
                if cf is not None and cf.find("X") is not None:
                    return float(cf.find("X").text), float(cf.find("Z").text)
    return None


def reref(subtree, prefix):
    """Gives every Item a fresh referent and remaps Ref properties that point inside the subtree."""
    mapping = {}
    for it in subtree.iter("Item"):
        _ref_counter[0] += 1
        new = "%s%08X" % (prefix, _ref_counter[0])
        mapping[it.get("referent")] = new
        it.set("referent", new)
    for it in subtree.iter("Item"):
        p = props(it)
        if p is None:
            continue
        for prop in list(p):
            if prop.tag == "Ref" and prop.text in mapping:
                prop.text = mapping[prop.text]
            elif prop.tag == "UniqueId":
                # Studio refuses places with duplicate UniqueId/HistoryId; it assigns fresh ones when absent
                p.remove(prop)
    return subtree


def set_name(item, n):
    for c in props(item):
        if c.get("name") == "Name":
            c.text = n


def clone(item, prefix="RRC"):
    return reref(copy.deepcopy(item), prefix)


def rojo_build(out):
    rojo = os.environ.get("ROJO", "rojo")
    subprocess.run([rojo, "build", os.path.join(ROOT, "default.project.json"), "-o", out], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    tree = ET.parse(args.source)
    root = tree.getroot()

    # ---- 1. strip the old game code and parody models
    sss = path(root, "ServerScriptService")
    remove_children(sss)
    sps = path(root, "StarterPlayer", "StarterPlayerScripts")
    remove_children(sps)
    scs = path(root, "StarterPlayer", "StarterCharacterScripts")
    if scs is not None:
        remove_children(scs)
    rs = path(root, "ReplicatedStorage")
    for n in ("Config", "Remotes", "CharacterModels", "GuardianModels", "Shared"):
        c = child(rs, n)
        if c is not None:
            rs.remove(c)

    # ---- 2. re-theme the Rift Run
    zones = path(root, "Workspace", "RiftRun", "Zones")
    z = {i: child(zones, "Zone%d" % i) for i in range(1, 9)}
    for i in (1, 2, 3, 4, 5, 6):
        if z[i] is None:
            sys.exit("source place has no Zone%d" % i)

    def take(zone, n):
        c = child(zone, n)
        if c is not None:
            zone.remove(c)
        return c

    for i in (2, 5):
        take(z[i], "Decor")
        take(z[i], "Backdrop")
    bamboo = [take(z[4], "Decor"), take(z[4], "Backdrop")]
    crystals = [take(z[6], "Decor"), take(z[6], "Backdrop")]

    if z[7] is None:
        for i, dx in ((7, ZONE_LEN), (8, 2 * ZONE_LEN)):
            nz = clone(z[6])
            set_name(nz, "Zone%d" % i)
            shift(nz, dx)
            zones.append(nz)
            z[i] = nz
    for part in bamboo:
        if part is not None:
            for c in items(part):
                if name(c) in JUNGLE_DROP:
                    part.remove(c)
            shift(part, ZONE_LEN)
            z[5].append(part)
    for part in crystals:
        if part is not None:
            shift(part, 2 * ZONE_LEN)
            z[8].append(part)

    run = path(root, "Workspace", "RiftRun")
    for n in ("EndWall", "EndWallCap"):
        c = child(run, n)
        if c is not None:
            pos = pivot_x_z(c)
            if pos and pos[0] < 3700:
                shift(c, 2 * ZONE_LEN)

    # lane barriers for the two new zones + clear scenery that now overlaps them
    barriers = path(root, "Workspace", "Scenery", "Barriers")
    if barriers is not None:
        for b in items(barriers):
            pos = pivot_x_z(b)
            if pos and abs(pos[0] - 3060) < 1 and abs(abs(pos[1]) - 175) < 1:
                nb = clone(b)
                shift(nb, 2 * ZONE_LEN)
                barriers.append(nb)
    scenery = path(root, "Workspace", "Scenery")
    if scenery is not None:
        lane_max = 350 + 8 * ZONE_LEN + 20
        for folder in items(scenery):
            if name(folder) in ("Mountains", "Hills", "Forest", "CastleWalls"):
                for m in items(folder):
                    pos = pivot_x_z(m)
                    if pos and 3590 < pos[0] < lane_max and abs(pos[1]) < 200:
                        folder.remove(m)

    # ---- 3. sign texts
    for sv in root.iter("Item"):
        if sv.get("class") == "StringValue":
            for prop in props(sv):
                if prop.get("name") == "Value" and prop.text in SIGN_TEXT:
                    prop.text = SIGN_TEXT[prop.text]

    # ---- 4. inject the new code
    with tempfile.TemporaryDirectory() as tmp:
        built = os.path.join(tmp, "scripts.rbxlx")
        rojo_build(built)
        broot = ET.parse(built).getroot()
        reref(broot, "RRS")
        rs.append(path(broot, "ReplicatedStorage", "Shared"))
        sss.append(path(broot, "ServerScriptService", "Server"))
        sps.append(path(broot, "StarterPlayer", "StarterPlayerScripts", "Client"))

    tree.write(args.out, encoding="utf-8", xml_declaration=False)
    print("wrote", args.out)


if __name__ == "__main__":
    main()
