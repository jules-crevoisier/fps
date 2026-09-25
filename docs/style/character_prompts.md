# Prompts de concept des agents (v4 — « La Ruée vers la Braise »)

> 2026-09-24. Histoire et raison d'être de chaque agent : [`docs/LORE.md`](../LORE.md) §4. Gabarit et fiches visuelles : [`docs/STYLE_BIBLE.md`](../STYLE_BIBLE.md) §4.1 et §4.4.
> Outil : Tripo Studio, générateur d'image Nano Banana Pro, puis image→3D.
> Les prompts sont en anglais, parce que les modèles d'image y répondent mieux. Ils ne citent aucun jeu, studio ou artiste existant : on décrit le style, on ne l'emprunte pas.
> Changements par rapport à la v3.1 :
> - Roc est remplacé par **Vanne** (humaine) et Baume par **Roseau** (héronne) ;
> - Guet passe de la tête de dé au **vautour** ;
> - Verrou et Vif sont alignés sur leurs modèles 3D approuvés ;
> - Choc ne change pas.

## Mode d'emploi

1. **Générer.** Coller le bloc de l'agent **tel quel**. Il contient déjà le gabarit, le style et la liste `Avoid:`. Si l'outil a un champ négatif, y déplacer ce qui suit `Avoid:`.
2. **Trier.** Générer 4 variantes et garder celle qui passe la grille ci-dessous.
3. **Faire valider.** Montrer l'image retenue à l'utilisateur **avant** toute 3D.
4. **Passer en 3D.** Lancer l'image→3D en **forme seule**, sans texture HD ni auto-rig. On retexture en aplats et on skinne sur le squelette commun UAL-G (bible §4.1 et §4.5).
5. **Tracer.** Enregistrer la provenance (prompt, modèle, date, graine) dans `docs/style/concepts/provenance.json`.

Les hex du prompt orientent le modèle, qui ne les respecte pas exactement. Les couleurs finales sont posées dans Blender à partir de la bible.

**Verrou et Vif existent déjà en 3D** (`assets/models/characters/verrou.glb`, `vif.glb`). Leur prompt ne sert qu'aux variantes et aux cosmétiques ; il décrit le modèle approuvé, il ne le redessine pas.

## Grille de contrôle de l'image, avant la 3D

Mesures en pourcentage de la hauteur du personnage (semelle à 0 %, point le plus haut à 100 %), à tracer sur l'image :

| Repère | Cible | Équivalent en jeu |
|---|---|---|
| Point le plus haut (chapeau, huppe, flamme compris) | 100 % | 1,80 m |
| Ligne des yeux (sauf Verrou, yeux au sommet du crâne) | ≈ 90 % | 1,62 m |
| Menton | ≈ 83 % | 1,49 m |
| Jonction col–épaules | ≈ 78 % | 1,40 m |
| Sommet des épaules | ≤ 77 % | 1,38 m |
| Entrejambe | ≈ 47 % | 0,84 m |
| Largeur de la tête, tout compris | ≤ 19 % | 0,34 m |
| Largeur aux épaules | 26–33 % | 0,46–0,60 m |

L'image est rejetée si l'une de ces conditions n'est pas remplie :
- **Cadrage :** un seul personnage, entier, vu de face, pieds visibles et à plat.
- **Pose :** A-pose symétrique ; les bras ne touchent pas le corps et les mains sont ouvertes.
- **Proportions :** tête de taille normale (le crâne fait environ 1/7 de la hauteur), épaules basses sous un col haut.
- **Fond :** gris clair uni, sans grille, sans sol, sans ombre au sol, sans socle ni décor.
- **Armes :** aucune arme en main. Seul Verrou porte son revolver, à l'étui. Les gadgets sont portés à la ceinture, à la cuisse ou au buste.
- **Silhouette :** rien de flottant ni de très fin. Pas de cape au vent, pas de mèche isolée, pas de plume fine, pas de particules.
- **Couleur-clé :** elle est sur la tête pour **les six agents** : flamme, casque, suroît, peau, plumage. L'exception de Roc disparaît avec lui.
- **Éveillés :** mains à **quatre doigts**, aucune aile, aucune queue. C'est la « forme d'éveil » du lore.

Les concepts à tête-objet de `docs/style/concepts/` (`vif_s*`, `verrou_s*`, `lot1_contact.png`) montrent ce qu'on ne veut plus : grosses têtes, socles, rendu jouet en vinyle.

