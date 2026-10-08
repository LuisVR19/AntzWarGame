# Avance del cliente Godot (handoff)

**Fecha:** 2026-10-07
**Estado:** **ejecutado y verificado en Godot 4.7.2** (Windows, renderer Compatibility). Compila sin errores, 30/30 tests en verde y el flujo completo se revisó con capturas de pantalla (ver §11).

Este documento explica qué hay, qué se verificó, qué no, y qué hacer primero en una máquina con Godot 4.

---

## 1. Resumen rápido

| Área | Estado |
|------|--------|
| Estructura del proyecto, `project.godot`, escenas `.tscn` | ✅ escrito a mano (texto) |
| Datos centralizados (terreno, ejército, reglas, mapa) en JSON | ✅ |
| Modelo de datos: `DivisionData`, `Order`, `BattleState`, `MapData`, `TerrainTable`, `GameEvent` | ✅ |
| Sistema de órdenes como datos (MOVE, ATTACK, DEFEND, RETREAT, HOLD) | ✅ |
| Simulación local aislada (`LocalGameSimulation`), que imita al servidor | ✅ |
| Capa de red (`NetworkManager` + `NetworkGameState`) para el servidor Go | ✅, protocolo validado contra el servidor real |
| Mapa con formas: llanura, bosque, colinas, agua (obstáculo), bases (hormigueros) | ✅ |
| Divisiones como "colonias de hormigas" (puntos), barras de fuerza/moral, nombre, cantidad | ✅ |
| Selección, línea de orden, radio de movimiento | ✅ |
| Cámara: zoom, pan, límites | ✅ |
| UI: barra superior, panel de división con botones, registro de eventos, pantalla de fin | ✅ |
| Modo debug (F3) | ✅ |
| Tests automáticos (unitarios, integración y prueba de humo de escenas), ejecutables en headless | ✅ 30/30 OK |
| **Probado ejecutando en Godot** | ✅ Godot 4.7.2 |
| Ajuste visual (tamaños, colores, legibilidad) | ✅ primera pasada (nombres cortados corregidos) |
| Ataque local a través del río | ⚠️ se detiene en el agua (sin pathfinding local, ver §11) |

---

## 2. Qué se verificó sin Godot

1. **Sintaxis GDScript:** los 47 scripts (39 del juego + 8 de tests) pasan el parser de `gdtoolkit` 4.x (`gdparse`).
2. **Lint:** `gdlint` sin errores, con la configuración en `gdlintrc` (líneas de hasta 130 caracteres).
3. **Referencias cruzadas** (con un script propio basado en expresiones regulares):
   - todos los `res://...` existen;
   - cada `$Nodo` de un script existe como hijo en su escena;
   - cada `Clase.miembro` y `variable_tipada.miembro` existe en la clase;
   - cada señal conectada está declarada;
   - no hay `class_name` duplicados.
4. **Protocolo contra el servidor Go real** (`../game.server`): un script Python envió exactamente los mensajes que genera el cliente (`Order.to_message()`, `Protocol.*`). Verificó create, join, lobby, ready, game_started, las 5 órdenes, errores y snapshots, y que la respuesta trae todos los campos que lee el parser del cliente. **Resultado: OK.**

**Lo que NO se pudo verificar** (lo detecta solo el motor):
- errores de tipos estáticos del analizador de Godot (inferencia con `:=`, arrays tipados);
- nombres de métodos o propiedades de la API de Godot mal escritos;
- el aspecto visual: posiciones de la UI, tamaños de fuente, solapamientos;
- la lógica de la simulación local en ejecución (no hay tests automáticos todavía).

---

## 3. Primeros pasos en la máquina con Godot (checklist)

1. Instalar **Godot 4.3 o superior** (versión estándar, no .NET).
2. Abrir `game.client/project.godot` desde el Project Manager (*Import*).
   - La primera vez Godot escanea el proyecto, crea `.godot/` y registra los `class_name`. **No ejecutar en modo headless antes de abrirlo en el editor**, o las clases globales no estarán registradas.
   - Godot puede añadir `uid=` a las escenas y crear archivos `.uid` (4.4+). Es normal; conviene hacer commit de esos cambios.
3. Revisar el panel **Errores / Depurador** y la pestaña *Output*. Corregir lo que marque el analizador (ver sección 7, riesgos).
4. **Ejecutar los tests** (sección 10). Son la forma más rápida de detectar errores de ejecución antes de probar a mano.
5. Pulsar **F5**. Debería aparecer el menú principal.
6. **Partida local:** botón "Partida local (sin servidor)". Seguir el guion de la sección 4.
7. **Contra el servidor:** en `../game.server` ejecutar `go run ./cmd/server`. Abrir dos instancias del juego (en Godot: *Debug → Customize Run Instances… → 2*) y usar "Conectar": una con ID vacío (crea la partida) y la otra con el ID que aparece en la barra superior de la primera. Pulsar "¡Listo!" en ambas.
8. Opcional: crear un `Theme` y una fuente propia, y ajustar `scripts/core/palette.gd`.

---

## 4. Guion de prueba manual (resultado esperado del prompt)

