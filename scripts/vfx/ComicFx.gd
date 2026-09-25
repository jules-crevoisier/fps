## ComicFx.gd
## Bibliothèque VFX partagée (tâche ART-40, STYLE_BIBLE.md §9.1/§9.3) : palette
## fermée, réglages "sur deux"/budget (docs/style/tokens.json "vfx", mêmes
## valeurs recopiées à la main — comme Cartoon.INK/PAPER/... — puisque
## `tools/style/gen_style_tokens.py` ne générait, avant cette tâche, que la
## section "maps" de StyleTokens.gd), et des FABRIQUES DE SPECS pures (aucun
## Node) + UNE fonction qui les instancie en `GPUParticles3D` (`spawn_from_spec`,
## seule partie non pure de ce fichier — voir tests/vfx/test_comic_fx.gd pour
## ce qui est réellement testé, même principe que ViewModel.AnimState : la
## logique vit dans des données/fonctions pures, testables sans arbre de
## scène ; seule la construction de nœuds ne l'est pas, comme
## ViewModel._spawn_muzzle_flash()).
##
## Portée RÉELLE de cette tâche (voir aussi ImpactFx.gd) : Weapon.gd (GF-06,
## hors périmètre de cette tâche) ne transmet à `ImpactFx.spawn()` que
## `pos`/`normal` — jamais le collider touché ni sa matière. Cette bibliothèque
## ne peut donc construire QUE les effets du §9.3 qui ne dépendent pas de la
## matière de la surface : "Monde, générique" (poussière + éclats) et
## "Personnage" (rembourrage + confettis, + anneau CLONK/étoiles en cas de
## headshot cosmétique local). Les variantes par matière (étincelles métal,
## échardes bois, cratère sable/neige, fissures verre) exigeraient soit de
## modifier Weapon.gd pour qu'il transmette la matière touchée, soit une
## convention de groupe/metadata qu'aucun prop du jeu ne pose aujourd'hui —
## les deux sont hors des fichiers possédés par cette tâche : signalé dans le
## rendu de tâche (`blocked_on`), pas implémenté ici en code mort.
##
## §9.2 (flash de bouche, traceur, douille) est déjà livré ailleurs
## (ViewModel.gd/ThirdPersonWeapon.gd/Weapon.gd, GF-06) : hors des fichiers de
## cette tâche, non touché ici.
class_name ComicFx
extends RefCounted

## -- Palette VFX fermée (docs/style/tokens.json "color.vfx", STYLE_BIBLE.md
## §9.1 #3 : "toujours hors des bandes réservées" — aucune de ces teintes
## n'entre dans les bandes 300-355°/105-145° de StyleTokens.RESERVED_HUE_BANDS_DEG).
const FLASH_CORE := Color("fff3d6")
const FLASH_YELLOW := Color("ffd24a")
const FLASH_ORANGE := Color("f59a2e")
const SMOKE_1 := Color("ede4cf")
const SMOKE_2 := Color("cfc3ac")
const SMOKE_3 := Color("a99e8c")
const DUST := Color("e6d5b8")
const SPARK := Color("ffc24a")
const HEAL_GEL := Color("9fd8c8")
const STUFFING := Color("f4ede1")
const WHITEOUT := Color("fff8ec")
const TRACER := Color("fff3d6")
const SCORCH := Color("3a2e26")
const BRASS := Color("d9a21b")
## Jeton `game.headshot` (docs/style/tokens.json "color") : anneau CLONK et
## étoiles de tête (§9.3 "Personnage (tête)").
const HEADSHOT_ORANGE := Color("f28a1e")

