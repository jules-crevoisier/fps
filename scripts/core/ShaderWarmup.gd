## ShaderWarmup.gd
## Préchauffage des pipelines de rendu (docs/research/07_godot_tech.md §C2,
## "Ce que les ubershaders ne couvrent pas" / doc officielle Godot 4.7,
## "Pipeline precompilation instancing" : « attach an invisible or off-screen
## version of dynamically spawned effects to a node guaranteed to load
## early »). Le shader baker (export_presets.cfg, `shader_baker/enabled`)
## précompile déjà vers le format du pilote (SPIR-V/DXIL/MIL) mais ne crée
## PAS les pipelines GPU finaux ; ce nœud force leur PREMIER usage réel — un
## `MeshInstance3D` invisible pour chaque matériau Cartoon effectivement
## utilisé en jeu (toon, coques d'encre, peint par kind) et le seul VFX
## existant (flash de bouche) — pour que ce premier coût soit payé ICI, au
## chargement de la carte, et non en pleine partie (moniteur
## `PIPELINE_COMPILATIONS_DRAW`, ajouté par TECH-02 dans PerfOverlay.gd/
## Benchmark.gd — hors de mon périmètre, voir tools/tasks/plan.py prompt
## TECH-01).
##
## `visible = false` suffit et n'est PAS un raccourci qui saute la
## compilation : la doc officielle ci-dessus le confirme explicitement, et
## le moniteur "Surface" se déclenche « quand des objets 3D sont instanciés
## dans l'arbre de scène » pour la première fois — pas seulement quand ils
## sont effectivement dessinés à l'écran.
##
## Instancié par `MapSetup._enter_tree()` (dernière étape, après le reste de
## la carte) comme enfant de lui-même — même règle que tous les autres nœuds
## construits par ce fichier (voir l'en-tête de MapSetup.gd). Se détruit tout
## seul après `WARMUP_FRAMES` frames (contrat TECH-01 : "pendant au moins
## 2 frames" — le temps que le moteur lance ET termine la compilation
## déclenchée par ces instances avant qu'on libère ce qui l'a déclenchée).
class_name ShaderWarmup
extends Node

## Kinds peints (Cartoon.gd `_PAINTED`, lui-même aligné 1-pour-1 sur
## `tools/textures/gen_textures.py`'s `MATERIALS`). Dupliqué ici à dessein :
## ce nœud ne lit aucun membre "privé" (préfixé `_`) d'un autre script, et
## TECH-01 n'a pas le droit de toucher Cartoon.gd (hors de son périmètre)
## pour y ajouter un accesseur public à cette liste.
const _PAINTED_KINDS: Array[StringName] = [
	&"painted_metal", &"rust", &"corrugated_metal", &"container_paint",
	&"wood_planks", &"sand_dirt", &"cracked_concrete", &"asphalt",
	&"ship_deck", &"rubber_tire", &"dirty_glass",
]

## Frames pendant lesquelles les instances de préchauffage restent dans
## l'arbre après `_ready()` avant leur destruction (contrat : "pendant au
## moins 2 frames").
const WARMUP_FRAMES := 2

## Taille des maillages de préchauffage : n'a aucune importance (invisibles,
## jamais dessinés à l'écran) — juste assez petite pour ne rien coûter.
const _RIG_SIZE := 0.05

func _ready() -> void:
	_spawn_toon_and_shells()
	_spawn_painted_kinds()
	_spawn_vfx()
	for _i in WARMUP_FRAMES:
		await get_tree().process_frame
	queue_free()

## Toon (`world()`) + les deux formes de coques d'encre réellement posées en
## jeu : la coque à estompe par distance (`character()`, alliés/mannequins/
## viewmodel) — avec ET sans la surbrillance ennemie, qui chaîne un
## `next_pass` supplémentaire (`Cartoon.character`'s branche
## `highlight_color.a > 0.0`) — et la coque plate sans estompe
## (`prop()`, pickups/décor interactif).
func _spawn_toon_and_shells() -> void:
	_spawn(Cartoon.world(Color.WHITE))
	_spawn(Cartoon.character(Cartoon.ally_color()))
	_spawn(Cartoon.character(Cartoon.ally_color(), 3.0, Cartoon.enemy_color()))
	_spawn(Cartoon.prop(Color.WHITE))

## Un matériau peint par kind connu de `Cartoon._PAINTED` (partagent tous le
## même shader `ink_toon` que `world()`/`character()` — un seul pipeline au
## total — mais chacun charge sa PROPRE texture albedo/grime : ce premier
## upload GPU par texture est aussi une source de saccade au premier usage,
## couverte ici en même temps).
func _spawn_painted_kinds() -> void:
	for kind in _PAINTED_KINDS:
		_spawn(Cartoon.painted(kind))

## Réplique le matériau du flash de bouche (`ThirdPersonWeapon.gd`/
## `ViewModel.gd`, méthode privée `_spawn_muzzle_flash` — hors de mon
## périmètre) : `StandardMaterial3D` non éclairé + transparence alpha +
## billboard. C'est le seul effet visuel du jeu à ce jour (aucune scène
## `GPUParticles3D`/`CPUParticles3D` encore livrée — voir
## docs/research/07_godot_tech.md §C2, "instancier les effets ... invisibles
## dès le chargement de la carte") : cette combinaison de réglages génère un
## shader `BaseMaterial3D` distinct de celui d'un matériau opaque par
## défaut, donc un pipeline à part, jamais couvert par `world()`/`painted()`/
## `character()`.
func _spawn_vfx() -> void:
	var mesh := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(_RIG_SIZE, _RIG_SIZE)
	mesh.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.92, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material_override = mat
	mesh.visible = false
	add_child(mesh)

func _spawn(mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(_RIG_SIZE, _RIG_SIZE, _RIG_SIZE)
	mesh.mesh = box
	mesh.material_override = mat
	mesh.visible = false
	add_child(mesh)
