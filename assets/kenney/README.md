# Модели Kenney

Готовые 3D-модели в формате glTF (`.glb`) от [Kenney](https://kenney.nl), лицензия CC0 (можно использовать
как угодно, без указания автора). Взяты из его стартовых наборов для Godot 4 на GitHub (код наборов — MIT,
рядом лежат их файлы LICENSE):

- `racing/` — из [Starter Kit Racing](https://github.com/KenneyNL/Starter-Kit-Racing): грузовички
  `vehicle-truck-red/yellow/green/purple.glb`, мотоцикл `vehicle-motorcycle.glb`, лес `decoration-forest.glb`.
  У машин дети `body`, `underside`, `wheel-front-left`, `wheel-front-right`, `wheel-back-left`, `wheel-back-right`;
  перёд машины смотрит в +Z, длина кузова 2,8 единицы (в игре масштаб 1,4 → 3,9 м).
- `city/` — из [Starter Kit City Builder](https://github.com/KenneyNL/Starter-Kit-City-Builder): домики
  `building-small-a…d.glb`, гараж `building-garage.glb`, деревья `grass-trees.glb`, `grass-trees-tall.glb`,
  фонтан `pavement-fountain.glb`. Каждая модель занимает плитку 1×1 (в игре масштаб 6–8).

Текстура `Textures/colormap.png` в каждой папке нужна моделям (ссылка внутри `.glb`), не переносить.
Godot импортирует `.glb` сам при открытии проекта; в описаниях сцен модель вставляется операцией
`{"op": "instance", "scene": "res://assets/kenney/racing/vehicle-truck-red.glb", ...}` как обычная сцена.
