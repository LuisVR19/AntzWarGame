# Avance del cliente Godot (handoff)

**Fecha:** 2026-10-07
**Estado:** código escrito y verificado estáticamente. **Nunca se ejecutó en Godot**: en la máquina donde se escribió no hay Godot instalado.

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
| **Probado ejecutando en Godot** | ❌ **pendiente** |
| Ajuste visual (tamaños, colores, legibilidad) | ❌ pendiente (requiere verlo) |

---

## 2. Qué se verificó sin Godot

1. **Sintaxis GDScript:** los 39 scripts pasan el parser de `gdtoolkit` 4.x (`gdparse`).
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
4. Pulsar **F5**. Debería aparecer el menú principal.
5. **Partida local:** botón "Partida local (sin servidor)". Seguir el guion de la sección 4.
6. **Contra el servidor:** en `../game.server` ejecutar `go run ./cmd/server`. Abrir dos instancias del juego (en Godot: *Debug → Customize Run Instances… → 2*) y usar "Conectar": una con ID vacío (crea la partida) y la otra con el ID que aparece en la barra superior de la primera. Pulsar "¡Listo!" en ambas.
7. Opcional: crear un `Theme` y una fuente propia, y ajustar `scripts/core/palette.gd`.

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

- Tests automáticos de `LocalGameSimulation` con GUT o `SceneTree` en modo headless (lógica pura, fácil de testear).
- Reconexión automática a la partida usando el `session_token` (ya se guarda en `GameStateSource.session_token`; falta reintentar tras una desconexión).
- Selección múltiple: `SelectionManager` ya trabaja con listas; faltan la selección por arrastre y el envío de una orden por cada división.
- Pathfinding en la simulación local (sustituir `MovementSystem` por `AStarGrid2D`), o usar siempre el servidor.
- Niebla de guerra: el servidor ya filtra la información por jugador; en el cliente bastará con no dibujar lo que no llega.

## 9. Herramientas usadas para validar (reproducibles)

```bash
pip install "gdtoolkit==4.*"
gdparse scripts/**/*.gd      # sintaxis
gdlint scripts               # estilo (usa ./gdlintrc)
```
