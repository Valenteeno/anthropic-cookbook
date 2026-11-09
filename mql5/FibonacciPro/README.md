# Fibonacci Pro (MetaTrader 5 indicator)

**Current version: 1.70, `Fibonacci_Pro_6.mq5`.** Earlier versions are kept side by side; see `CHANGELOG.md` for the version table and what changed in each.

Install: copy `Fibonacci_Pro_6.mq5` to `MQL5/Indicators`, compile it in MetaEditor, then attach it to a chart. Remove an older copy from the chart first. Saved drawings, presets and the toolbar position carry over between versions (same files, same format).

The sections below explain the fixes made in 1.60. 1.70's changes are in `CHANGELOG.md`.

## Why it sometimes did not attach, or stopped responding

1. **Timeframe switch race.** MT5 can run the new copy's `OnInit` before the old copy's `OnDeinit`. In 1.50 that caused three problems:
   - The new copy found the old copy's `Alive` marker or storage lock, returned `INIT_FAILED` and was removed from the chart, so the tool didn't attach.
   - When the new copy did attach, the old copy's `OnDeinit` then deleted objects by the shared prefix. That removed the new copy's canvases, so drawings vanished until the chart was resized.
   - The old copy's `OnDeinit` also switched `CHART_EVENT_MOUSE_MOVE` off. Toolbar buttons kept working, but press-drag drawing got no mouse events and did nothing.

   **Fix:** each copy now uses instance-unique object names. A new copy waits, without failing, until the old copy has released the workspace marker (a heartbeat) and the storage lock. `OnDeinit` only deletes its own objects, and only removes the marker if it still owns it. A leftover marker restored from a saved profile is recognised as stale and cleaned up.
2. **New drawings could be invisible on the timeframe they were drawn on.** With a customised visibility set, new Fibs inherited that set, which could exclude the current timeframe. Drawing appeared to do nothing. **Fix:** a new drawing is always visible on its drawing timeframe.
3. **Silent refusals.** Messages such as "Drawing limit reached" only appeared in a tooltip, so the tool looked frozen. **Fix:** messages now show for 5 seconds in a status line under the toolbar. The drawing limit is raised from 24 to 64 by default (128 maximum).
4. **Self-repair.** Once a second the tool turns mouse-move events back on if another program switched them off, and recreates its canvas or toolbar if they were deleted from outside.

## Speed

- **No synchronous object calls in hot paths.** `ObjectFind` and `ObjectGet*` wait for the whole chart command queue, and 1.50 called them for every control it built (more than 140 times when opening the colour palette). A local registry of owned objects replaces those calls, and rebuilds send only the properties that changed.
- **Stable controls.** Controls are no longer deleted and recreated on every panel change; stale ones are swept. Reading the edit boxes only touches the panel's own edit boxes, not every object on the chart.
- **Fill layer uploads.** The full-chart fill bitmap is only re-uploaded when its pixels would change, for example not while dragging a Fib that has no fill.
- **One projection per frame.** Each drawing is projected once per frame and the result is shared by rendering, selection and hover. The per-frame copy of every drawing (64 levels with strings each) is gone.
- **Smaller costs.** The OHLC magnet uses one `CopyRates` call instead of three. The colour spectrum uses a linear mix instead of a full HSV conversion per pixel. Hover work is limited to one update per frame, and the chart only redraws when the tooltip changes.

## New features

1. **Candle hover:** an OHLC tooltip shows when the pointer is over any part of a candle (body or wick).
2. **Fib hover:** a tooltip on any level shows the Fib's name, its description, the level, the price on that line and the timeframe it was anchored on.
3. **Opacity slider:** a slider sits next to the opacity number field (Fill tab). It is draggable or clickable, and the fill previews live.
4. **Delete presets:** a Delete button in the Load preset dialog. Click it twice to confirm. The selected preset is highlighted.
5. **Label position:** three dropdowns next to "Show level labels":
   - Above or below the line.
   - Left (origin) or right (end).
   - Fixed at the Fib's end, or floating at the chart edge when the level is rayed.

   The defaults reproduce the 1.50 placement.
6. **New Fib modes:**
   - Press-drag-release draws a Fib with the last used levels, as before.
   - A single click draws a horizontal line: one boundary level on (0%), all others off, and the origin snapped to the nearest OHLC point (radius set by `InpLineSnapPixels`), rayed right.
   - To move the line, drag its origin handle (time and price) or drag the line itself (price only). It re-snaps to OHLC and both anchors move together, so it stays horizontal. A plain click or double-click never moves it.
   - Horizontal lines never replace the "last used" Fib template.
7. **Higher timeframes:** every timeframe toggle on the Visualization tab is now enabled, including those above the drawing timeframe. There is also a new "All timeframes" button.

## New inputs

| Input | Default | Meaning |
|---|---|---|
| `InpLineSnapPixels` | 20 | OHLC magnet radius for single-click horizontal lines and moving them |
| `InpMaximumSetups` | 64 | Drawings per workspace (1..128) |
| `InpHoverCandleInfo` | true | Candle OHLC tooltip |
| `InpHoverFibInfo` | true | Fib level tooltip |

Level labels now use a fixed 15 px font height, so their size no longer depends on the Windows font scaling setting.

## Verification

MetaEditor is not available on Linux. `tests/` contains a mock-MQL5 harness: `translate.py` rewrites the source as C++ against stubbed MT5 APIs (`mql5_stubs.h`), `mql5_defaults.h` gives every MT5 function an inert default, and `tests.cpp` checks the logic: label rules, visibility masks, the native-object caches (no commands when nothing changed, hide-not-delete grips, slot shifting after a delete, recovery from external deletion), list search, filter and sort with 1000 drawings, and the horizontal-line price math.

```bash
cd tests && python3 translate.py ../Fibonacci_Pro_6.mq5 fp5.cpp && g++ -std=c++17 -fsyntax-only -Wall fp5.cpp
```

```bash
g++ -std=c++17 -w tests.cpp -o tests && ./tests
```

This catches typos, wrong signatures and logic errors. It does not replace a MetaEditor compile and a test on a live chart.
