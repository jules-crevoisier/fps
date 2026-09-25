## AbilityVfx.gd
## Bibliothèque VFX des 6 capacités SIGNATURE (tâche VFX-20, AGT-09,
## docs/AGENTS.md, docs/STYLE_BIBLE.md §9.6/§9.1) : braise de Faux départ
## (Vif), Tape-la-cloche (Choc), Piquet d'arpenteur (Vanne), Glu (Verrou),
## Baume du Palud (Roseau), Coup de dé (Guet — « révélation »). MÊME
## architecture que ComicFx.gd (tâche ART-40) : des FABRIQUES DE SPECS pures
## (Dictionary, aucun Node — testées sans arbre de scène) + des fonctions
## `spawn_*` qui les instancient réellement (impures, couvertes par un
## aller-retour d'intégration dans tests/vfx/test_ability_vfx.gd, même
## principe que ComicFx.spawn_from_spec/ImpactFx.gd). Réutilise directement
## `ComicFx.Shape`/`ComicFx.shape_material`/`ComicFx.spawn_from_spec`/
## `ComicFx.clamp_particle_count` plutôt que de redupliquer le pipeline
## GPUParticles3D + fx_flat.gdshader : AUCUN nouveau shader, AUCUNE nouvelle
## texture — les 5 primitives plates de fx_flat.gdshader (DISC/STREAK/STAR/
## RECT/RING) suffisent à chaque effet ci-dessous, exactement comme son
## en-tête le documente déjà (« assets/vfx/ reste vide »). C'est le point
## central du critère d'acceptation « jamais une sphère unie » : ces 5 formes
## sont TOUTES des quads plats (silhouette SDF en fragment()), donc un
## SphereMesh est structurellement impossible à produire depuis cette
## bibliothèque (voir test_no_spec_factory_ever_uses_a_sphere).
##
## Portée RÉELLE de cette tâche — ce qui n'est PAS fait ici (blocked_on du
## rendu) : les 6 fichiers `scripts/agents/abilities/{FauxDepart,BellCharge,
## Grapple,Glue,BalmZone}Ability.gd` (+ RevealAbility.gd pour Coup de dé) ne
## sont PAS dans les fichiers possédés par ce contrat — aucun ne peut être
## modifié ici. Les objets qu'ils posent déjà restent donc des primitives
## simples (ex. FauxDepartAbility._spawn_ember : SphereMesh, BalmZoneAbility.
## _spawn_zone : SphereMesh) : CE fichier ne les remplace pas, il fournit la
## bibliothèque d'effets peints prête à être appelée par ces capacités (même
## position/signature que le reel `tools/review/vfx_reel.gd` utilise pour les
## démontrer) — le câblage réel dans `activate_server`/`activate_local`
## revient à une tâche future qui possède ces fichiers (même schéma que
## ART-40 -> ImpactFx.gd, ou ART-42, non commencée à ce jour, pour la bulle de
## reveal/les gouttes de soin PARTAGÉES à toutes les capacités — cette tâche-ci
## ne couvre que les 6 signatures, voir tasks/backlog.yaml VFX-20/ART-42).
##
## `assets/vfx/abilities/` (fichier possédé par ce contrat) reste
## volontairement VIDE, pour la même raison que `assets/vfx/` sous ART-40
## (voir l'en-tête de fx_flat.gdshader) : aucun des 6 effets ci-dessous n'a
## besoin d'une texture peinte à la main — tous sont des SDF procédurales.
class_name AbilityVfx
extends RefCounted

# ==========================================================================
#  Timings (STYLE_BIBLE.md §9.6, docs/AGENTS.md, docs/style/tokens.json —
#  valeurs recopiées à la main, même convention que ComicFx.gd : voir son
#  en-tête pour la justification).
# ==========================================================================

