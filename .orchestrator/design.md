# Design direction v2: « Peint au soleil, encré gras »

v2, 2026-09-23, awaiting lock. It replaces v1 « Encre et papier », which the user rejected.

Refs: `.orchestrator/refs/` (no `inspiration.md`). Figures computed: WCAG 2.x, OKLCH, Machado 2009 (ΔE = OKLab×100).

## 1. Thesis

A sun-baked frontier, hand-painted and inked hard: saturated rust, sand and containers under a big blue sky. The enemy is the only thing wearing a colour the world may not use.

- **Rejected:** v1's chroma law (decor C ≤ 0.05). It bought readability by draining the world, and this user wants it loud.
- **Kept from v1:** ink outlines, the centre zone, colour-plus-shape, the type floor, motion and gamepad states.

## 2. What each reference teaches

- **wasteland_hero:**
  - Warm side sun, cool blue shadows, horizon haze, clouds only above the roofs.
  - Dense street edges (FUEL, awnings, cars), clear sand lane.
- **wasteland_sheet:** landmarks name spawns (FUEL blue, GAS red); derricks orient; one warm ground value makes bodies pop.
- **cargo_ship_hero:** single-colour container blocks with stencils and rusty feet. The deck is calm grey with hazard yellow; the sea and sky are the only cool masses.
- **cargo_ship_sheet:** colour by zone doubles as the callouts.
- **Both sheets:** the UI grammar in §11.

## 3. Research: Borderlands