| # | Acción | Qué debería verse |
|---|--------|-------------------|
| 1 | Menú → Partida local | Mapa de 2000×1200 con río, bosques, colinas y dos hormigueros. Cuenta atrás de 2 s en la barra superior |
| 2 | — | 3 divisiones azules (izquierda) y 3 rojas (derecha) |
| 3 | Clic izquierdo en una división azul | Anillo amarillo, círculo de radio de movimiento y estadísticas en el panel derecho |
| 4 | — | Panel con Cantidad, Fuerza, Defensa, Moral, Velocidad, Fatiga, Estado y Orden |
| 5 | Botón MOVER (o tecla 1) y luego clic en el mapa; o directamente clic derecho en el mapa | Línea discontinua hasta el destino. Log: "X recibió orden de movimiento" |
| 6 | — | La división avanza (más lento en bosque y colina); al llegar: "X llegó a su destino" |
| 7 | Clic izquierdo en una división roja | Se ven sus datos; los botones aparecen deshabilitados (no es tuya) |
| 8 | Seleccionar una azul → ATACAR (2) → clic en una roja; o clic derecho sobre la roja | Línea roja hacia el objetivo; la división persigue |
| 9 | — | Al entrar en rango: marcador naranja pulsante. Log: "X detectó al enemigo: combate iniciado…" |
| 10 | — | Cada segundo, "Ronda N: …". Bajan la cantidad, la moral y las barras, y desaparecen hormigas |
| 11 | Durante el combate: DEFENDER (3), RETIRARSE (4) o MANTENER (5) | Cambia el estado. MOVER/ATACAR en combate se rechazan con un mensaje |
| 12 | — | Todo aparece en el registro inferior. Con moral baja la división "se desbanda" y huye sola |
| extra | Tab | Cambia el jugador controlado (hot-seat) para mover también al ejército rojo |
| extra | F3 | Debug: FPS, número de divisiones, tick, terreno bajo el cursor y datos por división |
| extra | Rueda / WASD / flechas / arrastrar con el botón central | Zoom hacia el cursor, desplazamiento y límites del mapa |

La partida termina cuando un ejército queda aniquilado (aparece el panel de victoria o derrota).

---

## 5. Arquitectura

```
res://
  project.godot
  gdlintrc                       config de gdlint (gdtoolkit)
  data/definitions/              DATOS (única fuente de valores)
    terrain.json                 modificadores de terreno
    army.json                    divisiones iniciales por jugador
    rules.json                   reglas de la simulación local (= servidor)
    map_default.json             mapa 40x24 (mismo que el servidor)
  scenes/
    main/main.tscn               menú + cambio a batalla
    battle/battle.tscn           escena de batalla
    units/division_view.tscn     vista de una división
    ui/*.tscn                    hud, top_bar, division_panel, event_log, debug_overlay, game_over_panel, main_menu
  scripts/
    core/       modelo y abstracciones (sin presentación)
      game_state_source.gd       ★ interfaz que usa la UI (señales + parser del protocolo)
      battle_state.gd  division_data.gd  order.gd  map_data.gd  terrain_table.gd  game_event.gd
      game_types.gd  definitions.gd  input_actions.gd  palette.gd  main.gd
    simulation/ simulación local (mock del servidor)
      local_game_state.gd        GameStateSource que ejecuta la simulación en el proceso
      local_game_simulation.gd   reglas: órdenes, movimiento, encuentros, combate, moral, victoria
      movement_system.gd         movimiento en línea recta (reemplazable)
      combat_resolver.gd         fórmula de combate (misma que el servidor)
    network/
      network_manager.gd         WebSocket + JSON (no sabe nada del juego)
      network_game_state.gd      GameStateSource contra el servidor Go
      protocol.gd                constantes y constructores de mensajes
    battle/     presentación del campo de batalla
      battle_controller.gd       ★ conecta fuente ↔ vistas ↔ input ↔ HUD; convierte intenciones en Orders
      map_view.gd  terrain_painter.gd  battle_layer.gd  division_layer.gd
      battle_camera.gd  battle_input.gd  selection_manager.gd
    units/      division_view.gd  division_shape.gd  division_overlay.gd
    ui/         hud.gd  top_bar.gd  division_panel.gd  event_log.gd  debug_overlay.gd
                game_over_panel.gd  main_menu.gd  event_formatter.gd  ui_style.gd
  resources/  assets/placeholder/   vacíos (reservados para assets)
```

### Flujo de datos

```
     BattleController  ──submit_order(Order)──▶  GameStateSource
          ▲                                       │  _send(dict del protocolo)
          │ señales: state_updated,               ▼
          │ division_changed, game_event,  ┌───────────────┬──────────────────┐
          │ order_rejected, game_finished  │ LocalGameState│ NetworkGameState │
          │                                │  (simulación) │ (WebSocket → Go) │
          └──── _handle_message(dict) ◀────┴───────────────┴──────────────────┘
```

**Decisión clave:** la simulación local **habla el mismo protocolo JSON que el servidor**. Recibe los mensajes del cliente y devuelve mensajes del servidor (`game_state`, `division_updated`, `battle_started`…). Así, ambas fuentes comparten el mismo parser (`GameStateSource._handle_message`) y la UI no distingue entre las dos. Pasar de `LocalGameSimulation` a `NetworkGameState` no requiere tocar la UI (el menú ya ofrece ambas).

### Puntos de reemplazo para assets

| Placeholder | Dónde | Reemplazo futuro |
|-------------|-------|-----------------|
| Terreno con formas | `battle/terrain_painter.gd` (lo usa `map_view.gd`) | `TileMapLayer` con un tileset; `MapData` no cambia |
| Cuerpo de la división (puntos/hormigas) | `units/division_shape.gd` (nodo `Shape`) | `Sprite2D`/`AnimatedSprite2D` o partículas en `division_view.tscn` |
| Etiquetas y barras | `units/division_overlay.gd` | Controles o sprites de UI |
| Colores y tamaños | `core/palette.gd` | Theme / recursos |

---

## 6. Diferencias respecto al prompt original (decididas a propósito)

1. **Protocolo:** el prompt proponía `move_division` con `"target": {x, y}` y eventos envueltos en `{"type": "event", "event": …}`. El servidor Go **ya existe** y usa `x`/`y` planos y un `type` por evento (`battle_started`, …). El cliente sigue al servidor real; la referencia está en `../game.server/README.md`.
2. **Estados y órdenes** en MAYÚSCULAS internamente; en el JSON viajan en minúsculas (como manda el servidor). La conversión está en `GameTypes.from_wire/to_wire`.
3. **Simulación local = reglas del servidor** (moral, desbandada, reagrupamiento, posturas, rango de combate), pero con **movimiento en línea recta**: el agua bloquea y la división se detiene. Contra el servidor hay pathfinding A* y el cliente dibuja la ruta que recibe (`path`).
4. **"Obstáculos"** = agua (el río con dos vados), que es el único terreno intransitable del servidor.
5. **Bases** = hormigueros dibujados en los puntos de despliegue. Son decorativos: no hay mecánica de base, igual que en el servidor.
6. **"Tener dos jugadores" en local** = *hot-seat* (Tab cambia el jugador controlado). No hay IA, porque el prompt la excluye.
7. **Recursos ficticios** en la barra superior: no se añadieron (el prompt decía "si son necesarios").
8. **Acciones de entrada** registradas por código (`InputActions.ensure()`), no en `project.godot`, para no escribir a mano los eventos serializados. Se pueden mover al *Input Map* del editor después.
9. **Nombres de divisiones** sin tildes ni ª en `army.json`, para evitar problemas de codificación hasta probar las fuentes.

