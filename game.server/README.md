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

## Cadena de mando

Cada ejército puede tener un **general** y varios **comandantes** (`internal/game/command.go`). Se definen en la plantilla del ejército:

- `leads`: la división **lleva** una unidad de mando. Vale `"general"` o el nombre de un comandante.
- `commander`: indica a qué comandante **reporta** la división. Vacío significa que reporta directamente al general.

Un ejército sin `leads` no tiene cadena de mando y todas sus órdenes son inmediatas, como antes. El ejército por defecto es así:

| División | Lleva | Reporta a |
|----------|-------|-----------|
| 1st Infantry | Infantry Command | Infantry Command |
| 2nd Infantry | — | Infantry Command (necesita mensajero si se aleja más de 350) |
| 1st Armored | General | (el general) |

La división anfitriona de un comandante siempre reporta a ese comandante (se valida en la plantilla y en `assign_commander`).

**Unidad de mando.** Viaja con su división anfitriona: su posición es la de la división. Queda **incapacitada** mientras esa división está en desbandada y **eliminada** cuando la destruyen. Tiene dos radios independientes, `comm_radius` y `influence_radius`. Sus subordinados no se guardan aparte: son las divisiones cuyo `commander_id` apunta a ella.

**Quién transmite una orden.** Si el general viaja en la división, el general. Si no, el comandante de la división si está activo. Si no, el general, si está activo. Si no hay ninguno, la orden se rechaza con `no_command` y la división conserva su última orden. Si la regla explícita `general_relay` está activada (desactivada por defecto), el general también puede dar órdenes inmediatas dentro de su propio radio.

**Entrega.** Dentro del `comm_radius` de quien transmite, la orden es **inmediata**: se aplica en el tick siguiente, como siempre. Fuera de él, se crea un **mensajero**:
- registra emisor, división, orden, tick de envío y ETA;
- sale de la posición del emisor y sigue a la división con el `FindPath`/`Step` existentes, a `messenger_speed` y con los modificadores del terreno;
- a `messenger_delivery_range` de la división, la orden se **valida de nuevo** y entra en la misma cola que las inmediatas.

Si al llegar la orden ya no es válida (objetivo destruido, división en combate...), el mensaje se cancela con ese código. Mientras el mensajero viaja, la división sigue con su orden anterior.

**Reglas de los mensajes:**
- Hay como máximo un mensaje por división.
- Una orden nueva cancela la pendiente (`superseded`), tanto si sale con mensajero como si es inmediata.
- Una orden idéntica a la pendiente devuelve la misma orden y no envía otro mensajero.
- Los mensajeros no se pueden interceptar todavía (`intercepted` está reservado).

**Liderazgo.** Dentro del `influence_radius` de su comandante o de su general activos:
- la moral cuenta `leadership_morale_bonus` más en cada round de combate;
- la moral se recupera `leadership_recovery_factor` veces más rápido fuera de combate.

El bonus se calcula en cada round y **nunca se guarda**, así que no se acumula.

**Bajas en el mando:**
- **Si cae un comandante,** sus divisiones pierden el bonus y pasan a recibir órdenes del general. El jugador puede reasignarlas con `assign_commander` a otro mando activo, siempre que la división esté dentro del `comm_radius` del nuevo mando. Si no lo está, la respuesta es `commander_out_of_range`; así una reasignación no sirve para saltarse un mensajero. La reasignación solo la ve su dueño.
- **Si cae el general,** las divisiones y los comandantes siguen con sus órdenes. Tras `succession_delay_ticks`, el primer comandante activo asciende a general con sus radios y conserva sus divisiones. Si no queda ninguno, las divisiones conservan su última orden.

## Tipos de hormiga y formaciones

Cada división tiene sus propias propiedades (`internal/game/formation.go`, mismos valores que `game.client/data/definitions/`):

- **Tipo** (`unit_types`): `WORKER` (obrera), `SOLDIER` (soldado), `ARCHER` (arquera), `TANK` (acorazada) y `SCOUT` (exploradora). Da las estadísticas base. En la plantilla del ejército, `type` elige el tipo y cualquier estadística que se escriba lo sobrescribe (si se omite o vale 0, se usa la del tipo).
- **Formación** (`formations`): `LINE`, `SHIELD_WALL`, `WEDGE`, `SQUARE` y `COLUMN`. Multiplica ataque, velocidad y la defensa **según el lado por el que llega el golpe**: frente (hasta 60° de su orientación), flanco o retaguardia (desde 120°). `frontage` limita los soldados que luchan a la vez y `bonus_vs` da ventaja contra otra formación. En la plantilla, `formation` es la inicial (por defecto `formation_rules.default`).
- **Orientación** (`facing`): al marchar mira hacia donde avanza; en combate gira hacia su enemigo a `turn_rate` grados/s. Por eso un ataque por el flanco o la espalda hace más daño, sobre todo a formaciones que giran despacio (muro de escudos).
- **Cambiar de formación** (`set_formation`): no es una orden, así que no pasa por la cadena de mando. Se aplica en el tick siguiente (`division_updated`, `reason: formation_changed`) y la división pasa `formation_rules.change_seconds` reorganizándose (`reforming`), con ataque y defensa × `reform_penalty` y velocidad × `reform_speed_factor`. Al terminar llega `formation_ready`. Errores: `invalid_formation`, `same_formation`, `division_routed`, etc.
- **Arqueras** (tipo con `ranged`): sin estar en combate ni marchando, disparan una vez por round a un enemigo a menos de `range` (prioridad: su objetivo de ATACAR). Solo sufre el objetivo, con bajas × `combat.volley_casualty_factor`. Con ATACAR se detienen al entrar en alcance en lugar de ir al cuerpo a cuerpo.

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