---

## Vif — « l'Allumette » (Entrée, humaine)

```
Vif, a lean 19-year-old human woman, street sprinter and claim runner, confident half-grin, athletic and light on her feet. Her hair is a solid sculpted flame: a short chunky quiff swept up and back like a match flame, dark vermilion at the roots (#B8421A), vermilion-orange body (#EE6A24), amber-yellow tips (#F2C53D), smooth solid shapes kept close to the head, NOT real fire. Warm tan skin (#D29A6E), amber eyes, thick eyebrows. Cropped ember-red track jacket (#9A4A2C) with a high zipped collar up to the chin and cream stripes (#EBDDC0) down the sleeves, dark sports top, full-length charcoal leggings (#2A2522), high-top cream sneakers (#E6E1D6) with vermilion soles, leather wristbands. A brown leather striker band (#8A4B2E) on the left forearm, a diagonal leather bandolier across the chest holding four chunky brass-capped match-shaped flash grenades, a small spring-loaded matchbox clipped at the hip, a round brass belt buckle. Silhouette: a flame quiff on a slim V-shaped body with long legs.
Full-body character concept for image-to-3D: one single character, full body, front view, centered, camera at chest height with no perspective distortion, symmetrical A-pose with both arms held about 40 degrees away from the body, open relaxed hands not touching the body, legs straight and slightly apart, both feet flat on the ground, whole figure visible from head to toe with margin. Athletic humanoid proportions, head-to-body 1:7, tall hero-shooter character, NOT chibi, NOT mascot: long legs, short torso, relaxed sloping shoulders sitting low under a high collar, normal game-character head size.
Stylized painted cel-shaded look with bold dark ink outlines, thicker on the silhouette and thinner inside: two flat tones per material (one lit tone, one cool blue-violet shadow tone), clean solid colour blocks, chunky bevelled readable shapes, no texture noise, a single hard glossy highlight only on lacquered, metal or wet parts, soft even studio light. Plain flat light-grey background (#D9D9D9), no grid, no floor, no floor shadow, no pedestal, nothing else in the image.
Avoid: chibi, big head, mascot, toy figurine, pedestal, turnaround sheet, multiple views, text, logo, watermark, grid, floor shadow, weapon in hands, action pose, cropped feet, fisheye, flowing cape, particles, glow, neon, photorealistic, PBR, grunge, purple, magenta, lime green, leaf green, blood, real fire, burning hair, long hair.
```

**À vérifier :** la flamme reste une masse pleine, à 5 cm au plus au-dessus du crâne, couchée vers l'arrière ; le col zippé monte jusqu'au menton.

## Choc — « la Cloche » (Entrée, humain)

```
Choc, a broad 34-year-old human man, fairground heavyweight boxer raised by a travelling fair, the widest fighter of the roster but athletic, not fat, warm showman smile. Deep brown skin (#6B4330), short trimmed beard, low heavy eyebrows. He wears a glossy red enamel boxing headguard (#BE2D25) shaped like the dome of an alarm bell, open on the face, with a brass chin guard (#D9A21B) shaped like a bell clapper. Sleeveless padded training vest in warm cream (#E6E1D6) with red piping and a high padded collar, red satin boxing shorts with a cream waistband over full-length charcoal compression leggings (#2A2522), cream boxing boots with red laces. Wrapped hands in open-finger charcoal fight mitts with red cuffs, fingers free. A cracked brass ring bell mounted on a back harness between the shoulder blades, kept below the shoulders, a belt holding three small brass bell-shaped mines, a round brass belt buckle. Silhouette: a bell-dome head on a massive V-shaped torso with big fists, strong but low sloping shoulders.
Full-body character concept for image-to-3D: one single character, full body, front view, centered, camera at chest height with no perspective distortion, symmetrical A-pose with both arms held about 40 degrees away from the body, open relaxed hands not touching the body, legs straight and slightly apart, both feet flat on the ground, whole figure visible from head to toe with margin. Athletic humanoid proportions, head-to-body 1:7, tall hero-shooter character, NOT chibi, NOT mascot: long legs, short torso, relaxed sloping shoulders sitting low under a high collar, normal game-character head size.
Stylized painted cel-shaded look with bold dark ink outlines, thicker on the silhouette and thinner inside: two flat tones per material (one lit tone, one cool blue-violet shadow tone), clean solid colour blocks, chunky bevelled readable shapes, no texture noise, a single hard glossy highlight only on lacquered, metal or wet parts, soft even studio light. Plain flat light-grey background (#D9D9D9), no grid, no floor, no floor shadow, no pedestal, nothing else in the image.
Avoid: chibi, big head, mascot, toy figurine, pedestal, turnaround sheet, multiple views, text, logo, watermark, grid, floor shadow, weapon in hands, action pose, cropped feet, fisheye, flowing cape, particles, glow, neon, photorealistic, PBR, grunge, purple, magenta, lime green, leaf green, blood, obese, closed boxing gloves, face guard covering the face, visor.
```

