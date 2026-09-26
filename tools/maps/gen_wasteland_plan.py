"""Génère data/maps/wasteland_plan.json (v6) — moitié ouest 'W' + centre 'C'.

Reprend meta/metrics/levels/mirror/materials du JSON existant (métriques de jeu
inchangées) et réécrit bornes, volumes, repères, couloirs, régions de vue, callouts.
"""
import json
from pathlib import Path

ROOT = Path(r"C:/Users/srko/Desktop/fps")
PLAN = ROOT / "data/maps/wasteland_plan.json"
old = json.loads((Path(__file__).parent / "wasteland_plan_v5.json").read_text(encoding="utf-8"))

V = []


def add(**kw):
    V.append(kw)
    return kw


def box(id_, kind, half, x, z, y, label, label_e=None, **kw):
    d = dict(id=id_, kind=kind, half=half, x=[float(x[0]), float(x[1])], z=[float(z[0]), float(z[1])],
             y=[float(y[0]), float(y[1])], label=label)
    if label_e:
        d["label_e"] = label_e
    d.update(kw)
    return add(**d)


def door(side, floor=0, offset=0.0, type_="M"):
    return {"side": side, "floor": floor, "offset": float(offset), "type": type_}


def win(side, floor=0, offset=0.0):
    return {"side": side, "floor": floor, "offset": float(offset)}


def fence(id_, half, a, b, h, cls, label, y=0.0, t=0.2, label_e=None):
    d = dict(id=id_, kind="fence", **{"class": cls}, half=half, **{"from": [float(a[0]), float(a[1])]},
             to=[float(b[0]), float(b[1])], y=float(y), h=float(h), t=float(t), label=label)
    if label_e:
        d["label_e"] = label_e
    return add(**d)


def seg3(id_, kind, half, a, b, w, label):
    return add(id=id_, kind=kind, half=half, **{"from": [float(v) for v in a]}, to=[float(v) for v in b],
               w=float(w), label=label)


def cover(id_, cls, half, x, z, label, label_e=None, y0=0.0):
    h = {"C1": 1.0, "C2": 1.4, "C3": 2.2}[cls]
    return box(id_, "cover", half, x, z, (y0, y0 + h), label, label_e, **{"class": cls})


UP = 3.2          # étage
GAL = (2.95, 3.2)  # dalle de balcon / galerie / passerelle
RAMPS = {          # entailles de rampe canyon (moitié ouest) : x0, x1 ; haut z=7 (y 0) -> bas z=13 (y -2)
    "W1": (-42.0, -37.5, "Rampe Cour"),       # sortie sud de l'apparition
    "W2": (-26.25, -21.75, "Rampe Ruelle"),     # ruelle arrière -> carrière
    "W3": (-10.25, -5.75, "Rampe Place"),       # place -> carrière
}
RZ0, RZ1 = 7.0, 13.0

# ------------------------------------------------------------------ sol et limites
box("G_PlateauW", "ground", "W", (-42, 0), (-25, RZ0), (-2, 0), "Plateau ouest", "Plateau est")
rim_x = [(-37.5, -26.25), (-21.75, -10.25), (-5.75, 0)]
for i, (a, b) in enumerate(rim_x, 1):
    box(f"G_BordW{i}", "ground", "W", (a, b), (RZ0, RZ1), (-2, 0), "Bord de carriere", "Bord de carriere")
for k, (a, b, _) in RAMPS.items():
    box(f"G_Entaille{k}", "ground", "W", (a, b), (RZ0, RZ1), (-4, -2), "Fond d'entaille", "Fond d'entaille")
box("G_Carriere", "ground", "C", (-42, 42), (RZ1, 25), (-4, -2), "Carriere (-2 m)")
box("CliffN", "boundary", "C", (-42, 42), (-26, -25), (0, 6), "Falaise nord")
box("CliffS", "boundary", "C", (-42, 42), (25, 26), (-2, 4), "Paroi sud")
box("CliffW", "boundary", "W", (-43, -42), (-25, 25), (-2, 6), "Falaise ouest", "Falaise est")

# ------------------------------------------------------------------ rangée nord (Grand-Rue)
box("EcurieW", "building", "W", (-42, -30), (-25, -13), (0, 3.6), "Ecurie FUEL", "Ecurie GAS",
    floors=1, stair_side="N", roof={"pitch_deg": 27.0},
    doors=[door("S", 0, 2.0, "L"), door("E", 0, 2.5, "L")],
    windows=[win("E", 0, -1.0), win("S", 0, -3.0)])
