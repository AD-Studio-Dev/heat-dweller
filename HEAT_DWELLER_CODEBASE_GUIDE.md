# Heat Dweller: Lore, Systems, and Codebase Guide

This guide summarizes the narrative reference supplied for *Heat Dweller* and
the implementation visible in the current repository. It is intended as a
handoff document for future developers and AI assistants. Narrative statements
in the lore section come from the official lore reference supplied with the
request; implementation statements describe the code as it currently exists.
Where those differ, this guide calls out the distinction rather than treating
planned story as already implemented content.

**Verification note.** The implementation sections below were checked against
`main.lua`, `renderer.lua`, `rooms.lua` and `conf.lua`. Statements about modules
that were not re-read for this revision (`player.lua`, `items.lua`,
`mainmenu.lua`, enemy/boss files, projectile files) are marked *(not re-verified)*
and carried over from the previous version of this guide; check them against the
source before relying on exact numbers.

## 1. Narrative Premise and Lore Context

### The child and the house

Matthew is an eight- or nine-year-old child. He sees himself as living in an
ordinary, loving home with his father and does not understand the danger or
secrets surrounding him. His immediate, childlike goal is to find a piece of
candy in the basement. That small domestic errand becomes the starting point
for an ordeal much larger than he can comprehend.

Mark, Matthew's father, loves his son unconditionally, but he is struggling
with severe anger-management problems after a difficult divorce. Mark is also
part of a secret group of divorced fathers called the Arsonists. The cult
channels resentment into targeted arson: its members burn houses in order to
make children orphans as a grotesque form of revenge.

The central tragedy is Mark's failure to tell the other Arsonists to spare his
own house. While Matthew is downstairs looking for candy, the cult sets the
house on fire. Matthew does not realize what is happening above him until the
fire has made escape impossible.

### Nightmare as the playable world

The basement is both a physical place and the point of view through which the
player experiences Matthew's crisis. Its rooms, enemies, and hazards take on a
feverish, surreal quality as heat, smoke, fear, and the child's limited
understanding blur together. The strange monsters are not necessarily
literal creatures in a normal house; they can be read as the nightmare logic
of a child trapped in an overwhelming emergency.

The reference names Scar, spiders, and flies as examples of the bizarre
creatures Matthew encounters. That imagery supports psychological surrealism:
ordinary surroundings become threatening, and a desperate survival journey is
filtered through a child's perception.

### The ascent and Kagutsuchi

Matthew does not escape the burning house in the physical world. Instead, his
journey carries him through surreal depths and then upward toward the sky or
heaven. The ultimate confrontation is with Kagutsuchi, also called Kagu, the
entity worshipped by the Arsonists and described in the lore as the source of
their destructive influence.

This ascent gives the roguelite journey a tragic double reading. In gameplay,
the player advances through floors and defeats bosses; in the narrative, the
upward movement may represent Matthew's final passage beyond the burning
house. The exact metaphysical interpretation is intentionally presented as
surreal rather than explained as ordinary physical geography.

### Lore-to-implementation boundary

The reference above is the canonical narrative brief supplied for this guide.
The current gameplay progression covers seven floors (basement, living room,
kitchen, bedroom, attic, roof, and sky) with four bosses: The Crawler, Lil'
Snake, The Stuffing, and The Geometric. Heaven and Fireland (Kagu) are not
implemented as floors, and Kagutsuchi is not implemented as a boss. The full
Arsonist/Mark backstory is not encoded in gameplay dialogue. Treat those
elements as official narrative direction, not as proof that those scenes or
encounters are already present in code.

## 2. Technical Architecture and Code Summary

### Framework and entry point

The project is a LÖVE 2D game written in Lua. Run it from the repository root
with `love .` after installing a compatible LÖVE 11.x runtime. `main.lua` is
the application entry point and owns LÖVE callbacks, global game-state
orchestration, persistence, audio setup, combat coordination, and transitions.
Gameplay systems are split into required Lua modules; art, audio, fonts, JSON,
and XML data live under `resources/`.

