"""Models the five special-move "spirit" creatures and writes:
  assets/meshes/spirits.fbx        -> import into Roblox Studio (one MeshPart per creature)
  src/shared/SpiritMeshData.lua    -> bounding-box size and triangle count of every spirit mesh
  assets/previews/spirits.png      -> all five, 3/4 front view, rendered glowing and translucent like the game
  assets/previews/spirits_top.png  -> the same from high above (~50 degrees, like the overhead camera)

Run from the repo root (needs `pip install bpy`, numpy comes with it), or inside Blender:
  python3 tools/blender/build_spirits.py                full build (meshes, data, previews)
  python3 tools/blender/build_spirits.py --quick        faster, noisier previews
  python3 tools/blender/build_spirits.py --views DIR    also write opaque side/front/top/3-4 check renders to DIR

How the shapes are made: in game the spirit is one flat translucent colour (ForceField + Highlight), so only the
silhouette matters and any inner faces would show through. Each creature is therefore sculpted as a signed distance
field: tapered capsules ("tubes") for spine, legs and tail, ellipsoids for chest and haunches, long tapered tubes for
horns, antlers, spikes and flames, and flattened tubes for feathers, fins and ears. Everything is smooth-blended into
ONE closed surface, extracted with surface nets on a voxel grid, then decimated to a light game mesh (2-9k tris).

All designs are ORIGINAL. Each creature is authored in "creature units" with its head toward -Y, then normalised:
feet on z = 0, centred in X/Y, height 1.0 (drake 1.2, roc wingspan 1.6), and finally turned to face +Y, because the
FBX export below maps Blender (x, y, z) -> Roblox (x, z, -y): Blender +Y becomes Roblox -Z, the LookVector.
"""
import math
import os
import sys
import time

import bpy  # must come before bmesh when running as the bpy module
import bmesh
import numpy as np
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
FACE_BLENDER_Y = 1.0  # +1: head toward Blender +Y = Roblox -Z (forward). Set -1 to flip the export 180 degrees.
TRI_TARGET = 6000

# ------------------------------------------------------------------------------------------------ SDF sculpting


def V(p):
    return np.asarray(p, dtype=np.float64)


def unit(p):
    p = V(p)
    return p / np.linalg.norm(p)


def sd_round_cone(p, a, b, r1, r2):
    """Distance from points p (N,3) to a sphere r1 at a swept to a sphere r2 at b (Inigo Quilez's round cone)."""
    ba = b - a
    l2 = ba @ ba
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    pa = p - a
    y = pa @ ba
    z = y - l2
    w = pa * l2 - np.outer(y, ba)
    x2 = np.einsum("ij,ij->i", w, w)
    y2 = y * y * l2
    z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    d_end = np.sqrt(x2 + z2) * il2 - r2
    d_start = np.sqrt(x2 + y2) * il2 - r1
    d_side = (np.sqrt(np.maximum(x2 * a2 * il2, 0.0)) + y * rr) * il2 - r1
    return np.where(np.sign(z) * a2 * z2 > k, d_end, np.where(np.sign(y) * a2 * y2 < k, d_start, d_side))


def catmull(points, per=6):
    """Smooth curve through the control points (Catmull-Rom), `per` samples per span."""
    pts = [V(p) for p in points]
    pts = [2 * pts[0] - pts[1]] + pts + [2 * pts[-1] - pts[-2]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for s in range(per):
            t = s / per
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(pts[-2])
    return out


class Sculpt:
    """A list of SDF primitives, each smooth-unioned (or carved) into the field with its own blend radius k."""

    def __init__(self):
        self.prims = []  # (fn, lo, hi, k, op)

    def tube(self, pts, radii, k=0.03, squash=None, op="add"):
        """Tapered capsule chain through pts with a radius per point. squash=(normal, f) flattens it to f thickness."""
        pts = [V(p) for p in pts]
        segs = [(pts[i], pts[i + 1], radii[i], radii[i + 1]) for i in range(len(pts) - 1)]
        for a, b, r1, r2 in segs:
            assert np.linalg.norm(b - a) > abs(r1 - r2) + 1e-6, (a, b, r1, r2)
        if squash is not None:
            n, f = unit(squash[0]), squash[1]
            c = pts[0]
        else:
            n, f, c = None, 1.0, None

        boxes = [(np.minimum(a, b) - max(r1, r2) - 0.1, np.maximum(a, b) + max(r1, r2) + 0.1) for a, b, r1, r2 in segs]

        def fn(p):
            if n is not None:
                p = p + np.outer((p - c) @ n * (1.0 / f - 1.0), n)
            d = np.full(len(p), 1.0)
            for (a, b, r1, r2), (blo, bhi) in zip(segs, boxes):  # only evaluate a segment near itself
                m = np.all((p >= blo) & (p <= bhi), axis=1)
                if m.any():
                    d[m] = np.minimum(d[m], sd_round_cone(p[m], a, b, r1, r2))
            return d * f

        r = max(radii)
        lo = np.min(pts, axis=0) - r
        hi = np.max(pts, axis=0) + r
        self.prims.append((fn, lo, hi, k, op))

    def horn(self, pts, r0, tip=0.004, k=0.02, squash=None, power=1.0, op="add"):
        """A spike / horn / antler tine: tube tapering from r0 to a near-sharp tip along a (curved) path."""
        pts = [V(p) for p in pts]
        lens = np.cumsum([0.0] + [np.linalg.norm(pts[i + 1] - pts[i]) for i in range(len(pts) - 1)])
        t = lens / lens[-1]
        self.tube(pts, [tip + (r0 - tip) * (1 - x) ** power for x in t], k, squash, op)

    def curve(self, ctrl, radii, per=6, k=0.03):
        """Smooth tube along a Catmull-Rom curve; radii are given per control point. Returns the sampled points."""
        pts = catmull(ctrl, per)
        rs = np.interp(np.linspace(0, len(radii) - 1, len(pts)), np.arange(len(radii)), radii)
        self.tube(pts, list(rs), k)
        return pts, rs

    def ell(self, c, r, k=0.04, axes=None, op="add"):
        """Ellipsoid with semi-axes r; axes = 3x3 rows (local x, y, z directions in world), default world axes."""
        c, r = V(c), V(r)
        R = np.eye(3) if axes is None else np.array([unit(a) for a in axes])

        def fn(p):
            q = (p - c) @ R.T
            k0 = np.linalg.norm(q / r, axis=1)
            k1 = np.linalg.norm(q / (r * r), axis=1) + 1e-9
            return k0 * (k0 - 1.0) / k1

        m = r.max()
        self.prims.append((fn, c - m, c + m, k, op))


def build_field(sc, h, ground=True):
    """Evaluate the sculpt on a voxel grid of spacing h. Returns (F, origin)."""
    adds = [p for p in sc.prims if p[4] == "add"]
    lo = np.min([p[1] for p in adds], axis=0) - 5 * h
    hi = np.max([p[2] for p in adds], axis=0) + 5 * h
    if ground:
        lo[2] = -4 * h
    n = np.ceil((hi - lo) / h).astype(int) + 1
    F = np.full(tuple(n), 1.0, np.float32)
    axes = [lo[i] + h * np.arange(n[i]) for i in range(3)]
    for fn, plo, phi, k, op in sc.prims:
        i0 = np.clip(np.floor((plo - k - h - lo) / h).astype(int), 0, n - 1)
        i1 = np.clip(np.ceil((phi + k + h - lo) / h).astype(int) + 1, 0, n)
        if np.any(i1 <= i0):
            continue
        X, Y, Z = np.meshgrid(axes[0][i0[0]:i1[0]], axes[1][i0[1]:i1[1]], axes[2][i0[2]:i1[2]], indexing="ij")
        d = fn(np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1)).reshape(X.shape)
        sl = (slice(i0[0], i1[0]), slice(i0[1], i1[1]), slice(i0[2], i1[2]))
        a = F[sl].astype(np.float64)
        if op == "sub":
            d = -d
        if k > 0:  # polynomial smooth min / max
            if op == "add":
                t = np.clip(0.5 + 0.5 * (d - a) / k, 0.0, 1.0)
                F[sl] = d + (a - d) * t - k * t * (1 - t)
            else:
                t = np.clip(0.5 - 0.5 * (d - a) / k, 0.0, 1.0)
                F[sl] = d + (a - d) * t + k * t * (1 - t)
        else:
            F[sl] = np.minimum(a, d) if op == "add" else np.maximum(a, d)
    if ground:  # flat base on z = 0 (soles, the drake's coil)
        F = np.maximum(F, -axes[2][None, None, :].astype(np.float32))
    return F, lo