- Everything is hand-made except the Sobel outline ([Cook and Becker](https://www.cookandbecker.com/en/article/224/borderlands-3-art-director-scott-kester-on-communicating-an-attitude.html)).
- Hand-drawn textures, sharpened shadows, lines on hills ([Destructoid](https://www.destructoid.com/borderlands-explains-its-not-cel-shaded-actually-art-style/)).
- Inks sit on UV breaks with an offset line and a ~20% curvature overlay; base noise stays low so the ink survives ([80.lv](https://80.lv/articles/creating-a-laser-rifle-in-the-borderlands-style)).
- Ink masks derived from normal maps give a 60–80% baseline ([Game World Observer](https://gameworldobserver.com/2022/12/19/how-ai-helps-artists-gearbox-borderlands-prevent-crunch)).
- Outlines fade with distance ([Simonschreibt](https://simonschreibt.de/gat/cell-shading/)).

**So:** ink lives in textures (baked, then hand-finished); post draws silhouettes; v1's hatching and grain go.

## 4. Lighting script

- **Sun:** warm, at 25–50° (per map, §7). It crosses the main lanes at 60–90° and never sits behind a spawn sightline.
- **Ramp:** three bands. The terminator band gets +15% chroma. Shadow = albedo × map tint, at 55–60% of lit value and never under 45%.
- **Shadows:** blue-violet (the #5C6EA8 family), never grey.
- **Ambient:** zenith at 25%, plus 15% sand bounce.
- **Sky:** zenith to haze, with a soft warm sun disc.
- **Clouds:** painted cumulus, flat-bottomed, #FFF8EC lit and #A7B8E0 shade, no ink.
  - They sit 8–35° up at 20–35% coverage.
  - Below 8° is haze only, so rooftop silhouettes read.
- **Fog:** the horizon colour, starting at 35 m and reaching 30% at 120 m. It also tints far outlines.
- **GI:** LightmapGI and one directional light.

## 5. Outlines

Widths are for 1080p, scaled by height/1080.

- **Characters:** ink #1A1410 hull, 3 px to 10 m, 2 px at 40 m, 1.5 px floor.
- **Enemies:** a highlight hull, 3.5→2.5 px, that never fades.
  - A 1 px ink hull outside it, and a matching fresnel rim at 0.6.
  - The ink reads on bright backgrounds, the colour on dark ones.
- **Viewmodel and pickups:** 2 px ink.
- **Decor silhouettes (post):** 4 px to 10 m, 1.5 px at 60 m, 40% opacity at 90 m, tinted by haze.
- **Decor creases:** 2 px, gone by 30 m.
- **Inner lines:** painted only.
- **Encre renforcée** (accessibility): ×1.5.

## 6. Painted texture library

- **Textures:** painted albedo, a normal map, and a mask (R ink, G wear, B grime, A AO).
- **Density:** 256 px/m, specular off.
- **Triplanar:** terrain (4 m) and big structures (2 m) only; everything else uses trim sheets.

**Materials:**
- Sable #D9A15C, pebbles #B97E43
- Piste #C58B4E
- Rouille #B5562A, edges #E08A3C
- Tôle #4F7FA8/#E9DDBF
- Bois #9C6A42, edges #C99A68
- Béton #B8AFA0
- Conteneurs #C8322B, #2F63B8, #E3872A, #E6E1D6
- Pont #8D959B, hazard #F2B51D/#2A2622
- Coque #A13326/#22262B
- Enseignes #F1E2C0 on #B8322A
- Auvents #3E7BB5/#E9DFC9
- Pneus #2B2724
- Vitres #3C5A6E
- Sauge #8E9464

**Rules:**
- **Ink:** baked from UV borders, curvature and normals, 3–8 texels. Hand-finished on landmarks only.
- **Wear:** convex edges 12–18% lighter, 1–3 cm wide; 10–25% of them chip.
- **Grime:** from AO and height over the bottom 40 cm, with drips. Dirt #6B5236, at most 20% darker.
- **Detail:** base noise ≤ ±6%, nothing under 4 cm.

## 7. Map palettes

Format: sky zenith→horizon; sun colour/elevation; shadow; materials.

- **08 Cargo Ship** (flagship, late morning at sea): #3E86E0→#CDE8F8; #FFF0C8/45°; #5A6EA8. One container colour per quadrant, sea #1E7FA0.
- **07 Wasteland** (flagship, late-afternoon oil town): #2F74D8→#BFDDF2; #FFD99A/32°; #5B6CA6. Sand, rust, faded blue tin.
- **01 Port-Ferraille** (morning, fog removed): #4A8FE0→#D6ECF6; #FFF1D0/40°; #5F71A8. Quay #BBA98C, hulls #2E8C86.
- **02 Val-Poussière** (golden hour): #3C7FD9→#F2D7A8; #FFC98A/28°; #6A63A0. Adobe #D08F5A, shutters #3FA3A0.
- **03 Saint-Ombre** (after a storm, the darkest map): #3F6F86→#F0B860; #FFB870/25°; #3E4F7A. Brick #A5492F, lamps #FFB347.
- **04 Col du Vautour** (alpine noon): #1F63D0→#CFE6F7; #FFF6E0/42°; #6C86C8. Snow #F1F4F8/#A9BCE3, cabins #B83A2C.
- **05 La Fosse** (quarry): #3A80DC→#D3E7F5; #FFE0A6/50°; #6072AE. Limestone #E3D3AE, ochre #C9853F.
- **06 Le Belvédère** (dawn): #5A8FD8→#FFD9A0; #FFD3A0/25°; #5E6AA8. Terracotta #C4603A, zinc #8FA3B0.

## 8. Props by theme

- **Desert:** pickups, FUEL/GAS signs, pumps, derricks, cranes, shacks with awnings, water tower, barrels, power poles, pipes. Wagons at Val-Poussière, an excavator at La Fosse.
- **Port:** containers, gantry cranes, bollards, lifebuoys, pallets, forklift, boats.
- **Mountain:** snowcat, cabins, radio mast.
- **Town:** chimneys, water towers, scaffolding.

**Placement:** dense outside lanes and above 3 m; nothing human-like at 1.5–1.9 m; one saturated colour per prop.

## 9. Readability

1. **Reserved hues:** the world never uses OKLCH hue 300–355° or 105–145° above C 0.08. Lint it per map.
2. **Enemy highlight**, the player's choice: Magenta #FF3DC8 (default) or Citron #C8FF1F.
   - Minimum ΔE against 20 world colours (normal/protan/deutan/tritan): Magenta 23.5/2.9/5.9/9.1, Citron 19.1/16.3/11.2/5.5.
   - Citron is recommended for protan and deutan players.
   - Red is excluded: 0.9 against rust for protans.
3. **Never hue alone:** enemies have a coloured contour and no nameplate; allies have a plain contour and a ● chip.
4. **Value gate:** at 30 m, the enemy contour must reach ≥ 3:1 against its background in ≥ 90% of sampled shots.
5. **FX:**
   - Smoke is cream (#EDE4CF).
   - Abilities use ally blue or the highlight only.

## 10. Characters

- **Outfits:** one saturated colour over 30–45% of the body, gear in #2A2522, one light accent.
- **Agent colours:** Vif #E8703F, Choc #C23B2E, Roc #2F6FC0, Baume #F2C53D. Guet moves to #2E8C7A and Verrou to #4B4FA8, since both old colours fell in reserved bands.
- **Role shapes:** crest helmet (Entrée), backpack (Contrôle), satchel (Soutien).
- **Team cue:** per-viewer shoulder panels, ally blue with ● or highlight with ▼.

## 11. UI v2

Charcoal pages, red brush headers, white condensed italic titles, bulleted caps labels.

**Colour** (contrast on `panel`):
- **Surfaces:** `bg` #101113, `panel` #1A1B1E, `panel_hi` #232428, `rule` #2E3034.
- **Text:** `text` #F2EFE9 (15.0:1), `text_dim` #A9A6A0 (7.1:1), `disabled` #6E6C68 (3.3:1).
- **Brush:** `brush` #C8242C (white text on it 5.6:1), `pressed` #9E1C22, `bullet` #E23B33 (4.0:1).
- **Game:** `ally` #3B8BFF (5.2:1), Magenta 5.5:1, Citron 14.6:1, `objective` #F2C230.
- Red means brand or low HP; errors use a yellow ⚠.

**Type (OFL):**
- Titles: Barlow Condensed ExtraBold Italic in caps. Add the italic files ([Barlow](https://github.com/jpt/barlow)); no new family.
- Labels: Barlow Condensed SemiBold caps. Numbers: ExtraBold, tabular. Sentences: Barlow Semi Condensed.
- Protest Revolution for onomatopoeia only. Lato is dropped.
- Scale 20–95 (ratio 1.25) at 1080p; the 20 floor gives 13 px at 800p.

**Shapes:**
- **Panels:** radius 2, a 1 px rule, never nested.
- **Brush bar:** a NinePatch at 1.5× title height, bleeding off the panel with a 64 px dry tail, e.g. "07. WASTELAND".
- **Labels:** each takes a red bullet.
- **Spacing:** multiples of 6.

**States:**
- **Hover:** `panel_hi` + bullet. **Pressed:** 2 px down. **Selected:** brush underline.
- **Focus-visible (gamepad):** brush underlay + 2 px outline, offset 4 px.
- **Disabled:** hatching + reason.
- **Loading:** the bar fills; after 1 s, "Connexion au serveur… 3 s".
- **Empty:** "Aucun ami en ligne — Inviter".
- **Error:** ⚠ "ÉCHEC", code, Réessayer.

## 12. HUD

- **Centre:** the middle 40%×40% holds only the crosshair, hitmarkers, damage arcs and the scope.
- **Chips:** white on sky is 2.3:1, so every element sits on a `bg` chip at 80% alpha.

```
+----------------------------------------------------------+
| [MAP]     [● ALLIÉS 7 | 1:42 | 5 ENNEMIS ▼]   [killfeed] |
|            .------------------------.                    |
|            |  centre zone, crosshair |                    |
|            '------------------------'                    |
| [VIF ▰▰▰▰▱ 100]     [sous-titres]      [▬ RAVAGE]        |
| [C][Q][E] [X 72%]                          25/90         |
+----------------------------------------------------------+
```

- **1920×1080:** minimap 240, ammo 61, HP 49, timer 39, killfeed 25 with 5 entries, chips 72. HP turns red under 30%.
- **1280×800:** 1920×1200 logical at ×0.667, same corners. Minimap 160 px, 4 killfeed entries, text ≥ 13 px.

## 13. Motion

- Cubic easing: 150 ms focus, 200 ms brush wipe (left to right), 250 ms reveal, 400 ms end page.
- Numbers snap; FX at 12 fps; the enemy contour never animates.
- Reduced motion: fades only.

## 14. Risks

1. **Colour noise** hides bodies. The value gate blocks release, starting with Cargo Ship.
2. **Colour-blind gaps:** Magenta against sky for protans (2.9), Citron on snow for tritans (5.5). Shape has to carry them.
3. **Texture memory:** about 4 MB per 1024² set, about 225 MB per map. Triplanar stays limited so the Deck holds 60 fps.
4. **Draw calls:** MultiMesh repeated props and merge static dressing per 16 m cell.
5. **Double lines** (creases over inks).
6. **Inking time:** baked baseline everywhere, about 20 landmarks inked by hand.

**Next:** an in-engine target image of Wasteland's blue spawn. That pass will update `Comic.gd`, `Cartoon.gd`, `ink_sky`, `ink_edges`, `Settings.enemy_color` (Magenta 0, Citron 1) and the fonts.
