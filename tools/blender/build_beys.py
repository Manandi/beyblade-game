"""Models the 33 bey parts in a hard-surface style and writes:
  assets/meshes/{layers,discs,drivers}.fbx  -> import into Roblox Studio (README: "Better-looking beys")
  src/shared/BeyMeshData.lua                -> size and centre of every mesh, read by BeyVisuals
  assets/previews/*.png                     -> Cycles renders of every part and some assembled beys

Run from the repo root (needs `pip install bpy shapely mapbox_earcut`), or inside Blender with those modules:
  python3 tools/blender/build_beys.py            full build (meshes, data, previews)
  python3 tools/blender/build_beys.py --quick    lower-quality previews, faster

How the shapes are made: each part is a stack of TIERS. A tier is a 2D outline (shapely polygon, holes allowed)
extruded between two heights, then every hard edge gets a small chamfer. That gives the crisp, layered,
machined look of a real spinning top. Round things (tips, bolts) are lathed with few sides so they stay faceted.

All designs are ORIGINAL. Units: 1 Blender unit = 1 stud. The bey spins about +Z, fits inside radius ~2.1,
and spans z = -1.45 .. 1.15 (the same frame BeyVisuals uses). Each part is two objects, <id>_P (primary colour)
and <id>_A (accent colour); Roblox tints them from BeyDesigns, so the FBX carries no materials.
"""
import math
import os
import re
import sys

import bpy  # must come before bmesh when running as the bpy module
import bmesh
import mapbox_earcut
import numpy as np
from mathutils import Vector
from shapely import affinity
from shapely.geometry import MultiPolygon, Polygon
from shapely.geometry.polygon import orient
from shapely.ops import unary_union

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TAU = math.tau
RANK = {"Common": 1, "Uncommon": 2, "Rare": 3, "Epic": 4, "Legendary": 5, "UltraLegendary": 6}