def surface_nets(F, origin, h):
    """Naive surface nets: one vertex per sign-changing cell (mean of its edge crossings), one quad per crossing edge."""
    s = F < 0
    shp = F.shape
    cshape = tuple(x - 1 for x in shp)
    acc = np.zeros(cshape + (3,), np.float32)
    cnt = np.zeros(cshape, np.float32)
    crossings = []
    for ax in range(3):
        o1, o2 = (ax + 1) % 3, (ax + 2) % 3
        lo, hi = [slice(None)] * 3, [slice(None)] * 3
        lo[ax], hi[ax] = slice(0, -1), slice(1, None)
        a, b = F[tuple(lo)], F[tuple(hi)]
        m = s[tuple(lo)] != s[tuple(hi)]
        with np.errstate(divide="ignore", invalid="ignore"):
            t = np.where(m, a / (a - b), 0.0).astype(np.float32)
        mf = m.astype(np.float32)
        for d1 in (0, 1):
            for d2 in (0, 1):
                sl = [slice(None)] * 3
                sl[o1] = slice(d1, d1 + cshape[o1])
                sl[o2] = slice(d2, d2 + cshape[o2])
                sl = tuple(sl)
                acc[..., ax] += t[sl]
                acc[..., o1] += d1 * mf[sl]
                acc[..., o2] += d2 * mf[sl]
                cnt += mf[sl]
        crossings.append((ax, o1, o2, m, s[tuple(lo)]))
    occ = np.nonzero(cnt > 0)
    vid = np.full(cshape, -1, np.int64)
    vid[occ] = np.arange(len(occ[0]))
    verts = (np.stack(occ, 1) + acc[occ] / cnt[occ][:, None]) * h + origin
    quads = []
    for ax, o1, o2, m, inside_lo in crossings:
        sl = [slice(None)] * 3
        sl[o1] = slice(1, shp[o1] - 1)
        sl[o2] = slice(1, shp[o2] - 1)
        sl = tuple(sl)
        I = np.nonzero(m[sl])
        flip = ~inside_lo[sl][I]

        def cell(dj, dk):
            c = list(I)
            c[o1] = I[o1] + 1 + dj
            c[o2] = I[o2] + 1 + dk
            return vid[tuple(c)]

        q = np.stack([cell(-1, -1), cell(0, -1), cell(0, 0), cell(-1, 0)], 1)
        q[flip] = q[flip][:, ::-1]
        quads.append(q)
    return verts, np.concatenate(quads)


# ------------------------------------------------------------------------------------------------ creatures
# Authored with the head toward -Y, x = left/right, z up, roughly 1 unit tall. sym(f) builds f(+1) and f(-1).


def sym(f):
    f(1.0)
    f(-1.0)


