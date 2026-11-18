# Fibonacci Pro changelog

Each version is kept as its own source file, so any version can be installed or compared without git:

| Version | File | Status |
|---|---|---|
| 1.63 | `Fibonacci_Pro_9.mq5` | **Current.** 1.62 with separate marker strips you can place, and tooltips on zone lines. |
| 1.62 | `Fibonacci_Pro_8.mq5` | Kept unchanged. Commit `cae310b`. 1.61 plus sessions, killzones & macros. |
| 1.61 | `Fibonacci_Pro_7.mq5` | Kept unchanged. Built on 1.60. |
| 1.70 | `Fibonacci_Pro_6.mq5` | Reverted. Recoverable from git history at commit `77f8a8d`; reverted in `cdcad53`. |
| 1.60 | `Fibonacci_Pro_5.mq5` | Kept unchanged. Commit `5d7bcca`. |
| 1.50 | `Fibonacci_Pro_4.mq5` | Original upload. |

All versions read and write the same drawings file, presets and toolbar layout. Moving back to an older version has limits:
- 1.60 opens files with up to 128 drawings.
- 1.50 opens files with up to 24 drawings.
- With more drawings than that, the older version falls back to its last backup.
- Zone settings and zone presets saved by 1.63 can't be read by 1.62 (details under 1.63).

## 1.63

**Every zone has its own marker strip.** Overlapping zones no longer share one engulfing rectangle.
- **Automatic separation:** overlapping strips separate automatically. The longest zone sits nearest its position (the low, the high, or the chart edge), and the others step away from it one row at a time. Strips that only touch still share a row.
- **Stack**, a new option in each zone's Marker popup:
  - **Auto** (the default) moves the strip clear of other strips.
  - **Fixed** keeps the strip exactly at its distance, even on top of another strip. Where strips overlap, their colours are blended.
- **Distance** now applies to all four positions. It is measured from the zone's low, from its high, or from the chart's bottom or top edge. Strips at the chart edge start at 0, flush with the edge, as in 1.62.
- **Drag to place:** while the Zones window is open, press a marker strip on the chart and drag it up or down. The strip follows the pointer.
  - When you release it, its zone switches to Fixed at that distance, so the strip moves the same way on every day.
  - Esc during the drag puts it back.
  - Apply or OK keeps the change; Cancel reverts it.

**Tooltips on zone lines.** Pointing at a line, within 3 px of it, shows what the line is and its price:
- **50% line (midline):** its price, plus the range high and low.
- **Extended high and low:** the price and whether price has taken it out, for example "Taken 03:00 New York" or "Not taken yet". The tooltip works along the whole extension, up to the time it was taken or to the chart's right edge.
- **Range box high and low**, and the **opening-price line**.

Each line tooltip also shows the zone's name, group, date and New York times. Marker strips keep the full zone tooltip. While the Zones window is open, it adds "Drag up or down to place this marker".

**The 50% line has its own switch** in the "..." options, separate from the range box. Settings from 1.62 look the same as before: a zone that had the range box gets both.

**Settings format.** Zone settings and zone presets are saved in a new format (version 2).
- 1.63 reads 1.62's zone settings and presets.
- 1.62 can't read zone settings saved by 1.63. It falls back to the backup file while that is still in 1.62's format, otherwise to its default zones. It doesn't overwrite the 1.63 file unless you press Apply or OK in its Zones window.
- 1.62 can't load zone presets saved by 1.63. The two built-in presets work in both versions.

## 1.62

**Sessions, killzones & macros.** A new **Zones** button, left of the × on the toolbar's title row, opens a window styled like Properties. All times are New York time, with daylight saving handled automatically.

The window has four tabs:
- **Macros:** the zone table. Filter it by group: All, Sessions, Killzones, Silver Bullet, Macros or Time lines. Each row has:
  - On/off, Name, Start and End;
  - boundary-line style (or None), width and colour;
  - Label: Off, Name, or Name + times;
  - Marker, which opens a popup with:
    - position: below the low, above the high, chart bottom or chart top;
    - alignment: centre or right;
    - distance and height in pixels;
    - opacity;
  - a "..." button with more options:
    - group;
    - fill this zone;
    - range box with a 50% line;
    - extend the high and low until price takes them out;
    - opening-price line, to the zone end or the end of the day;
    - alert when the zone starts.

  Start = End draws a single time line, and End before Start runs past midnight. The tab also has Add, Defaults, Sort by time and paging.
