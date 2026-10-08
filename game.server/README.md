# Servidor de juego 1v1: estrategia militar (Go)

Servidor **autoritativo** para un juego de estrategia 1v1 en tiempo real. El cliente (Godot 4) solo envía **intenciones** (órdenes). El servidor valida, simula y decide posiciones, combates y resultados.

Todo el estado vive en memoria. Si el servidor se reinicia, las partidas se pierden (es intencional en el MVP).

```bash
go run ./cmd/server                 # escucha en :8080
go run ./cmd/server -addr :9000     # otro puerto (también vale la variable PORT)
go run ./cmd/server -print-config   # imprime la configuración por defecto
go test ./...                       # pruebas unitarias + integración
```

## Arquitectura

```
Network  (internal/network)      WebSocket/HTTP, JSON <-> structs, sin reglas
   ↓ comandos            ↑ Output
Application (internal/app)        Room: una goroutine dueña de cada partida
   ↓                     ↑ eventos / vistas
Domain (internal/game)            Game, Division, Order, Battle, GameEvent, Tick()
   ├── internal/movement          pathfinding A* + integración de movimiento
   ├── internal/combat            interfaz CombatEngine + SimpleEngine
   ├── internal/terrain           tipos de terreno, modificadores, mapa
   └── internal/player            Player
internal/matchmaking              registro de salas: CreateGame / JoinGame
internal/ai                       bot por reglas para create_ai_game (sin red ni estado propio del juego)
internal/config                   todos los valores ajustables (configs/server.json)
pkg/geom, pkg/idgen               utilidades
```

**Concurrencia.** Cada partida la ejecuta un `app.Room`: una sola goroutine que es la única dueña del `game.Game`. El ticker del game loop y los comandos de los jugadores pasan por el mismo `select`, así que no hay mutex sobre el estado del juego. Las conexiones WebSocket tienen una goroutine de lectura (envía comandos a la sala y espera la respuesta) y otra de escritura (la única que escribe en el socket). La sala publica mensajes con `Deliver` sin bloquearse: si un cliente no consume su cola, se le desconecta. El único mutex está en el registro de salas.

**Game loop** (`game.Tick`, 10 ticks/s por defecto, `game.tick_rate`):
1. aplicar las órdenes validadas desde el tick anterior
2. movimiento (velocidad × terreno × fatiga, límites del mapa, agua intransitable)
3. detectar encuentros (enemigos a menos de `engagement_range`)
4. combates (un round cada `combat_round_ticks`)
5. moral y fatiga (recuperación en reposo, desbandada y reagrupamiento)
6. condiciones de victoria
7. eventos
8. la `Room` envía los eventos y el snapshot (`game_state`) a cada jugador

**Niebla de guerra (preparada, no implementada).** Todo lo que se envía a un jugador pasa por `Game.ViewFor(player)`, `DivisionViewFor` y `EventVisibleTo`, que consultan una `VisibilityPolicy` (hoy `FullVisibility`). Las órdenes y rutas del rival ya no se envían. Atacar una división no visible devuelve `target_not_found`. Hay un test con una política de ejemplo.

**Combate reemplazable.** `combat.Engine` es una interfaz con `ResolveRound(a, b Combatant) RoundResult`. `SimpleEngine` es determinístico:

```
effective_attack  = attack  × moral_mod × terreno.attack  × exp_mod × fatiga_mod × postura
effective_defense = defense × moral_mod × terreno.defense × exp_mod × fatiga_mod × postura
bajas(B) = unidades(A) × base_casualty_rate × clamp(eff_attack(A) / eff_defense(B), 0.25, 4)
```

Cada round también baja la moral (más cuanto mayores las bajas), sube la fatiga y da experiencia. Con moral ≤ `rout_morale_threshold` la división se desbanda: se retira sola a su despliegue y solo acepta RETREAT hasta recuperar `rally_morale_threshold`. Con unidades ≤ `destroyed_unit_threshold` queda destruida.

**Victoria:** el rival se queda sin divisiones (`annihilation`), se alcanza `max_duration_ticks` (gana quien tenga más tropas, `time_limit`), el rival lleva desconectado más de `disconnect_grace_ticks` (`opponent_disconnected`) o ambos abandonan (`abandoned`, sin ganador).

## Partida contra la IA

`create_ai_game` crea una partida en la que el segundo jugador es un **bot del servidor**. El bot es un jugador normal: tiene su propio `player_id` (`bot-N`), está marcado con `bot: true`, siempre está listo y no tiene conexión WebSocket. La partida empieza cuando el humano envía `ready`, con la cuenta atrás y las condiciones de victoria habituales. Si el humano se desconecta, la partida sigue, puede reconectarse con su token y, pasado `disconnect_grace_ticks`, gana el bot (`opponent_disconnected`). Si abandona en el lobby, la sala se cierra.