# id: (slot, rarity, style, count, params). Ids and styles must match src/shared/BeyDesigns.lua.
PARTS = {
    "layer_cinderlash": ("Layer", "Common", "Spike", 4, dict(sweep=0.25)),
    "layer_thornwhirl": ("Layer", "Common", "Hook", 3, dict(sweep=1.1)),
    "layer_skyrend": ("Layer", "Uncommon", "Blade", 4, dict(sweep=0.55)),
    "layer_mossback": ("Layer", "Uncommon", "Armor", 8, {}),
    "layer_ironvane": ("Layer", "Rare", "Blade", 5, dict(sweep=0.3, width=0.42)),
    "layer_stormcleat": ("Layer", "Rare", "Hook", 4, dict(sweep=0.9)),
    "layer_voidpetal": ("Layer", "Epic", "Petal", 5, dict(sweep=0.55)),
    "layer_sunhammer": ("Layer", "Epic", "Armor", 6, dict(teeth=True)),
    "layer_solsticerend": ("Layer", "Legendary", "Blade", 6, dict(sweep=0.6, width=0.36)),
    "layer_tempesthalo": ("Layer", "Legendary", "Petal", 6, dict(sweep=0.3)),
    "layer_eclipsesovereign": ("Layer", "UltraLegendary", "Spike", 6, dict(sweep=0.55)),
    "disc_pebbledisc": ("Disc", "Common", "Stack", 0, dict(sides=10)),
    "disc_tinplate": ("Disc", "Common", "Ring", 0, dict(spokes=4)),
    "disc_bulwarkring": ("Disc", "Uncommon", "Heavy", 0, dict(holes=6, sides=12)),
    "disc_driftweight": ("Disc", "Uncommon", "Fly", 0, dict(teeth=12)),
    "disc_granitecore": ("Disc", "Rare", "Heavy", 0, dict(holes=8, sides=8)),
    "disc_hollowanvil": ("Disc", "Rare", "Ring", 0, dict(spokes=6)),
    "disc_titanballast": ("Disc", "Epic", "Heavy", 0, dict(holes=10, sides=10)),
    "disc_stillwater": ("Disc", "Epic", "Fly", 0, dict(teeth=16)),
    "disc_worldrootmass": ("Disc", "Legendary", "Heavy", 0, dict(holes=12, sides=12)),
    "disc_astralflywheel": ("Disc", "Legendary", "Fly", 0, dict(teeth=20)),
    "disc_singularityplate": ("Disc", "UltraLegendary", "Stack", 0, dict(sides=6, extra=True)),
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

# ------------------------------------------------------------------------------------------------ 2D outlines


def lerp(a, b, t):
    return a + (b - a) * t


def ts(n):
    return [i / (n - 1) for i in range(n)]


def circle(r, n=96, at=(0.0, 0.0)):
    return Polygon([(at[0] + r * math.cos(TAU * i / n), at[1] + r * math.sin(TAU * i / n)) for i in range(n)])


def ngon(r, n, rot=0.0):
    return Polygon([(r * math.cos(rot + TAU * i / n), r * math.sin(rot + TAU * i / n)) for i in range(n)])


def ring(r_out, r_in, n=96):
    return circle(r_out, n).difference(circle(r_in, n))


def ribbon(points, widths):
    """Outline of a band following `points` with a half-width per point (0 = sharp point)."""
    left, right = [], []
    n = len(points)
    for i, (p, w) in enumerate(zip(points, widths)):
        a, b = points[max(i - 1, 0)], points[min(i + 1, n - 1)]
        tx, ty = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / ln, tx / ln
        left.append((p[0] + nx * w, p[1] + ny * w))
        right.append((p[0] - nx * w, p[1] - ny * w))
    poly = Polygon(left + right[::-1])
    return poly if poly.is_valid else poly.buffer(0)


def spiral(r0, r1, a, sweep, n=24, power=1.0):
    return [(lerp(r0, r1, t) * math.cos(a + sweep * t ** power), lerp(r0, r1, t) * math.sin(a + sweep * t ** power)) for t in ts(n)]


def around(shape, count, offset=0.0):
    """`count` copies of `shape` rotated evenly about the centre (offset in degrees)."""
    return unary_union([affinity.rotate(shape, offset + 360.0 * i / count, origin=(0, 0)) for i in range(count)])


def clean(shape, min_area=0.05):
    """Drop slivers and tiny islands so inlays read as solid plates, not shards."""
    shape = shape.buffer(-0.035, join_style=2).buffer(0.035, join_style=2)
    polys = list(shape.geoms) if isinstance(shape, MultiPolygon) else [shape]
    return unary_union([p for p in polys if isinstance(p, Polygon) and p.area >= min_area])


def star(r_out, r_in, points, rot=0.0):
    pts = []
    for i in range(points * 2):
        r = r_out if i % 2 == 0 else r_in
        a = rot + math.pi * i / points
        pts.append((r * math.cos(a), r * math.sin(a)))
    return Polygon(pts)


# ------------------------------------------------------------------------------------------------ 3D


def tier(bm, shape, z0, z1):
    """Extrude a 2D outline (holes allowed) between z0 and z1 as a closed solid."""
    if shape.is_empty:
        return
    polys = list(shape.geoms) if isinstance(shape, MultiPolygon) else [shape]
    for poly in polys:
        if not isinstance(poly, Polygon) or poly.area < 1e-4:
            continue
        poly = orient(poly.simplify(0.002), 1.0)
        rings = [list(poly.exterior.coords)[:-1]] + [list(r.coords)[:-1] for r in poly.interiors]
        flat = np.array([pt for r in rings for pt in r], dtype=np.float64)
        ends = np.cumsum([len(r) for r in rings]).astype(np.uint32)
        tris = mapbox_earcut.triangulate_float64(flat, ends)
        bot = [bm.verts.new((x, y, z0)) for x, y in flat]
        top = [bm.verts.new((x, y, z1)) for x, y in flat]
        for i in range(0, len(tris), 3):
            a, b, c = int(tris[i]), int(tris[i + 1]), int(tris[i + 2])
            try:
                bm.faces.new((top[a], top[b], top[c]))
                bm.faces.new((bot[c], bot[b], bot[a]))
            except ValueError:
                pass
        start = 0
        for end in ends:
            for k in range(start, int(end)):
                nxt = k + 1 if k + 1 < end else start
                bm.faces.new((bot[k], bot[nxt], top[nxt], top[k]))
            start = int(end)


def lathe(bm, prof, seg=8, at=(0.0, 0.0), rot=0.0):
    """Revolve an (r, z) profile; few segments keeps it faceted (hard-surface)."""
    ax, ay = at
    rings = []
    for s in range(seg):
        a = rot + TAU * s / seg
        rings.append([bm.verts.new((ax + r * math.cos(a), ay + r * math.sin(a), z)) for r, z in prof])
    for s in range(seg):
        r0, r1 = rings[s], rings[(s + 1) % seg]
        for k in range(len(prof) - 1):
            bm.faces.new((r0[k], r1[k], r1[k + 1], r0[k + 1]))
    if prof[0][0] > 1e-6:
        bm.faces.new([rings[s][0] for s in range(seg)][::-1])
    if prof[-1][0] > 1e-6:
        bm.faces.new([rings[s][-1] for s in range(seg)])


def bolt(bm, x, y, r, z0, z1):
    lathe(bm, [(0, z0), (r, z0), (r, z1 - r * 0.35), (r * 0.6, z1), (0, z1)], 6, at=(x, y), rot=math.atan2(y, x))


# ------------------------------------------------------------------------------------------------ layers (z 0.42 .. 1.15)


def blade_shape(style, count, prm):
    sw = prm.get("sweep", 0.3)
    if style == "Spike":
        blade = ribbon(spiral(0.7, 2.1, 0, sw, 20, 1.5), [0.42 * (1 - t) ** 1.15 for t in ts(20)])
        back = ribbon(spiral(0.8, 1.55, -0.45, sw * 0.6, 12, 1.2), [0.18 * (1 - t) for t in ts(12)])  # rear barb
        return around(unary_union([blade, back]), count)
    if style == "Hook":
        blade = ribbon(spiral(0.75, 2.02, 0, sw, 28, 1.8), [0.3 * (1 - 0.55 * t) for t in ts(28)])
        tip = ribbon(spiral(2.02, 1.55, sw, 0.55, 12, 0.8), [0.17 * (1 - t) for t in ts(12)])
        return around(unary_union([blade, tip]), count)
    if style == "Blade":
        w = prm.get("width", 0.4)
        blade = ribbon(spiral(0.7, 2.1, 0, sw, 22, 1.2), [w * (1.0 if t < 0.55 else max(0.0, 1 - (t - 0.55) / 0.45)) for t in ts(22)])
        notch = ribbon(spiral(1.25, 1.6, sw * 0.25, 0.1, 6), [0.08] * 6)  # cut groove for detail
        return around(blade.difference(notch.buffer(0.01)), count)
    if style == "Petal":
        leaf = ribbon(spiral(0.6, 2.05, 0, sw, 22, 1.0), [0.62 * math.sin(math.pi * (0.04 + 0.92 * t)) ** 0.75 for t in ts(22)])
        return around(leaf, count)
    if style == "Armor":
        d = math.pi / count * 0.82
        plates = []
        for i in range(count):
            a = TAU * i / count
            plates.append(Polygon([(r * math.cos(a + s * d), r * math.sin(a + s * d)) for r, s in ((1.0, -1.0), (1.95, -0.85), (2.05, 0.0), (1.95, 0.85), (1.0, 1.0))]))
        shape = unary_union(plates)
        if prm.get("teeth"):
            shape = unary_union([shape, around(Polygon([(1.0, -0.12), (2.16, 0.0), (1.0, 0.12)]), count, 180.0 / count)])
        return shape
    raise ValueError(style)


def build_layer(P, A, style, count, prm, rank):
    sw = prm.get("sweep", 0.3)
    body = unary_union([circle(1.12), blade_shape(style, count, prm)])
    if rank >= 3 and style != "Armor":  # Rare+: small secondary fins between the blades
        fin = ribbon(spiral(0.9, 1.55, 0, sw * 0.5, 10), [0.16 * (1 - t) for t in ts(10)])
        body = unary_union([body, around(fin, count, 180.0 / count)])
    body = body.buffer(0.015).buffer(-0.015)  # removes slivers where shapes meet
    tier(P, body.difference(circle(0.36)), 0.42, 0.62)  # main attack ring

    inlay = body.buffer(-0.13).intersection(circle(1.95))  # coloured plate following the blades, inset from the edge
    if rank >= 4:  # Epic+: engraved lines cut through the plate
        inlay = inlay.difference(around(ribbon(spiral(0.95, 1.8, 0, sw, 14), [0.03] * 14), count))
    tier(A, clean(inlay.difference(circle(0.8))), 0.62, 0.7)

    hub_sides = max(6, count * 2 if count <= 4 else count)
    hub = ngon(0.92, hub_sides, math.pi / hub_sides).difference(around(Polygon([(0.78, -0.07), (1.0, -0.07), (1.0, 0.07), (0.78, 0.07)]), count))
    tier(P, hub.difference(circle(0.36)), 0.62, 0.84)  # faceted hub ring with notches
    tier(A, ngon(0.52, 8, math.pi / 8), 0.84, 0.98)  # core
    tier(P, star(0.36, 0.17, count if count >= 4 else 6, math.pi / 2), 0.98, 1.04)  # emblem
    if rank >= 5:  # Legendary+: raised accent ridges along each blade
        ridge = around(ribbon(spiral(1.0, 1.85, 0, sw, 16, 1.2), [0.045 * (1 - 0.6 * t) for t in ts(16)]), count)
        tier(A, clean(ridge.intersection(body.buffer(-0.08)), 0.01), 0.7, 0.76)
    if rank >= 6:  # Ultra: crown of spikes round the core
        tier(A, star(0.72, 0.53, 8, 0.0).difference(circle(0.5)), 0.84, 1.12)


# ------------------------------------------------------------------------------------------------ discs (z -0.34 .. 0.32)


def build_disc(P, A, style, prm, rank):
    if style == "Heavy":  # thick machined wheel, polygonal edge, weight holes
        n, h = prm.get("sides", 10), prm.get("holes", 8)
        outer = ngon(1.64, n, math.pi / n).intersection(circle(1.58)).union(circle(1.5))
        holes = around(circle(0.16, 24, (1.08, 0)), h)
        tier(P, outer.difference(holes).difference(circle(0.3)), -0.32, 0.14)
        tier(P, ring(1.2, 0.3).difference(holes), 0.14, 0.3)  # raised inner deck
        tier(A, ring(1.66, 1.5), -0.14, 0.04)  # accent band round the rim
        for i in range(h):
            a = TAU * (i + 0.5) / h
            bolt(A, 1.32 * math.cos(a), 1.32 * math.sin(a), 0.07, 0.14, 0.24)
    elif style == "Ring":  # open wheel: rim + spokes + hub
        n = prm.get("spokes", 4)
        spokes = around(Polygon([(0.4, -0.13), (1.3, -0.17), (1.3, 0.17), (0.4, 0.13)]), n)
        tier(P, unary_union([ring(1.66, 1.2), spokes]).difference(circle(0.3)), -0.22, 0.16)
        tier(P, ring(1.66, 1.42), 0.16, 0.26)
        tier(A, ngon(0.62, 6, 0).difference(circle(0.3)), -0.3, 0.3)
        tier(A, around(Polygon([(1.22, -0.06), (1.4, -0.06), (1.4, 0.06), (1.22, 0.06)]), n * 2), 0.16, 0.22)
    elif style == "Fly":  # wide thin flywheel with a toothed outer lip
        n = prm.get("teeth", 12)
        teeth = around(Polygon([(1.86, -0.09), (2.02, -0.04), (2.02, 0.04), (1.86, 0.09)]), n)
        tier(P, unary_union([circle(1.88), teeth]).difference(circle(0.3)), -0.1, 0.04)
        tier(P, ring(1.9, 1.6), 0.04, 0.2)
        tier(A, ngon(0.66, 8, math.pi / 8).difference(circle(0.3)), -0.3, 0.3)
        tier(A, around(Polygon([(0.75, -0.05), (1.5, -0.1), (1.5, 0.1), (0.75, 0.05)]), n // 2), 0.04, 0.1)
    elif style == "Stack":  # stepped tiers
        n = prm.get("sides", 10)
        tier(P, ngon(1.6, n, math.pi / n).difference(circle(0.3)), -0.34, -0.12)
        tier(A, ngon(1.3, n, 0).difference(circle(0.3)), -0.12, 0.08)
        tier(P, ngon(1.0, n, math.pi / n).difference(circle(0.3)), 0.08, 0.3)
        if prm.get("extra"):
            tier(A, ring(1.7, 1.56), -0.3, -0.16)
            tier(A, around(Polygon([(1.0, -0.05), (1.32, -0.08), (1.32, 0.08), (1.0, 0.05)]), 6), 0.08, 0.14)


# ------------------------------------------------------------------------------------------------ drivers (z -1.45 .. -0.32)


def build_driver(P, A, style, prm, rank):
    top = -0.32
    tier(P, ngon(0.62, 8, math.pi / 8), top - 0.16, top)  # every driver has a faceted collar plate
    if style == "Flat":
        w = 0.95 if prm.get("wide") else 0.72
        lathe(P, [(0.5, top - 0.16), (0.42, top - 0.36), (w, top - 0.5), (w, top - 0.58), (0.0, top - 0.58)], 10)
        lathe(A, [(w * 0.82, top - 0.58), (w * 0.82, top - 0.7), (w * 0.6, top - 0.78), (0.0, top - 0.78)], 16)
    elif style == "Round":
        br = 0.5 if prm.get("big") else 0.4
        lathe(P, [(0.5, top - 0.16), (0.38, top - 0.3), (0.26, top - 0.45), (0.0, top - 0.45)], 8)
        zc = top - 0.45 - br * 0.8
        lathe(A, [(0.0, zc + br)] + [(br * math.cos(math.radians(a)), zc + br * math.sin(math.radians(a))) for a in range(75, -91, -15)], 16)
    elif style == "Needle":
        ln = prm.get("length", 0.6)
        zb = top - 0.45
        lathe(P, [(0.55, top - 0.16), (0.42, top - 0.28), (0.24, zb), (0.0, zb)], 8)
        lathe(A, [(0.2, zb), (0.1, zb - ln * 0.5), (0.03, zb - ln), (0.0, zb - ln - 0.06)], 8)
    elif style == "Tripod":
        lathe(P, [(0.5, top - 0.16), (0.48, top - 0.36), (0.0, top - 0.36)], 6)
        for i in range(3):
            a = TAU * i / 3 + math.pi / 6
            claw = affinity.rotate(ribbon([(0.15, 0), (0.45, 0), (0.62, 0)], [0.09, 0.08, 0.02]), math.degrees(a), origin=(0, 0))
            tier(P, claw, top - 0.7, top - 0.36)
            lathe(A, [(0.07, top - 0.7), (0.03, top - 1.0), (0.0, top - 1.05)], 6, at=(0.52 * math.cos(a), 0.52 * math.sin(a)))
    elif style == "Cup":
        lathe(P, [(0.6, top - 0.16), (0.84, top - 0.22), (0.66, top - 0.52), (0.34, top - 0.7), (0.0, top - 0.7)], 12)
        tier(A, ring(0.78, 0.58, 12), top - 0.5, top - 0.42)
    if prm.get("collar"):
        tier(A, ngon(0.7, 8, 0).difference(ngon(0.58, 8, 0)), top - 0.13, top - 0.03)


# ------------------------------------------------------------------------------------------------ objects


def finish(obj):
    """Chamfer every hard edge and keep shading crisp (sharp edges stay sharp in Roblox too)."""
    mod = obj.modifiers.new("chamfer", "BEVEL")
    mod.width = 0.022
    mod.segments = 1
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(30)
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
            e.smooth = e.calc_face_angle(0) < math.radians(30)
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(me)
    bm.free()


def make_object(name, bm):
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
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
        build_layer(P, A, style, count, prm, rank)
    elif slot == "Disc":
        build_disc(P, A, style, prm, rank)
    else:
        build_driver(P, A, style, prm, rank)
    return {s: make_object(f"{pid}_{s}", bm) for s, bm in (("P", P), ("A", A))}


# ------------------------------------------------------------------------------------------------ previews (Cycles)


def read_colours():
    src = open(os.path.join(ROOT, "src", "shared", "BeyDesigns.lua")).read()
    rgb = lambda h: tuple((int(h[i:i + 2], 16) / 255) ** 2.2 for i in (1, 3, 5)) + (1.0,)  # sRGB -> linear
    return {m.group(1): (rgb(m.group(2)), rgb(m.group(3))) for m in re.finditer(r'(\w+) = \{[^}\n]*?Primary = c\("(#\w+)"\), Accent = c\("(#\w+)"\)', src)}


def material(name, colour, metal, rough, glow=0.0):
    m = bpy.data.materials.new(name)
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = colour
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if glow:
        b.inputs["Emission Color"].default_value = colour
        b.inputs["Emission Strength"].default_value = glow
    return m


def setup_render(quick):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24 if quick else 64
    sc.cycles.use_denoising = True
    world = bpy.data.worlds.new("w")
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.035, 0.04, 0.055, 1)
    sc.world = world
    for name, loc, energy, size in (("key", (6, -8, 10), 2600, 8), ("rim", (-8, 6, 6), 1500, 6), ("fill", (0, -10, 2), 600, 10), ("top", (0, 0, 14), 900, 12)):
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
        light.data.energy = energy
        light.data.size = size
        light.location = loc
        light.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(light)
    floor = bpy.data.objects.new("floor", bpy.data.meshes.new("floor"))
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=200)
    bm.to_mesh(floor.data)
    bm.free()
    floor.data.materials.append(material("floor", (0.05, 0.055, 0.07, 1), 0.0, 0.6))
    sc.collection.objects.link(floor)
    return floor


def render(path, cam_loc, target, res, lens=50):
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = res
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = lens
    sc.collection.objects.link(cam)
    cam.location = cam_loc
    cam.rotation_euler = (Vector(target) - Vector(cam_loc)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


# ------------------------------------------------------------------------------------------------ main


def main():
    quick = "--quick" in sys.argv
    only_previews = "--previews" in sys.argv
    bpy.ops.wm.read_factory_settings(use_empty=True)
    meshes = os.path.join(ROOT, "assets", "meshes")
    previews = os.path.join(ROOT, "assets", "previews")
    os.makedirs(meshes, exist_ok=True)
    os.makedirs(previews, exist_ok=True)
    colours = read_colours()
    for pid in PARTS:
        assert pid in colours, f"{pid} is not in BeyDesigns.lua"
    objs = {pid: build_part(pid) for pid in PARTS}

    if not only_previews:
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
                vs = [v.co for v in o.data.vertices]
                lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
                hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
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
                mesh_smooth_type="OFF",
                use_mesh_modifiers=False,
                add_leaf_bones=False,
                bake_anim=False,
            )

    # Materials only for the previews (the FBX was already written without them). Roughly what Roblox will show:
    # discs are Metal, the rest SmoothPlastic, Legendary+ accents Neon.
    for pid, parts in objs.items():
        slot, rarity = PARTS[pid][0], PARTS[pid][1]
        prim, acc = colours[pid]
        parts["P"].data.materials.append(material(pid + "P", prim, 0.9 if slot == "Disc" else 0.0, 0.32 if slot == "Disc" else 0.4))
        parts["A"].data.materials.append(material(pid + "A", acc, 0.0, 0.35, 2.5 if RANK[rarity] >= 5 else 0.0))
    floor = setup_render(quick)

    def show(pids, spacing, cols, z_floor):
        for o in bpy.data.objects:
            if o.type == "MESH" and o is not floor:
                o.hide_render = True
        floor.location.z = z_floor
        for k, pid in enumerate(pids):
            for o in objs[pid].values():
                o.hide_render = False
                o.location = ((k % cols) * spacing, -(k // cols) * spacing, 0)

    for slot, zf, look_z, cam_h in (("Layer", 0.4, 0.7, 17), ("Disc", -0.36, 0.0, 17), ("Driver", -1.47, -0.8, 7)):
        pids = [p for p in PARTS if PARTS[p][0] == slot]
        show(pids, 4.8, 6, zf)
        cx, cy = 2.5 * 4.8, -2.4
        render(os.path.join(previews, f"{slot.lower()}s.png"), (cx, cy - 22, look_z + cam_h), (cx, cy - 0.3, look_z), (1800, 900), lens=42)

    combos = [
        ["layer_cinderlash", "disc_pebbledisc", "driver_flatnub"],
        ["layer_ironvane", "disc_hollowanvil", "driver_orbitball"],
        ["layer_solsticerend", "disc_worldrootmass", "driver_zerofrictiontip"],
        ["layer_eclipsesovereign", "disc_singularityplate", "driver_perpetualaxis"],
    ]
    for o in bpy.data.objects:
        if o.type == "MESH" and o is not floor:
            o.hide_render = True
    floor.location.z = -1.47
    def span(pid):
        zs = [v.co.z for o in objs[pid].values() for v in o.data.vertices]
        return min(zs), max(zs)

    for k, (layer, disc, driver) in enumerate(combos):
        # Stack flush exactly like BeyVisuals does in game: layer on the wheel's top, driver under its bottom.
        d_bot, d_top = span(disc)
        lifts = {disc: 0.0, layer: d_top - 0.02 - span(layer)[0], driver: d_bot + 0.02 - span(driver)[1]}
        for pid, lift in lifts.items():
            for o in objs[pid].values():
                o.hide_render = False
                o.location = (k * 5.2, 0, lift)
    render(os.path.join(previews, "assembled.png"), (7.8, -21, 8), (7.8, 0, -0.2), (1800, 700), lens=36)
    print("done")


if __name__ == "__main__":
    main()