## §9.6 "Ruée / Charge / Piquet" : "300 ms" — partagé par Tape-la-cloche
## (Choc) et Piquet d'arpenteur (Vanne, "Piquet" dans cette ligne du tableau).
const MOVEMENT_TRAIL_S := 0.3
## Écho "DING" de Tape-la-cloche : plus long qu'un simple CLONK de tête
## (§9.3, 0,12 s) pour se lire comme une vraie onde de choc, toujours "sur
## deux" (2-3 images à 12 i/s).
const BELL_DING_S := 0.18
## Braise (pose/retour) : bref grésillement, jamais figé plus de 350 ms.
const EMBER_BURST_S := 0.35
## Glu : le "floc" d'atterrissage de la plaque.
const GLUE_SPLAT_S := 0.3
## §9.6 "Soin" : "500 ms" — gouttes de gel montantes + « + » papier.
const BALM_DROPLET_S := 0.5
## docs/style/tokens.json "vfx.reveal_bubble.pop_ms" = 150 (copié à la main).
const DICE_POP_S := 0.15
## docs/AGENTS.md, Guet, Coup de dé : "lance un dé qui vole 0,5 s".
const DICE_FLIGHT_S := 0.5
## Corde du grappin : temps de "tension" avant de rester tendue le temps de
## la traction (GrappleAbility.pull_duration, 0,8 s — hors fichiers possédés,
## valeur non importée pour ne pas coupler les deux fichiers : voir spawn_piquet_arpenteur).
const GRAPPLE_ROPE_GROW_S := 0.12
## Braise posée : durée de vie par défaut du feu qui couve (FauxDepartAbility.
## EMBER_LIFETIME, 8 s — même remarque : constante indépendante, l'appelant
## passe la vraie valeur s'il en a une).
const EMBER_GLOW_LIFETIME_S := 8.0
## Bulles de Glu : par défaut, un aperçu court (le reel/les tests passent la
## vraie durée de la plaque quand ils l'ont).
const GLUE_BUBBLE_LIFETIME_S := 4.0

# ==========================================================================
#  PUR — fabriques de specs (Dictionary, clés compatibles ComicFx.spawn_from_spec :
#  shape/color/count/lifetime/spread_deg/speed_min/speed_max/scale_min/
#  scale_max/gravity_y/size_m/draw_outline), testables sans Node
#  (tests/vfx/test_ability_vfx.gd).
# ==========================================================================

