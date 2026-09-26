"""Outils de pose pour le rig Mixamo de la grenouille (Blender, espace armature).

Repère du personnage dans l'espace armature (constaté sur le rig, 2026-09-26) :
avant = -Y, haut = +Z, gauche du personnage = +X. Taille 1,0 unité (le jeu met
le modèle à 1,8 m). Rotations en degrés, axes exprimés dans l'espace armature.
"""
import math

import bpy
from mathutils import Matrix, Quaternion, Vector

FWD = Vector((0.0, -1.0, 0.0))
UP = Vector((0.0, 0.0, 1.0))
LEFT = Vector((1.0, 0.0, 0.0))
AX_X = Vector((1.0, 0.0, 0.0))  # axe latéral : rotation + = pointe vers l'arrière pour un os vers le bas
AX_Y = Vector((0.0, 1.0, 0.0))
AX_Z = Vector((0.0, 0.0, 1.0))

PREFIX = "mixamorig:"
FINGERS = ("Index", "Middle", "Ring", "Pinky")


def smooth(u: float) -> float:
    u = min(max(u, 0.0), 1.0)
    return u * u * (3.0 - 2.0 * u)


def lerp(a, b, u):
    return a + (b - a) * u


class Rig:
    def __init__(self, arm_obj, fps=30):
        self.arm = arm_obj
        # Les clips sont calculés à 30 i/s : une scène à 24 i/s les allongeait de 25 % à l'export.
        scene = bpy.context.scene
        scene.render.fps = fps
        scene.render.fps_base = 1.0
        for p in arm_obj.pose.bones:
            p.rotation_mode = "QUATERNION"
        self._prev_q = {}

    # -- accès -------------------------------------------------------------
    def pb(self, name):
        pose = self.arm.pose.bones
        return pose[name] if name in pose else pose[PREFIX + name]

    def rest(self, name) -> Matrix:
        return self.pb(name).bone.matrix_local.copy()

    def rest_head(self, name) -> Vector:
        return self.pb(name).bone.head_local.copy()

    def length(self, name) -> float:
        return self.pb(name).bone.length

    def update(self):
        bpy.context.view_layer.update()

    def reset(self):
        for p in self.arm.pose.bones:
            p.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
            p.location = (0.0, 0.0, 0.0)
            p.scale = (1.0, 1.0, 1.0)

    # -- cinématique directe ---------------------------------------------------
    def rot(self, name, axis, deg):
        """Rotation autour d'un axe de l'espace armature, dans le repère de repos de l'os
        (s'ajoute aux rotations déjà posées sur cet os ; les enfants suivent)."""
        if abs(deg) < 1e-6:
            return
        p = self.pb(name)
        m = p.bone.matrix_local.to_3x3()
        q_arm = Quaternion(Vector(axis).normalized(), math.radians(deg))
        q_loc = (m.inverted() @ q_arm.to_matrix() @ m).to_quaternion()
        p.rotation_quaternion = q_loc @ p.rotation_quaternion

    def local_rot(self, name, axis, deg):
        """Rotation autour d'un axe LOCAL de l'os (doigts)."""
        p = self.pb(name)
        p.rotation_quaternion = Quaternion(Vector(axis), math.radians(deg)) @ p.rotation_quaternion

    def hips_offset(self, v):
        p = self.pb("Hips")
        m = p.bone.matrix_local.to_3x3()
        p.location = m.inverted() @ Vector(v)

    # -- orientation absolue / IK ------------------------------------------------
    def posed(self, name) -> Matrix:
        return self.pb(name).matrix.copy()

    def set_matrix(self, name, mat: Matrix):
        self.update()
        self.pb(name).matrix = mat
        self.update()

    def aim(self, name, direction):
        """Oriente l'axe Y de l'os vers `direction` (rotation minimale depuis sa pose actuelle)."""
        self.update()
        p = self.pb(name)
        cur = p.matrix.copy()
        q = cur.to_3x3().col[1].normalized().rotation_difference(Vector(direction).normalized())
        new = (q.to_matrix() @ cur.to_3x3()).to_4x4()
        new.translation = cur.translation
        self.set_matrix(name, new)

    def orient(self, name, y_dir, x_dir):
        """Orientation absolue : Y de l'os = y_dir, X = x_dir (orthogonalisé)."""
        self.update()
        p = self.pb(name)
        y = Vector(y_dir).normalized()
        x = Vector(x_dir)
        x = (x - y * x.dot(y)).normalized()
        z = x.cross(y)
        m = Matrix((x, y, z)).transposed().to_4x4()
        m.translation = p.matrix.translation
        self.set_matrix(name, m)

    def ik2(self, upper, lower, target, pole) -> float:
        """IK deux os (épaule/hanche -> coude/genou -> poignet/cheville).
        Renvoie l'erreur de portée (0 si la cible est atteinte)."""
        self.update()
        a = self.length(upper)
        b = self.length(lower)
        s = self.posed(upper).translation
        t = Vector(target)
        d = t - s
        dist = d.length
        reach = (a + b) * 0.999
        err = max(0.0, dist - reach)
        dist = min(max(dist, abs(a - b) * 1.001 + 1e-4), reach)
        dn = d.normalized()
        pole_v = Vector(pole) - s
        perp = pole_v - dn * pole_v.dot(dn)
        if perp.length < 1e-6:
            perp = FWD.copy()
        perp.normalize()
        cos_a = (a * a + dist * dist - b * b) / (2.0 * a * dist)
        ang = math.acos(min(max(cos_a, -1.0), 1.0))
        up_dir = dn * math.cos(ang) + perp * math.sin(ang)
        elbow = s + up_dir * a
        self.aim(upper, up_dir)
        self.aim(lower, (s + dn * dist) - elbow)
        return err

    def spread_twist(self, fore, hand, share=0.6):
        """Reporte `share` de la torsion main/avant-bras (autour de l'axe de l'avant-bras) sur
        l'avant-bras, en gardant l'orientation finale de la main : sans os de torsion (rig
        Mixamo), toute la rotation au poignet le pince (« papillote »)."""
        self.update()
        f = self.posed(fore)
        h = self.posed(hand)
        axis = f.to_3x3().col[1].normalized()

        def flat(v):
            v = v - axis * v.dot(axis)
            return v.normalized() if v.length > 1e-6 else None

        fx = flat(f.to_3x3().col[0])
        hx = flat(h.to_3x3().col[0])
        if fx is None or hx is None:
            return
        ang = math.atan2(axis.dot(fx.cross(hx)), fx.dot(hx))
        # Continuité d'une image à l'autre : atan2 repasse de +180° à -180°, ce qui faisait
        # tourner l'avant-bras de ~145° d'un coup (bras qui « part », arme en travers 1 image).
        memo = self.__dict__.setdefault("_twist_prev", {})
        prev = memo.get(fore)
        if prev is not None:
            while ang - prev > math.pi:
                ang -= 2.0 * math.pi
            while ang - prev < -math.pi:
                ang += 2.0 * math.pi
        memo[fore] = ang
        rot = Matrix.Rotation(ang * share, 3, axis)
        nf = (rot @ f.to_3x3()).to_4x4()
        nf.translation = f.translation
        self.set_matrix(fore, nf)
        nh = h.copy()
        nh.translation = self.posed(hand).translation
        self.set_matrix(hand, nh)

    # -- doigts -------------------------------------------------------------
    def curl(self, side, amount_deg, thumb_deg=0.0, index_deg=None):
        """Referme les doigts (côté 'Left'/'Right'). Paume droite = +Z local, gauche = -Z."""
        sign = 1.0 if side == "Right" else -1.0
        for f in FINGERS:
            deg = amount_deg if (f != "Index" or index_deg is None) else index_deg
            for i in (1, 2, 3):
                n = f"{side}Hand{f}{i}"
                if PREFIX + n in self.arm.pose.bones:
                    self.local_rot(n, AX_X, sign * deg * (0.8 if i == 1 else 1.0))
        if thumb_deg:
            for i in (1, 2, 3):
                n = f"{side}HandThumb{i}"
                if PREFIX + n in self.arm.pose.bones:
                    self.local_rot(n, self._thumb_axis(side, n), thumb_deg * (0.6 if i == 1 else 1.0))

    def _thumb_axis(self, side, name):
        """Axe local qui replie ce segment de pouce vers la paume (base du majeur).
        Les os du pouce Mixamo n'ont pas l'orientation des autres doigts : l'axe X
        des doigts le faisait se dresser (« pouce levé »)."""
        cache = self.__dict__.setdefault("_thumb_axes", {})
        if name in cache:
            return cache[name]
        bone = self.pb(name).bone
        target = self.pb(f"{side}HandMiddle1").bone.head_local
        m = bone.matrix_local.to_3x3()
        best, best_d = AX_X, float("inf")
        for axis in (Vector((1, 0, 0)), Vector((-1, 0, 0)), Vector((0, 0, 1)), Vector((0, 0, -1))):
            q = Quaternion(axis, math.radians(45.0))
            tip = bone.head_local + m @ (q @ Vector((0.0, bone.length, 0.0)))
            d = (tip - target).length
            if d < best_d:
                best, best_d = axis, d
        cache[name] = best
        return best

    # -- clés ------------------------------------------------------------------
    def key(self, frame: int, with_hips_loc=True):
        for p in self.arm.pose.bones:
            q = p.rotation_quaternion.copy()
            prev = self._prev_q.get(p.name)
            if prev is not None and prev.dot(q) < 0.0:
                q.negate()
                p.rotation_quaternion = q
            self._prev_q[p.name] = q
            p.keyframe_insert("rotation_quaternion", frame=frame)
        if with_hips_loc:
            self.pb("Hips").keyframe_insert("location", frame=frame)

    def new_action(self, name: str):
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        if self.arm.animation_data is None:
            self.arm.animation_data_create()
        self.arm.animation_data.action = act
        self._prev_q = {}
        self._twist_prev = {}
        return act
