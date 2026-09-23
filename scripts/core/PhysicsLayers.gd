## PhysicsLayers.gd
## Calques physiques partagés (bits de collision_layer / collision_mask).
## Calque 1 = monde et joueurs (défaut Godot). Calque 5 = VISION : objets qui
## bloquent la vue sans bloquer les corps ni les balles (fumées).
class_name PhysicsLayers
extends RefCounted

const WORLD := 1 << 0
const VISION := 1 << 4
## Masque des rayons de tir : tout sauf les bloqueurs de vision (on tire à
## travers une fumée, comme dans les shooters tactiques de référence).
const SHOT_MASK := 0xFFFFFFFF & ~VISION