La IA (`internal/ai.Bot`) se ejecuta dentro de la goroutine de la `Room`, después de cada tick y cada `ai.decision_interval_ticks`:

1. Lee **solo** `Game.ViewFor(bot)`, así que ve lo mismo que vería un humano en su lugar (respeta la `VisibilityPolicy`).
2. Decide con reglas deterministas:
   - **retirarse:** si tiene pocas tropas (`retreat_strength_ratio`) o poca moral (`retreat_morale`, con histéresis hasta `recover_morale`). Ya en la base, defiende.
   - **defender:** si hay enemigos a menos de `base_threat_radius` de su despliegue, envía las divisiones más cercanas hasta igualar su fuerza.
   - **atacar:** elige un objetivo por probabilidades (tropas × ataque/defensa × moral × fatiga) y distancia. Reparte el ejército (`max_attackers_per_target`) y solo cambia de objetivo si otro es claramente mejor (`target_switch_factor`). Un ataque ya iniciado continúa mientras las probabilidades superen `keep_attack_odds`.
   - **reagruparse:** con malas probabilidades (`min_attack_odds`) y aislada (`regroup_radius`), va hacia el aliado más cercano que esté más cerca de su base. El más cercano a la base mantiene la posición.
   - **mantener posiciones:** no reenvía una orden que la división ya ejecuta, ni repite la misma orden antes de `reissue_cooldown_ticks`. Las divisiones en combate o en desbandada no reciben órdenes.
3. Envía las órdenes con `Game.SubmitOrder`, con la misma validación que las de un humano. Nunca toca posiciones, tropas ni combates.
4. Deja de decidir cuando la partida termina.

Cada orden se registra (`msg="ai decision"`) con división, acción, objetivo y motivo. Los cambios de modo se registran como `msg="ai mode changed"`. Como no hay comandantes ni mensajeros, el bot da órdenes con la misma latencia que un jugador humano (se aplican en el siguiente tick).

## Configuración

`configs/server.json` se generó con `-print-config` y contiene todos los valores: tick rate, rangos, moral, fatiga, ejército inicial, parámetros de combate, la tabla de terreno y la sección `ai` (parámetros del bot). Se puede borrar cualquier clave y se usará su valor por defecto. Si el archivo define `army`, reemplaza la lista completa.

| Terreno | movimiento | ataque | defensa | visibilidad |
|---------|-----------|--------|---------|-------------|
| PLAIN   | 1.0 | 1.0 | 1.0 | 1.0 |
| FOREST  | 0.7 | 0.9 | 1.2 | 0.6 |
| HILL    | 0.8 | 1.1 | 1.3 | 1.3 |
| WATER   | 0 (intransitable) | – | – | 1.0 |

Mapa por defecto: 40×24 casillas de 50 unidades (2000×1200), un río central con dos vados (filas 5-6 y 17-18), bosques y colinas. Cada jugador empieza con 3 divisiones.

## HTTP

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET  | `/health` | `{"status":"ok","games":N}` |
| POST | `/games` | crea una partida vacía → `{"game_id": "..."}` |
| GET  | `/games/{id}` | resumen (estado, jugadores, divisiones vivas). El estado completo solo va por WebSocket, por jugador |
| GET  | `/ws` | WebSocket |

## Protocolo WebSocket (JSON)

Cada mensaje es un objeto plano con `type`. Todos los mensajes del cliente aceptan un `request_id` opcional, que el servidor devuelve en `order_accepted`, en `error` y en `game_created`/`game_joined`. Los enums viajan en minúsculas (`moving`, `running`, `forest`...).

### Cliente → servidor

```jsonc
{"type":"create_game","player_name":"Alice"}
{"type":"create_ai_game","player_name":"Alice"}   // partida contra el bot; responde game_created
{"type":"join_game","game_id":"game-ab12cd34ef56","player_name":"Bob"}
{"type":"join_game","game_id":"game-...","session_token":"tok-..."}   // reconexión
{"type":"ready"}                       // {"type":"ready","ready":false} para cancelar
{"type":"move_division","division_id":"division-1","x":640,"y":420}
{"type":"attack_division","division_id":"division-1","target_division_id":"division-4"}
{"type":"defend_division","division_id":"division-1"}
{"type":"retreat_division","division_id":"division-1"}               // x,y opcionales; por defecto a su despliegue
{"type":"hold_division","division_id":"division-1"}
```

### Servidor → cliente