**Cadena de mando:** la IA usa las mismas reglas que un humano:
- sus órdenes fuera de rango viajan con mensajero;
- no reenvía una orden que ya transporta un mensajero;
- no da órdenes a divisiones sin mando;
- no cambia las órdenes de divisiones fuera de rango salvo por urgencia (retirada o defensa de la base);
- reasigna las divisiones de un comandante caído al comandante activo más cercano.

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
{"type":"assign_commander","division_id":"division-2","commander_id":"commander-4"}   // cadena de mando
{"type":"set_formation","division_id":"division-1","formation":"shield_wall"}           // line, shield_wall, wedge, square, column
```

### Servidor → cliente

| type | cuándo |
|------|--------|
| `game_created` / `game_joined` | respuesta a create/join: `game_id`, `player_id`, `session_token` (guardarlo para reconectar), `side`, `tick_rate`, `map`, `state` |
| `lobby_updated` | alguien entra, sale, cambia `ready` o se desconecta. Cada jugador lleva `bot: true` si lo controla el servidor |
| `game_started` | fin de la cuenta atrás, incluye el estado inicial |
| `game_state` | snapshot autoritativo cada `snapshot_every_ticks` |
| `order_accepted` | orden validada. `delivery`: `immediate` (se aplica en el próximo tick) o `messenger` (con `messenger_id` y `eta_ticks` estimados) |
| `messenger_updated` | (solo al dueño) mensajero `pending`/`dispatched`, `delivered` o `cancelled` (`reason`: `superseded`, `recipient_destroyed`, `game_finished` o el código de validación al llegar), con la `order` |
| `command_updated` | un general o comandante cambia de `status` (`active`, `incapacitated`, `eliminated`; `reason`: `host_routed`, `host_rallied`, `host_destroyed`) o asciende (`promoted`) |
| `division_updated` | cambia la orden o el estado de una división (`reason`: order, arrived, blocked, battle_started, battle_ended, routed, rallied, target_destroyed, formation_changed, formation_ready) |
| `battle_started` / `battle_updated` / `battle_ended` | contacto (con `attacker_exposure` / `defender_exposure`: front, flank o rear), cada round (bajas, moral, ataque/defensa efectivos y `exposure` de cada lado) y final |
| `volley` | una arquera dispara: `shooter_id`, `target_id`, `losses`, `unit_count`, `exposure`, `from`, `to` |

Cada división del estado lleva además `unit_type`, `formation`, `facing` (radianes) y `reforming`.
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

Códigos de error: `bad_request`, `unknown_message_type`, `not_in_game`, `already_in_game`, `game_not_found`, `game_closed`, `game_full`, `invalid_state`, `game_not_running`, `player_not_found`, `division_not_found`, `not_owner`, `division_destroyed`, `division_routed`, `division_engaged` (una división en combate solo acepta RETREAT/DEFEND/HOLD), `target_required`, `target_not_found`, `target_friendly`, `target_destroyed`, `invalid_position`, `impassable_position`, `unreachable_position`, `no_command`, `commander_not_found`, `commander_inactive`, `commander_out_of_range`, `invalid_assignment` (la división anfitriona de un comandante siempre reporta a él), `timeout`.

**Cadena de mando en `game_state`:**
- `commanders` lista cada general y comandante visible: `id`, `player_id`, `role`, `name`, `host_division_id`, `x`, `y`, `status`, `comm_radius` y `influence_radius`.
- `messengers` lista los mensajeros propios en tránsito: `id`, `sender_id`, `division_id`, `x`, `y`, `sent_tick`, `eta_ticks` y `order`.
- Las divisiones propias llevan `commander_id`, `command_link` (`in_range`, `out_of_range` o `no_command`) y `pending_order` (`messenger_id`, `eta_ticks` y `order`).

El rival no recibe nada de esto, salvo la lista `commanders`, que es visible porque las unidades de mando viajan con divisiones visibles. Todo se omite si no hay cadena de mando.

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
- `game` (cadena de mando):
  - despliegue;
  - orden inmediata en rango y orden por mensajero fuera de él, que llega según la ETA y mantiene la orden anterior mientras tanto;
  - sustitución y deduplicación;
  - nueva validación al llegar y destinatario destruido;
  - caída de un comandante y reasignación;
  - caída del general y sucesión;
  - incapacitado mientras su división está en desbandada;
  - `no_command`;
  - bonus de moral no acumulativo;
  - privacidad;
  - ejércitos sin cadena de mando sin cambios;
  - validación de la plantilla.
- `ai`: atacar, defender la base, retirada y guardia, histéresis de moral y de ataque, reagrupamiento, reparto de objetivos, no repetir órdenes, solo información visible, sin órdenes fuera de RUNNING, determinismo, respeto de rangos y órdenes pendientes, sin órdenes a divisiones sin mando, reasignación tras la caída de un comandante. También en `app`: las órdenes del bot a divisiones fuera de rango no se aplican antes de que llegue el mensajero
- `network` (cadena de mando): comandantes y enlaces en el estado, orden con mensajero (`order_accepted`, `messenger_updated` pendiente y entregado, `pending_order`), privacidad frente al rival, `assign_commander` y su error
- `game` (formaciones): estadísticas del tipo y sobrescrituras de la plantilla, validación, cambio de formación con reorganización, velocidad por formación, frente/flanco/retaguardia, muro de escudos, giro en combate al ritmo de la formación y disparos de arqueras sin cuerpo a cuerpo. En `network`: `set_formation` de extremo a extremo
- `app` (IA): partida completa contra un humano pasivo hasta el final. Se comprueba que no hay órdenes rechazadas, que las bajas coinciden con los rounds de combate, que la velocidad y el terreno se respetan, que no hay oscilaciones y que el bot no decide después del final. También la victoria del bot por desconexión y el cierre del lobby