box("HotelW", "building", "W", (-30, -19), (-25, -18), (0, 6.4), "Hotel", "Pension",
    floors=2, stair_side="N", pp="PP1",
    doors=[door("S", 0, -2.5, "M"), door("E", 0, 1.5, "M"), door("S", 1, 2.5, "M")],
    windows=[win("S", 0, 2.5), win("S", 1, -2.5), win("E", 1, -1.5)])
box("MagasinW", "building", "W", (-19, -6), (-25, -18), (0, 6.4), "Magasin", "Epicerie",
    floors=2, stair_side="N",
    doors=[door("S", 0, -1.5, "L"), door("W", 0, 1.5, "M"), door("E", 0, 1.5, "M"), door("S", 1, 3.5, "M")],
    windows=[win("S", 0, 3.5), win("S", 1, -3.0), win("S", 1, 0.5)])
box("BanqueC", "building", "C", (-6, 6), (-25, -10), (0, 6.4), "Banque",
    floors=2, stair_side="N", pp="PP5",
    doors=[door("W", 0, -2.5, "M"), door("E", 0, -2.5, "M"),       # vers Magasin / Epicerie
           door("W", 0, 3.5, "M"), door("E", 0, 3.5, "M"),         # rue ouest / rue est
           door("S", 0, 0.0, "L"),                                  # place
           door("W", 1, 0.75, "M"), door("E", 1, 0.75, "M")],      # galeries
    windows=[win("S", 1, -3.5), win("S", 1, 3.5), win("W", 1, 5.0), win("E", 1, 5.0)])
box("CoffreC", "wall", "C", (-2, 2), (-16, -13), (0, 3.2), "Coffre (bloque l'axe des portes)")
box("GalerieW", "slab", "W", (-30, -6), (-18, -15.5), GAL, "Galerie", "Galerie", solid_below=False)
fence("GardeCorpsGalerieW1", "W", (-30, -15.5), (-20.5, -15.5), 1.0, "rail", "Garde-corps galerie", y=UP, t=0.05)
fence("GardeCorpsGalerieW2", "W", (-18, -15.5), (-12, -15.5), 1.0, "rail", "Garde-corps galerie", y=UP, t=0.05)
fence("GardeCorpsGalerieW3", "W", (-12, -15.5), (-6, -15.5), 1.0, "rail", "Garde-corps galerie", y=UP, t=0.05)
box("PasserelleW", "slab", "W", (-20.5, -18), (-15.5, -8), GAL, "Passerelle", "Passerelle", solid_below=False)
fence("GardeCorpsPasserelleW1", "W", (-20.5, -15.5), (-20.5, -8), 1.0, "rail", "Garde-corps passerelle", y=UP, t=0.05)
fence("GardeCorpsPasserelleW2", "W", (-18, -15.5), (-18, -8), 1.0, "rail", "Garde-corps passerelle", y=UP, t=0.05)

# ------------------------------------------------------------------ bande centrale (Saloon + Place)
box("SaloonW", "building", "W", (-26, -14), (-8, 4), (0, 6.4), "Saloon FUEL", "Saloon GAS",
    floors=2, stair_side="S", pp="PP3",
    doors=[door("W", 0, 4.5, "L"), door("N", 0, 3.5, "M"), door("E", 0, 0.0, "L"),
           door("N", 1, 1.75, "M"), door("E", 1, -2.0, "L")],
    windows=[win("E", 1, 3.5), win("S", 1, -3.0), win("S", 1, 3.0), win("W", 1, 2.0), win("N", 1, -3.0)])
box("BalconSaloonW", "slab", "W", (-14, -11.5), (-8, 4), GAL, "Balcon du Saloon", "Balcon du Saloon",
    solid_below=False)
fence("GardeCorpsBalconW1", "W", (-11.5, -8), (-11.5, -2), 1.0, "rail", "Garde-corps balcon", y=UP, t=0.05)
fence("GardeCorpsBalconW3", "W", (-11.5, -2), (-11.5, 4), 1.0, "rail", "Garde-corps balcon", y=UP, t=0.05)
fence("GardeCorpsBalconW2", "W", (-14, 4), (-11.5, 4), 1.0, "rail", "Garde-corps balcon", y=UP, t=0.05)
seg3("EscalierBalconW", "stairs", "W", (-12.75, 0, -13), (-12.75, UP, -8), 2.5, "Escalier du balcon (rue)")