**À vérifier :** les épaules restent sous le col, sans trapèzes qui montent aux oreilles ; le visage est entièrement visible ; la cloche dorsale ne dépasse pas des épaules.

## Vanne — « la Digue » (Contrôle, humaine) — nouvelle

```
Vanne, a sturdy middle-aged human woman, chief hydraulic engineer of a mining-and-power company, calm, severe and precise, strong practical build. She wears a glossy chrome-yellow oilskin sou'wester rain hat (#F2B51D): front brim turned up, back brim sloping down to the nape, kept close to the head. Round brass-rimmed spectacles, short dark auburn bob under the hat, light warm skin with freckles (#D8A27E), a thick navy roll-neck collar (#2E4A6B) up to the chin. Boxy ecru canvas work coverall (#BFAE86) with sleeves rolled to the forearm, navy shoulder patches with a sun-and-comet emblem, a numbered armband with yellow and ink-black chevrons, brown leather work gauntlets (#6B4A2E), a leather tool belt with a round brass valve-handwheel buckle, a chunky surveyor stake tool strapped flat to the right thigh, a flat grey sprayer tank strapped tight to her back and kept below the shoulders, charcoal rubber boots (#2A2522). Silhouette: a yellow sou'wester with a long back brim over a square, boxy, planted body.
Full-body character concept for image-to-3D: one single character, full body, front view, centered, camera at chest height with no perspective distortion, symmetrical A-pose with both arms held about 40 degrees away from the body, open relaxed hands not touching the body, legs straight and slightly apart, both feet flat on the ground, whole figure visible from head to toe with margin. Athletic humanoid proportions, head-to-body 1:7, tall hero-shooter character, NOT chibi, NOT mascot: long legs, short torso, relaxed sloping shoulders sitting low under a high collar, normal game-character head size.
Stylized painted cel-shaded look with bold dark ink outlines, thicker on the silhouette and thinner inside: two flat tones per material (one lit tone, one cool blue-violet shadow tone), clean solid colour blocks, chunky bevelled readable shapes, no texture noise, a single hard glossy highlight only on lacquered, metal or wet parts, soft even studio light. Plain flat light-grey background (#D9D9D9), no grid, no floor, no floor shadow, no pedestal, nothing else in the image.
Avoid: chibi, big head, mascot, toy figurine, pedestal, turnaround sheet, multiple views, text, logo, watermark, grid, floor shadow, weapon in hands, action pose, cropped feet, fisheye, flowing cape, particles, glow, neon, photorealistic, PBR, grunge, purple, magenta, lime green, leaf green, blood, fisherman, raincoat, hard hat, helmet, goggles, thin hoses.
```

> Tripo Studio a refusé la première version de ce prompt (« ne respecte pas nos directives de contenu »,
> 2026-09-24) : ne pas mettre de terme à connotation sexuelle, même dans `Avoid:`. Version ci-dessus acceptée.

**À vérifier :**
- Le rabat arrière du suroît s'arrête au-dessus de la nuque, au plus bas vers 1,50 m, jamais sur les épaules.
- Le suroît ne dépasse pas la largeur de la tête de plus d'un bord étroit.
- La tenue se lit « ingénieure », pas « pêcheuse » : pas de ciré jaune sur le corps, le jaune reste sur la tête.

## Guet — « le Dé » (Contrôle, vautour éveillé) — adapté

