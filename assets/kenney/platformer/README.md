# Картинки Kenney для 2D-примера

Спрайты (готовые картинки) от [Kenney](https://kenney.nl), лицензия CC0: можно использовать как угодно,
в том числе в продаваемой игре, без указания автора. Взяты из зеркала наборов Kenney на GitHub
([ETdoFresh/kenney.nl](https://github.com/ETdoFresh/kenney.nl), снимок 2020 г.), потому что сам kenney.nl
из облака недоступен. Рядом лежат файлы License из каждого набора.

- `player_stand/walk1/walk2/jump/duck/cheer1.png` — человечек «Player» из набора *Platformer Characters 1*
  (80×110, ноги у нижнего края). В игре их собирает в анимацию `game/hero_sprite2d.gd`.
- `coinGold.png`, `hudCoin.png`, `grassMid.png`, `grassCenter.png`, `brickGrey.png`, `colored_grass.png` — из
  *Platformer Pack Redux* (плитки 128×128). У фона `colored_grass.png` верх сделан прозрачным
  (плавно от 300 до 560 px), чтобы холмы сливались с небом-градиентом из `game/sky2d.gd`.
- `cloud1/2/3.png` — из *Background Elements Redux*.

Плитки земли и кирпичи кладутся `TextureRect` с `stretch_mode` = TILE и `texture_repeat` = ENABLED,
в описании сцены это `{"texture": "res://assets/kenney/platformer/grassMid.png", "stretch_mode": 1, "texture_repeat": 2}`.