## Copie volontaire de ComicFx._burst_spec (privée à son fichier) plutôt
## qu'une dépendance croisée pour 12 lignes — même motif déjà établi dans ce
## dépôt pour les petites fonctions utilitaires dupliquées entre fichiers
## possédés séparément (ex. GlueAbility.ground_hit vs StunTrapAbility.ground_hit,
## voir leurs docstrings).
static func _spec(shape: int, color: Color, count: int, lifetime: float, spread_deg: float,
		speed_min: float, speed_max: float, scale_min: float, scale_max: float,
		gravity_y: float, size_m: float, draw_outline: bool = true) -> Dictionary:
	return {
		"shape": shape,
		"color": color,
		"count": ComicFx.clamp_particle_count(count),
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

## §9.6 "Ruée / Charge / Piquet" : "3 bouffées de fumée rondes dans le
## sillage + 3 traits de vitesse encre", couleurs "crème + encre". Partagé
## par Tape-la-cloche (charge) et Piquet d'arpenteur (traction) — la ligne du
## tableau les regroupe explicitement.
static func movement_trail_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	specs.append(_spec(ComicFx.Shape.DISC, ComicFx.DUST, 3, MOVEMENT_TRAIL_S, 50.0, 0.6, 1.3, 0.6, 1.0, -0.8, 0.06))
	specs.append(_spec(ComicFx.Shape.STREAK, Cartoon.INK, 3, MOVEMENT_TRAIL_S, 22.0, 1.6, 2.6, 0.5, 0.9, -0.3, 0.03))
	return specs

## §9.6 "Ruée / Charge / Piquet" : "Charge : onde « DING » en anneau
## papier" — l'impact de Tape-la-cloche (victime touchée OU mur percuté).
## `size_m = 0.6`, jamais 1.2 (retour QA du 2026-09-25 : à 1.2 m l'anneau
## débordait du cadre du reel en gros plan, `tools/review/vfx_reel.gd`,
## rendu illisible — voir reports/vfx_reel/2026-09-25_vfx20/tape_la_cloche).
## 0.6 aligne cette onde sur le SEUL autre anneau d'impact du dépôt,
## `ComicFx.character_hit_specs` (l'anneau CLONK de headshot, "Ø0,6 m",
## ComicFx.gd ligne ~173) : assez grand pour se lire comme une onde de choc
## face aux étincelles/bouffées de quelques cm qui l'entourent, jamais assez
## pour sortir du cadre d'un gros plan de combat rapproché.
static func bell_ding_spec() -> Dictionary:
	return _spec(ComicFx.Shape.RING, Cartoon.PAPER, 1, BELL_DING_S, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.6)

## Braise de Faux départ : un grésillement bref, palette "Flash" (§9.1 #3 :
## cœur papier / jaune / orange), jamais une lueur ronde unie — une étoile de
## braise + une bouffée de fumée chaude qui l'accompagne.
static func ember_burst_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	specs.append(_spec(ComicFx.Shape.STAR, ComicFx.FLASH_ORANGE, 3, EMBER_BURST_S, 60.0, 0.5, 1.1, 0.4, 0.7, -0.6, 0.045))
	specs.append(_spec(ComicFx.Shape.DISC, ComicFx.DUST, 2, EMBER_BURST_S, 45.0, 0.3, 0.6, 0.5, 0.8, -0.5, 0.05))
	return specs

## Piquet d'arpenteur : le piquet mord le décor — étincelles métalliques
## (palette "Étincelles" §9.1 #3) + une bouffée de poussière à l'ancrage.
static func grapple_impact_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	specs.append(_spec(ComicFx.Shape.STAR, ComicFx.SPARK, 4, 0.15, 55.0, 1.0, 2.0, 0.35, 0.6, -1.0, 0.035))
	specs.append(ComicFx.dust_puff_spec())
	return specs

## Glu : le "floc" quand la plaque touche le sol — des gouttes anguleuses
## (RECT, "découpées au ciseau" §9.1 #1) dans la couleur DONNÉE (celle de la
## plaque posée par GlueAbility, jamais une couleur inventée ici) + de
## petites bulles rondes.
static func glue_splat_specs(color: Color) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	specs.append(_spec(ComicFx.Shape.RECT, color, 6, GLUE_SPLAT_S, 70.0, 0.8, 1.8, 0.4, 0.8, -1.4, 0.075))
	specs.append(_spec(ComicFx.Shape.DISC, color, 3, GLUE_SPLAT_S, 40.0, 0.3, 0.7, 0.35, 0.6, -0.6, 0.05))
	return specs

## Baume du Palud : "gouttes de gel #9FD8C8 montantes" (§9.6 "Soin") —
## `gravity_y` POSITIF (dérive vers le haut), à l'inverse des bursts qui
## retombent (poussière/éclats).
static func balm_droplet_spec() -> Dictionary:
	return _spec(ComicFx.Shape.DISC, ComicFx.HEAL_GEL, 4, BALM_DROPLET_S, 35.0, 0.25, 0.5, 0.5, 0.8, 0.6, 0.045)

## Coup de dé (Guet, capacité "révélation") : le pop d'atterrissage du dé —
## un éclat papier (RECT, comme un bristol qui retombe) + une étincelle
## (STAR, "20 naturel" qui accroche l'œil), 150 ms (tokens.json). Complète,
## sans la dupliquer, la bulle "!" déjà posée par
## AbilityController.net_show_markers (hors fichiers possédés ici).
static func dice_pop_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	specs.append(_spec(ComicFx.Shape.RECT, Cartoon.PAPER, 3, DICE_POP_S, 65.0, 0.6, 1.2, 0.4, 0.7, -0.8, 0.04))
	specs.append(_spec(ComicFx.Shape.STAR, ComicFx.SPARK, 2, DICE_POP_S, 40.0, 0.3, 0.6, 0.35, 0.55, -0.4, 0.035))
	return specs

# ==========================================================================
#  IMPUR — construit réellement les nœuds (non testé en pur, comme
#  ComicFx.spawn_from_spec), couvert par un aller-retour d'intégration dans
#  tests/vfx/test_ability_vfx.gd.
# ==========================================================================

## Instancie CHAQUE spec de `specs` à `pos`/`normal` via `ComicFx.spawn_from_spec`
## (jamais une réimplémentation du pipeline GPUParticles3D+fx_flat) — le point
## d'entrée commun à tous les bursts "un coup" ci-dessous. Retourne un
## tableau vide sans effet si `parent` est nul (même garde que
## DecalPool.spawn/ComicFx.spawn_from_spec).
static func spawn_specs(parent: Node, pos: Vector3, normal: Vector3, specs: Array[Dictionary]) -> Array[GPUParticles3D]:
	var out: Array[GPUParticles3D] = []
	if parent == null:
		return out
	for spec in specs:
		var gp := ComicFx.spawn_from_spec(parent, pos, normal, spec)
		if gp != null:
			out.append(gp)
	return out

## Construit un émetteur EN BOUCLE (contrairement à `ComicFx.spawn_from_spec`,
## toujours "un coup") : même matériau/quad (`ComicFx.shape_material`,
## budget `ComicFx.clamp_particle_count`) mais `one_shot = false`, pour les
## effets qui "couvent" pendant toute la durée de vie de l'objet posé (braise
## qui grésille, Glu qui goutte, flaque de Baume qui exhale du gel) — jamais
## un `get_tree().create_timer()` avec un lambda capturant `gp` (règle du
## projet) : le nettoyage passe par `connect(gp.queue_free)` (référence de
## méthode, pas une closure) quand `duration > 0.0`.
static func _spawn_looping(parent: Node, pos: Vector3, shape: int, color: Color, amount: int,
		lifetime: float, size_m: float, direction: Vector3, spread_deg: float,
		speed_min: float, speed_max: float, gravity_y: float, duration: float) -> GPUParticles3D:
	if parent == null:
		return null
	var gp := GPUParticles3D.new()
	gp.amount = ComicFx.clamp_particle_count(amount)
	gp.one_shot = false
	gp.explosiveness = 0.0
	gp.lifetime = lifetime
	gp.fixed_fps = int(ComicFx.FRAME_RATE_SHAPES)
	gp.interpolate = false
	gp.local_coords = false
	gp.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE * size_m
	gp.draw_pass_1 = qm
	gp.material_override = ComicFx.shape_material(shape, color, true, false)
	var pm := ParticleProcessMaterial.new()
	pm.direction = direction
	pm.spread = spread_deg
	pm.initial_velocity_min = speed_min
	pm.initial_velocity_max = speed_max
	pm.gravity = Vector3(0.0, gravity_y, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	gp.process_material = pm
	parent.add_child(gp)
	gp.global_position = pos
	gp.emitting = true
	if duration > 0.0 and parent.is_inside_tree():
		var t := parent.get_tree().create_timer(duration)
		t.timeout.connect(gp.queue_free)
	return gp

# -------------------------------------------------------- Faux départ (Vif) — braise

## Premier appui (pose de la braise) : grésillement bref à `pos`.
static func spawn_faux_depart_pose(parent: Node, pos: Vector3) -> Array[GPUParticles3D]:
	return spawn_specs(parent, pos, Vector3.UP, ember_burst_specs())

## Second appui (retour) : un grésillement au point de départ (la braise se
## consume) ET un au point d'arrivée (le joueur "pop" sur place) — jamais un
## simple fondu d'écran seul (déjà géré par FauxDepartAbility._teleport_back,
## hors fichiers possédés ici : cette fonction complète le cosmétique visible
## des AUTRES joueurs, qui ne voient pas le fondu d'écran du propriétaire).
static func spawn_faux_depart_return(parent: Node, from_pos: Vector3, to_pos: Vector3) -> Array[GPUParticles3D]:
	var out: Array[GPUParticles3D] = []
	out.append_array(spawn_specs(parent, from_pos, Vector3.UP, ember_burst_specs()))
	out.append_array(spawn_specs(parent, to_pos, Vector3.UP, ember_burst_specs()))
	return out

## Braise posée : couve en continu tant qu'elle existe (contraste avec le
## SphereMesh statique que pose FauxDepartAbility._spawn_ember, hors
## fichiers possédés — voir l'en-tête de fichier) : petites étoiles de flamme
## qui dérivent doucement vers le haut, "sur deux".
static func spawn_ember_glow(parent: Node, pos: Vector3, duration: float = EMBER_GLOW_LIFETIME_S) -> GPUParticles3D:
	return _spawn_looping(parent, pos, ComicFx.Shape.STAR, ComicFx.FLASH_ORANGE, 4, 0.6, 0.045,
		Vector3(0.0, 1.0, 0.0), 20.0, 0.15, 0.35, 0.15, duration)

# -------------------------------------------------------- Tape-la-cloche (Choc) — cloche

## Sillage de la charge (`origin` -> `impact_pos`, §9.6 movement_trail) +
## l'onde « DING » au point d'impact (victime touchée ou mur percuté).
static func spawn_tape_la_cloche(parent: Node, origin: Vector3, impact_pos: Vector3) -> Array[GPUParticles3D]:
	var out: Array[GPUParticles3D] = []
	var mid := origin.lerp(impact_pos, 0.5)
	out.append_array(spawn_specs(parent, mid, Vector3.UP, movement_trail_specs()))
	var dir := (impact_pos - origin)
	var facing := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.UP
	var ding := ComicFx.spawn_from_spec(parent, impact_pos, facing, bell_ding_spec())
	if ding != null:
		out.append(ding)
	return out

# -------------------------------------------------------- Piquet d'arpenteur (Vanne) — grappin

## Base orthonormée dont l'axe Y local pointe selon `dir` — le QuadMesh de la
## corde (`size.y` = longueur) s'étire alors exactement le long du segment
## origine -> ancrage, jamais en billboard (une corde tendue ne doit PAS
## tourner avec la caméra, contrairement aux particules de `spawn_specs`).
## Même famille de construction que `ComicFx._orient_to_normal`, mais alignée
## sur Y (élongation de STREAK, "capsule verticale" — voir fx_flat.gdshader)
## plutôt que sur Z (normale d'un décalque plaqué contre une surface).
static func _orient_along_y(dir: Vector3) -> Basis:
	var y := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.UP
	var reference := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.999 else Vector3.RIGHT
	var x := y.cross(reference)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

## Corde tendue (un seul quad STREAK, encre, billboard=false — jamais une
## réimplémentation en tube 3D) le long de `origin` -> `anchor_pos`, qui se
## tend en `GRAPPLE_ROPE_GROW_S` (tween porté par le nœud lui-même, jamais un
## `create_timer` avec lambda) puis se libère après `hold_s` ; + les
## étincelles d'ancrage (`grapple_impact_specs`). Retourne
## `{"rope": MeshInstance3D, "sparks": Array[GPUParticles3D]}` (vide/nul si
## `parent` est nul).
static func spawn_piquet_arpenteur(parent: Node, origin: Vector3, anchor_pos: Vector3, hold_s: float = 0.5) -> Dictionary:
	if parent == null:
		return {"rope": null, "sparks": []}
	var to_anchor := anchor_pos - origin
	var length := to_anchor.length()
	var mesh := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.03, maxf(length, 0.01))
	mesh.mesh = qm
	mesh.material_override = ComicFx.shape_material(ComicFx.Shape.STREAK, Cartoon.INK, true, false)
	parent.add_child(mesh)
	mesh.global_transform = Transform3D(_orient_along_y(to_anchor), origin.lerp(anchor_pos, 0.5))
	# 0.001, jamais 0.0 : annuler le facteur d'échelle annulerait aussi la
	# colonne Y de la base (direction perdue) — `basis.y` doit rester
	# colinéaire au segment origine->ancrage dès la création, pas seulement
	# une fois le tween écoulé (voir test_spawn_piquet_arpenteur_orients_...).
	mesh.scale.y = 0.001
	var tw := mesh.create_tween()
	tw.tween_property(mesh, "scale:y", 1.0, GRAPPLE_ROPE_GROW_S)
	if mesh.is_inside_tree():
		var t := mesh.get_tree().create_timer(GRAPPLE_ROPE_GROW_S + hold_s)
		t.timeout.connect(mesh.queue_free)
	var sparks := spawn_specs(parent, anchor_pos, -to_anchor.normalized() if length > 0.0001 else Vector3.UP, grapple_impact_specs())
	return {"rope": mesh, "sparks": sparks}

# -------------------------------------------------------- Glu (Verrou)

## Pose de la plaque : le "floc" d'atterrissage (`glue_splat_specs`).
static func spawn_glu_pose(parent: Node, pos: Vector3, radius: float, color: Color) -> Array[GPUParticles3D]:
	return spawn_specs(parent, pos + Vector3(0.0, 0.02, 0.0), Vector3.UP, glue_splat_specs(color))

## Bulles qui remontent doucement à la surface de la plaque tant qu'elle est
## active — donne vie à la plaque plate posée par GlueAbility.spawn_zone
## (hors fichiers possédés) sans en toucher le mesh.
static func spawn_glu_bubbles(parent: Node, pos: Vector3, radius: float, color: Color, duration: float = GLUE_BUBBLE_LIFETIME_S) -> GPUParticles3D:
	return _spawn_looping(parent, pos + Vector3(0.0, 0.03, 0.0), ComicFx.Shape.DISC, color, 3, 0.5,
		0.03, Vector3(0.0, 1.0, 0.0), 60.0 * clampf(radius / 2.5, 0.4, 1.5), 0.1, 0.25, 0.08, duration)

# -------------------------------------------------------- Baume du Palud (Roseau) — baume

## Gouttes de gel montantes en continu tant que la flaque est active (§9.6
## "Soin"). `radius` élargit le cône d'apparition pour couvrir toute la
## flaque plutôt qu'un seul point central.
static func spawn_baume_du_palud(parent: Node, pos: Vector3, radius: float, duration: float) -> GPUParticles3D:
	var gp := _spawn_looping(parent, pos + Vector3(0.0, 0.05, 0.0), ComicFx.Shape.DISC, ComicFx.HEAL_GEL, 6,
		BALM_DROPLET_S * 2.0, 0.045, Vector3(0.0, 1.0, 0.0), 30.0, 0.2, 0.4, 0.5, duration)
	if gp == null:
		return null
	var pm := gp.process_material as ParticleProcessMaterial
	if pm:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = maxf(radius, 0.1)
	return gp

## Le « + » papier qui pop au-dessus d'une cible soignée (§9.6 "Soin"),
## même convention que le "!" de AbilityController.net_show_markers
## (Label3D, encré, billboard) puisque fx_flat.gdshader n'a pas de primitive
## "croix" — un Label3D reste la façon idiomatique Godot de dessiner un
## glyphe, plutôt qu'une 6e forme SDF pour un seul usage.
static func spawn_balm_plus_pop(parent: Node, pos: Vector3) -> Label3D:
	if parent == null:
		return null
	var label := Label3D.new()
	label.text = "+"
	label.modulate = ComicFx.HEAL_GEL
	label.outline_modulate = Cartoon.INK
	label.font_size = 72
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.double_sided = true
	parent.add_child(label)
	label.global_position = pos + Vector3(0.0, 0.4, 0.0)
	label.scale = Vector3.ONE * 0.001
	var tw := label.create_tween()
	tw.tween_property(label, "scale", Vector3.ONE * 1.15, BALM_DROPLET_S * 0.35).set_trans(Tween.TRANS_BACK)
	tw.tween_property(label, "scale", Vector3.ONE, BALM_DROPLET_S * 0.25)
	tw.parallel().tween_property(label, "position:y", label.position.y + 0.5, BALM_DROPLET_S)
	tw.chain().tween_property(label, "modulate:a", 0.0, BALM_DROPLET_S * 0.4)
	tw.tween_callback(label.queue_free)
	return label

# -------------------------------------------------------- Coup de dé (Guet) — révélation

## Le dé qui vole de `origin` à `target_pos` en `flight_time` (0,5 s, docs/
## AGENTS.md) : un unique quad RECT plat (jamais un mesh 3D cubique — cohérent
## avec le reste du kit, "découpé au ciseau" §9.1) qui tumble sur lui-même en
## trajectoire, puis pop (`dice_pop_specs`) et se libère à l'arrivée. Le
## marqueur "!" révélé lui-même reste posé par
## AbilityController.net_show_markers (hors fichiers possédés) — cette
## fonction ne couvre que l'objet qui vole et son atterrissage, pas la bulle.
static func spawn_coup_de_de(parent: Node, origin: Vector3, target_pos: Vector3, flight_time: float = DICE_FLIGHT_S) -> MeshInstance3D:
	if parent == null:
		return null
	var die := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE * 0.12
	die.mesh = qm
	die.material_override = ComicFx.shape_material(ComicFx.Shape.RECT, Cartoon.PAPER, true, false)
	parent.add_child(die)
	die.global_position = origin
	var tw := die.create_tween()
	tw.set_parallel(true)
	tw.tween_property(die, "global_position", target_pos, flight_time).set_trans(Tween.TRANS_SINE)
	tw.tween_property(die, "rotation_degrees:x", 720.0, flight_time)
	tw.tween_property(die, "rotation_degrees:y", 480.0, flight_time)
	tw.chain().tween_callback(Callable(AbilityVfx, "_on_dice_landed").bind(die))
	return die

## Callback nommé (jamais un lambda anonyme, même règle que le minuteur
## ci-dessus) : le pop d'atterrissage du dé, puis sa libération. `bind(die)`
## depuis `spawn_coup_de_de` plutôt qu'une closure — testable directement.
static func _on_dice_landed(die: MeshInstance3D) -> void:
	if not is_instance_valid(die):
		return
	if die.is_inside_tree():
		spawn_specs(die.get_parent(), die.global_position, Vector3.UP, dice_pop_specs())
	die.queue_free()