```
Guet, a tall slender humanoid vulture gentleman, an awakened griffon vulture with an elegant, lean, athletic human body, sly and composed. Bald head of normal game-character head size covered in smooth deep indigo-blue skin (#5157B8, blue not purple), a strong ivory hooked beak (#D8CFB8) with a dark tip, projecting only a little in front of the face, sharp golden eyes (#F2C53D) under heavy brows. A thick cream feather ruff (#E6E1D6) circles the base of the neck like a high collar, sitting just below the chin, made of a few large chunky feather shapes. A small crushed charcoal top hat with a wine-red band, tilted on the head. Wine-red waistcoat (#8E2F42) with thin gold piping and a gold bow tie, short charcoal tailcoat (#2A2522) with tails above the knee, slim charcoal pinstripe trousers, cream spats over black shoes. White gloves on four-fingered hands, short dark-brown feather cuffs at the wrists, NO wings. A gold watch chain with a twenty-sided die fob, a round brass belt buckle. Silhouette: a small bald hooked-beak head with a tilted top hat, sitting on a cream feather ruff, on a narrow vertical body.
Full-body character concept for image-to-3D: one single character, full body, front view, centered, camera at chest height with no perspective distortion, symmetrical A-pose with both arms held about 40 degrees away from the body, open relaxed hands not touching the body, legs straight and slightly apart, both feet flat on the ground, whole figure visible from head to toe with margin. Athletic humanoid proportions, head-to-body 1:7, tall hero-shooter character, NOT chibi, NOT mascot: long legs, short torso, relaxed sloping shoulders sitting low under a high collar, normal game-character head size.
Stylized painted cel-shaded look with bold dark ink outlines, thicker on the silhouette and thinner inside: two flat tones per material (one lit tone, one cool blue-violet shadow tone), clean solid colour blocks, chunky bevelled readable shapes, no texture noise, a single hard glossy highlight only on lacquered, metal or wet parts, soft even studio light. Plain flat light-grey background (#D9D9D9), no grid, no floor, no floor shadow, no pedestal, nothing else in the image.
Avoid: chibi, big head, mascot, toy figurine, pedestal, turnaround sheet, multiple views, text, logo, watermark, grid, floor shadow, weapon in hands, action pose, cropped feet, fisheye, flowing cape, particles, glow, neon, photorealistic, PBR, grunge, purple, magenta, lime green, leaf green, blood, wings, feathered arms, talons, bird legs, pink or red head, dice head, mask, carrion.
```

**À vérifier :**
- La tête nue est de la taille d'une tête humaine, et le bec ne double pas la profondeur du visage.
- La collerette reste sous le menton et moins large que les épaules.
- L'indigo reste bleu, jamais violet.
- Aucune aile.

## Roseau — « la Passeuse » (Soutien, héronne éveillée) — nouvelle

```
Roseau, a tall lean humanoid heron woman, an awakened grey heron from the marsh, smuggler and guide, calm, watchful and dry-humoured, athletic human body. Head of normal game-character head size: sleek teal-turquoise head plumage (#2E9C8A), a cream face mask (#EFE3C8), a straight ochre dagger beak (#E0A43A) of moderate length, sharp yellow eyes (#F2C53D) with a dark ink stripe running back into a chunky swept-back crest made of three merged dark plumes, kept close to the head. A high woven cream scarf (#E6E1D6) with a teal triangle frieze wrapped up to the jaw, hiding the long neck. A long slate-blue waxed coat (#6F8594) with a high collar, belted at the waist, split at the back and flaring into a gentle A-shape that ends above the knee. A leather bandolier of chunky red-and-cream fishing floats across the chest, two glass jars of pale mist and a small brass lantern at the hip, a round brass belt buckle, fingerless brown leather gloves (#6B4A2E) on four-fingered grey scaly hands, charcoal thigh-high waders (#2A2522). NO wings. Silhouette: a pointed-beak head with a swept-back crest on top of a long A-shaped coat.
Full-body character concept for image-to-3D: one single character, full body, front view, centered, camera at chest height with no perspective distortion, symmetrical A-pose with both arms held about 40 degrees away from the body, open relaxed hands not touching the body, legs straight and slightly apart, both feet flat on the ground, whole figure visible from head to toe with margin. Athletic humanoid proportions, head-to-body 1:7, tall hero-shooter character, NOT chibi, NOT mascot: long legs, short torso, relaxed sloping shoulders sitting low under a high collar, normal game-character head size.
Stylized painted cel-shaded look with bold dark ink outlines, thicker on the silhouette and thinner inside: two flat tones per material (one lit tone, one cool blue-violet shadow tone), clean solid colour blocks, chunky bevelled readable shapes, no texture noise, a single hard glossy highlight only on lacquered, metal or wet parts, soft even studio light. Plain flat light-grey background (#D9D9D9), no grid, no floor, no floor shadow, no pedestal, nothing else in the image.
Avoid: chibi, big head, mascot, toy figurine, pedestal, turnaround sheet, multiple views, text, logo, watermark, grid, floor shadow, weapon in hands, action pose, cropped feet, fisheye, flowing cape, particles, glow, neon, photorealistic, PBR, grunge, purple, magenta, lime green, leaf green, blood, wings, feathered arms, bare long neck, very long beak, thin crest feathers, bird feet, hood, nurse, medic.
```