## -- Réglages partagés (docs/style/tokens.json "vfx") ------------------------
## "Animé sur deux" (§9.1 #2) : 12 images/s, jamais une interpolation continue.
const FRAME_RATE_SHAPES := 12.0
## "Un contour d'encre de 2 px" (§9.1 #1) — synchronisé explicitement vers
## fx_flat.gdshader `outline_width_px` par `shape_material()` (comme
## `Cartoon.INK` l'est vers `outline_color`) : la mesure en pixels écran
## réels se fait dans le shader via `fwidth(d)`, voir sa docstring.
const OUTLINE_PX := 2.0
## Budget §9.1 #6 : "≤ 64 particules par effet, ≤ 600 à l'écran". Le plafond
## PAR EFFET est appliqué ici (`clamp_particle_count`, `_burst_spec`) ; le
## plafond GLOBAL À L'ÉCRAN n'a pas de registre central dans cette tâche (rien
## d'existant à étendre sans sortir des fichiers possédés) — chaque effet
## d'ImpactFx est un `one_shot` court (≤ 0.6 s) qui se libère seul
## (`finished.connect(queue_free)`), ce qui borne le nombre concurrent dans la
## pratique sans compteur dédié.
const MAX_PARTICLES_PER_EFFECT := 64
const MAX_PARTICLES_ON_SCREEN := 600

## "Jamais de rouge sang" (§9.3, CHK-45 ; docs/style/tokens.json "no_blood") —
## documentaire ici : le style_check.py du dépôt laisse CHK-45 "non mesuré"
## exprès ("risque de faux positifs sur les teintes peau/cuir légitimes" — un
## vrai lint OKLCH sortirait de cette tâche). La garantie tenue ICI est plus
## simple et vérifiable par lecture/test : `character_hit_specs()` ne
## construit jamais que `STUFFING` (corps), `agent_key_color` (confettis) et
## `HEADSHOT_ORANGE` (tête) — aucune autre couleur de base, jamais dérivée
## d'un rouge.
const NO_BLOOD_FORBID_HUE_DEG := Vector2(10.0, 40.0)
const NO_BLOOD_FORBID_CHROMA_ABOVE := 0.12
const NO_BLOOD_FORBID_LIGHTNESS_BELOW := 0.55

const _SHADER := preload("res://assets/shaders/fx_flat.gdshader")

## Primitives de fx_flat.gdshader — valeurs synchronisées À LA MAIN avec
## `shape_kind` du shader (un .gdshader ne peut pas lire un enum GDScript).
enum Shape { DISC = 0, STREAK = 1, STAR = 2, RECT = 3, RING = 4 }

# ==========================================================================
#  PUR — testable sans Node (tests/vfx/test_comic_fx.gd)
# ==========================================================================

## Quantifie `t` (secondes écoulées) au pas "sur deux" (STYLE_BIBLE.md §9.1
## #2, `FRAME_RATE_SHAPES` = 12 i/s) : deux instants dans la même fenêtre de
## 1/12 s renvoient la MÊME valeur — une pose qui "tient" au lieu d'interpoler
## en continu, comme un dessin animé classique plutôt qu'un tween lissé.
## Référence pure de ce pas (couverte par tests/vfx/test_comic_fx.gd) : pour
## les effets réels, tous construits en `GPUParticles3D` (`spawn_from_spec`),
## le MÊME quantum est posé nativement par le nœud lui-même (`fixed_fps` =
## `FRAME_RATE_SHAPES`, `interpolate = false`, Godot docs classe
## GPUParticles3D — "fixed_fps fixes the rendering frame rate ... without
## slowing down simulation", "interpolate ... smooth[s] movement when
## fixed_fps is lower than screen refresh rate") plutôt que d'être recalculée
## à la main ici : demander à GPUParticles3D de tenir la pose est la façon
## idiomatique Godot d'obtenir exactement ce que cette fonction modélise, sans
## réimplémenter un minuteur par-dessus sa simulation GPU.
static func stepped_time(t: float) -> float:
	return floor(t * FRAME_RATE_SHAPES) / FRAME_RATE_SHAPES

## Budget §9.1 #6 ("≤ 64 particules par effet") appliqué une bonne fois pour
## toutes : jamais un appelant silencieusement ignoré, toujours recadré.
static func clamp_particle_count(n: int) -> int:
	return clampi(n, 1, MAX_PARTICLES_PER_EFFECT)