- **Parameters:**
  - master switch;
  - group toggles;
  - trading days (a day ends at 17:00 New York, so Sunday evening's Asian session belongs to Monday);
  - days back and today's upcoming zones;
  - broker clock: Auto-detect, NY + 7 h, or GMT+N with no DST, EU DST or US DST, with a live "New York = server" check line;
  - alerts: sound and push to phone, minutes before, and a Test button.
- **Visualization:**
  - the highest timeframe each group is drawn on;
  - boundary lines full height or zone range only;
  - label size;
  - hide labels that don't fit, highlight the live zone, fade older days, hover info.
- **Fill:**
  - on/off;
  - full height, range box, or both;
  - vertical gradient;
  - opacity slider.

**Overlaps stack in an engulfing manner** (replaced in 1.63 by a separate strip per zone):
- An outer zone's marker keeps its own name row on the outer side and wraps the markers of the zones inside it. For example, London wraps London AM and London PM, and New York wraps New York AM and PM.
- Zones that only partly overlap stack in separate rows.
- Zones that just touch share a row.
- Overlapping fills and strips are blended, not overwritten, so nested zones darken naturally.

**Defaults:**
- The seven sessions: Asian 19:00-04:00, London 03:00-12:00, New York 08:00-17:00, London AM 03:00-07:00, London PM 07:00-12:00, New York AM 08:00-12:00, New York PM 12:00-17:00.
- The killzones, Silver Bullet windows, macros and time lines from the lecture. In total the list has 33 zones.

**Highs and lows** come from M1 data, so a 20-minute macro is exact even on an H1 chart.

**Other features:**
- **Presets:** save, load and delete named zone presets. ICT Forex and ICT Indices are built in. Loading a preset keeps your broker-time setting.
- **Shared settings:** they apply to every chart using the same workspace name. Changes made on one chart reach the others within a couple of seconds.
- **Zones button:** it takes the colour of the live zone. Its tooltip shows the New York time, the live zone with the time left, and the next zone with a countdown.
- **Hover tooltip:** pointing at a zone's marker or line shows its name, group, date, New York and server times, high, low, range, open and status.
- **Alerts:** sound and/or push notification when a zone starts. Each alert fires once per zone and day, even with the indicator on several charts.
- **Hotkey:** `InpZonesHotkey` (Ctrl+Shift+K) shows or hides all zones.

## 1.61

Built on 1.60, which draws on a canvas. 1.70's chart-anchored native objects are not included.

**Drawings list**, opened from the new List button on the toolbar. It is the same panel as in 1.70:
- Search by name or description.
- Filter by All, This TF, Fibs or Lines.
- Sort by #, Name, Type, TF or Price; click a header again to reverse the order.
- Each row has a colour swatch and buttons to:
  - show or hide the drawing on this timeframe;
  - Go, which scrolls the chart to it;
  - Edit;
  - Delete, clicking twice to confirm.
- Click a row to select the drawing; double-click to open Properties.
- "Show all here" and "Hide all here" act on every drawing in the filtered list.
- Page with the < > buttons or the mouse wheel. The list follows the drawing selected on the chart.

**Drawings per workspace:** the default and the maximum are both 1000 (`InpMaximumSetups`). Drawings outside the visible time window are skipped before any projection or drawing work, so 1000 drawings mostly cost memory, not redraw time.

**Redraw interval:** the default is now 8 ms (`InpFrameMilliseconds`, range 8 to 100). With canvas rendering every redraw re-sends a full-chart bitmap. If panning makes the terminal feel heavy, set it back to 16.

**Candle tooltip:** the instrument and timeframe are on their own line under the date and time, which makes the tooltip narrower.

**Fibo levels tab:** an "All" colour button sits under the Color column. It opens the colour palette and sets every level to the chosen colour.
- The button shows the shared colour when all levels already match, and white when they differ.
- Like other edits, the change is kept only after Apply or OK.

**Other changes:**
- The toolbar title shows the version number.
- New symbols are built from code points, so they display correctly whatever encoding MetaEditor assumes.

## 1.70 (reverted)

Drew levels, labels, the diagonal and handles as native MT5 chart objects, which move with the chart without lag. Reverted at the user's request. The code is still in git history at `77f8a8d`.

## 1.60

See `README.md`. In short:
- Fixed the tool sometimes failing to attach and sometimes ignoring new draw requests.
- Removed synchronous chart-object calls.
- New features: hover tooltips, opacity slider, preset delete, label position, single-click horizontal lines, higher-timeframe visibility.

## 1.50

The original version.
