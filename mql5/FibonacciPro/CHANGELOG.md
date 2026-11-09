# Fibonacci Pro changelog

Each version is kept as its own source file, so any version can be installed or compared without git:

| Version | File | Status |
|---|---|---|
| 1.61 | `Fibonacci_Pro_7.mq5` | **Current.** Built on 1.60. |
| 1.70 | `Fibonacci_Pro_6.mq5` | Reverted. Recoverable from git history at commit `77f8a8d`; reverted in `cdcad53`. |
| 1.60 | `Fibonacci_Pro_5.mq5` | Kept unchanged. Commit `5d7bcca`. |
| 1.50 | `Fibonacci_Pro_4.mq5` | Original upload. |

All versions read and write the same drawings file, presets and toolbar layout. Moving back to an older version has limits:
- 1.60 opens files with up to 128 drawings.
- 1.50 opens files with up to 24 drawings.
- With more drawings than that, the older version falls back to its last backup.

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
