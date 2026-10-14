"""Builds the 33 bey part meshes with Blender and writes:
  assets/meshes/{layers,discs,drivers}.fbx  -> import into Roblox Studio (README: "Better-looking beys")
  src/shared/BeyMeshData.lua                -> size and centre of every mesh, read by BeyVisuals
  assets/previews/*.png                     -> pictures of every part and some assembled beys

Run from the repo root with the `bpy` module (`pip install bpy`) or with Blender:
  python3 tools/blender/build_beys.py
  blender --background --python tools/blender/build_beys.py

All designs are ORIGINAL. Units: 1 Blender unit = 1 stud. The bey spins about +Z, fits inside radius ~2.05,
and spans z = -1.45 .. 1.1 (the same frame BeyVisuals uses). Each part is two objects, <id>_P (primary colour)
and <id>_A (accent colour); Roblox tints them from BeyDesigns, so the FBX carries no materials.
"""
import math
import os
import re

import bpy  # must come before bmesh when running as the bpy module
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TAU = math.tau
SEG = 48

RANK = {"Common": 1, "Uncommon": 2, "Rare": 3, "Epic": 4, "Legendary": 5, "UltraLegendary": 6}

# id: (slot, rarity, style, count, params). Ids and styles must match src/shared/BeyDesigns.lua.
PARTS = {
    "layer_cinderlash": ("Layer", "Common", "Spike", 4, dict(sweep=0.15)),
    "layer_thornwhirl": ("Layer", "Common", "Hook", 3, dict(sweep=0.95)),
    "layer_skyrend": ("Layer", "Uncommon", "Blade", 4, dict(sweep=0.45)),
    "layer_mossback": ("Layer", "Uncommon", "Armor", 8, dict(height=0.32)),
    "layer_ironvane": ("Layer", "Rare", "Blade", 5, dict(sweep=0.25, width=0.3)),
    "layer_stormcleat": ("Layer", "Rare", "Hook", 4, dict(sweep=0.75, width=0.21)),
    "layer_voidpetal": ("Layer", "Epic", "Petal", 5, dict(sweep=0.6)),
    "layer_sunhammer": ("Layer", "Epic", "Armor", 6, dict(height=0.42)),
    "layer_solsticerend": ("Layer", "Legendary", "Blade", 6, dict(sweep=0.5, width=0.24)),
    "layer_tempesthalo": ("Layer", "Legendary", "Petal", 6, dict(sweep=0.35)),
    "layer_eclipsesovereign": ("Layer", "UltraLegendary", "Spike", 6, dict(sweep=0.4)),
    "disc_pebbledisc": ("Disc", "Common", "Stack", 0, {}),
    "disc_tinplate": ("Disc", "Common", "Ring", 0, dict(spokes=4)),
    "disc_bulwarkring": ("Disc", "Uncommon", "Heavy", 0, dict(bolts=6)),
    "disc_driftweight": ("Disc", "Uncommon", "Fly", 0, dict(studs=8)),
    "disc_granitecore": ("Disc", "Rare", "Heavy", 0, dict(bolts=8)),
    "disc_hollowanvil": ("Disc", "Rare", "Ring", 0, dict(spokes=6)),
    "disc_titanballast": ("Disc", "Epic", "Heavy", 0, dict(bolts=10)),
    "disc_stillwater": ("Disc", "Epic", "Fly", 0, dict(studs=12)),
    "disc_worldrootmass": ("Disc", "Legendary", "Heavy", 0, dict(bolts=12)),
    "disc_astralflywheel": ("Disc", "Legendary", "Fly", 0, dict(studs=16)),
    "disc_singularityplate": ("Disc", "UltraLegendary", "Stack", 0, dict(extra=True)),
    "driver_flatnub": ("Driver", "Common", "Flat", 0, {}),
    "driver_roundpeg": ("Driver", "Common", "Round", 0, {}),
    "driver_glidepin": ("Driver", "Uncommon", "Needle", 0, dict(length=0.45)),
    "driver_spikegrip": ("Driver", "Uncommon", "Tripod", 0, {}),
    "driver_needlefoot": ("Driver", "Rare", "Needle", 0, dict(length=0.6)),
    "driver_orbitball": ("Driver", "Rare", "Round", 0, dict(big=True)),
    "driver_hoverstud": ("Driver", "Epic", "Flat", 0, dict(wide=True)),
    "driver_anchorcup": ("Driver", "Epic", "Cup", 0, {}),
    "driver_zerofrictiontip": ("Driver", "Legendary", "Needle", 0, dict(length=0.72, collar=True)),
    "driver_gyroheart": ("Driver", "Legendary", "Round", 0, dict(big=True, collar=True)),
    "driver_perpetualaxis": ("Driver", "UltraLegendary", "Needle", 0, dict(length=0.8, collar=True)),
}