`main.lua` is close to Lua's limit of 200 top-level `local`s per chunk. That is
why screen-fitting helpers live as fields of a single `View` table and why many
helpers (`drawWorld`, `enterRoom`, `startGame`, the music start/stop functions,
and so on) are intentionally global functions. Add new state to `View` or an
existing module instead of declaring more top-level locals.

The main LÖVE lifecycle is:

1. `love.load()` first sets the nearest-neighbor default filter, then installs
   the `View` canvas shim, builds the 16:9 canvas, loads tile assets, profile
   and items, creates the world/player/input/renderer objects, initializes
   audio, and finally starts the opening cutscene (or its fallback card).
2. `love.update(dt)` dispatches by `gameState`, advances transitions and audio
   fades, and, while playing, updates input, player, enemies, bosses,
   projectiles, items, active effects, autosave, and room/floor progression.
3. `love.draw()` renders the whole frame into the fixed canvas through
   `View.drawFrame()`, then draws that canvas to the window with whole-number
   scaling over a dark starfield (see *Display* below).
4. `love.resize()` refreshes the camera size and the display audit log.

### Core modules

| File | Responsibility |
| --- | --- |
| [`main.lua`](./main.lua) | LÖVE callbacks; `View` display pipeline; game-state flow; world setup; audio/profile/save handling; combat and progression orchestration; room entry/transitions; active-item effects; shop and cultist-deal interaction; drawing of the floor, decals, and furniture. |
| [`conf.lua`](./conf.lua) | LÖVE configuration: desktop fullscreen, windowed size and minimum size, gamma correction, high-DPI setting, resizability, and vsync. |
| [`renderer.lua`](./renderer.lua) | Sprite/atlas drawing, the angled stone wall frame and door sprites, the overlay HUD, boss health bar, minimap, projectiles, enemy/boss drawing, boss intro, character carousel, and pickup notification. |
| [`rooms.lua`](./rooms.lua) | Seeded procedural room graph and layouts, enemy placement, boss/shop/item/deal room placement, and the per-floor wall color themes. |
| [`player.lua`](./player.lua) | *(not re-verified)* Player state, movement, facing, damage/invulnerability, hurt animation timing, collectible effects, sweat-shot cooldown/recoil. |
| [`input.lua`](./input.lua) | *(not re-verified)* Keyboard movement and held attack directions, gamepad D-pad input, configurable bindings. |
| [`mainmenu.lua`](./mainmenu.lua) | *(not re-verified)* Title/menu sections, settings, extras, pause UI, item selector, selection, back-stack navigation, transitions. |
| [`items.lua`](./items.lua) | *(not re-verified)* XML-driven item definitions, inventory, pickup/offer behavior, stat effects, active items, notifications. |
| [`atlas.lua`](./atlas.lua) | *(not re-verified)* Loads character sprite metadata and creates frame quads. |
| [`sweat_projectile.lua`](./sweat_projectile.lua), [`acid_projectile.lua`](./acid_projectile.lua) | *(not re-verified)* Player sweat shots and enemy acid shots. |
| [`firefoam.lua`](./firefoam.lua), [`wet.lua`](./wet.lua) | *(not re-verified)* Directional fire-foam beam and wet/fire interaction support. |
| [`enemy.lua`](./enemy.lua), [`scar.lua`](./scar.lua), [`spider.lua`](./spider.lua), [`fly.lua`](./fly.lua), [`centipede.lua`](./centipede.lua), [`stationary_angel.lua`](./stationary_angel.lua) | *(not re-verified)* Regular enemies; the Stationary Angel is the Sky floor's only enemy. |
| [`crawler.lua`](./crawler.lua), [`baby_widow.lua`](./baby_widow.lua), [`lil_snake.lua`](./lil_snake.lua), [`the_stuffing.lua`](./the_stuffing.lua), [`the_geometric.lua`](./the_geometric.lua) | *(not re-verified)* Boss and boss-minion state, attacks, movement. |
| [`json.lua`](./json.lua) | JSON encoding/decoding used for saves, profile, and sprite metadata. |

