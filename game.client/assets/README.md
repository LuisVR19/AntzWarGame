# Assets

Hoy está vacío: todo se dibuja con formas (`scripts/units/placeholder_painter.gd`).
Si existe un archivo en la ruta esperada, se usa en lugar del placeholder **sin tocar la lógica**.
Formatos admitidos: SVG, PNG y WebP. Godot los importa al abrir el editor.

| Carpeta | Archivo esperado | Dónde se configura | Anclaje |
|---------|------------------|--------------------|---------|
| `units/` | `division.svg` | `resources/visual_config.tres` → `unit_texture` | centro inferior = pies de la división; se tiñe con el color del bando |
| `buildings/` | `anthill.svg`, `barracks.svg`, `storehouse.svg` | `data/definitions/buildings.json` → `asset` | centro inferior = esquina frontal (inferior) de la huella; ancho = ancho de la huella |
| `resources/` | `gold.svg`, `wood.svg`, `stone.svg`, `food.svg` | `data/definitions/resources.json` → `asset` | centro inferior = centro de la casilla |
| `decorations/` | `tree.svg`, `rock.svg` | `visual_config.tres` → `tree_texture`, `rock_texture` | centro inferior = base del árbol o roca |
| `terrain/` | `terrain_atlas.png` | `visual_config.tres` → `terrain_atlas` | atlas de rombos de `tile_width`×`tile_height` (64×32); una fila por terreno (PLAIN, FOREST, HILL, WATER) y una columna por variante |
| `effects/`, `ui/` | — | reservado | — |

El punto de anclaje es también el punto de **ordenación por profundidad**, porque `World` usa Y-sort.
Por eso un sprite debe tener su "suelo" en el borde inferior de la imagen.