# ------------------------------------------------------------------------------------------------ geometry


def lerp(a, b, t):
    return a + (b - a) * t


def ts(n):
    return [i / (n - 1) for i in range(n)]


def arc(cr, cz, rad, a0, a1, n=5):
    """(r, z) points on an arc, angles in degrees, both ends included."""
    return [(cr + rad * math.cos(math.radians(lerp(a0, a1, i / n))), cz + rad * math.sin(math.radians(lerp(a0, a1, i / n)))) for i in range(n + 1)]


def puck(r, z0, z1, rad=0.08, inner=0.0):
    """Profile of a disc (or a ring when inner > 0) with rounded outer corners, bottom to top."""
    rad = max(0.005, min(rad, (z1 - z0) / 2 - 1e-3, (r - inner) / 2))
    return [(inner, z0)] + arc(r - rad, z0 + rad, rad, -90, 0) + arc(r - rad, z1 - rad, rad, 0, 90)[1:] + [(inner, z1)]


def lathe(bm, prof, seg=SEG, at=(0.0, 0.0), closed=False):
    """Revolve an (r, z) profile about a vertical axis through `at`."""
    ax, ay = at
    vs = [bm.verts.new((ax + r, ay, z)) for r, z in prof]
    es = [bm.edges.new((vs[i], vs[i + 1])) for i in range(len(vs) - 1)]
    if closed:
        es.append(bm.edges.new((vs[-1], vs[0])))
    bmesh.ops.spin(bm, geom=vs + es, cent=(ax, ay, 0), axis=(0, 0, 1), angle=TAU, steps=seg, use_merge=True)


def stud(bm, x, y, r, z0, z1):
    lathe(bm, puck(r, z0, z1, r * 0.4), 12, at=(x, y))


def sweep(bm, centres, half_w, half_h, up_hint=Vector((0, 0, 1))):
    """Extrude a rounded 8-sided cross-section along a path; half sizes are per station."""
    n = len(centres)
    rings = []
    sect = [(-1, 0), (-0.85, -0.7), (-0.35, -1), (0.35, -1), (0.85, -0.7), (1, 0), (0.85, 0.7), (0.35, 1), (-0.35, 1), (-0.85, 0.7)]
    m = len(sect)
    for i, c in enumerate(centres):
        t = (centres[min(i + 1, n - 1)] - centres[max(i - 1, 0)]).normalized()
        lat = t.cross(up_hint)
        if lat.length < 1e-6:
            lat = Vector((1, 0, 0))
        lat.normalize()
        up = lat.cross(t).normalized()
        w, h = max(half_w[i], 0.006), max(half_h[i], 0.006)
        rings.append([bm.verts.new(c + lat * (sx * w) + up * (sz * h)) for sx, sz in sect])
    for i in range(n - 1):
        for k in range(m):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % m], rings[i + 1][(k + 1) % m], rings[i + 1][k]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])


def spiral(r0, r1, a, sweep_total, z, n=16, power=1.0, dz=0.0):
    """Path from radius r0 to r1 starting at angle a, curling by sweep_total radians (counter-clockwise)."""
    out = []
    for t in ts(n):
        r = lerp(r0, r1, t)
        th = a + sweep_total * t ** power
        out.append(Vector((r * math.cos(th), r * math.sin(th), z + dz * t)))
    return out


def circle_arc(r, a0, a1, z, n=12):
    return [Vector((r * math.cos(lerp(a0, a1, t)), r * math.sin(lerp(a0, a1, t)), z)) for t in ts(n)]


# ------------------------------------------------------------------------------------------------ layers
# The layer sits on top of the disc: plate z 0.42..0.66, blades around z 0.55, hub up to 1.05.