def emberwolf(s):
    # Lean but chunky body: deep chest, tucked waist, strong haunch.
    s.tube([(0, 0.40, 0.52), (0, 0.12, 0.545), (0, -0.16, 0.575), (0, -0.30, 0.60)], [0.135, 0.12, 0.16, 0.175], k=0.06)
    s.ell((0, -0.26, 0.48), (0.145, 0.18, 0.17), k=0.07)
    s.ell((0, 0.36, 0.51), (0.125, 0.14, 0.13), k=0.06)
    # Neck runs down and forward: the head is low, below the shoulders (snarling lunge).
    s.tube([(0, -0.32, 0.62), (0, -0.46, 0.58), (0, -0.58, 0.525)], [0.145, 0.12, 0.1], k=0.05)
    s.ell((0, -0.635, 0.515), (0.108, 0.11, 0.09), k=0.035)  # skull
    s.tube([(0, -0.69, 0.525), (0, -0.87, 0.485)], [0.066, 0.04], k=0.03)  # muzzle / upper jaw
    s.tube([(0, -0.66, 0.455), (0, -0.82, 0.37)], [0.05, 0.028], k=0.012)  # lower jaw, dropped open
    s.tube([(0, -0.62, 0.565), (0, -0.74, 0.55)], [0.052, 0.032], k=0.03)  # brow wrinkle of the snarl

    def head(x):
        s.horn([(x * 0.055, -0.60, 0.57), (x * 0.09, -0.565, 0.68), (x * 0.10, -0.53, 0.77)], 0.055, k=0.02, squash=((0, 1, 0.35), 0.5))  # ear, laid back
        s.horn([(x * 0.026, -0.845, 0.47), (x * 0.026, -0.85, 0.40)], 0.016, k=0.004)  # upper fang
        s.horn([(x * 0.022, -0.80, 0.38), (x * 0.022, -0.805, 0.43)], 0.012, k=0.004)  # lower fang
        # Ruff: flame spikes flaring sideways and back from the neck, so the collar reads from above and in front.
        s.horn([(x * 0.07, -0.50, 0.61), (x * 0.18, -0.42, 0.68), (x * 0.26, -0.32, 0.75)], 0.055, k=0.03, power=1.3)
        s.horn([(x * 0.09, -0.46, 0.53), (x * 0.21, -0.38, 0.56), (x * 0.29, -0.29, 0.57)], 0.05, k=0.03, power=1.3)
        s.horn([(x * 0.08, -0.40, 0.45), (x * 0.18, -0.34, 0.41), (x * 0.24, -0.26, 0.39)], 0.04, k=0.03, power=1.3)

    sym(head)
    # Hackles: a crest of flame spikes along the neck and back, tallest over the shoulders, licking backward.
    for y, z, ln in ((-0.58, 0.59, 0.12), (-0.50, 0.645, 0.18), (-0.41, 0.70, 0.23), (-0.31, 0.745, 0.24), (-0.20, 0.735, 0.2), (-0.09, 0.705, 0.15), (0.02, 0.675, 0.11), (0.12, 0.655, 0.08)):
        s.horn([(0, y, z - 0.03), (0, y + 0.3 * ln, z + 0.55 * ln), (0, y + 0.85 * ln, z + 0.85 * ln), (0, y + 1.25 * ln, z + 0.95 * ln)], 0.3 * ln + 0.025, k=0.025, squash=((1, 0, 0), 0.6), power=1.2)
    # Front legs: right planted and reaching forward, left raised and curled (lunging).
    s.tube([(0.1, -0.27, 0.50), (0.105, -0.33, 0.31), (0.105, -0.40, 0.13), (0.105, -0.45, 0.04)], [0.085, 0.056, 0.04, 0.045], k=0.04)
    s.ell((0.105, -0.48, 0.03), (0.05, 0.07, 0.036), k=0.02)
    s.tube([(-0.1, -0.27, 0.50), (-0.115, -0.43, 0.40), (-0.12, -0.55, 0.34), (-0.12, -0.60, 0.27)], [0.085, 0.056, 0.042, 0.044], k=0.04)
    s.ell((-0.12, -0.625, 0.245), (0.05, 0.06, 0.044), k=0.02, axes=((1, 0, 0), (0, 0.6, -0.8), (0, 0.8, 0.6)))

    # Hind legs: thigh, stifle forward, hock back; the left one stretched further back (push-off).
    def hind(x):
        back = 0.0 if x > 0 else 0.07
        s.ell((x * 0.09, 0.36, 0.43), (0.075, 0.14, 0.15), k=0.05)
        s.tube([(x * 0.1, 0.35, 0.40), (x * 0.105, 0.27 + back, 0.25), (x * 0.105, 0.46 + back, 0.13), (x * 0.105, 0.44 + back, 0.04)], [0.075, 0.052, 0.038, 0.043], k=0.04)
        s.ell((x * 0.105, 0.41 + back, 0.03), (0.05, 0.07, 0.035), k=0.02)

    sym(hind)
    # Bushy tail streaming back, ending in three flame licks.
    s.tube([(0, 0.46, 0.555), (0, 0.60, 0.615), (0, 0.76, 0.645), (0, 0.90, 0.64)], [0.05, 0.095, 0.105, 0.075], k=0.04)
    s.horn([(0, 0.88, 0.64), (0, 0.99, 0.69), (0, 1.07, 0.76)], 0.06, k=0.03)
    s.horn([(0.035, 0.87, 0.62), (0.08, 0.98, 0.59), (0.12, 1.05, 0.585)], 0.05, k=0.03)
    s.horn([(-0.035, 0.87, 0.62), (-0.08, 0.98, 0.59), (-0.12, 1.05, 0.585)], 0.05, k=0.03)
    for y, ln in ((0.62, 0.09), (0.76, 0.1)):
        s.horn([(0, y, 0.69), (0, y + 0.06, 0.69 + 0.6 * ln), (0, y + 0.12, 0.69 + ln)], 0.04, k=0.02, squash=((1, 0, 0), 0.6))