box("WagonC", "building", "C", (-1.5, 1.5), (-4.5, 4.5), (0, 3.4), "Wagon (traversant N-S)",
    floors=1, stair_side="W", roof={"pitch_deg": 24.0}, pp="PP6",
    doors=[door("N", 0, 0.0, "M"), door("S", 0, 0.0, "M")], windows=[])
box("PompeC", "solid", "C", (-2, 2), (7.5, 13), (0, 3.0), "Pompe (socle du chateau d'eau)")
box("ChateauPiedNW", "landmark", "W", (-1.9, -1.5), (7.6, 8.0), (3.0, 8.0), "Pied NO", "Pied NE")
box("ChateauPiedSW", "landmark", "W", (-1.9, -1.5), (10.1, 10.5), (3.0, 8.0), "Pied SO", "Pied SE")
box("ChateauCuveC", "landmark", "C", (-2.2, 2.2), (7.5, 10.5), (8.0, 12.0), "Cuve du chateau d'eau")

cover("AbreuvoirPlaceW", "C1", "W", (-10, -8), (-5, -4), "Abreuvoir place")
cover("CaissesBanqueW", "C3", "W", (-6, -3.5), (-10, -7.5), "Caisses Banque")
box("RemiseW", "building", "W", (-18, -14), (4, 13), (0, 3.4), "Remise", "Remise",
    floors=1, stair_side="N", roof={"pitch_deg": 27.0},
    doors=[door("W", 0, -2.5, "M"), door("E", 0, 2.0, "M")], windows=[win("S", 0, 0.0)])
cover("TonneauxPlaceW", "C2", "W", (-9, -7.5), (0, 1.5), "Tonneaux place")

# ------------------------------------------------------------------ rue : couverts
cover("CharretteRueW", "C3", "W", (-26, -23), (-13.5, -11.5), "Charrette rue")
cover("CiterneW", "C3", "W", (-34, -31), (-10, -7), "Citerne FUEL", "Citerne GAS")

# ------------------------------------------------------------------ cour d'apparition
cover("CaisseCourW", "C2", "W", (-33, -31.5), (0, 2), "Caisses cour")

# ------------------------------------------------------------------ rebord : garde-fous et palissades
fence("PalissadeW2", "W", (-37.5, 12.9), (-26.25, 12.9), 2.2, "C3", "Palissade")
fence("ParapetW3", "W", (-21.75, 12.9), (-18, 12.9), 1.0, "C1", "Parapet")
fence("ParapetW5", "W", (-14, 12.9), (-10.25, 12.9), 1.0, "C1", "Parapet")
fence("ParapetW4", "W", (-5.75, 12.9), (-2, 12.9), 1.0, "C1", "Parapet")

# ------------------------------------------------------------------ rampes canyon
for k, (a, b, lab) in RAMPS.items():
    cx = (a + b) / 2
    seg3(f"Rampe{k}", "ramp", "W", (cx, 0, RZ0), (cx, -2, RZ1), b - a, lab)

# ------------------------------------------------------------------ carrière (-2 m)
for id_, (x0, x1), att, lab in [
        ("RocherS0W", (-6.5, -2.5), "S", "Aiguille du Gue"), ("RocherN1W", (-15.5, -11.5), "N", "Aiguille N1"),
        ("RocherS1W", (-24.5, -20.5), "S", "Aiguille S1"), ("RocherN2W", (-33.5, -29.5), "N", "Aiguille N2"),
        ("RocherS2W", (-42.0, -38.5), "S", "Aiguille S2")]:
    zz = (13.0, 19.5) if att == "N" else (18.5, 25.0)
    box(id_, "rock", "W", (x0, x1), zz, (-2, 1.8), lab, lab)

# ------------------------------------------------------------------ assemblage
new = {
    "schema": old["schema"],
    "meta": dict(old["meta"], version="v6-greybox", date="2026-09-26",
                 note=old["meta"]["note"] + " v6 : refonte (docs/maps/WASTELAND_DESIGN.md)."),
    "metrics": old["metrics"],
    "levels": old["levels"],
    "bounds": {"x": [-42.0, 42.0], "z": [-25.0, 25.0]},
    "mirror": old["mirror"],
    "materials": old["materials"],
    "volumes": V,
}

