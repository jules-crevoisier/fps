## AgentAnimProfile.gd
## Ressource : personnalité d'animation ADDITIVE d'un agent (docs/STYLE_BIBLE.md
## §4.6, tâche ART-15) — rebond, inclinaison de buste, balancement latéral,
## cadence de pas et « idle unique ». Chargée par nom d'agent depuis
## resources/agents/anim/<agent minuscule>.tres (voir
## scripts/player/CharacterAnimator.gd : `load_profile`).
##
## Purement COSMÉTIQUE, comme le reste du modèle 3D (§4.1 : « aucun choix
## d'art ne peut modifier la hitbox »). Aucun champ ici ne représente une
## position, une vitesse ou un état de jeu : uniquement des offsets visuels
## appliqués sur "%CharacterModel" (scripts/player/CharacterBody.gd), jamais
## sur PlayerController / la CapsuleShape3D. Les bornes des champs (cadence,
## inclinaison) sont les garde-fous du §4.6, vérifiées par
## CharacterAnimator.profile_respects_hitbox_floor (voir
## tests/player/test_character_animator.gd).
class_name AgentAnimProfile
extends Resource

## Nom de l'agent (AgentDatabase.agent_name, ex. "Vif") — clé de résolution,
## indépendante du nom de fichier (utile pour les tests qui construisent un
## profil en mémoire sans passer par un .tres).
@export var agent_name: String = ""

## Multiplicateur de cadence de pas — §4.6 : « de ×0,9 à ×1,15 ». Appliqué à
## la lecture de la couche Locomotion via un AnimationNodeTimeScale
## (`parameters/Cadence/scale`, voir `_build_tree`) : ne touche que la vitesse
## de LECTURE du clip, jamais `MovementConfig`/la vitesse réelle du joueur.
@export var cadence_scale: float = 1.0

## Inclinaison additive du buste, en degrés, vers l'avant — §4.6 : « buste
## penché de 8° au plus ». Bornée à la construction par
## CharacterAnimator.MAX_TORSO_TILT_DEG, jamais appliquée aux états
## pleine-pose (Slide/Dive/Crouch/Roll/Stun/Interact/Dead) qui ont leur propre
## inclinaison dédiée.
@export var torso_tilt_deg: float = 0.0

## Balancement latéral additif, en degrés — réservé pour une démarche future
## qui en aurait besoin (§4.6) : aucun des 6 profils livrés
## (resources/agents/anim/*.tres) ne s'en sert aujourd'hui, toutes les
## démarches actuelles (voir la table du §4.6) s'exprimant en cadence/
## inclinaison/rebond seuls.
@export var lateral_sway_deg: float = 0.0

## Amplitude de rebond vertical en idle/marche/course, en mètres — cosmétique,
## jamais assez grande pour faire passer les yeux sous 1,56 m ni le menton
## sous 1,43 m (garde-fou vérifié par
## CharacterAnimator.profile_respects_hitbox_floor).
@export var bounce_amplitude_m: float = 0.0

## Étiquette descriptive de l'« idle unique » du §4.4 (ex. "tapote du pied et
## sautille" pour Vif) — sert à prouver par le test que chaque agent a un
## idle distinct ; ne pilote aucun clip séparé (l'idle reste le clip UAL
## partagé "Idle", §4.6 : « Base partagée : les 46 actions UAL... pour tous
## les agents »).
@export var idle_style: String = ""