def tidedrake(s):
    # Tail coil half-sunk in the ground, then the body rises in an S and the head strikes forward (-Y).
    ctrl = [(0.30, 0.30, 0.03), (0.17, 0.44, 0.05), (-0.04, 0.46, 0.06), (-0.22, 0.32, 0.07), (-0.26, 0.10, 0.07), (-0.13, -0.05, 0.08),
            (0.03, -0.06, 0.15), (0.06, 0.04, 0.33), (0.03, 0.13, 0.52), (0.0, 0.10, 0.70), (0, -0.02, 0.86), (0, -0.14, 0.97), (0, -0.25, 1.03)]
    radii = [0.028, 0.05, 0.07, 0.085, 0.095, 0.105, 0.112, 0.112, 0.107, 0.1, 0.092, 0.084, 0.078]
    pts, rs = s.curve(ctrl, radii, per=6, k=0.03)
    # Fin crest along the back: blades swept toward the tail, flattened sideways.
    n = len(pts)
    for i in range(4, n - 2, 3):
        p, r = pts[i], rs[i]
        t = unit(pts[i + 1] - pts[i - 1])
        dorsal = unit(np.cross(t, (1, 0, 0))) if p[2] > 0.2 else V((0, 0, 1))
        dorsal = unit(dorsal - (dorsal @ t) * t)
        ln = 0.08 + 1.05 * r
        side = unit(np.cross(dorsal, t))
        base = p + dorsal * (r * 0.6)
        s.horn([base, base + dorsal * ln * 0.6 - t * ln * 0.25, base + dorsal * ln - t * ln * 0.75], 0.05 + 0.3 * r, k=0.02, squash=(side, 0.3), power=1.4)
    # Tail fluke: two fins fanning up at the tip.
    tip, t0 = pts[0], unit(pts[0] - pts[2])
    for sx in (1, -1):
        s.horn([tip, tip + t0 * 0.05 + V((0.0, sx * 0.04, 0.09)), tip + t0 * 0.08 + V((0.0, sx * 0.09, 0.17))], 0.045, k=0.02, squash=((1, 0, 0), 0.35))
    # Head: long skull and snout, jaw dropped open.
    s.ell((0, -0.315, 1.045), (0.09, 0.125, 0.076), k=0.03)
    s.tube([(0, -0.36, 1.065), (0, -0.56, 1.035)], [0.068, 0.04], k=0.03)
    s.tube([(0, -0.33, 0.99), (0, -0.52, 0.89)], [0.048, 0.025], k=0.01)

    def head(x):
        s.tube([(x * 0.045, -0.37, 1.10), (x * 0.06, -0.27, 1.12)], [0.03, 0.022], k=0.02)  # brow ridge
        s.horn([(x * 0.045, -0.28, 1.10), (x * 0.085, -0.18, 1.17), (x * 0.115, -0.07, 1.22), (x * 0.12, 0.04, 1.29)], 0.04, k=0.02)  # swept horn
        s.horn([(x * 0.06, -0.28, 1.03), (x * 0.16, -0.21, 1.03), (x * 0.26, -0.13, 1.01)], 0.04, k=0.02, squash=((0, 0.2, 1), 0.4))  # cheek fin
        s.horn([(x * 0.06, -0.24, 1.0), (x * 0.14, -0.15, 0.95), (x * 0.21, -0.07, 0.91)], 0.034, k=0.02, squash=((0, 0.2, 1), 0.4))
        s.horn([(x * 0.03, -0.535, 1.02), (x * 0.03, -0.54, 0.97)], 0.013, k=0.004)  # fangs
        s.horn([(x * 0.03, -0.45, 1.03), (x * 0.03, -0.455, 0.985)], 0.011, k=0.004)
        s.horn([(x * 0.04, -0.54, 1.05), (x * 0.12, -0.62, 1.0), (x * 0.2, -0.62, 0.92)], 0.014, tip=0.006, k=0.01)  # whisker barbel
        # Small pectoral fins where the body leaves the ground (the "tiny legs").
        s.horn([(x * 0.07, 0.10, 0.44), (x * 0.18, 0.17, 0.40), (x * 0.27, 0.26, 0.33)], 0.055, k=0.03, squash=((0, 0.3, 1), 0.35))

    sym(head)