---

## 7. Riesgos conocidos y qué revisar primero

Ordenados de más a menos probable:

1. **Avisos o errores del analizador estático.** El código usa tipado estático con cuidado: nada de `:=` sobre `Variant`, y los arrays tipados solo se llenan con `append`. Aun así, Godot puede marcar casos puntuales. Suelen arreglarse con un cambio de una línea (`var x: Tipo = ...`).
2. **Constantes de otra clase en expresiones `const`**, por ejemplo `const TOP := -(DivisionShape.RADIUS + 40.0)` en `division_overlay.gd`. Si Godot se queja, sustituirlo por el literal `-64.0`.
3. **Tamaño y legibilidad del texto** en el mapa con zoom. La escala de las etiquetas se ajusta inversamente al zoom (`DivisionLayer.set_label_scale`); revisar los límites `0.6..2.5` en `battle_controller.gd`.
4. **Posición de los paneles** con otras resoluciones: los anclajes están definidos por código en `_ready()` de cada panel (`top_bar.gd`, `division_panel.gd`, etc.).
5. **Exportar el juego:** los `.json` de `data/` no son recursos de Godot. En el preset de exportación hay que añadir `data/*.json` en *Filters to export non-resource files*.
6. `draw_dashed_line` y `ThemeDB.fallback_font` existen desde Godot 4.0 o 4.1, así que no deberían dar problemas en 4.3.

---

## 8. Siguientes pasos sugeridos (después de que funcione)

- Reconexión automática a la partida usando el `session_token` (ya se guarda en `GameStateSource.session_token`; falta reintentar tras una desconexión).
- Selección múltiple: `SelectionManager` ya trabaja con listas; faltan la selección por arrastre y el envío de una orden por cada división.
- Pathfinding en la simulación local (sustituir `MovementSystem` por `AStarGrid2D`), o usar siempre el servidor.
- Niebla de guerra: el servidor ya filtra la información por jugador; en el cliente bastará con no dibujar lo que no llega.

## 9. Herramientas de validación estática (reproducibles sin Godot)

```bash
pip install "gdtoolkit==4.*"
gdparse scripts/**/*.gd      # sintaxis
gdlint scripts               # estilo (usa ./gdlintrc)
```

---

## 10. Tests automáticos

Usan un runner propio, sin plugins: `tests/run_tests.gd` y `tests/framework/test_case.gd`.

```bash
# 1) Una sola vez: registrar las clases globales (class_name).
#    Basta con abrir el proyecto en el editor, o en terminal:
godot --headless --path . --editor --quit

# 2) Ejecutar todos los tests (código de salida 0 = OK, 1 = fallos)
godot --headless --path . --script res://tests/run_tests.gd

# Solo los archivos cuya ruta contiene un texto:
godot --headless --path . --script res://tests/run_tests.gd -- --filter=simulation
```

| Archivo | Qué cubre |
|---------|-----------|
| `tests/unit/test_terrain_map.gd` | valores de terreno desde JSON, mapa por defecto (río, vados, bosque, colina, bases), ida y vuelta del protocolo del mapa |
| `tests/unit/test_protocol_parsing.gd` | `Order.to_message()` igual al protocolo del servidor, `DivisionData`/`BattleState` desde mensajes reales del servidor, parser de `GameStateSource` (sesión, lobby, errores, victoria/derrota/empate) |
| `tests/unit/test_movement_combat.gd` | velocidad por terreno, bloqueo por agua, sin pasarse del destino; combate simétrico, determinista, terreno, posturas, moral y límites de bajas |
| `tests/unit/test_local_simulation.gd` | cuenta atrás, validación de órdenes (10 casos de error), orden aplicada en el siguiente tick, llegada, cambio de órdenes, río que bloquea, encuentro y combate, persecución, restricciones en combate, retirada, destrucción y victoria, desbandada y reagrupamiento, límite de tiempo, partida completa con guion (determinismo + invariantes) |
| `tests/integration/test_local_game_state.gd` | `LocalGameState` completo a través de sus señales: inicio, órdenes, movimiento, rechazo `not_owner`, hot-seat |
| `tests/integration/test_battle_scene.gd` | **prueba de humo de las escenas reales**: menú → batalla local → seleccionar → clic derecho (MOVER) → modo ATACAR → división enemiga con botones deshabilitados → debug → zoom → volver al menú |

Notas:
- Cada test termina con `return done()`. Si un error de ejecución lo aborta, el runner lo marca como **abortado**; el detalle aparece como `SCRIPT ERROR` en la salida.
- Los tests acceden a algunos miembros privados (`_views`, `_by_id`…) a propósito, para comprobar el estado interno sin exponerlo en la API.
- Las coordenadas de los tests de simulación dependen de `data/definitions/map_default.json`. Si se cambia el mapa, hay que revisarlas.
- Para CI: cualquier imagen con Godot 4 en headless sirve (por ejemplo `barichello/godot-ci`) con los dos comandos de arriba.
- **Si fallan muchos tests a la vez**, empezar por el primer `SCRIPT ERROR` de la salida: suele ser un único problema de tipos que arrastra al resto.

---

## 11. Primera ejecución en Godot 4.7.2 (2026-10-07)