def layer_core(P, A, rank):
    lathe(P, puck(1.18, 0.42, 0.74, 0.12))  # body: a solid ring the blades grow out of
    lathe(P, [(0, 0.74), (0.86, 0.74), (0.76, 0.9), (0, 0.9)])  # raised centre ring
    lathe(A, puck(0.46, 0.9, 1.08, 0.12))  # hub boss (gets the glow colour)
    lathe(A, puck(0.3, 1.08, 1.12, 0.02))  # hub cap
    if rank >= 3:  # Rare+: accent rim round the body
        lathe(A, puck(1.25, 0.5, 0.64, 0.04, inner=1.1))
    if rank >= 5:  # Legendary+: ring of studs on the centre ring
        for i in range(8):
            a = TAU * (i + 0.5) / 8
            stud(A, 0.64 * math.cos(a), 0.64 * math.sin(a), 0.06, 0.86, 0.97)
    if rank >= 6:  # Ultra: a crown of small points around the hub
        for i in range(6):
            a = TAU * i / 6
            c = [Vector((r * math.cos(a), r * math.sin(a), z)) for r, z in ((0.47, 0.95), (0.5, 1.08), (0.47, 1.22))]
            sweep(A, c, [0.07, 0.05, 0.01], [0.07, 0.05, 0.01], up_hint=Vector((-math.sin(a), math.cos(a), 0)))


def blade(P, A, path, hw, hh, ridge=(0.1, 0.85), ridge_w=0.045, ridge_side=0.0):
    """A blade along `path` plus an accent ridge that sits ON its top surface (optionally shifted sideways)."""
    sweep(P, path, hw, hh)
    n = len(path)
    i0, i1 = int(ridge[0] * (n - 1)), int(ridge[1] * (n - 1))
    pts, ws = [], []
    for i in range(i0, i1 + 1):
        t = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized()
        lat = t.cross(Vector((0, 0, 1))).normalized()
        pts.append(path[i] + Vector((0, 0, hh[i] * 0.82)) + lat * (ridge_side * hw[i]))
        ws.append(ridge_w * min(1.0, hw[i] / 0.08))
    sweep(A, pts, ws, [0.035] * len(pts))


def layer_blades(P, A, style, count, prm, rank):
    z = 0.58
    sw = prm.get("sweep", 0.3)
    for i in range(count):
        a = TAU * i / count
        if style == "Spike":  # tapering spears with a ridge
            path = spiral(0.95, 2.08, a, sw, z, 18, 1.4)
            k = ts(18)
            blade(P, A, path, [0.38 * (1 - 0.92 * t) for t in k], [0.17 * (1 - 0.7 * t) for t in k])
        elif style == "Hook":  # blades that curl back into a barb
            w = prm.get("width", 0.25)
            path = spiral(0.95, 2.0, a, sw, z, 20, 1.8)
            k = ts(20)
            hw, hh = [w * (1 - 0.45 * t) for t in k], [0.17 * (1 - 0.3 * t) for t in k]
            blade(P, A, path, hw, hh, ridge=(0.15, 0.7))
            end = path[-1]
            barb = spiral(2.0, 1.55, a + sw, 0.5, z, 10, 0.8)
            barb[0] = end
            sweep(A, barb, [hw[-1] * (1 - 0.85 * t) for t in ts(10)], [hh[-1] * (1 - 0.5 * t) for t in ts(10)])
        elif style == "Blade":  # long swept wings with a bright leading edge
            w = prm.get("width", 0.25)
            path = spiral(0.95, 2.08, a, sw, z, 18, 1.2)
            k = ts(18)
            hw = [w * (1.0 if t < 0.6 else max(0.08, 1 - (t - 0.6) / 0.4)) for t in k]
            blade(P, A, path, hw, [0.16 * (1 - 0.4 * t) for t in k], ridge=(0.05, 0.9), ridge_w=0.035, ridge_side=0.55)
        elif style == "Petal":  # wide leaf shapes with a centre vein
            path = spiral(0.9, 2.0, a, sw, z, 18, 1.0)
            k = ts(18)
            blade(P, A, path, [0.48 * math.sin(math.pi * (0.08 + 0.86 * t)) ** 0.8 for t in k], [0.05 + 0.13 * math.sin(math.pi * (0.1 + 0.8 * t)) ** 0.7 for t in k], ridge=(0.12, 0.85), ridge_w=0.05)
        elif style == "Armor":  # chunky curved plates with a crest
            h = prm.get("height", 0.32)
            d = math.pi / count * 0.86
            plate = circle_arc(1.62, a - d, a + d, z + h * 0.3, 14)
            k = ts(14)
            sweep(P, plate, [0.34 * (0.8 + 0.2 * math.sin(math.pi * t)) for t in k], [h * (0.75 + 0.25 * math.sin(math.pi * t)) for t in k])
            crest = circle_arc(1.66, a - d * 0.65, a + d * 0.65, z + h * 0.3 + h * 0.95, 10)
            sweep(A, crest, [0.07] * 10, [0.03 + 0.04 * math.sin(math.pi * t) for t in ts(10)])
    if rank >= 5 and style != "Armor":  # Legendary+: small fins between the main blades
        for i in range(count):
            a = TAU * (i + 0.5) / count
            fin = spiral(1.25, 1.72, a, sw * 0.45, z - 0.02, 8, 1.0)
            sweep(A, fin, [0.09 * (1 - 0.7 * t) for t in ts(8)], [0.08 * (1 - 0.5 * t) for t in ts(8)])