new["markers"] = {
    "team_spawns": [{"team": 0, "half": "W", "pos": [-41.0, 0.0, z], "look": [1.0, 0.0]} for z in (-9.0, -6.5, -4.0, -1.5)],
    "tdm_spawns": [{"half": "W", "pos": p, "pocket": k} for k, p in [
        ("cour", [-38.0, 0.0, -10.0]), ("cour", [-36.5, 0.0, 4.0]), ("cour", [-29.5, 0.0, 1.0]),
        ("cour", [-37.0, 0.0, -4.0]), ("ecurie", [-38.0, 0.0, -19.0]), ("ecurie", [-33.0, 0.0, -22.0]),
        ("hotel", [-27.0, 0.0, -21.5]), ("saloon", [-22.0, 0.0, -5.0]), ("ruelle", [-30.0, 0.0, 9.0]),
        ("carriere", [-35.5, -2.0, 15.0]), ("carriere", [-33.0, -2.0, 22.0]), ("magasin", [-15.0, 0.0, -22.0])]],
    "strong_positions": [
        {"id": "PP1", "half": "W", "mirror_id": "PP2", "pos": [-24.5, UP, -16.75],
         "counter": "rue (tir vers le haut), Banque etage, passerelle", "label": "Galerie Hotel/Magasin",
         "label_e": "Galerie Pension/Epicerie"},
        {"id": "PP3", "half": "W", "mirror_id": "PP4", "pos": [-12.75, UP, -2.0],
         "counter": "balcon adverse (23 m), Banque etage (fenetres S), place", "label": "Balcon Saloon FUEL",
         "label_e": "Balcon Saloon GAS"},
        {"id": "PP5", "half": "C", "pos": [0.0, UP, -12.0],
         "counter": "2 galeries (portes O1/E1), rampe interieure, balcons", "label": "Banque etage"},
        {"id": "PP6", "half": "C", "pos": [0.0, 0.0, -1.0], "counter": "2 portes N/S, contournement", "label": "Wagon"}],
    "fronts": [{"half": "W", "pos": [-7.5, 0.0, -9.0], "label": "bouche de rue (Banque)"},
               {"half": "W", "pos": [-3.5, 0.0, -7.0], "label": "place (bout N du wagon)"},
               {"half": "W", "pos": [-5.0, -2.0, 15.0], "label": "gue"}],
    "flip_line_x": 14.0,
}

new["lanes"] = [
    {"id": "grand_rue", "label": "1 - Grand-Rue", "range": "moyenne, demi-rue 24 m", "level": 0.0, "color": "#E0703A",
     "region": {"x": [-30.0, 30.0], "z": [-18.5, -8.0]},
     "widths": [{"what": "facade a facade (Hotel/Magasin -> Saloon)", "w": 10.0},
                {"what": "bouche de rue (escalier balcon -> Banque)", "w": 5.5},
                {"what": "coude de la cour (Ecurie -> Citerne -> Saloon)", "w": 3.0}],
     "route_w": [[-41.0, -6.5], [-35.0, -11.5], [-28.0, -15.0], [-10.0, -15.0], [-7.5, -7.0], [-3.0, -6.5], [0.0, -6.5]]},
    {"id": "place", "label": "2 - Place", "range": "courte-moyenne, 28 m", "level": 0.0, "color": "#2FA37A",
     "region": {"x": [-26.0, 26.0], "z": [-8.0, 13.0]},
     "widths": [{"what": "place facade a facade (Saloons)", "w": 28.0},
                {"what": "place : Banque -> chateau d'eau", "w": 16.5},
                {"what": "wagon -> Banque / -> pompe", "w": 4.5},
                {"what": "ruelle arriere (Saloon -> bord)", "w": 9.0}],
     "route_w": [[-41.0, -4.0], [-26.0, 2.5], [-22.0, -2.6], [-18.0, -2.6], [-14.0, -2.0], [-5.0, -4.0], [-2.5, -5.5], [0.0, -6.0]]},
    {"id": "carriere", "label": "3 - Carriere (-2 m)", "range": "moyenne, lacets de 5 m", "level": -2.0, "color": "#5A4FB0",
     "region": {"x": [-42.0, 42.0], "z": [13.0, 25.0]},
     "widths": [{"what": "paroi a paroi", "w": 12.0}, {"what": "rampes", "w": 4.5},
                {"what": "passage rocher / paroi (mini)", "w": 3.5}],
     "route_w": [[-41.0, -1.5], [-39.75, 4.0], [-39.75, 7.0], [-39.75, 13.0], [-38.0, 16.0], [-31.5, 22.0], [-22.5, 16.0],
                 [-13.5, 22.0], [-4.5, 16.0], [0.0, 16.0]]},
]