Correcciones aplicadas:
1. `local_game_simulation.gd` (`_update_battles`): `for b in battles.duplicate()` daba error de inferencia de tipos (`duplicate()` devuelve un `Array` sin tipo). Ahora es `for b: SimBattle in ...`. Era el único error del analizador.
2. `division_overlay.gd`: los nombres largos salían cortados ("1a Division Obrer"). El texto ahora usa un ancho propio (`TEXT_WIDTH`), independiente del de las barras.
3. `battle_controller.gd`: el registro decía "Controlas a player-1", porque `game_created` llega antes que `lobby_updated` (también con el servidor real). El anuncio ahora espera a que se conozca el nombre del jugador.
4. Godot generó los archivos `*.gd.uid` (4.4+). Deben incluirse en el commit.

Limitación observada: en la partida local, una orden ATACAR contra un enemigo al otro lado del río va en línea recta y la división se detiene en el agua ("se detuvo: terreno intransitable"). Para llegar al combate hay que mover antes la división por un vado. Contra el servidor Go no ocurre, porque este usa A*. La solución sería sustituir `MovementSystem` por `AStarGrid2D` (ver §8).

---

## 12. Migración a 2D isométrico (2026-10-07)

Solo cambió la **capa visual**. La simulación, el protocolo y el servidor siguen igual y trabajan en **coordenadas de mundo** (50 unidades por casilla).

### Espacios de coordenadas

```
Mundo (simulación / servidor)  →  Grid (mundo / cell_size)  →  Pantalla isométrica (vistas)
                   ↑ toda conversión pasa por scripts/core/iso_projection.gd ↑
screen.x = (gx - gy) * tile_width / 2      screen.y = (gx + gy) * tile_height / 2
```

- Los clics llegan en pantalla y `BattleController` los convierte a mundo con `IsoProjection` antes de crear una `Order`.
- Las vistas suavizan la posición en **mundo** y la proyectan en cada frame (`DivisionView.world_position`).
- La selección (hit-test) es de presentación: cada vista comprueba si el punto de pantalla cae dentro de su silueta.

### Escena de batalla

```
Battle (BattleController, visual_config = resources/visual_config.tres)
├── Map (MapView)
│   ├── Ground        TileMapLayer isométrico (64×32, DIAMOND_DOWN)
│   └── GroundMarks   cuadrícula, borde, rutas de órdenes, radio de movimiento
├── World             y_sort_enabled ← profundidad compartida
│   ├── Decorations   árboles (bosque) y rocas (colina), un nodo cada uno
│   ├── Buildings     MapObjectLayer + building_view.tscn
│   ├── Resources     MapObjectLayer + resource_view.tscn
│   └── Units         DivisionLayer + division_view.tscn
├── Effects           marcadores de batalla
├── Camera · SelectionManager · BattleInput · HUD
```

**Profundidad:** `World` y sus cuatro capas tienen Y-sort. Godot ordena juntos a sus nietos, así que un árbol, un edificio y una división se intercalan según su Y de pantalla. El origen de cada nodo es su punto de suelo: los pies de la unidad, el centro de la huella del edificio o la base del árbol. Verificado: una división al norte del cuartel queda tapada y otra detrás del hormiguero asoma parcialmente.
Para huellas cuadradas, ordenar por el centro de la huella es una aproximación correcta en los casos habituales. Si más adelante hubiera edificios muy alargados, habría que ordenarlos por tramos.

### Entidades

| Entidad | Nodos | Datos |
|---------|-------|-------|
| División | `Shadow`, `SelectionIndicator`, `Visual` (DivisionShape), `HealthBar` | `DivisionData` (sin cambios) |
| Edificio | `SelectionIndicator` (huella), `Visual`, `HealthBar` | `BuildingData` + `data/definitions/buildings.json` (1×1, 2×2, 3×3) |
| Recurso | `SelectionIndicator`, `Visual`, `HealthBar` | `ResourceNodeData` + `resources.json` (oro, madera, piedra, comida) |

- Colocación: `data/definitions/map_objects.json`. Siempre hay un hormiguero (3×3) centrado en cada spawn; el resto solo se coloca si el mapa mide 40×24.
- **Edificios y recursos son solo del cliente:** no bloquean el movimiento ni se pueden atacar o recolectar (el prompt excluye la economía). Las divisiones pueden atravesarlos. Para que bloqueen haría falta cambiar la simulación y el servidor.
- Las etiquetas de edificios y recursos solo se muestran al seleccionarlos, para no saturar el mapa.

### Assets

`EntityVisual` dibuja una textura si el archivo existe y, si no, el placeholder. Las rutas y los anclajes están en `assets/README.md`. El terreno usa un atlas generado en memoria mientras no exista `assets/terrain/terrain_atlas.png`.

### Configuración

`resources/visual_config.tres` (`VisualConfig`) reúne el tamaño de tile, el zoom mínimo y máximo, el paso de zoom, la velocidad de cámara, el margen del desplazamiento por bordes, las escalas de unidades, edificios, recursos y decoraciones, la escala de etiquetas, el grosor de la selección y las rutas de assets. Los colores siguen en `Palette`.

### Terreno pedido → terreno del juego

Hierba = PLAIN · Árboles = FOREST (suelo + árboles) · Piedra = HILL (suelo pedregoso + rocas) · Agua = WATER.
"Obstáculos": el agua sigue siendo el único terreno intransitable. Un tipo de obstáculo nuevo requeriría cambiar la lógica y el servidor, por eso no se añadió.

### Otros cambios

- Corregido: las órdenes aparecían en el registro con "00:00", porque `order_accepted` no trae `tick` (tampoco en el servidor Go). Ahora se usa el tick actual.
- `division_overlay.gd` → `entity_overlay.gd` (genérico) y `terrain_painter.gd` → `terrain_tileset.gd`.
- Tests: 36/36 en verde (nuevo `tests/unit/test_iso_projection.gd`; `test_battle_scene.gd` ahora hace clics en pantalla isométrica y comprueba el TileMap, el Y-sort y la selección de edificios y recursos).
- Rendimiento medido: unos 59 FPS (límite de vsync), tanto en la vista normal como con el mapa entero en pantalla.

### Pendiente o limitaciones

- La selección múltiple sigue sin existir. Cada vista ya tiene su propio indicador, así que al añadirla bastará con seleccionar varias.
- ~~En la partida local no hay pathfinding~~ → resuelto en §14.

---