# ------------------------------------------------------------------------------------------------ discs (z -0.35 .. 0.4)


def build_disc(P, A, style, prm, rank):
    if style == "Heavy":  # thick weighted wheel with a proud rim and bolts
        lathe(P, puck(1.55, -0.32, 0.32, 0.14))
        lathe(P, [(0, 0.32), (1.05, 0.32), (0.95, 0.4), (0, 0.4)])
        lathe(A, puck(1.66, -0.12, 0.12, 0.05, inner=1.5))
        n = prm.get("bolts", 8)
        for i in range(n):
            a = TAU * i / n
            stud(A, 1.25 * math.cos(a), 1.25 * math.sin(a), 0.1, 0.3, 0.4)
    elif style == "Ring":  # open ring on spokes around a solid hub
        lathe(P, puck(1.65, -0.22, 0.22, 0.1, inner=1.12))
        n = prm.get("spokes", 4)
        for i in range(n):
            a = TAU * i / n
            spoke = [Vector((r * math.cos(a), r * math.sin(a), 0)) for r in (0.5, 0.8, 1.18)]
            sweep(P, spoke, [0.12, 0.1, 0.13], [0.13, 0.11, 0.14])
        lathe(A, puck(0.62, -0.3, 0.32, 0.12))
    elif style == "Fly":  # wide thin flywheel with a raised lip and rim studs
        lathe(P, [(0, -0.1), (1.86, -0.1)] + arc(1.86, 0.04, 0.14, -90, 90, 6)[1:] + [(1.62, 0.18), (1.55, 0.1), (0, 0.1)])
        lathe(A, puck(0.66, -0.3, 0.3, 0.12))
        n = prm.get("studs", 10)
        for i in range(n):
            a = TAU * (i + 0.5) / n
            stud(A, 1.74 * math.cos(a), 1.74 * math.sin(a), 0.07, 0.15, 0.27)
    elif style == "Stack":  # stepped tiers
        lathe(P, puck(1.55, -0.34, -0.12, 0.08))
        lathe(A, puck(1.25, -0.12, 0.1, 0.06))
        lathe(P, puck(0.95, 0.1, 0.34, 0.08))
        if prm.get("extra"):
            lathe(A, puck(1.66, -0.29, -0.17, 0.04, inner=1.5))
            for i in range(6):
                a = TAU * i / 6
                stud(A, 0.7 * math.cos(a), 0.7 * math.sin(a), 0.08, 0.32, 0.44)


# ------------------------------------------------------------------------------------------------ drivers (z -1.45 .. -0.32)