The `resources/` tree holds sprites, tiles, fonts, music/SFX, and data. Item
definitions come from `resources/items.xml`; sprite sheet frame data is JSON
(for example `resources/sprites/attack/firefoam.json` and the door sheets'
`doors.json`). Prefer extending the system that already owns the behavior
instead of adding duplicate orchestration to `main.lua`.

### Display, scaling, and framing

The whole game is drawn into **one fixed offscreen canvas of 1344 x 756
(exactly 16:9)**. Game code never sees the real window size:
`love.graphics.getWidth/getHeight/getDimensions` and
`love.mouse.getPosition` are redirected by `View.install()` to canvas
coordinates, so menus, HUD, boss intro and mouse aiming all work in canvas
space.

- **Window.** `conf.lua` starts in **desktop fullscreen** (borderless, native
  desktop resolution, so any monitor size or aspect ratio works). The windowed
  size is 1344 x 756 with a 672 x 378 minimum, resizable, high-DPI off, gamma
  correction off, vsync on. **F** or **F11** toggles fullscreen
  (`View.toggleFullscreen`, which calls `love.window.setFullscreen(..., 'desktop')`).
  The old maximize/restore toggle is gone.
- **Integer scaling.** `View.fit()` picks `math.floor(min(windowW / 1344,
  windowH / 756))` as the scale and centers the canvas at whole-pixel offsets,
  so every texel is an exact block of screen pixels. The room is never stretched
  to fill the monitor; the leftover area is a dark starfield ("outer space").
  Only when the window is smaller than the canvas (scale would be below 1) does
  it fall back to a fractional fit so the whole room stays visible. Consequence:
  1080p and 1440p screens get 1x; 2x needs a window of at least 2688 x 1512.
- **Pixel art.** `love.graphics.setDefaultFilter('nearest', 'nearest')` is the
  first call in `love.load()` (before anything creates an image, canvas or
  font), and sprites/canvas also set the filter explicitly. Keep that when
  adding assets. There is no shader or color-grading pass.
- **Room inside the canvas.** The playable room is 1344 x 704 (21 x 11 tiles of
  64 px). It sits at `View.ROOM_OFFSET_X/Y` = (0, 26) inside the canvas; the 26 px
  above and below belong to the wall frame, so the framed room fills the canvas
  exactly. Gameplay uses a frozen camera whose offset equals that room offset
  (plus screen shake); `drawWorldFramed()` applies the same offset for screens
  that call `drawWorld()` outside normal play (game over, floor transition,
  floor complete).
- **Diagnostics.** `logFullscreenColorState` prints window/graphics dimensions,
  DPI scale, fullscreen flags, active canvas, colors and blend mode on resize
  and around the fullscreen toggle. It is instrumentation only.

### Room frame: angled stone walls and doors

The room is surrounded by an Isaac-style 2.5D stone frame drawn by
`Renderer:drawRoomFrame(theme, frame, doors)`, called from `drawWorld()` after
the floor, decals, furniture and floor holes.

- **Geometry.** Four trapezoid bands joined by 45 degree mitres, like a picture
  frame. The outer edge is the canvas border; the inner edge is the floor
  rectangle (`View.WALL_THICKNESS` = 64, so the floor is 1216 x 576). Because the
  outer edge is longer than the inner one, brick joints lean toward the room
  center and courses shorten toward the floor, giving the slanted, thick look.
  Each band has a lit "cap" along the outer edge, three staggered brick rows with
  deterministic per-brick shade noise, a bevel line at the floor edge, per-wall
  lighting (top brightest, bottom darkest), and a soft contact shadow on the
  floor.
- **Collision.** The outer 64 px tile ring is solid: `world.wall` is set from
  `View.WALL_THICKNESS`, and `rooms.lua` already keeps obstacles inside tile
  columns 1-19 / rows 1-9.
- **Floor themes.** Wall colors come from `Rooms.getWallTheme(floorType,
  roomType)` using `Rooms.wallThemes` (`face`, `mortar`, optional `cap`, optional
  pulsing `glow`). There are palettes for all seven floors, plus ready-made
  `cellar` and `burning_basement` entries for floors that do not exist yet. Shop
  and Cultist Deal rooms tint their floor's walls (gold-ish and purple). Unknown
  floors fall back to the basement palette. Add an entry whenever a floor type
  is added.