def thornstag(s):
    # Deep-chested body on long legs; the neck drops so the head is low and the antlers rake forward to charge.
    s.tube([(0, 0.32, 0.72), (0, 0.05, 0.70), (0, -0.22, 0.73)], [0.145, 0.135, 0.165], k=0.06)
    s.ell((0, -0.22, 0.65), (0.14, 0.19, 0.185), k=0.06)
    s.ell((0, 0.30, 0.71), (0.13, 0.15, 0.145), k=0.06)
    s.tube([(0, -0.27, 0.79), (0, -0.44, 0.70), (0, -0.55, 0.60)], [0.135, 0.1, 0.085], k=0.05)
    s.ell((0, -0.585, 0.585), (0.085, 0.11, 0.085), k=0.03)
    s.tube([(0, -0.62, 0.57), (0, -0.73, 0.44)], [0.068, 0.044], k=0.03)  # muzzle pointing down-forward

    def side(x):
        s.horn([(x * 0.06, -0.55, 0.63), (x * 0.14, -0.53, 0.66), (x * 0.21, -0.52, 0.64)], 0.05, k=0.015, squash=((0, 0.3, 1), 0.45))  # ear
        # Antler: thick main beam sweeping out, up and forward (a lyre), tines raking forward, a crown fork on top.
        beam = [(x * 0.045, -0.60, 0.64), (x * 0.13, -0.59, 0.79), (x * 0.25, -0.59, 0.96), (x * 0.37, -0.63, 1.12), (x * 0.45, -0.71, 1.27), (x * 0.47, -0.83, 1.39)]
        s.horn(beam, 0.072, tip=0.015, k=0.02, power=0.6)
        tines = (
            ([(0.09, -0.60, 0.70), (0.13, -0.74, 0.72), (0.14, -0.86, 0.78)], 0.045),  # brow tine, forward
            ([(0.19, -0.59, 0.88), (0.21, -0.73, 0.94), (0.21, -0.84, 1.02)], 0.042),  # bez tine, forward
            ([(0.31, -0.60, 1.04), (0.45, -0.58, 1.08), (0.56, -0.58, 1.15)], 0.04),  # outward
            ([(0.41, -0.67, 1.20), (0.44, -0.60, 1.33), (0.45, -0.54, 1.45)], 0.036),  # crown, up-back
            ([(0.44, -0.70, 1.25), (0.55, -0.71, 1.33), (0.62, -0.72, 1.43)], 0.034),  # crown, up-out
        )
        for path, r in tines:
            s.horn([(x * p[0], p[1], p[2]) for p in path], r, k=0.015)
        for p, d in (((0.13, -0.59, 0.79), (0.0, 0.05, 0.06)), ((0.25, -0.59, 0.96), (0.03, 0.07, 0.0)), ((0.40, -0.66, 1.17), (0.06, 0.04, -0.02))):
            p = V((x * p[0], p[1], p[2]))
            s.horn([p, p + V((x * d[0], d[1], d[2]))], 0.024, k=0.008)  # thorns on the beam
        # Thorns on the shoulders: round, wide-based, curving back and out.
        for b, mid, tipp, r in (((0.07, -0.20, 0.85), (0.10, -0.16, 0.93), (0.12, -0.10, 0.98), 0.045), ((0.12, -0.26, 0.77), (0.18, -0.23, 0.82), (0.23, -0.18, 0.85), 0.04)):
            s.horn([(x * b[0], b[1], b[2]), (x * mid[0], mid[1], mid[2]), (x * tipp[0], tipp[1], tipp[2])], r, k=0.015, power=1.2)
        # Hind legs: thigh, stifle forward, hock back, hoof; left one pushes off further back.
        back = 0.0 if x > 0 else 0.06
        s.ell((x * 0.08, 0.30, 0.61), (0.075, 0.14, 0.16), k=0.05)
        s.tube([(x * 0.085, 0.29, 0.58), (x * 0.09, 0.23 + back, 0.42), (x * 0.09, 0.40 + back, 0.26), (x * 0.09, 0.37 + back, 0.05)], [0.072, 0.052, 0.036, 0.038], k=0.03)
        s.tube([(x * 0.09, 0.37 + back, 0.06), (x * 0.09, 0.355 + back, 0.0)], [0.035, 0.04], k=0.01)

    sym(side)
    s.horn([(0, -0.16, 0.86), (0, -0.11, 0.94), (0, -0.04, 0.99)], 0.045, k=0.015, power=1.2)  # withers thorn
    # Front legs braced for the charge: right reaching forward, left under the chest.
    s.tube([(0.085, -0.25, 0.62), (0.09, -0.28, 0.42), (0.09, -0.33, 0.24), (0.09, -0.37, 0.05)], [0.072, 0.052, 0.036, 0.038], k=0.03)
    s.tube([(0.09, -0.37, 0.06), (0.09, -0.39, 0.0)], [0.035, 0.04], k=0.01)
    s.tube([(-0.085, -0.25, 0.62), (-0.09, -0.25, 0.42), (-0.09, -0.27, 0.24), (-0.09, -0.29, 0.05)], [0.072, 0.052, 0.036, 0.038], k=0.03)
    s.tube([(-0.09, -0.29, 0.06), (-0.09, -0.31, 0.0)], [0.035, 0.04], k=0.01)
    s.tube([(0, 0.43, 0.77), (0, 0.50, 0.72)], [0.045, 0.022], k=0.02)  # tail


def stormroc(s):
    # Braking to strike: body tilted head-up, talons thrust forward, wings raised high with their undersides turned
    # forward (so they show from the front and from above), jagged primaries spread like fingers.
    s.tube([(0, -0.16, 0.50), (0, 0.0, 0.47), (0, 0.17, 0.43)], [0.12, 0.13, 0.08], k=0.05)
    s.ell((0, -0.10, 0.46), (0.11, 0.125, 0.125), k=0.05)
    s.tube([(0, -0.20, 0.53), (0, -0.28, 0.58)], [0.09, 0.075], k=0.04)
    s.ell((0, -0.32, 0.60), (0.078, 0.092, 0.078), k=0.03)
    s.tube([(0, -0.38, 0.615), (0, -0.435, 0.61), (0, -0.475, 0.585), (0, -0.49, 0.55), (0, -0.473, 0.518)], [0.044, 0.034, 0.022, 0.012, 0.004], k=0.012)  # hooked beak
    s.tube([(0, -0.37, 0.575), (0, -0.43, 0.563)], [0.03, 0.013], k=0.008)  # lower mandible
    s.horn([(0, -0.30, 0.65), (0, -0.22, 0.72), (0, -0.12, 0.77)], 0.04, k=0.02, squash=((1, 0, 0), 0.4))  # crest

    def side(x):
        s.tube([(x * 0.042, -0.375, 0.645), (x * 0.052, -0.30, 0.668)], [0.021, 0.015], k=0.012)  # brow ridge
        s.horn([(x * 0.035, -0.29, 0.64), (x * 0.08, -0.19, 0.69), (x * 0.11, -0.10, 0.71)], 0.03, k=0.015, squash=((0, 0, 1), 0.45))
        # Wing: leading edge shoulder -> elbow -> wrist -> hand, then feathers laid in the wing plane.
        le = [V((x * 0.09, -0.09, 0.56)), V((x * 0.33, -0.11, 0.73)), V((x * 0.55, -0.15, 0.91)), V((x * 0.76, -0.12, 1.07))]
        s.tube(le, [0.065, 0.048, 0.036, 0.022], k=0.03)
        seg_len = [np.linalg.norm(le[i + 1] - le[i]) for i in range(3)]
        total = sum(seg_len)

        def at(u):
            d = u * total
            for i in range(3):
                if d <= seg_len[i] or i == 2:
                    return le[i] + (le[i + 1] - le[i]) * min(d / seg_len[i], 1.0)
                d -= seg_len[i]

        span = unit(le[3] - le[0])
        chord = unit(V((0, 1.0, 0.5)) - (V((0, 1.0, 0.5)) @ span) * span)  # trailing edge goes back and up
        normal = unit(np.cross(span, chord))
        nf = 16
        for j in range(nf):
            u = 0.03 + 0.97 * j / (nf - 1)
            root = at(u)
            # Inner feathers trail straight back; the hand's primaries fan outward like fingers.
            fan = max(0.0, (u - 0.5) / 0.5)
            d = unit(chord * (1 - fan) + span * fan * 1.6 + chord * 0.12)
            ln = 0.30 + 0.10 * u + 0.10 * fan ** 2
            tip = root + d * ln
            mid = root + d * ln * 0.55
            w = 0.055 if fan < 0.6 else 0.042
            s.tube([root, mid, tip], [w, w * 0.85, 0.008], k=0.02 if fan < 0.6 else 0.01, squash=(normal, 0.32))
        # Covert layer: fills the inner wing so the feathers read as one surface, not a comb.
        s.tube([at(0.02) + chord * 0.09, at(0.4) + chord * 0.1, at(0.7) + chord * 0.08], [0.1, 0.09, 0.06], k=0.03, squash=(normal, 0.3))
        # Legs thrust forward, three hooked talons forward and one back.
        s.ell((x * 0.065, 0.01, 0.37), (0.055, 0.08, 0.085), k=0.04)
        foot = V((x * 0.07, -0.21, 0.07))
        s.tube([V((x * 0.065, 0.0, 0.35)), V((x * 0.07, -0.12, 0.17)), foot], [0.036, 0.028, 0.028], k=0.03)
        for dx in (-0.04, 0.0, 0.04):
            s.horn([foot, foot + V((dx * 1.2, -0.06, -0.01)), foot + V((dx * 1.6, -0.11, -0.03)), foot + V((dx * 1.7, -0.13, -0.08))], 0.021, k=0.01)
        s.horn([foot, foot + V((0, 0.06, -0.02)), foot + V((0, 0.08, -0.07))], 0.019, k=0.01)

    sym(side)
    # Tail fan.
    for j in range(5):
        u = (j - 2) / 2
        root = V((u * 0.03, 0.15, 0.43))
        tipp = V((u * 0.19, 0.52, 0.38 + 0.01 * abs(u)))
        s.tube([root, (root + tipp) / 2, tipp], [0.055, 0.05, 0.01], k=0.02, squash=((0, 0.15, 1), 0.34))