def build_driver(P, A, style, prm, rank):
    top = -0.32
    if style == "Flat":  # wide flat pad: fast and aggressive
        w = 0.95 if prm.get("wide") else 0.72
        lathe(P, [(0, top), (0.55, top), (0.5, top - 0.2), (w, top - 0.42), (w, top - 0.5), (0, top - 0.5)])
        lathe(A, puck(w * 0.85, top - 0.72, top - 0.5, 0.09))
    elif style == "Round":  # ball tip: steady, moves in arcs
        br = 0.5 if prm.get("big") else 0.4
        lathe(P, [(0, top), (0.42, top), (0.36, top - 0.22), (0.24, top - 0.42), (0, top - 0.42)])
        if prm.get("collar"):
            lathe(A, puck(0.6, top - 0.14, top - 0.04, 0.03, inner=0.36))
        zc = top - 0.42 - br * 0.8
        lathe(A, [(0, zc - br)] + arc(0, zc, br, -90, 90, 10)[1:-1] + [(0, zc + br)])
    elif style == "Needle":  # tapered spike: spins in place for a long time
        ln = prm.get("length", 0.6)
        zb = top - 0.45
        lathe(P, [(0, top), (0.56, top), (0.5, top - 0.1), (0.3, top - 0.32), (0.22, zb), (0, zb)])
        if prm.get("collar"):
            lathe(A, puck(0.66, top - 0.13, top - 0.03, 0.03, inner=0.4))
        lathe(A, [(0, zb - ln - 0.1), (0.035, zb - ln - 0.06), (0.1, zb - ln * 0.45), (0.2, zb), (0, zb)])
    elif style == "Tripod":  # three claws: grips and bites
        lathe(P, puck(0.55, top - 0.3, top, 0.09))
        for i in range(3):
            a = TAU * i / 3 + math.pi / 6
            leg = [Vector(((0.2 + 0.38 * t) * math.cos(a), (0.2 + 0.38 * t) * math.sin(a), top - 0.25 - 0.75 * t)) for t in ts(8)]
            sweep(P, leg, [0.1 * (1 - 0.45 * t) for t in ts(8)], [0.09 * (1 - 0.45 * t) for t in ts(8)], up_hint=Vector((math.cos(a), math.sin(a), 0)))
            tip = [Vector(((0.58 + 0.05 * t) * math.cos(a), (0.58 + 0.05 * t) * math.sin(a), top - 1.0 - 0.22 * t)) for t in ts(5)]
            sweep(A, tip, [0.055 * (1 - 0.85 * t) for t in ts(5)], [0.055 * (1 - 0.85 * t) for t in ts(5)], up_hint=Vector((math.cos(a), math.sin(a), 0)))
    elif style == "Cup":  # wide cup: holds its ground
        lathe(P, [(0, top - 0.7), (0.32, top - 0.7), (0.62, top - 0.52), (0.84, top - 0.22), (0.86, top), (0, top)])
        lathe(A, puck(0.74, top - 0.56, top - 0.46, 0.03, inner=0.5))


# ------------------------------------------------------------------------------------------------ objects


def finish(obj):
    """Bevel hard edges, then smooth-shade while keeping creases sharp."""
    mod = obj.modifiers.new("bevel", "BEVEL")
    mod.width = 0.018
    mod.segments = 2
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(40)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    old = obj.data
    obj.modifiers.remove(mod)
    obj.data = me
    bpy.data.meshes.remove(old)
    bm = bmesh.new()
    bm.from_mesh(me)
    for e in bm.edges:
        if len(e.link_faces) == 2:
            e.smooth = e.calc_face_angle(0) < math.radians(40)
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(me)
    bm.free()


def make_object(name, bm):
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-4)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    finish(obj)
    return obj


def build_part(pid):
    slot, rarity, style, count, prm = PARTS[pid]
    rank = RANK[rarity]
    P, A = bmesh.new(), bmesh.new()
    if slot == "Layer":
        layer_core(P, A, rank)
        layer_blades(P, A, style, count, prm, rank)
    elif slot == "Disc":
        build_disc(P, A, style, prm, rank)
    else:
        build_driver(P, A, style, prm, rank)
    return {s: make_object(f"{pid}_{s}", bm) for s, bm in (("P", P), ("A", A))}


# ------------------------------------------------------------------------------------------------ output


def bounds(obj):
    vs = [v.co for v in obj.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def read_colours():
    src = open(os.path.join(ROOT, "src", "shared", "BeyDesigns.lua")).read()
    rgba = lambda h: tuple(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)) + (1.0,)
    return {m.group(1): (rgba(m.group(2)), rgba(m.group(3))) for m in re.finditer(r'(\w+) = \{[^}\n]*?Primary = c\("(#\w+)"\), Accent = c\("(#\w+)"\)', src)}