new["sight_regions"] = [
    {"id": "grand_rue", "level": 0.0, "x": [-30.0, 30.0], "z": [-18.0, -8.0], "cap": 60.0},
    {"id": "place", "level": 0.0, "x": [-26.0, 26.0], "z": [-10.0, 13.0], "cap": 30.0},
    {"id": "carriere", "level": -2.0, "x": [-42.0, 42.0], "z": [13.0, 25.0], "cap": 40.0},
]
new["plaza"] = {"x": [-14.0, 14.0], "z": [-7.5, 6.5], "centerpiece": "WagonC"}

new["callouts"] = [
    {"half": "C", "name": "Banque", "x": [-6.0, 6.0], "z": [-25.0, -10.0]},
    {"half": "C", "name": "Place", "x": [-14.0, 14.0], "z": [-7.5, 6.5]},
    {"half": "C", "name": "Wagon", "x": [-1.5, 1.5], "z": [-4.5, 4.5]},
    {"half": "C", "name": "Chateau d'eau", "x": [-2.0, 2.0], "z": [7.5, 13.0]},
    {"half": "C", "name": "Gue", "x": [-4.0, 4.0], "z": [13.0, 25.0]},
    {"half": "W", "name": "Cour FUEL", "name_e": "Cour GAS", "x": [-42.0, -26.0], "z": [-13.0, 13.0]},
    {"half": "W", "name": "Ecurie", "name_e": "Ecurie", "x": [-42.0, -30.0], "z": [-25.0, -13.0]},
    {"half": "W", "name": "Hotel", "name_e": "Pension", "x": [-30.0, -19.0], "z": [-25.0, -18.0]},
    {"half": "W", "name": "Magasin", "name_e": "Epicerie", "x": [-19.0, -6.0], "z": [-25.0, -18.0]},
    {"half": "W", "name": "Galerie FUEL", "name_e": "Galerie GAS", "x": [-30.0, -6.0], "z": [-18.0, -15.5]},
    {"half": "W", "name": "Passerelle", "name_e": "Passerelle", "x": [-20.5, -18.0], "z": [-15.5, -8.0]},
    {"half": "W", "name": "Rue FUEL", "name_e": "Rue GAS", "x": [-30.0, -6.0], "z": [-18.0, -8.0]},
    {"half": "W", "name": "Saloon FUEL", "name_e": "Saloon GAS", "x": [-26.0, -14.0], "z": [-8.0, 4.0]},
    {"half": "W", "name": "Balcon FUEL", "name_e": "Balcon GAS", "x": [-14.0, -11.5], "z": [-8.0, 4.0]},
    {"half": "W", "name": "Ruelle FUEL", "name_e": "Ruelle GAS", "x": [-26.0, -18.0], "z": [4.0, 13.0]},
    {"half": "W", "name": "Remise", "name_e": "Remise", "x": [-18.0, -14.0], "z": [4.0, 13.0]},
    {"half": "W", "name": "Carriere FUEL", "name_e": "Carriere GAS", "x": [-42.0, -4.0], "z": [13.0, 25.0]},
]

def c(v):
    return json.dumps(v, ensure_ascii=False)


def fmt_val(v, ind):
    pad = " " * ind
    if isinstance(v, list) and v and all(isinstance(e, dict) for e in v):
        return "[\n" + ",\n".join(pad + "  " + c(e) for e in v) + "\n" + pad + "]"
    if isinstance(v, dict) and ind <= 2:
        return "{\n" + ",\n".join(f'{pad}  "{k}": {fmt_val(x, ind + 2)}' for k, x in v.items()) + "\n" + pad + "}"
    return c(v)


text = "{\n" + ",\n".join(f'  "{k}": {fmt_val(v, 2)}' for k, v in new.items()) + "\n}\n"
assert json.loads(text) == new
PLAN.write_bytes(text.encode("utf-8"))  # LF, comme l'original
print("volumes W/C:", len(V))