- **Doors.** Each door is a 32 x 32 frame from a 128 x 64 sheet (closed, three
  opening frames, open), drawn at 2x so it is exactly one tile in the 64 px wall
  ring, rotated per wall. A locked door shows the closed frame; when the room
  clears it plays the opening frames (0.1 s each) and rests on the open frame.
  Re-entering a room never replays the animation. `DOOR_SHEET_PATHS` and
  `DOOR_SHEET_FOR_KIND` at the top of `renderer.lua` choose the sheet per door
  kind (`normal`, `boss`, `shop`; the `deal` and `item` kinds reuse the boss and
  shop sheets). If a sheet file is missing, that door falls back to a
  procedural stone door. The door opening is `View.DOOR_LENGTH` = 64 px, while
  `View.DOOR_TRIGGER_LENGTH` = 112 px is how far off-center the player may be and
  still use it (`View.atDoor`).

### HUD

There are no sidebars. All HUD elements float on the wall frame at about 88%
opacity so the brick shows through; text gets a 1 px shadow.

| Element | Placement |
| --- | --- |
| Minimap | Top-left, 176 x 112 translucent panel (seen/explored/cleared/boss/current colors). |
| Hearts | Top-right, right-aligned, 20 HP per heart, wrapping after 10 per row; a half heart is drawn when under 20 HP remains in that slot. Only the red full/half heart sprites are drawn. |
| Coins | Right-aligned directly under the hearts. |
| Stats | A column on the left wall, vertically centered: icon against the wall, value to its right. |
| Collected items | Bottom-left over the bottom wall, 7 per row, growing upward. |
| Active item | Bottom-right corner with a cooldown overlay and "Q: USE" prompt. |
| Boss health bar | Bottom center (`getHeight() - 56`) while in a boss room. |
| Pickup notification | Top center panel for 3.4 seconds. |
| Floor name banner | Fades over 3 seconds after entering a floor. |

Displayed stat values (presentation only; underlying values are not changed):

| HUD row | Value shown |
| --- | --- |
| Damage | `floor(player.stats.damage)` |
| Speed | `max(1, floor(player.speed / 35))` |
| Attack speed | `player:getAttackSpeed()` (whole numbers without a decimal, otherwise one decimal) |
| Range | Constant 1 (`112 / 112`), not a modifiable stat |
| Defense | `player.stats.defense or 0` |

The character-select carousel shows hard-coded preview stats (5 hearts, speed
350, damage 20, range 540, attack speed 2.9) that are not read from the player.

### Game state, menus, and input

`main.lua` represents the application flow with a `gameState` string:
`opening_cutscene`, `cutscene_fallback`, `title`, `character_select`, `playing`,
`paused`, `item_selector`, `boss_intro`, `cultist_choice`, `floor_transition`,
`floor_complete` (a drawing branch exists), and `game_over`. LÖVE key, mouse,
and gamepad callbacks route events to the current state's owner. The menu owns
section navigation and returns actions (new game, continue, quit); `main.lua`
performs them.

The title screen supports keyboard, mouse and gamepad, back navigation,
transitions, and settings (music volume, SFX volume, screen shake). If
`resources/gfx/cutscenes/mainmenucutscene.ogv` exists it plays first and can be
skipped; otherwise a short template card appears.

Character select offers Matthew (unlocked) and Stella ("The Unstable Spark",
locked, shown as `???`). Picking a locked character only plays the select sound.
There is no unlock code for Stella in `main.lua`.

Controls: **WASD** moves; arrow keys/D-pad hold-to-fire; holding the left mouse
button aims at the cursor (mouse position is converted from window to canvas to
world coordinates); **E** or **Enter** uses shop and cultist offers; **Q** fires
the held active item; **P** or **Esc** pauses; **F** or **F11** toggles
fullscreen; **R** or **Space** restarts after death. Key bindings are
configurable and saved with the run.