**À vérifier :**
- Le bec dépasse d'au plus 0,14 m devant le visage, soit environ la moitié de la largeur de la tête.
- La huppe reste dans la hauteur de 1,80 m et ne fait pas d'aigrettes fines.
- L'écharpe cache le cou jusqu'à la mâchoire.
- Le manteau s'arrête au-dessus du genou, et on voit les jambes.

## Verrou — « le Crapaud » (Soutien, dendrobate éveillé) — modèle approuvé

```
Verrou, a humanoid poison-dart frog marshal and gunslinger, standing upright with a tall athletic humanoid body and straight human-length legs, calm and laconic. Frog head of normal game-character head size: wide flat mouth with a slight calm smile, two large bulging golden eyes (#F2C53D) with black pupils set high on the head, glossy wet cobalt-blue skin (#2A5FC4) with irregular dark ink spots (#1A1410), pale sky-blue throat (#A9C1DE). Dark brown leather cowboy hat (#6B4A2E) pushed back behind the eyes, its brim curled up at the sides and kept compact. A short greige-sand woven poncho (#CDBB98) with a high soft cowl collar and a cobalt-and-cream triangle frieze along the hem, worn over a mustard-yellow shirt (#C98F3A) with rolled sleeves and a charcoal vest (#2A2522). Bare cobalt spotted forearms, dark brown fingerless leather gauntlets (#4A3528) on blue four-fingered frog hands with round finger pads. A brown leather gun belt with a round steel buckle, a leather holster on his right hip holding a revolver with a coral-red crayfish-shell grip and cylinder guard (#E0574A), a dark grey utility pouch on the left hip. Dark navy denim jeans (#2B3550), charcoal leather cowboy boots (#2F2A2A). Silhouette: two round eyes under a tipped-back hat on top of a triangular poncho body.
Full-body character concept for image-to-3D: one single character, full body, front view, centered, camera at chest height with no perspective distortion, symmetrical A-pose with both arms held about 40 degrees away from the body, open relaxed hands not touching the body, legs straight and slightly apart, both feet flat on the ground, whole figure visible from head to toe with margin. Athletic humanoid proportions, head-to-body 1:7, tall hero-shooter character, NOT chibi, NOT mascot: long legs, short torso, relaxed sloping shoulders sitting low under a high collar, normal game-character head size.
Stylized painted cel-shaded look with bold dark ink outlines, thicker on the silhouette and thinner inside: two flat tones per material (one lit tone, one cool blue-violet shadow tone), clean solid colour blocks, chunky bevelled readable shapes, no texture noise, a single hard glossy highlight only on lacquered, metal or wet parts, soft even studio light. Plain flat light-grey background (#D9D9D9), no grid, no floor, no floor shadow, no pedestal, nothing else in the image.
Avoid: chibi, big head, mascot, toy figurine, pedestal, turnaround sheet, multiple views, text, logo, watermark, grid, floor shadow, weapon in hands, action pose, cropped feet, fisheye, flowing cape, particles, glow, neon, photorealistic, PBR, grunge, purple, magenta, lime green, leaf green, blood, crouching, bent frog legs, webbed feet, toad warts, fat belly, sombrero, visible sheriff star, olive-green skin.
```

**À vérifier :**
- Il est debout, avec des jambes droites de longueur humaine.
- Les yeux et le chapeau tiennent dans 0,34 m de large ; le bord du chapeau du modèle approuvé est à mesurer (bible §4.4).
- Le revolver reste dans l'étui.
- L'étoile ne se voit pas : il la porte sous le poncho (lore).