## 13. Controles: arrastre con clic derecho y menú de órdenes (2026-10-07)

- **Clic derecho + arrastrar** desplaza el mapa. `BattleInput` distingue entre arrastre y clic: si el ratón se mueve más de `camera_drag_threshold` (6 px, en `visual_config.tres`) con el botón pulsado, es un arrastre y emite `pan_requested`, que llega a `BattleCamera.pan_screen`. Si no se mueve, al soltar sigue siendo la orden rápida (mover o atacar).
- **Menú de órdenes** (`scripts/ui/division_action_menu.gd`, nodo `HUD/ActionMenu`): se abre al hacer clic izquierdo en una división propia, sigue a la división en pantalla y emite la misma señal `order_requested` que el panel derecho y las teclas 1–5. Se cierra al elegir una orden, con Esc, al cambiar la selección o cuando la división deja de poder recibir órdenes (destruida, fin de partida, cambio de jugador).
- **MOVER / ATACAR con clics:** tras elegir la orden, `GroundMarks` dibuja una línea discontinua desde la división hasta el cursor (blanca para mover, roja para atacar) hasta que se hace el clic de destino.
- Tests: `test_battle_scene.gd` cubre el menú (DEFENDER inmediato y MOVER con clic de destino), el arrastre con clic derecho (mueve la cámara sin dar órdenes) y el clic derecho corto (sigue dando la orden).

---

## 14. Rutas que rodean obstáculos, y dividir/unir divisiones (2026-10-07)

### Rutas (simulación local)

- `scripts/simulation/pathfinder.gd`: A* sobre las casillas con `AStarGrid2D`, con las mismas reglas que `game.server/internal/movement/pathfinding.go`. El agua es sólida, no se cortan esquinas en diagonal y una casilla cuesta 1 / su modificador de movimiento, así que se evitan el bosque y la colina si hay un camino más rápido. Después la ruta se simplifica en pocos tramos rectos ("string pulling").
- `MovementSystem.follow()` recorre la lista de puntos de la ruta. MOVER y RETIRARSE la calculan al aplicarse la orden. ATACAR y UNIR la recalculan cuando el objetivo se aleja más de `path_recompute_distance` del final de la ruta. Si un tramo se bloquea, se recalcula; tras 4 intentos fallidos la orden termina con `blocked`.
- Un destino inalcanzable se rechaza al dar la orden (`unreachable`).
- La ruta viaja al cliente en el campo `path` de la división, igual que con el servidor, y se dibuja en el suelo.
- Rendimiento: unos 0,03 ms el A* y alrededor de 1 ms con el suavizado, para una ruta que cruza todo el mapa (medido en Godot 4.7.2).

### Dividir y unir (solo simulación local)

| Acción | Mensaje | Reglas |
|--------|---------|--------|
| DIVIDIR [6] | `split_division {division_id, ratio=0.5}` | Propia, viva, no desbandada ni en combate; cada parte ≥ `min_split_units` (300). La nueva aparece al lado con las mismas estadísticas y el nombre "X (2)". Evento `division_split {division, new_division}` |
| UNIR [7] + clic en otra propia | `merge_division {division_id, target_division_id}` | Es una orden: la división camina hasta la otra (estado MOVING) y, a `merge_range` (60) o menos, la absorbe. Las unidades y el máximo se suman; ataque, defensa, moral, experiencia y fatiga se promedian según el número de unidades; la velocidad es la del más lento. La absorbida desaparece y quien la perseguía pasa a perseguir a la resultante. Evento `divisions_merged {division, merged_division_id, merged_division_name}` |

- **El servidor Go no lo implementa todavía.** `GameStateSource.supports_split_merge()` devuelve `false` en red, y los botones DIVIDIR y UNIR se ocultan. Para llevarlo al servidor habría que replicar estos dos mensajes y eventos en `game.server`.
- Las reglas nuevas (`min_split_units`, `merge_range` y `path_recompute_distance`) están en `data/definitions/rules.json` y solo existen en el cliente.
- Tests: 44/44. Nuevos: `tests/unit/test_pathfinder.gd`. En `test_local_simulation.gd`: rodear el río, atacar al otro lado del río, dividir y unir. En `test_protocol_parsing.gd`: mensajes y eventos. `test_battle_scene.gd` prueba DIVIDIR desde el menú y UNIR. El antiguo `test_water_blocks_straight_line` se sustituyó, porque ahora la división rodea el río en lugar de detenerse.

---

## 15. Formaciones, orientación y tamaño según los soldados (2026-10-07)

Objetivo: que una división más grande no gane siempre. La posición, la orientación y la formación deben importar.

### Mecánicas (simulación local; `scripts/simulation/local_game_simulation.gd`)

1. **Orientación (`facing`).** Cada división mira hacia donde marcha. Al empezar, cada bando mira hacia el enemigo. En combate gira hacia su rival principal según el `turn_rate` de su formación.
2. **Lado del golpe.** `Formations.exposure()` compara la orientación con la dirección del enemigo: hasta 60° es **frente**, desde 120° **retaguardia** y entre medias **flanco**. La defensa se multiplica por `defense_front`, `defense_flank` o `defense_rear` según la formación.
3. **Frente de combate (`frontage`).** Solo luchan a la vez `min(soldados, frontage)`. El resto es reserva: no golpea, pero amortigua la pérdida de moral, que se calcula sobre el total. Una división de 6000 en línea golpea como una de 2000.
4. **Ataque por formación.** `attack` × `bonus_vs[formación enemiga]`; por ejemplo, la cuña contra el muro ×1,4.
5. **Cambiar de formación cuesta.** Durante `formation_change_seconds` (3 s) la división se reorganiza: ataque y defensa ×0,75 y velocidad ×0,5. Una división desbandada no puede cambiar de formación.