def sunmane(s):
    # Heavy front, chest and shoulders; head thrust forward with the jaw wide open; a sun-ray mane.
    s.tube([(0, 0.34, 0.50), (0, 0.06, 0.505), (0, -0.22, 0.55)], [0.14, 0.13, 0.18], k=0.06)
    s.ell((0, -0.22, 0.47), (0.175, 0.2, 0.2), k=0.06)
    s.ell((0, 0.32, 0.49), (0.13, 0.145, 0.14), k=0.06)
    s.tube([(0, -0.30, 0.60), (0, -0.42, 0.65)], [0.145, 0.13], k=0.05)
    s.ell((0, -0.48, 0.67), (0.115, 0.105, 0.108), k=0.04)  # skull
    s.tube([(0, -0.53, 0.675), (0, -0.635, 0.665)], [0.088, 0.074], k=0.03)  # broad muzzle / upper jaw, raised
    s.tube([(0, -0.50, 0.585), (0, -0.61, 0.50)], [0.066, 0.05], k=0.012)  # lower jaw, dropped
    s.tube([(0, -0.47, 0.735), (0, -0.59, 0.72)], [0.062, 0.048], k=0.03)  # brow / nose bridge
    s.ell((0, -0.37, 0.66), (0.21, 0.16, 0.22), k=0.05)  # mane mass hugging the neck behind the face
    # Sun-ray mane: three staggered rings of spikes radiating around the face, each swept further back.
    c = V((0, -0.41, 0.67))
    rings = ((16, -0.02, 0.16, 0.30, 0.10, 0.07, 1.0), (16, 0.08, 0.16, 0.27, 0.22, 0.065, 1.0), (10, 0.18, 0.15, 0.22, 0.30, 0.06, 0.0))
    for ring, (n, y0, r0, ln, sweep, rad, low) in enumerate(rings):
        for i in range(n):
            th = math.tau * (i + 0.5 * (ring % 2)) / n
            if math.cos(th) < -0.92 or (not low and math.cos(th) < -0.1):  # none straight down (chest), back ring only on top
                continue
            dr = V((math.sin(th), 0, math.cos(th)))
            scl = 0.75 if math.cos(th) < -0.3 else 1.0
            base = c + dr * r0 + V((0, y0, 0))
            s.horn([base, base + dr * ln * scl * 0.55 + V((0, sweep * 0.4, 0)), base + dr * ln * scl + V((0, sweep, 0))], rad, k=0.025, squash=((0, 1, 0), 0.6), power=1.2)

    def side(x):
        s.ell((x * 0.11, -0.24, 0.50), (0.085, 0.12, 0.15), k=0.05)  # shoulder muscle
        s.horn([(x * 0.034, -0.62, 0.635), (x * 0.034, -0.625, 0.56)], 0.019, k=0.004)  # upper fangs
        s.horn([(x * 0.03, -0.59, 0.51), (x * 0.032, -0.595, 0.57)], 0.015, k=0.004)  # lower fangs
        # Thick front legs, planted wide, big paws; the left one a step ahead.
        f = -0.04 if x < 0 else 0.0
        s.tube([(x * 0.125, -0.25, 0.44), (x * 0.13, -0.28 + f * 0.5, 0.24), (x * 0.135, -0.31 + f, 0.06)], [0.098, 0.072, 0.064], k=0.04)
        s.ell((x * 0.135, -0.34 + f, 0.035), (0.07, 0.085, 0.045), k=0.02)
        # Hind legs.
        b = 0.04 if x > 0 else 0.0
        s.ell((x * 0.105, 0.32, 0.42), (0.085, 0.15, 0.16), k=0.05)
        s.tube([(x * 0.11, 0.33, 0.38), (x * 0.115, 0.43 + b, 0.18), (x * 0.115, 0.38 + b, 0.05)], [0.078, 0.052, 0.052], k=0.04)
        s.ell((x * 0.115, 0.355 + b, 0.035), (0.058, 0.075, 0.04), k=0.02)

    sym(side)
    # Tail curling up behind, with a flame-like tuft.
    s.tube([(0, 0.44, 0.56), (0, 0.60, 0.60), (0, 0.71, 0.71), (0, 0.75, 0.85), (0, 0.72, 0.94)], [0.05, 0.038, 0.033, 0.03, 0.032], k=0.03)
    b = V((0, 0.715, 0.98))
    s.ell(b, (0.065, 0.065, 0.075), k=0.02)
    for d in ((0, 0.02, 1), (0.6, 0.1, 0.7), (-0.6, 0.1, 0.7), (0, 0.7, 0.6), (0, -0.5, 0.75)):
        s.horn([b, b + unit(d) * 0.14], 0.04, k=0.02)


