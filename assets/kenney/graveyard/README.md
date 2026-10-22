# Модели и звуки Kenney для 3D-игры «Кладбище»

Всё от [Kenney](https://kenney.nl), лицензия CC0 (можно использовать как угодно, без указания автора),
взято из зеркала наборов Kenney на GitHub ([ETdoFresh/kenney.nl](https://github.com/ETdoFresh/kenney.nl)),
потому что сам kenney.nl из облака недоступен. Лицензии лежат рядом.

- `models/*.glb` — 46 моделей из *Graveyard Kit 3.0*: нежить (`zombie`, `skeleton`, `ghost`, `vampire`, ростом
  около 0,8 м, в игре увеличены), надгробия, кресты, склеп, гробы, сосны, камни, скамейки, фонари
  (`lightpostSingle`, `lanternCandle`, `fireBasket`), тыквы, ограда (`ironFence`), плитка дорожки (`road`). Godot импортирует `.glb` сам.
  Кладбище расставляет их кодом `game/gy_game.gd`, врагов собирает `game/gy_enemy.gd`.
- `sounds/*.ogg` — `bolt` (zap1) и `hurt` (lowDown), `pickup` (pepSound3), `levelup` (powerUp5), `over`
  (lowThreeTone) из *Digital Audio*; `hit` (impactPunch_medium) , `die` (impactSoft_heavy), `boss`
  (impactBell_heavy) из *Impact Sounds*; `win` (jingles_PIZZI00) из *Music Jingles*; `swing` (knifeSlice)
  из *RPG Audio*; `click` (click1) из *UI Audio*. Добавлены позже: `die_zombie` (impactSoft_heavy_001), `die_skeleton`
  (impactPlank_medium_001), `die_elite` (impactBell_heavy_001), `punch` (impactPunch_medium_002), `step0`–`step3`
  (footstep_grass_000–003) из *Impact Sounds*; `die_ghost` (phaserDown2), `soul` (twoTone1), `heal` (powerUp7), `relic`
  (powerUp11), `alert` (zapThreeToneDown), `elite` (lowThreeTone) из *Digital Audio*; `windup` (drawKnife1) из *RPG Audio*;
  `hover` (rollover2), `select` (switch6) из *UI Audio*.

Герой лежит отдельно в `assets/kenney/characters` (*Blocky Characters*: `basicCharacter.gltf` и 8 скинов-картинок
в `skins/`; скин накладывается кодом как `albedo_texture` с фильтром NEAREST, конечности качаются через
шарниры-узлы, см. `game/gy_hero.gd`).