| Formación | Ataque | Def. frente / flanco / retaguardia | Velocidad | Frente | Giro | Idea |
|-----------|-------:|-----------------------------------:|----------:|-------:|-----:|------|
| Línea | 1,0 | 1,0 / 0,75 / 0,55 | 1,0 | 2000 | 60°/s | equilibrada |
| Muro de escudos | 0,75 | **1,7** / 0,6 / 0,45 | 0,6 | 1800 | 20°/s | frente impenetrable, costados débiles, gira lento |
| Cuña | **1,35** (×1,4 contra muro, ×1,15 contra línea) | 0,85 / 0,6 / 0,5 | 1,1 | 1000 | 45°/s | rompe defensas, defiende mal |
| Erizo | 0,7 | 1,25 / 1,25 / 1,25 | 0,45 | 1600 | 360°/s | sin flancos, casi inmóvil |
| Columna | 0,7 | 0,75 / 0,5 / 0,5 | **1,35** | 600 | 90°/s | para marchar, vulnerable |

Todos los valores están en `data/definitions/formations.json`. Los tiempos y penalizaciones de la reorganización están en `rules.json`.

Comprobado en el juego: una cuña que golpea a un muro por el flanco gana el intercambio (57 bajas causadas frente a 27 recibidas). Cuando el muro termina de girar hacia ella, el intercambio se invierte (20 frente a 27).

### Protocolo (solo local; el servidor Go aún no lo tiene)

- Cliente → `set_formation {division_id, formation}` (en minúsculas: `line`, `shield_wall`, `wedge`, `square`, `column`).
- Nuevos campos de la división: `formation`, `facing` (radianes, en el espacio del mundo) y `reforming`.
- Eventos: `division_updated` con los motivos `formation_changed` y `formation_ready`. `battle_started` incluye `attacker_exposure` y `defender_exposure`, y cada lado de `battle_updated` lleva `exposure`.
- `GameStateSource.supports_formations()`: en red devuelve `false` y el selector se oculta. Si el servidor no envía `formation`, el cliente asume Línea.

### Visual

- `DivisionShape` dibuja las hormigas con la forma de la formación (`FormationLayout`), giradas según la orientación, más una **flecha** que marca el frente. El muro lleva además una línea de escudos.
- **Tamaño según los soldados:** radio = `unit_radius × (soldados / unit_size_reference) ^ unit_size_exponent`, limitado entre `unit_radius_min` y `unit_radius_max` (en `visual_config.tres`). El exponente es 0,75: el doble de soldados da 1,68 veces el radio. Con 0,5 el área sería proporcional a los soldados; no se usa un crecimiento exponencial literal porque se dispararía. El número de hormigas dibujadas es proporcional a los soldados (`unit_soldiers_per_ant` = 60).
- UI: un selector de formación (`FormationPicker`) en el panel derecho y en el menú de la división, con un tooltip que explica cada una. La tecla **F** pasa a la siguiente formación. El registro indica los golpes "¡por el flanco!" o "¡por la retaguardia!" y marca `[flanco]` en las rondas.

Tests: 55/55. Nuevos: `tests/unit/test_formations.gd` (datos, lados del golpe, frente de combate, muro contra cuña, una división pequeña flanqueando a una grande, tamaño). Además, en la simulación se prueban el cambio con reorganización, la orientación al marchar y el flanco con el giro; en el protocolo, el mensaje y los campos; y en la escena, el tamaño y el selector.

---

## 16. Mapa grande, elección de ejército y tipos de hormiga (2026-10-07)

### Mapas (`data/definitions/maps.json`)

| id | Mapa | Origen |
|----|------|--------|
| `default` | Pequeño 40×24 (el original, que se mantiene) | `map_default.json` + `map_objects.json` |
| `large` | Grande 80×48 (2400×4000 unidades): río con 4 vados, 2 lagos por lado, bosques y colinas, **simétrico** | generado por `tools/generate_large_map.py` → `map_large.json` + `map_large_objects.json` |

Para modificar el mapa grande se edita el script (está pensado para retocarse) y se vuelve a ejecutar con `python tools/generate_large_map.py`. `MapObjects` busca los edificios y recursos en el catálogo según el tamaño del mapa.

### Ejércitos (`data/definitions/armies.json`, sustituye a `army.json`)

| id | Divisiones | Hormigas |
|----|-----------|----------|
| `small` (por defecto) | 3: el ejército original, que no cambia | 8.000 |
| `medium` | 6: de todos los tipos | 12.500 |
| `large` | 10: de todos los tipos | 21.000 |

Las entradas sin `offset` se despliegan automáticamente en columnas de 4 delante del spawn (`_deploy_slot`). Si una posición cae en el agua, se busca una cercana transitable. Los nombres se generan por tipo ("1a Arquera", "2a Arquera"...).

El menú principal tiene dos selectores (mapa y ejército) con una descripción. `LocalGameState.map_id` y `army_id` guardan la elección; vacíos significan los valores por defecto.

### Tipos de hormiga (`data/definitions/unit_types.json`, clase `UnitTypes`)

| Tipo | Ataque | Defensa | Velocidad | Moral | Particularidad |
|------|-------:|--------:|----------:|------:|----------------|
| Obrera | 10 | 12 | 30 | 80 | infantería básica |
| Soldado | 16 | 8 | 45 | 85 | mucho ataque |
| **Arquera** | 5 | 6 | 35 | 75 | **ataque a distancia**: alcance 220 (4,4 casillas), ataque del disparo 11 |
| **Acorazada** | 11 | **22** | 20 | 95 | tanque: lenta, casi no se desmoraliza |
| **Exploradora** | 9 | 7 | **70** | 70 | rapidísima: flanquear y cazar arqueras |

