# AntzGame: cliente Godot 4 (MVP)

Frontend del juego de estrategia 1v1 de ejércitos de hormigas. Todo se dibuja con formas simples, sin assets. Puede jugarse contra una **simulación local** o contra el **servidor Go autoritativo** (`../game.server`).

> ⚠️ Escrito sin Godot instalado: no se ha ejecutado nunca. Antes de nada, lee **[docs/AVANCE.md](docs/AVANCE.md)**: estado, checklist y riesgos.

## Ejecutar

1. Godot 4.3+ → *Import* → `project.godot` → F5.
2. **Partida local:** botón "Partida local (sin servidor)". Tab cambia el jugador controlado.
3. **Contra el servidor:** `cd ../game.server && go run ./cmd/server`. En el cliente, "Conectar" con el ID vacío crea la partida; el segundo jugador introduce ese ID. Ambos pulsan "¡Listo!".

## Tests

```bash
godot --headless --path . --editor --quit                      # una vez: registra las clases
godot --headless --path . --script res://tests/run_tests.gd    # todos los tests
```

Más detalles en `docs/AVANCE.md` §10.

## Controles

| Entrada | Acción |
|---------|--------|
| Clic izquierdo | seleccionar / deseleccionar |
| Clic derecho | orden contextual: suelo → MOVER, enemigo → ATACAR |
| 1 2 3 4 5 | MOVER, ATACAR, DEFENDER, RETIRARSE, MANTENER |
| Esc | cancelar la orden en curso o deseleccionar |
| Rueda | zoom hacia el cursor |
| WASD / flechas / botón central | desplazar la cámara |
| F3 | modo debug |
| Tab | (local) cambiar de jugador |

## Arquitectura en una línea

La UI solo habla con `GameStateSource`. `LocalGameState` (la simulación en el propio proceso) y `NetworkGameState` (WebSocket) entregan los **mismos mensajes del protocolo JSON** del servidor, así que pueden intercambiarse sin tocar la UI. Los valores de juego están en `data/definitions/*.json`. Los detalles están en `docs/AVANCE.md`.