# id: (name, colour, builder, ("height" | "span", target size))
SPIRITS = {
    "spirit_emberwolf": ("Ember Wolf", "#ff7a2e", emberwolf, ("height", 1.0)),
    "spirit_tidedrake": ("Tide Drake", "#4fe3ff", tidedrake, ("height", 1.2)),
    "spirit_thornstag": ("Thorn Stag", "#8cff6a", thornstag, ("height", 1.0)),
    "spirit_stormroc": ("Storm Roc", "#6f9bff", stormroc, ("span", 1.6)),
    "spirit_sunmane": ("Sunmane Lion", "#ffc940", sunmane, ("height", 1.0)),
}

# ------------------------------------------------------------------------------------------------ meshing


def islands(bm):
    """Connected face groups."""
    seen, groups = set(), []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, grp = [f], []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            grp.append(g)
            for e in g.edges:
                for o in e.link_faces:
                    if o.index not in seen:
                        seen.add(o.index)
                        stack.append(o)
        groups.append(grp)
    return groups


def build_creature(cid):
    name, colour, builder, (fit, size) = SPIRITS[cid]
    t0 = time.time()
    sc = Sculpt()
    builder(sc)
    adds = [p for p in sc.prims if p[4] == "add"]
    ext = (np.max([p[2] for p in adds], axis=0) - np.min([p[1] for p in adds], axis=0)).max()
    h = ext / 280.0
    F, origin = build_field(sc, h)
    verts, quads = surface_nets(F, origin, h)
    del F

    me = bpy.data.meshes.new(cid)
    me.vertices.add(len(verts))
    me.vertices.foreach_set("co", verts.astype(np.float32).ravel())
    me.loops.add(len(quads) * 4)
    me.loops.foreach_set("vertex_index", quads.astype(np.int32).ravel())
    me.polygons.add(len(quads))
    me.polygons.foreach_set("loop_start", np.arange(0, len(quads) * 4, 4, dtype=np.int32))
    me.update(calc_edges=True)
    me.validate()

    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=h * 0.05)
    bm.faces.ensure_lookup_table()
    bm.faces.index_update()
    groups = islands(bm)
    big = max(len(g) for g in groups)
    junk = [f for g in groups if len(g) < 0.02 * big for f in g]
    if len(groups) > 1:
        print(f"  {cid}: {len(groups)} islands, dropping {len(groups) - sum(1 for g in groups if len(g) >= 0.02 * big)} tiny ones")
    bmesh.ops.delete(bm, geom=junk, context="FACES")
    bmesh.ops.smooth_vert(bm, verts=bm.verts[:], factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)  # takes the voxel stair-steps off
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    dense = sum(len(p.vertices) - 2 for p in me.polygons)

    obj = bpy.data.objects.new(cid, me)
    bpy.context.scene.collection.objects.link(obj)
    mod = obj.modifiers.new("decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = min(1.0, TRI_TARGET / dense)
    mod.use_collapse_triangulate = True
    dg = bpy.context.evaluated_depsgraph_get()
    low = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    obj.modifiers.remove(mod)
    obj.data = low
    bpy.data.meshes.remove(me)
    low.name = cid

    bm = bmesh.new()
    bm.from_mesh(low)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=1e-5)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    loose = [e for e in bm.edges if not e.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="EDGES")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    # Normalise: centre X/Y, feet on z = 0, scale to the target height or wingspan, then face the export forward.
    co = np.array([v.co[:] for v in bm.verts])
    lo, hi = co.min(0), co.max(0)
    k = size / ((hi - lo)[2] if fit == "height" else (hi - lo)[0])
    centre = V(((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]))
    turn = -FACE_BLENDER_Y  # authored facing -Y; multiply x and y by -1 to face +Y
    for v in bm.verts:
        p = (V(v.co[:]) - centre) * k
        v.co = (p[0] * turn, p[1] * turn, p[2])
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(low)
    bm.free()
    tris = len(low.polygons)
    print(f"  {cid}: grid h={h:.4f}, {dense} dense tris -> {tris} tris ({time.time() - t0:.1f}s)")
    return obj