- **Arqueras:** cada `combat_round_ticks` (1 s) disparan al objetivo de su orden ATACAR si está a tiro; si no, al enemigo más cercano dentro del alcance. No disparan si están marchando, en retirada, desbandadas o en cuerpo a cuerpo. Con ATACAR se acercan solo hasta el 90 % de su alcance.
- **Daño del disparo:** `CombatResolver.resolve_volley`. Solo sufre el objetivo: bajas = soldados que disparan (según el frente de su formación) × 0,02 × `volley_casualty_factor` (0,6) × ataque/defensa. La formación y el lado del golpe también cuentan: un muro de escudos de frente aguanta muy bien el ácido. Un disparo puede destruir o desbandar al objetivo.
- Evento `volley {shooter_id, target_id, losses, unit_count, exposure, from, to}`. El cliente lo anota en el registro y dibuja el proyectil de ácido (`BattleLayer.add_volley`). Al seleccionar una arquera se ve su alcance en verde.
- **Unir:** solo divisiones del mismo tipo (`type_mismatch`). Dividir conserva el tipo.
- Campo nuevo de la división: `unit_type` (en minúsculas). Si el servidor Go no lo envía, el cliente asume Obrera.
- **Aspecto:** `look` en `unit_types.json` define el tamaño de la hormiga, el tamaño de la cabeza y una marca ("acid" para el ácido de las arqueras, "armor" para el borde claro de las acorazadas, "stripe" para el cuerpo alargado con raya de las exploradoras). La etiqueta muestra el tipo ("~1.5k · Arquera") y el panel tiene una fila "Tipo" con tooltip.

### Rendimiento (problema encontrado y resuelto)

El mapa grande con el ejército grande iba a **34 FPS** con todo el mapa en pantalla. La medición (sin vsync, con `viewport_get_measured_render_time_*`) mostró que el coste estaba en el render: cada árbol eran 5 primitivas y cada hormiga 2-3, unas 5000 llamadas de dibujo que Godot no puede agrupar.

- `scripts/units/placeholder_sprites.gd` rasteriza una sola vez en memoria (a 3× de resolución) el árbol, 4 variantes de roca y un atlas de hormigas por tipo en 8 direcciones (en grises, teñido con el color del bando; el ácido va en un atlas aparte sin teñir). Dibujar texturas se agrupa en muy pocas llamadas.
- `DecorationLayer` agrupa los árboles y rocas de cada diagonal isométrica en un solo nodo: 659 objetos en 85 nodos, manteniendo el orden de profundidad por fila.
- Resultado: mapa grande con todo visible, **455 FPS** (render 1,9 ms); mapa pequeño, 905 FPS. La batalla grande carga en 62 ms.
- Si existen los assets reales (`tree_texture`, `rock_texture` y `unit_texture`), se usan en lugar de los sprites generados.

Tests: 61/61. Nuevo `tests/unit/test_maps_and_units.gd`: mapa grande (tamaño, simetría, camino entre bases, objetos), despliegue de cada ejército en cada mapa (posiciones transitables, sin solapes, nombres únicos), estadísticas por tipo, unir solo del mismo tipo, arqueras que disparan a distancia sin cuerpo a cuerpo, ATACAR con arqueras que se detiene a distancia de tiro, y el parseo de `unit_type`.

Pendiente o limitaciones: con el mapa grande entero en pantalla, las etiquetas de 20 divisiones se solapan (con zoom normal se leen bien). El servidor Go no tiene mapas a elegir, ejércitos ni tipos.

---

## 17. Selección múltiple y espacio físico de las divisiones (2026-10-07)

### Selección múltiple

- **Recuadro:** al arrastrar con el clic izquierdo (más de `camera_drag_threshold` píxeles), `BattleInput` emite `box_dragged`, y `HUD/SelectionBox` dibuja el recuadro. Al soltar emite `box_released`, y el controlador selecciona las divisiones **propias** cuyo centro cae dentro. Un clic corto sigue siendo `primary_clicked`, que ahora se emite al soltar el botón.
- **Shift** añade a la selección (clic o recuadro) y **Ctrl+A** selecciona todas las divisiones propias.
- `SelectionManager` admite varias divisiones (`select_many`, `toggle`, `count`); la primera es la "principal", la que se muestra en el panel junto a "N seleccionadas: las órdenes van a todas".
- **Órdenes en grupo** (`_commandable_ids()`):
  - **MOVER** (clic derecho o el botón): `GroupMove.slots()` coloca las divisiones en filas de hasta 5, perpendiculares a la marcha y centradas en el clic. Las más adelantadas van en la primera fila y cada una conserva su posición izquierda/derecha para que sus rutas no se crucen.
  - **ATACAR:** todas al mismo objetivo.
  - **DEFENDER, RETIRARSE, MANTENER, DIVIDIR y formación (F):** a cada una.
  - **UNIR** con varias seleccionadas: todas se juntan en la primera. Solo funciona entre divisiones del mismo tipo; las demás se rechazan con un aviso.
- Cada división seleccionada muestra su anillo, y en el modo MOVER/ATACAR se previsualiza la línea de cada una. El círculo de radio de movimiento solo aparece con una sola división seleccionada.

### Espacio físico (simulación local)

- Cada división ocupa un círculo de radio `division_radius × (soldados / 3000) ^ 0,75`, limitado entre 10 y 60 (`rules.json`). Se envía al cliente como `radius` y el cliente lo dibuja con ese mismo tamaño: **lo que se ve es lo que choca**. Con el servidor Go, que no envía el radio, se usa la fórmula visual de `VisualConfig`.
- **Separación** (`_separate_divisions`, 2 pasadas por tick): las divisiones que se solapan, aliadas o enemigas, se separan.
  - La que marcha cede ante la que está quieta, defendiendo, manteniendo o combatiendo (peso 1 frente a 0,25).
  - Si una división en marcha choca con una parada, se desvía hacia un lado (`_sidestep`) y la **rodea**.
  - Si las dos marchan, se desvían ligeramente para cruzarse.
  - Nunca se empuja a nadie al agua.
- **Distancias por contacto entre bordes:** combate (contacto + `engagement_margin` 10), separación del combate (+ `disengage_margin` 40), unión (+ `merge_margin` 10) y persecución. Para dos divisiones de 3000 equivale a los antiguos 60/90, pero dos de 6000 ahora chocan con sus bordes en lugar de pelear solapadas.
- **Destino ocupado:** si una MOVER/RETIRARSE no se acerca a su destino durante `stall_ticks` (1,5 s, medido por la longitud de ruta que queda, así que un rodeo no cuenta como atasco), termina "llegó" si está cerca; si sigue sin avanzar mucho más tiempo, termina "bloqueada". Así dos divisiones enviadas al mismo punto quedan una al lado de la otra en lugar de empujarse indefinidamente.