| type | cuándo |
|------|--------|
| `game_created` / `game_joined` | respuesta a create/join: `game_id`, `player_id`, `session_token` (guardarlo para reconectar), `side`, `tick_rate`, `map`, `state` |
| `lobby_updated` | alguien entra, sale, cambia `ready` o se desconecta. Cada jugador lleva `bot: true` si lo controla el servidor |
| `game_started` | fin de la cuenta atrás, incluye el estado inicial |
| `game_state` | snapshot autoritativo cada `snapshot_every_ticks` |
| `order_accepted` | orden validada (se aplica en el próximo tick) |
| `division_updated` | cambia la orden o el estado de una división (`reason`: order, arrived, blocked, battle_started, battle_ended, routed, rallied, target_destroyed) |
| `battle_started` / `battle_updated` / `battle_ended` | contacto, cada round (bajas, moral, ataque/defensa efectivos) y final |
| `division_destroyed` | división eliminada |
| `game_finished` | `winner_player_id`, `reason`, `result` (victory/defeat/draw para el receptor) |
| `error` | `code`, `message`, `request_id` |

Ejemplo de `game_state`:

```json
{"type":"game_state","game_id":"game-...","status":"running","tick":100,
 "divisions":[{"id":"division-1","player_id":"player-1","name":"1st Infantry","x":230.5,"y":450,
   "unit_count":2940,"max_unit_count":3000,"attack":10,"defense":12,"speed":30,"morale":76.5,
   "experience":10.4,"fatigue":3.2,"state":"attacking","routed":false,"in_battle":true,"terrain":"plain",
   "order":{"id":"order-3","type":"attack","target_division_id":"division-4"},
   "path":[{"x":400,"y":450}]}],
 "battles":[{"id":"battle-1","attacker_id":"division-1","defender_id":"division-4","x":260,"y":450,
   "started_tick":90,"rounds":1,"attacker_losses":60,"defender_losses":66}]}
```

`map.tiles` es una lista de filas (la fila 0 corresponde a y=0) con un carácter por casilla: `P` llanura, `F` bosque, `H` colina, `W` agua. El mapa incluye su leyenda y la tabla de modificadores.

Códigos de error: `bad_request`, `unknown_message_type`, `not_in_game`, `already_in_game`, `game_not_found`, `game_closed`, `game_full`, `invalid_state`, `game_not_running`, `player_not_found`, `division_not_found`, `not_owner`, `division_destroyed`, `division_routed`, `division_engaged` (una división en combate solo acepta RETREAT/DEFEND/HOLD), `target_required`, `target_not_found`, `target_friendly`, `target_destroyed`, `invalid_position`, `impassable_position`, `unreachable_position`, `timeout`.

### Flujo mínimo desde Godot 4

```gdscript
var ws := WebSocketPeer.new()

func _ready():
    ws.connect_to_url("ws://127.0.0.1:8080/ws")

func _process(_dt):
    ws.poll()
    while ws.get_available_packet_count() > 0:
        var msg = JSON.parse_string(ws.get_packet().get_string_from_utf8())
        match msg.type:
            "game_created", "game_joined": print("Jugador ", msg.player_id, " en ", msg.game_id)
            "game_state": _apply_snapshot(msg)   # interpolar posiciones entre snapshots
            "error": push_warning(msg.code + ": " + msg.message)

func send(obj: Dictionary):
    ws.send_text(JSON.stringify(obj))

# send({"type": "create_game", "player_name": "Alice"})
# send({"type": "ready"})
# send({"type": "move_division", "division_id": "division-1", "x": 640, "y": 420})
```

El cliente nunca debe mover unidades por su cuenta. Solo interpola entre los snapshots que recibe del servidor.

## Pruebas

- `terrain`: tabla de modificadores, búsquedas en el mapa, validación, mapa por defecto
- `movement`: velocidad por terreno, waypoints, agua, límites del mapa, A* (rodeos, terreno más rápido, errores)
- `combat`: modificadores, simetría, determinismo, terreno, posturas, moral, límites de bajas
- `game`: validación de órdenes (tabla), restricciones en combate y desbandada, movimiento, encuentros, persecución, DEFEND, colina, retirada, desbandada y reagrupamiento, recuperación, todas las condiciones de victoria, visibilidad
- integración del game loop: partida completa con un guion en el mapa real (consistencia de eventos e invariantes) y determinismo (dos ejecuciones idénticas)
- `app`: ciclo de vida de una sala (join, partida llena, ready, inicio, órdenes, reconexión con token, desconexión obsoleta, abandono)
- `network`: endpoints HTTP y una partida completa por WebSocket real (crear, unirse, iniciar, MOVE, ATTACK, combate, DEFEND, desconexión y victoria), y una partida contra la IA (`create_ai_game`, bot en el lobby, plaza ocupada, órdenes del humano, el bot actúa y combate)
- `ai`: atacar, defender la base, retirada y guardia, histéresis de moral y de ataque, reagrupamiento, reparto de objetivos, no repetir órdenes, solo información visible, sin órdenes fuera de RUNNING, determinismo
- `app` (IA): partida completa contra un humano pasivo hasta el final. Se comprueba que no hay órdenes rechazadas, que las bajas coinciden con los rounds de combate, que la velocidad y el terreno se respetan, que no hay oscilaciones y que el bot no decide después del final. También la victoria del bot por desconexión y el cierre del lobby
