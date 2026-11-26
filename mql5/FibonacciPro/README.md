# Fibonacci Pro (MetaTrader 5 indicator)

**Current version: 1.71, `Fibonacci_Pro_17.mq5`, with the script `Fibonacci_Pro_Calibrate.mq5`.** Earlier versions are kept side by side; `CHANGELOG.md` has the version table and the changes in each version.

Install: copy `Fibonacci_Pro_17.mq5` to `MQL5/Indicators`, compile it in MetaEditor, then attach it to a chart. Remove any older copy from the chart first. For the lot-size calibration, also copy `Fibonacci_Pro_Calibrate.mq5` to `MQL5/Scripts` and compile it; run it by dropping it on any chart. Saved drawings, presets and the toolbar position carry over between versions (same files, same format). Zone settings carry over to newer versions. 1.63 can read zone settings saved by 1.64, but 1.62 can't read those saved by 1.63 or 1.64. To use the same settings in another terminal or account, use **Share** on the toolbar (1.70; 1.71 fixes its popup): Export in one, Import in the other.

1.62 added sessions, killzones & macros. 1.63 gave every zone its own marker strip, which you can drag into place, and added tooltips on zone lines. 1.64 blends Fib and zone shading, so killzones stay visible over Fib ranges. 1.65 recognises what you draw (FVG, VI, UFVG, SPB, OB, PW, DW, KH, KL, KR) and styles, colours and names it by type and timeframe. 1.66 adds a lot size & risk crosshair: press, drag to your stop, and it shows the volume for your risk per trade. A calibration script measures each symbol's value per lot, for brokers whose contract sizes or tick values differ. 1.67 adds the ICT price points (all 55 levels in 30 rows, plus NWOG) in their own window: they anchor to the minute, can end where price takes them, ray back or hide per chart, and alert. It also numbers new drawings per timeframe and type ("H1 FVG 2 ▲"). 1.68 rays price points back to the chart's first candle, can keep taken lines to the end of their day or week, adds quadrant and octant levels, bold labels, and 120 days back. 1.69 rays a price point forward or drags its end, acts on the one line you click, names the sessions AS, LN and NY on the chart, and looks back 120 days in Zones too. 1.70 shares settings between terminals: Export writes them to one file that every MetaTrader 5 on the computer can open, and Import takes them in another terminal or account. 1.71 fixes the Share popup, which closed as soon as it opened. See `CHANGELOG.md`. The sections below describe the fixes and features introduced in 1.60, which later versions build on.

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

MetaEditor is not available on Linux. `tests/` contains a mock-MQL5 harness: `translate.py` rewrites the source as C++ against stubbed MT5 APIs (`mql5_stubs.h`), `mql5_defaults.h` gives every MT5 function an inert default, and `test_common.h` holds the fakes both test programs share (chart objects, clock, files in memory, and a market with symbols, quotes and an account). `tests.cpp` checks the indicator:

- the 1.61 behaviour (defaults, label placement, masks, list);
- calendar, daylight-saving and broker-clock conversion, including the US/EU mismatch weeks;
- time entry parsing and trading-day mapping;
- the default zone list and the zone settings file round trip, including reading 1.62 settings;
- occurrence building (weekends, upcoming zones) and exact M1 highs and lows;
- liquidity sweeps and holiday detection;
- alert deduplication and the live state on the Zones button;
- compositing of translucent layers;
- blended shading: zones over Fib ranges, the cut-through, timeframe order, fading on lower timeframes and gradients;
- drawing types: the detection rules on every pattern, styles, timeframe colours and widths, names, creating a drawing with the mouse;
- the used state, the Fibo levels tools (sort, move, all widths, level groups, defaults), built-in presets and the list's Used switch;
- marker strips for every marker position: separate strips, Auto and Fixed stacking, and drag to place with Esc to undo;
- line tooltips: midline, extended high and low with their taken status, range box edges and opening price;
- an end-to-end render smoke test;
- the Zones window: tabs, edits, popups, palette, presets and apply;
- price points:
  - the default list (all 55 levels) and the settings file;
  - every window on the broker's clock, including daylight-saving weeks, NWOG and the week-open choice;
  - occurrences over trading days, weeks and months;
  - prices to the minute: windows, opens, gaps, FPFVG, FPOB, and periods from H1 candles;
  - taken levels: highs, lows, opens that price must leave first, CEs and fills, minute candles across a weekend, and hourly candles refined to the minute;
  - alerts, once per level;
  - drawing: line ends, dim, hide and keep, ray back, zone shading, merged and stacked labels, arrows and pinned names;
  - hover info, and selecting a level to ray it back or hide it on one chart;
  - the window: tabs, table edits, sorting (including a click that arrives before the table is rebuilt), dropdowns, colour, the options popup, presets, OK and Cancel;
  - the toolbar button and the shortcut;
  - ray back to the chart's first candle, also while the view is before the level;
  - taken lines to the take, the end of that day or the end of that week, globally and per row, for lines and zones;
  - quadrants and octants: switches, prices, style, labels, hover, taken levels and alerts;
  - bold labels for every row or per row;
  - 120 days back, and M5 candles where the terminal's M1 history ends;
  - ray forward, and an end dragged by hand (with the mouse, Esc, the limit at the level's start, Reset end), for lines, zones and range boxes;
  - the buttons acting on one line (a gap, FPFVG or FPOB as one), and the rays and hides 1.67 and 1.68 saved;
  - names on the chart (AS, LN, NY), and older settings taking them;
  - the settings file of 1.69 (schema 3), and reading the 1.68 and 1.67 ones; the chart's file of rays, hides and ends, and a damaged one;
- zones 120 days back, and M5 candles for their ranges and takes where the terminal's M1 history ends;
- shared settings: what is exported (and what never is), the file read back in full, the previous file kept, importing into another account with its own broker clock (or the file's), the parts chosen, presets replaced with backups, damaged, truncated and newer files, a damaged part, presets named like paths, a part that can't be saved, the Share button and popup (it stays open through the frames that follow a click, an import and an export, and opens below the status line), the folder box, the second click Import asks for, and the start-up hint;
- numbered drawing names per timeframe and type, and duplicates;
- lot size & risk: the volume calculation (rounded down, commission, minimum and maximum volume, and a 20,000-case check that the loss never exceeds the risk and is never a whole step short of it), the four risk modes, sides and entries at market and at a chosen price, targets, the value of a lot by each method with currency conversion, calibration, the settings files, the Risk window, and the measurement made with the mouse from start to finish.

`calib_tests.cpp` runs the calibration script against a fake terminal: the measured values, merging with an existing file, the readable report, the backup, the rule that two agreeing sources outvote the third, and the failure cases (not logged in, no quotes, a calculation the terminal refuses, a damaged file).

```bash
cd tests && python3 translate.py ../Fibonacci_Pro_17.mq5 fp5.cpp && g++ -std=c++17 -fsyntax-only -Wall fp5.cpp
```

```bash
g++ -std=c++17 -w -fsanitize=address,undefined tests.cpp -o tests && ./tests
```

```bash
python3 translate.py ../Fibonacci_Pro_Calibrate.mq5 calib.cpp && g++ -std=c++17 -fsyntax-only -Wall calib.cpp
```

```bash
g++ -std=c++17 -w -fsanitize=address,undefined calib_tests.cpp -o calib_tests && ./calib_tests
```

This catches typos, wrong signatures and logic errors. It does not replace a MetaEditor compile and a test on a live chart.
