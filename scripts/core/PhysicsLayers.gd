## PhysicsLayers.gd
## Calques physiques partagés (bits de collision_layer / collision_mask).
## Calque 1 = monde et joueurs (défaut Godot). Calque 5 = VISION : objets qui
## bloquent la vue sans bloquer les corps ni les balles (fumées). Calque 6 =
## PLAYER_CLIP (LD-44, Wasteland v4 §12.3 révisé) : volumes anti-joueur posés
## au-dessus des toits bas (`Kit.roof_clip_volumes`) — heurtés par le corps
## des joueurs/bots (`scenes/player/player.tscn` inclut ce bit dans son
## `collision_mask` par défaut), mais absents de `SHOT_MASK` : un tir, une
## grenade ou un grappin les traverse. Voir docs/COLLISION_LAYERS.md §3.
class_name PhysicsLayers
extends RefCounted

const WORLD := 1 << 0
const VISION := 1 << 4
const PLAYER_CLIP := 1 << 5
## Masque des rayons de tir : tout sauf les bloqueurs de vision (on tire à
## travers une fumée, comme dans les shooters tactiques de référence) et sauf
## les volumes anti-joueur `PLAYER_CLIP` (on tire/lance à travers eux : seul
## le corps du joueur s'y heurte, jamais un projectile ni un rayon).
const SHOT_MASK := 0xFFFFFFFF & ~VISION & ~PLAYER_CLIP