Developer shortcuts are off for players. Set the environment variable
`HEAT_DWELLER_DEBUG=1`, or place an empty `debug.flag` file beside `main.lua`
or in the save folder, to enable: **F7** during play opens the item selector,
**F7** on character select opens a boss-teleport menu (Crawler, Lil' Snake,
Geometric, Stuffing), and **F8** skips to the next floor. Do not ship
`debug.flag`.

### Combat and damage feedback

The primary player projectile is the sweat drop, spawned by the player's
`onShootSweat` callback for Matthew and updated by
`SweatProjectile.updateAll` against enemies, bosses, boss parts, minions and
room walls. Defeating a target awards dollars: +1 for a regular enemy, +3 for a
Baby Widow, +8 for a boss (boss limbs/parts award nothing).

*(not re-verified)* `sweat_projectile.lua` moves shots in a straight line at
constant speed with a fixed range, no gravity, arc or spread, and spawns a brief
splash on impact. Default internal damage is 20 and a sweat hit applies 20% of
that. Shooting updates facing and applies a small recoil impulse; movement
momentum is not added to projectile velocity.

Other offense:

- **Fire foam** is a separate beam system (`firefoam.lua`) active while the
  player owns item id 23; it damages every enemy, boss and boss part in its path
  and is drawn by `Renderer:drawFireFoam`.
- **Active items** (key **Q**, with a cooldown): playdough platform, cake (heal
  20 and 5 s of invulnerability), molotov (fire zone ahead of the player),
  charger (halves enemies' health, leaves the player at 10 HP or dead if already
  at 10 or less), duality (rerolls passive items), snowman (arms a familiar that
  activates when the player is next hit), cultist oath (damages everything,
  costs 20 HP), bread (50% full heal and invulnerability, otherwise lose 20 HP),
  and mallet (chance scales with luck to deal damage, otherwise drops the player
  to 10 HP). Their effects live in `activateHeldItem()`/`updateActiveEffects()`
  in `main.lua`.
- **Contact damage**: the Crawler and a Lil' Snake head cost a full heart
  (boss damage); a Lil' Snake body segment costs half.
- **Enemy attacks** include acid projectiles (Baby Widow), Stuffing
  projectiles/suction, and the Stationary Angel's telegraphed divine beam.

Taking damage plays a random hurt sound with a slight pitch variation and
triggers a 4-6 pixel screen shake (0.2 s, disabled by the screen-shake
setting). *(not re-verified)* The hurt animation lasts 0.4 s and invulnerability
1.0 s; both live in `player.lua`.

### Procedural rooms, floors, and progression

`rooms.lua` builds a connected room graph of up to 15 rooms per floor from a
deterministic seed (growing a random frontier on a grid), then assigns:

- **Layouts.** Every room is a 21 x 11 tile grid with one of four wall patterns
  (two pillars, two long bars, one 2x4 block, two 2x2 blocks), plus floor
  furniture: couch/table (living room), counter/cabinet (kitchen), bed/dresser
  (bedroom), crates, cobwebs and rafters (attic), roof edge (roof), cloud
  platforms and drifting clouds (sky). Attic blocks are shrunk; walls touching
  furniture are removed. These solid obstacles are separate from the stone frame.
- **Enemies.** 2-4 enemies per combat room (3-4 on the roof), spawned on tile
  centers in the middle of the room. Enemy pools: basement (scar, spider, fly,
  centipede), living room (scar, spider, centipede; 20% of rooms are a fixed
  scar + two spiders), kitchen (scar, fly, centipede), bedroom (scar, spider,
  centipede), attic (spider, fly, centipede), roof (scar, fly, centipede).
  **The Sky contains only Stationary Angels**, 1-4 per room on free slots that
  avoid walls and obstacles (never more than 4, never on any other floor).
- **Bosses.** The room farthest from the start (Manhattan distance on the grid)
  becomes the boss room. Basement and living room pick The Crawler or Lil'
  Snake; the bedroom uses The Stuffing; kitchen, attic, roof and sky use The
  Geometric. This placement is marked TODO for authored boss placement.