def render(path, cam_loc, target, res, lens=50):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x, sc.render.resolution_y = res
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.studio_light = "paint.sl" if "paint.sl" in [s.name for s in bpy.context.preferences.studio_lights] else sh.studio_light
    sh.color_type = "OBJECT"
    sh.show_cavity = True
    sh.cavity_type = "BOTH"
    sh.show_specular_highlight = True
    sh.show_shadows = True
    sc.display.shading.background_type = "VIEWPORT"
    sh.background_color = (0.11, 0.12, 0.15)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = lens
    sc.collection.objects.link(cam)
    cam.location = cam_loc
    cam.rotation_euler = (Vector(target) - Vector(cam_loc)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    meshes = os.path.join(ROOT, "assets", "meshes")
    previews = os.path.join(ROOT, "assets", "previews")
    os.makedirs(meshes, exist_ok=True)
    os.makedirs(previews, exist_ok=True)
    colours = read_colours()
    objs = {}
    for pid in PARTS:
        assert pid in colours, f"{pid} is not in BeyDesigns.lua"
        objs[pid] = build_part(pid)
        for s, o in objs[pid].items():
            o.color = colours[pid][0 if s == "P" else 1]

    # Manifest: Blender (Z up) -> Roblox (Y up, forward -Z): (x, y, z) -> (x, z, -y)
    lines = [
        "--!nonstrict",
        "-- GENERATED by tools/blender/build_beys.py. Do not edit by hand.",
        "-- Size and Center of every bey mesh in studs, in Roblox axes, relative to the bey's centre.",
        "-- BeyVisuals resizes each imported MeshPart to Size and places it at Center, so the import scale does not matter.",
        "return {",
    ]
    worst = ("", 0)
    for pid, parts in objs.items():
        for s, o in parts.items():
            lo, hi = bounds(o)
            c, d = (lo + hi) / 2, hi - lo
            lines.append(f"\t{o.name} = {{ Center = Vector3.new({c.x:.4f}, {c.z:.4f}, {-c.y:.4f}), Size = Vector3.new({d.x:.4f}, {d.z:.4f}, {d.y:.4f}) }},")
            tri = sum(len(p.vertices) - 2 for p in o.data.polygons)
            worst = max(worst, (o.name, tri), key=lambda w: w[1])
    lines.append("}")
    open(os.path.join(ROOT, "src", "shared", "BeyMeshData.lua"), "w").write("\n".join(lines) + "\n")
    print(f"{2 * len(objs)} meshes, most triangles: {worst[0]} {worst[1]} (Roblox allows 20000 per mesh)")

    for slot, fname in (("Layer", "layers"), ("Disc", "discs"), ("Driver", "drivers")):
        bpy.ops.object.select_all(action="DESELECT")
        for pid, parts in objs.items():
            if PARTS[pid][0] == slot:
                for o in parts.values():
                    o.select_set(True)
        bpy.ops.export_scene.fbx(
            filepath=os.path.join(meshes, fname + ".fbx"),
            use_selection=True,
            object_types={"MESH"},
            axis_forward="-Z",
            axis_up="Y",
            apply_scale_options="FBX_SCALE_ALL",
            mesh_smooth_type="FACE",
            use_mesh_modifiers=False,
            add_leaf_bones=False,
            bake_anim=False,
        )

    # Previews: each slot laid out in a grid, then four assembled beys.
    def show_only(pids, spacing=4.6, cols=6):
        for o in bpy.data.objects:
            o.hide_render = True
        for k, pid in enumerate(pids):
            for o in objs[pid].values():
                o.hide_render = False
                o.location = ((k % cols) * spacing, -(k // cols) * spacing, 0)

    for slot, height in (("Layer", 1.0), ("Disc", 0.0), ("Driver", -0.9)):
        pids = [p for p in PARTS if PARTS[p][0] == slot]
        show_only(pids)
        cx, cy = 2.5 * 4.6, -2.3
        render(os.path.join(previews, f"{slot.lower()}s.png"), (cx, cy - 24, height + 15), (cx, cy - 0.5, height), (1800, 900), lens=40)
        for pid in pids:
            for o in objs[pid].values():
                o.location = (0, 0, 0)

    combos = [
        ["layer_cinderlash", "disc_pebbledisc", "driver_flatnub"],
        ["layer_ironvane", "disc_hollowanvil", "driver_orbitball"],
        ["layer_solsticerend", "disc_worldrootmass", "driver_zerofrictiontip"],
        ["layer_eclipsesovereign", "disc_singularityplate", "driver_perpetualaxis"],
    ]
    for o in bpy.data.objects:
        o.hide_render = True
    for k, ids in enumerate(combos):
        for pid in ids:
            for o in objs[pid].values():
                o.hide_render = False
                o.location = (k * 5.0, 0, 0)
    render(os.path.join(previews, "assembled.png"), (7.5, -21, 7.5), (7.5, 0, -0.1), (1800, 640), lens=45)
    print("done")


if __name__ == "__main__":
    main()
