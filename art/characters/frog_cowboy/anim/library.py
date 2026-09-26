"""Construit tous les clips de la grenouille sur son armature (appelé par export_frog.py et preview.py)."""
from clips import GAITS, build_gait, build_idle
from extra import EXTRA
from rifle import REACH_LOG, add_weapon_grip, build_rifle
from rigkit import Rig

LOOPS = ("Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd", "Jump",
         "Rifle_Idle", "Rifle_Aim_Down", "Rifle_Aim_Neutral", "Rifle_Aim_Up")


def build_library(arm_obj, only=None):
    add_weapon_grip(arm_obj)
    rig = Rig(arm_obj)
    names = ["Idle", "Crouch_Idle", *GAITS, *EXTRA]

    def want(n):
        return only is None or n in only

    if want("Idle"):
        build_idle(rig, "Idle")
    if want("Crouch_Idle"):
        build_idle(rig, "Crouch_Idle", crouch=1.0, duration=2.8)
    for g in GAITS:
        if want(g):
            build_gait(rig, g)
    for n, fn in EXTRA.items():
        if want(n):
            fn(rig)
    names += build_rifle(rig, only)
    rig.reset()
    arm_obj.animation_data.action = None
    for entry in REACH_LOG:
        print("REACH", entry)
    return [n for n in names if want(n)]