- **Special rooms.** One shop (two item offers), one item room ("Forgotten
  Cache", reward spawned on entry), and a Cultist Deal room attached to the boss
  room on the first free side.
- **Doors** start unlocked in data; `main.lua` locks them while a room's enemies
  are alive.

`main.lua` themes each floor with a palette and a per-floor Base + Decal tile
floor: `resources/gfx/tiles/<floor>_tile.png` (the living room also accepts
`livingroom_tile.png`) with shared overlay decals from
`resources/gfx/tiles/overlays/`, filtered per floor by `TILE_FLOOR_DECALS`
(10% of tiles by default, 5% in the kitchen, none in the sky). Decals are seeded
from run seed + floor + room id, so a room looks the same on every visit and
after Continue. A floor without a tile image falls back to a procedural grid.
Floor music: basement, kitchen and sky have their own tracks; the other floors
share the background track scaled up slightly per floor. The Sky also swaps
Matthew to his angel sprite sheet.

Progression: clear a room's enemies to unlock its doors. In a boss room the
only exit is the Cultist Deal door, which unlocks when the boss dies. Killing a
boss plays a 1.8 s death sequence with particles and shake, counts toward the
profile's bosses-defeated total, spawns the floor reward, restores the floor
music, and (except on the last floor) spawns a ladder at the top-left of the
room that starts the 2.4 s floor transition to the next floor. Floors are
regenerated from `runSeed + floorIndex`. The Sky is the last floor: there is no
ladder there, no victory or ending state yet, and nothing after it.

Boss notes (details *not re-verified* beyond what `main.lua` wires up):

- **The Crawler** spawns a spider every 5 seconds; its Baby Widow phase spawns
  spiders and fires acid; the Crawler enters phase two when the Baby Widow dies.
- **Lil' Snake** leaves a trail and digs timed floor holes.
- **The Stuffing** (bedroom) has a normal and a "charred" sprite sheet, a
  suction attack and projectiles.
- **The Geometric** uses a large body, orbiting head armor, shield and invulnerability
  phases, and a final bouncing head; it reports screen shake to `main.lua`.

Shops: walking near an offer and pressing **E**/Enter buys it if the player has
enough dollars. Cultist Deal: the offer opens a choice screen where **1** costs
one heart container (20 max health) and **2** costs 15 speed (minimum 40);
**Esc** leaves the deal.

Item data is parsed from `resources/items.xml`. *(not re-verified)*
`items.lua` creates the inventory, loads sprites with nearest filtering,
applies passive stat changes, handles active-item cooldowns and pickup/offer
state, and emits stat-change notifications. `main.lua` increments the profile's
per-item pickup counts and refreshes the Extras menu whenever an item is acquired.

### Audio

`main.lua` coordinates the menu theme (fades in/out with the title and
character select), floor music, boss intro / active-start / loop tracks with a
0.2 s crossfade, hurt sounds, Baby Widow sounds, boss-defeat sound,
floor-transition sound, and generated menu tones. Boss music volumes are
restored before every boss track because several code paths mute them.
Item pickup briefly ducks and pauses game audio until the pickup sound ends.
`isAudioLocked` blocks music restarts during a floor transition. Music and SFX
volume settings propagate through the menu settings callback and are saved in
the profile. Avoid starting menu music during the opening cutscene; the
cutscene completion path owns the transition to the menu.

### Persistence

Persistence is stored in LÖVE's save directory, not beside the source files.

- **`heat_dweller_run.json`** (snapshot version 1) stores the seed, floor
  index/type, the full room graph and flags, current room, explored/seen rooms,
  door lock state, player position/facing/speed/stats/active effects/platform,
  inventory, active items, held active item and cooldown, fire zones and
  snowman timers, enemies and boss state (Crawler, Lil' Snake and its trail,
  Geometric, Stuffing, Baby Widow), acid projectiles, shop and Cultist offers,
  input bindings, and the selected character. Sweat projectiles/splashes, the
  Stuffing's projectiles, and the fire-foam beam are not saved. Autosave runs
  every 10 seconds, on entering a room, when quitting to the title from pause,
  and on exit. Continue validates the version and required fields before
  restoring, restarts the right floor music, and a new run deletes the old save.
  Room decals and wall themes are derived from the seed and floor type, so
  nothing about them is saved.
- **`heat_dweller_profile.json`** stores runs started, bosses defeated, per-item
  pickup counts, music and SFX volume, and the screen-shake setting.

When modifying save fields, update both snapshot creation and continue/restore
logic, and preserve validation/default handling for older or malformed data.
Dying and pressing **R**/**Space** starts a brand-new run (new seed, floor 1) with
the selected character; it does not reload the save.

## 3. Not Implemented / Planned

Treat these as direction, not as existing features:

- Heaven and Fireland floors, and the Kagutsuchi (Kagu) boss.
- Any victory, ending or run-summary screen after The Sky.
- Stella's unlock path (the character exists but is permanently locked in
  `main.lua`).
- Achievement and unlock tracking, including the roof unlock gate. The planned
  achievements live in `achivements.xml`; no loader or triggers exist in the
  files reviewed.
- Additional heart types (the HUD draws only red full and half hearts).
- Dedicated door art for treasure/item rooms and the Cultist Deal door (they
  reuse the shop and boss sheets).
- Authored (non-formula) boss and special-room placement in `rooms.lua`.
- `cellar` and `burning_basement` floors (wall themes exist; the floors do not).

## 4. Summary for Future AI Collaborations

### Quick-reference checklist

- **Runtime:** LÖVE 11.x, Lua; `main.lua` is the callback/orchestration entry
  point. Run from the project root with `love .`.
- **Display:** Fixed 1344 x 756 (16:9) canvas, integer-scaled and centered over a
  dark starfield; starts in desktop fullscreen; **F**/**F11** toggles. Game code
  works in canvas coordinates only. The room is 1344 x 704 at offset (0, 26).
- **Pixel art:** Preserve the `nearest, nearest` filter (set first in
  `love.load()`). Do not add blur, CRT or color-grading passes unless asked.
- **Walls and doors:** Drawn by `Renderer:drawRoomFrame`; the 64 px ring is solid;
  colors from `Rooms.getWallTheme`; door sheets configured at the top of
  `renderer.lua`.
- **HUD:** Floating over the walls: minimap top-left, hearts and coins
  top-right, stats on the left wall, items bottom-left, active item bottom-right.
- **Module ownership:** Keep player rules in `player.lua`, input and bindings in
  `input.lua`, drawing in `renderer.lua`, menu state/UI in `mainmenu.lua`, room
  generation and wall themes in `rooms.lua`, item data/effects in `items.lua`,
  and sweat projectile physics in `sweat_projectile.lua`. `main.lua` connects
  them and owns run progression, high-level state transitions, persistence,
  and shared audio. Mind the 200-local limit in `main.lua`.
- **Floors and bosses:** Seven floors; Crawler or Lil' Snake (basement, living
  room), Stuffing (bedroom), Geometric (kitchen, attic, roof, sky). Sky enemies
  are Stationary Angels only (max 4 per room).
- **Player controls:** WASD moves; arrow keys/D-pad hold-to-fire; mouse-left aims
  and fires; E/Enter interacts; Q uses the active item; P/Esc pauses.
- **Displayed stats:** Damage `floor(damage)`, speed `floor(speed / 35)`, attack
  speed from `player:getAttackSpeed()`, range fixed at 1, defense fallback 0.
  Only change what is displayed, not internal physics values.
- **Damage feedback:** 4-6 px screen shake over 0.2 s; respects the saved
  setting. *(Hurt animation 0.4 s and 1.0 s invulnerability: not re-verified.)*
- **Save compatibility:** Update both save serialization and restore paths
  for persistent run changes. Keep profile/preferences distinct from the
  active-run snapshot.
- **Debug:** `HEAT_DWELLER_DEBUG=1` or `debug.flag` enables F7/F8; never ship
  `debug.flag`.
- **Validation:** Use `luac -p` on changed Lua files and run targeted behavior
  checks. Check editor diagnostics after editing; there is no guarantee that
  every subsystem has a standalone automated test suite.
- **Documentation accuracy:** Clearly separate official lore, current code,
  and future narrative plans. Do not claim a story scene, boss, floor, shader,
  or gameplay feature is implemented merely because it appears in the design
  reference.