Comprobado en el juego: 5 divisiones marchan en grupo, rodean a una aliada parada en medio del camino y llegan en fila con solape 0,00.

Tests: 68/68. Nuevo `tests/unit/test_group_and_physics.gd`:
- filas de grupo (destinos distintos, centrados, sin cruzarse; dos filas con 7 divisiones);
- separación de divisiones solapadas;
- una división que rodea a una aliada parada sin pisarla;
- dos divisiones con el mismo destino que terminan una al lado de la otra;
- dos divisiones de 6000 que combaten borde con borde;
- nadie empujado al agua;
- el campo `radius` en el cliente.

`test_battle_scene.gd` prueba el recuadro, MOVER en grupo con destinos distintos y Ctrl+A.

Limitaciones: el recuadro solo selecciona divisiones propias. Las colisiones son círculos: una formación muy alargada (columna, muro) choca como un círculo de su radio.

---

## 18. Ayuda automática entre divisiones (2026-10-07)

Para que las batallas tengan más vida, las divisiones reaccionan cuando una compañera cercana está combatiendo (`LocalGameSimulation._update_assist`, cada `assist_check_ticks` = 0,5 s).

- **Quién ayuda:** una división propia, viva, no desbandada, que no esté combatiendo y **sin orden** (en espera), a menos de `assist_radius` (350 unidades, unas 7 casillas) de una aliada en combate. Recibe una orden ATACAR contra el enemigo de esa aliada, marcada como `"auto": true`.
- **Quién no:** las que tienen **MANTENER** (nunca); las que tienen **DEFENDER** (por defecto no, porque también es una orden de quedarse; `assist_while_defending: true` en `rules.json` lo cambia); y las que están marchando, atacando, uniéndose o retirándose, que siguen con la orden del jugador.
- Elige la aliada combatiendo más cercana. Las arqueras se acercan hasta tener al enemigo a tiro y disparan.
- Como la que acude suele llegar por un costado del enemigo, combina con las formaciones. En la prueba en el juego, dos obreras que acudieron golpearon **por el flanco y la retaguardia** y deshicieron a la obrera enemiga (de 3000 a 1392 soldados en pocos segundos).
- **Cliente:**
  - El registro muestra "X acude en ayuda de un aliado: ataca a Y" (`division_updated`, motivo `assisting`).
  - El panel describe la orden como "Ayudar a un aliado: atacar a Y" (`Order.automatic`).
  - El jugador puede dar otra orden en cualquier momento.
- Funciona igual para los dos bandos.

Efecto observado: cuando varias divisiones se apiñan en un mismo combate, la separación física puede apartar a una lo suficiente para romper su combate; si estaba en espera y cerca, la ayuda automática la devuelve enseguida.

Tests: 72/72. Nuevo `tests/unit/test_assist_ai.gd`:
- una división en espera cercana acude, se marca como automática, genera el evento y entra en combate;
- con MANTENER y con DEFENDER se queda quieta;
- lejos no reacciona;
- el cliente reconoce la orden automática.


## 19. Modo «Jugar contra IA» (2026-10-08, sin Godot)

La IA vive **solo en el servidor Go** (`game.server/internal/ai`, ver su README, sección "Partida contra la IA"). El cliente solo pide la partida y la dibuja como cualquier otra.

**Flujo:** menú → "Jugar contra IA" → `NetworkGameState(url, nombre, "", vs_ai = true)` → al conectar envía `create_ai_game` → `game_created` + `lobby_updated` (el bot aparece con `bot: true`, ya listo) → el jugador pulsa "¡Listo!" → `game_started` → partida normal → `game_finished` con el panel de resultado de siempre → "Volver al menú".

**Cambios en el cliente:**
- `Protocol.CREATE_AI_GAME` / `Protocol.create_ai_game()`.
- `NetworkGameState`: parámetro `vs_ai`. Un `error` recibido antes de `game_created`/`game_joined` (por ejemplo `create_failed`) se trata como fallo de sesión (`connection_lost` con un texto comprensible) y no como orden rechazada. Si el servidor no está disponible, el aviso es "No se pudo conectar con el servidor … ¿Está en ejecución?". Las dos mejoras sirven también para "Conectar".
- `GameStateSource.loading_text()` + `TopBar.set_status_text()`: la barra superior muestra "Creando partida contra la IA..." hasta que llega el primer estado.
- `MainMenu`: botón "Jugar contra IA" (señal `ai_requested`) y bloqueo de dobles clics en los tres botones de inicio hasta que el menú vuelve a mostrarse.
- `BattleState.set_players` conserva el campo `bot`.

**Verificado sin Godot:** `gdparse` y `gdlint` (gdtoolkit 4.5, con el `gdlintrc` del proyecto) sin errores en los archivos tocados. El único aviso es el `unused-argument` de `battle_controller.gd`, que ya existía. Un script Python envió al servidor real los mismos mensajes que genera el cliente (`create_ai_game`, `ready`, `hold_division`). Respuesta completa, bot en el lobby y divisiones del bot moviéndose: OK.

**Pendiente en la máquina con Godot:**
1. `godot --headless --path . --editor --quit` y luego `godot --headless --path . --script res://tests/run_tests.gd`. Nuevos tests: `tests/unit/test_ai_mode.gd` (mensaje, solicitud al conectar, errores antes de la sesión, bot en el lobby, botón sin dobles solicitudes) y `tests/integration/test_ai_battle_flow.gd` (escena real con un socket falso: carga → ready → órdenes → estado → derrota → menú, y servidor caído sin bloquear el cliente). Puntos a vigilar: los `class FakeNet extends NetworkManager` internos (firma de los métodos sobrescritos) y el `super(...)` de `FakeAiSource._init`.
2. Prueba manual: `go run ./cmd/server`, "Jugar contra IA", "¡Listo!". El ejército rival debe avanzar solo, combatir, retirarse si queda débil y la partida debe terminar con el panel de resultado. Probar también con el servidor apagado (debe aparecer el aviso y poder volver al menú).
3. Comprobar que "Conectar" (dos jugadores) sigue funcionando igual.