def bounds(obj):
    co = np.empty(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    return co.min(0), co.max(0)


def check_manifold(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bad = sum(1 for e in bm.edges if not e.is_manifold)
    shells = len(islands(bm)) if bm.faces else 0
    bm.free()
    return bad, shells


# ------------------------------------------------------------------------------------------------ previews (Cycles)


def srgb(hexcol):
    return tuple((int(hexcol[i:i + 2], 16) / 255) ** 2.2 for i in (1, 3, 5)) + (1.0,)


def glow_material(name, hexcol):
    """Roughly the in-game look: one flat colour, translucent in the middle, brighter and denser at the rims."""
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = srgb(hexcol)
    em.inputs["Strength"].default_value = 2.2
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.45
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["To Min"].default_value = 0.28
    mr.inputs["To Max"].default_value = 0.95
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lw.outputs["Facing"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], mix.inputs["Fac"])
    nt.links.new(tr.outputs["BSDF"], mix.inputs[1])
    nt.links.new(em.outputs["Emission"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return m


def solid_material(name, hexcol):
    m = bpy.data.materials.new(name)
    b = m.node_tree.nodes["Principled BSDF"]
    c = srgb(hexcol)
    b.inputs["Base Color"].default_value = (0.25 + 0.5 * c[0], 0.25 + 0.5 * c[1], 0.25 + 0.5 * c[2], 1)
    b.inputs["Roughness"].default_value = 0.6
    return m


def setup_scene(samples):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.transparent_max_bounces = 16
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("w")
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.008, 0.01, 0.018, 1)
    sc.world = world


def add_lights():
    sc = bpy.context.scene
    lights = []
    for name, loc, energy, size in (("key", (6, -8, 10), 3000, 8), ("rim", (-8, 6, 6), 1500, 6), ("fill", (0, -10, 2), 900, 10)):
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
        light.data.energy = energy
        light.data.size = size
        light.location = loc
        light.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(light)
        lights.append(light)
    return lights


def lay_out(objs, turn_deg, spacing=1.95):
    """Put the creatures in a row along X, each turned turn_deg about Z from its export orientation."""
    n = len(objs)
    for i, o in enumerate(objs):
        o.rotation_euler = (0, 0, math.radians(turn_deg))
        o.location = ((i - (n - 1) / 2) * spacing, 0, 0)


def render(path, elev_deg, res, ortho_scale, look_z=0.5):
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = res
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ortho_scale
    sc.collection.objects.link(cam)
    e = math.radians(elev_deg)
    target = Vector((0, 0, look_z))
    cam.location = target + Vector((0, -math.cos(e), math.sin(e))) * 30
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


# Turning an object by T about Z points its +Y head along (-sin T, cos T). 145 degrees -> toward the camera (-Y), a bit to the left.
def head_turn(deg_from_camera):
    return (180.0 - deg_from_camera) if FACE_BLENDER_Y > 0 else -deg_from_camera


# ------------------------------------------------------------------------------------------------ main


def write_outputs(objs, meshes, previews, quick):
    row = list(objs.values())
    # Data file: Blender (Z up) -> Roblox (Y up): (x, y, z) -> (x, z, -y), so Size = (dx, dz, dy).
    lines = [
        "--!nonstrict",
        "-- GENERATED by tools/blender/build_spirits.py. Do not edit by hand.",
        "-- Bounding-box Size of every spirit mesh in Roblox axes (Y up, the creature faces -Z). The game scales them to the",
        "-- height it wants, so only the proportions matter.",
        "return {",
    ]
    for cid, o in objs.items():
        lo, hi = bounds(o)
        d = hi - lo
        tris = len(o.data.polygons)
        bad, shells = check_manifold(o)
        assert 2000 <= tris <= 9000, (cid, tris)
        print(f"  {cid}: {tris} tris, size (Blender) {d[0]:.3f} x {d[1]:.3f} x {d[2]:.3f}, {shells} shell(s), {bad} non-manifold edges")
        lines.append(f"\t{cid} = {{ Size = Vector3.new({d[0]:.4f}, {d[2]:.4f}, {d[1]:.4f}), Tris = {tris} }},")
    lines.append("}")
    open(os.path.join(ROOT, "src", "shared", "SpiritMeshData.lua"), "w").write("\n".join(lines) + "\n")

    bpy.ops.object.select_all(action="DESELECT")
    for o in objs.values():
        o.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(meshes, "spirits.fbx"),
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

    # Previews (materials are added after the export, so the FBX carries none).
    setup_scene(16 if quick else 48)
    for cid, o in objs.items():
        o.data.materials.append(glow_material(cid + "_glow", SPIRITS[cid][1]))
    lay_out(row, head_turn(35))
    render(os.path.join(previews, "spirits.png"), 14, (2000, 600), 10.0, look_z=0.55)
    render(os.path.join(previews, "spirits_top.png"), 50, (2000, 600), 10.0, look_z=0.45)


def main():
    quick = "--quick" in sys.argv
    views = sys.argv[sys.argv.index("--views") + 1] if "--views" in sys.argv else None
    only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else None  # dev: check renders only
    bpy.ops.wm.read_factory_settings(use_empty=True)
    meshes = os.path.join(ROOT, "assets", "meshes")
    previews = os.path.join(ROOT, "assets", "previews")
    os.makedirs(meshes, exist_ok=True)
    os.makedirs(previews, exist_ok=True)

    objs = {cid: build_creature(cid) for cid in SPIRITS if not only or cid in only}
    row = list(objs.values())
    if only:
        setup_scene(12)
    else:
        write_outputs(objs, meshes, previews, quick)
    sc = bpy.context.scene

    if views:  # opaque turnaround for judging the silhouettes
        os.makedirs(views, exist_ok=True)
        for cid, o in objs.items():
            o.data.materials.clear()
            o.data.materials.append(solid_material(cid + "_solid", SPIRITS[cid][1]))
        sc.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.12, 0.13, 0.16, 1)
        add_lights()
        sc.cycles.samples = 12
        side = -90.0 if FACE_BLENDER_Y > 0 else 90.0  # head to the right of the frame (+X)
        shots = (("side", side, 2), ("front", head_turn(0), 8), ("q34", head_turn(35), 18), ("top50", head_turn(35), 50), ("back", head_turn(150), 25))
        from PIL import Image  # only needed for these check sheets

        for cid, o in objs.items():
            for other in row:
                other.hide_render = other is not o
            lay_out([o], 0)
            lo, hi = bounds(o)
            scale = max(hi - lo) * 1.15
            tiles = []
            for vname, turn, elev in shots:
                o.rotation_euler = (0, 0, math.radians(turn))
                path = os.path.join(views, f"_{cid}_{vname}.png")
                render(path, elev, (440, 400), scale, look_z=(hi[2] - lo[2]) / 2)
                tiles.append(Image.open(path))
            sheet = Image.new("RGB", (440 * len(tiles), 400))
            for i, t in enumerate(tiles):
                sheet.paste(t, (440 * i, 0))
            sheet.save(os.path.join(views, f"{cid}.png"))
    print("done")


if __name__ == "__main__":
    main()
