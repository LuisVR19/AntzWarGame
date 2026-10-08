# AntzGame: cliente Godot 4 (MVP)

Frontend del juego de estrategia 1v1 de ejércitos de hormigas, en **2D isométrico**. Todo se dibuja con formas simples; los assets se añaden en `assets/` sin tocar la lógica (ver `assets/README.md`). Puede jugarse contra una **simulación local** o contra el **servidor Go autoritativo** (`../game.server`).

> Verificado en Godot 4.7.2 (30/30 tests OK). Estado y detalles en **[docs/AVANCE.md](docs/AVANCE.md)**.

## Ejecutar

1. Godot 4.3+ → *Import* → `project.godot` → F5.
2. **Partida local:** elige el **mapa** (pequeño 40x24 o grande 80x48) y el **tamaño del ejército** (pequeño, mediano o grande) y pulsa "Partida local (sin servidor)". Tab cambia el jugador controlado.
3. **Contra el servidor:** `cd ../game.server && go run ./cmd/server`. En el cliente, "Conectar" con el ID vacío crea la partida; el segundo jugador introduce ese ID. Ambos pulsan "¡Listo!".
4. **Contra la IA:** con el servidor en marcha, pulsa "Jugar contra IA" (usa la URL del servidor del menú) y luego "¡Listo!". Un bot del servidor controla el ejército rival.

## Tests

```bash
godot --headless --path . --editor --quit                      # una vez: registra las clases
godot --headless --path . --script res://tests/run_tests.gd    # todos los tests
```

Más detalles en `docs/AVANCE.md` §10.

## Controles

| Entrada | Acción |
|---------|--------|
| Clic izquierdo | seleccionar división, edificio o recurso / deseleccionar. En una división tuya abre su **menú de órdenes** |
| Clic izquierdo + arrastrar | **recuadro de selección**: selecciona varias divisiones propias; las órdenes van a todas |
| Shift + clic / Shift + recuadro | añadir o quitar divisiones de la selección |
| Ctrl+A | seleccionar todas tus divisiones |
| Menú → MOVER / ATACAR | el siguiente clic izquierdo elige el destino o el enemigo (con línea de previsualización) |
| Clic derecho (corto) | orden rápida: suelo → MOVER, enemigo → ATACAR |
| Clic derecho + arrastrar | desplazar el mapa |
| 1 2 3 4 5 | MOVER, ATACAR, DEFENDER, RETIRARSE, MANTENER |
| 6 / 7 | DIVIDIR (en dos mitades) / UNIR (luego clic en otra división propia). Solo en partida local |
| F | siguiente formación (también hay botones en el panel y en el menú de la división). Solo en partida local |
| Esc | cancelar la orden en curso, cerrar el menú o deseleccionar |
| Rueda | zoom hacia el cursor |
| WASD / flechas / ratón en el borde / botón central | desplazar la cámara |
| F3 | modo debug |
| Tab | (local) cambiar de jugador |

## Arquitectura en una línea

La UI solo habla con `GameStateSource`. `LocalGameState` (la simulación en el propio proceso) y `NetworkGameState` (WebSocket) entregan los **mismos mensajes del protocolo JSON** del servidor, así que pueden intercambiarse sin tocar la UI. Los valores de juego están en `data/definitions/*.json`. Los detalles están en `docs/AVANCE.md`.