## Matériau plat réutilisable (fx_flat.gdshader) pour UNE forme/couleur.
## `billboard` reste à `false` pour tout usage sous `GPUParticles3D` — voir
## `spawn_from_spec` : c'est alors `GPUParticles3D.transform_align` (natif à
## Godot, appliqué avant que le shader ne voie quoi que ce soit) qui oriente
## la particule vers la caméra ; le billboard MAISON du shader ne sert qu'à un
## usage hors particules (aucun dans cette tâche aujourd'hui, gardé pour un
## futur flash à instance unique — voir l'en-tête de fx_flat.gdshader).
static func shape_material(shape: Shape, color: Color, draw_outline: bool = true, billboard: bool = false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _SHADER
	m.set_shader_parameter("shape_kind", shape)
	m.set_shader_parameter("fill_color", color)
	m.set_shader_parameter("draw_outline", draw_outline)
	m.set_shader_parameter("outline_color", Cartoon.INK)
	m.set_shader_parameter("outline_width_px", OUTLINE_PX)
	m.set_shader_parameter("billboard", billboard)
	return m

## Spec pure d'un effet "un coup" (aucune référence à l'arbre de scène) :
## Dictionary à clés stables (shape/color/count/lifetime/spread_deg/speed_min/
## speed_max/scale_min/scale_max/gravity_y/size_m/draw_outline), consommée par
## `spawn_from_spec`. `count` est TOUJOURS recadré (`clamp_particle_count`).
static func _burst_spec(shape: Shape, color: Color, count: int, lifetime: float, spread_deg: float,
		speed_min: float, speed_max: float, scale_min: float, scale_max: float,
		gravity_y: float, size_m: float, draw_outline: bool = true) -> Dictionary:
	return {
		"shape": shape,
		"color": color,
		"count": clamp_particle_count(count),
		"lifetime": lifetime,
		"spread_deg": spread_deg,
		"speed_min": speed_min,
		"speed_max": speed_max,
		"scale_min": scale_min,
		"scale_max": scale_max,
		"gravity_y": gravity_y,
		"size_m": size_m,
		"draw_outline": draw_outline,
	}

## §9.3 "Monde, générique" : "bouffée de poussière crème (3 ronds, 250 ms)" —
## `color` permet de réutiliser la même fabrique pour un pouf teinté par le
## sol (ligne "Sable, neige"), même si rien dans les fichiers de cette tâche
## ne peut aujourd'hui distinguer cette matière (voir l'en-tête de fichier).
static func dust_puff_spec(color: Color = DUST) -> Dictionary:
	return _burst_spec(Shape.DISC, color, 3, 0.25, 55.0, 0.4, 1.0, 0.7, 1.1, -1.2, 0.05)

## §9.3 "Monde, générique" : "3 à 5 éclats biseautés (1-4 cm) de la couleur de
## la surface" — `color` est fourni par l'appelant (ImpactFx retombe sur une
## teinte neutre, faute de connaître la surface réelle, voir blocked_on).
static func debris_shards_spec(color: Color, count: int = 4) -> Dictionary:
	return _burst_spec(Shape.STREAK, color, count, 0.2, 40.0, 1.2, 2.4, 0.4, 0.8, -3.0, 0.035)

## §9.3 "Personnage" : rembourrage + confettis couleur-clé de l'agent touché,
## jamais de rouge sang (CHK-45) — la couleur de base du corps est TOUJOURS
## `STUFFING`, jamais dérivée de `agent_key_color`. En cas de headshot
## cosmétique local (ImpactFx.is_headshot_height) : anneau CLONK orange
## (Ø0,6 m, 120 ms, sans contour — "lueur", §9.1 #1 exception) + 2 étoiles.
static func character_hit_specs(agent_key_color: Color, headshot: bool = false) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	specs.append(_burst_spec(Shape.DISC, STUFFING, 9, 0.4, 60.0, 0.5, 1.2, 0.7, 1.1, -1.5, 0.07))
	specs.append(_burst_spec(Shape.RECT, agent_key_color, 2, 0.6, 70.0, 1.0, 2.0, 0.5, 0.9, -2.2, 0.04))
	if headshot:
		specs.append(_burst_spec(Shape.RING, HEADSHOT_ORANGE, 1, 0.12, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.8, false))
		specs.append(_burst_spec(Shape.STAR, HEADSHOT_ORANGE, 2, 0.3, 50.0, 0.3, 0.6, 0.5, 0.8, -0.3, 0.05))
	return specs

# ==========================================================================
#  IMPUR — construit réellement les nœuds (non testé, comme
#  ViewModel._spawn_muzzle_flash)
# ==========================================================================

## Base orthonormée dont l'axe Z local pointe selon `n` — copie volontaire de
## `ImpactFx.basis_for_normal` (même formule) plutôt qu'une dépendance
## croisée entre les deux classes pour une fonction de 6 lignes.
static func _orient_to_normal(n: Vector3) -> Basis:
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.999 else Vector3.RIGHT
	var x := up.cross(n)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT.cross(n)
	x = x.normalized()
	var y := n.cross(x).normalized()
	return Basis(x, y, n)

## Instancie `spec` (voir les fabriques ci-dessus) en un `GPUParticles3D` "un
## coup" attaché à `parent`, posé à `pos` orienté selon `normal` — `STREAK`
## s'aligne sur sa vélocité (`Z_BILLBOARD_Y_TO_VELOCITY`, "traits de vitesse"),
## les autres formes billboardent à plat (`Z_BILLBOARD`), toutes deux NATIVES
## à Godot (§9.1 #6 : "GPUParticles3D avec des quads maillés"). Se libère
## seul à la fin (`finished.connect(queue_free)`, jamais un timer détaché).
##
## "Sur deux" (§9.1 #2, `FRAME_RATE_SHAPES`) posé ICI, sur le nœud
## réellement instancié — `fixed_fps` fige la simulation à 12 i/s et
## `interpolate = false` empêche Godot de lisser le rendu entre deux pas fixes
## (déf. moteur : `fixed_fps` = 30, `interpolate` = true — sans ces deux
## lignes les particules bougeraient en continu au framerate réel, jamais par
## pose tenue). Voir `stepped_time()` pour la même quantification, exprimée en
## pur GDScript et vérifiée par test.
static func spawn_from_spec(parent: Node, pos: Vector3, normal: Vector3, spec: Dictionary) -> GPUParticles3D:
	if parent == null:
		return null
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var shape: int = spec.get("shape", Shape.DISC)
	var gp := GPUParticles3D.new()
	gp.amount = clamp_particle_count(int(spec.get("count", 1)))
	gp.one_shot = true
	gp.explosiveness = 1.0
	gp.lifetime = float(spec.get("lifetime", 0.3))
	gp.fixed_fps = int(FRAME_RATE_SHAPES)
	gp.interpolate = false
	gp.local_coords = false
	gp.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY if shape == Shape.STREAK else GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE * float(spec.get("size_m", 0.06))
	gp.draw_pass_1 = qm
	gp.material_override = shape_material(shape, spec.get("color", Color.WHITE), spec.get("draw_outline", true), false)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.0, 1.0)
	pm.spread = float(spec.get("spread_deg", 45.0))
	pm.initial_velocity_min = float(spec.get("speed_min", 0.5))
	pm.initial_velocity_max = float(spec.get("speed_max", 1.0))
	pm.gravity = Vector3(0.0, float(spec.get("gravity_y", -1.0)), 0.0)
	pm.scale_min = float(spec.get("scale_min", 0.8))
	pm.scale_max = float(spec.get("scale_max", 1.2))
	gp.process_material = pm
	parent.add_child(gp)
	gp.global_transform = Transform3D(_orient_to_normal(n), pos)
	gp.emitting = true
	gp.finished.connect(gp.queue_free)
	return gp
