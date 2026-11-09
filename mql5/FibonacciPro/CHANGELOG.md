# Fibonacci Pro changelog

Each released version is kept as its own source file, so any version can be installed or compared without git:

| Version | File | Commit |
|---|---|---|
| 1.70 | `Fibonacci_Pro_6.mq5` | this branch, after 1.60 |
| 1.60 | `Fibonacci_Pro_5.mq5` | `5d7bcca` |
| 1.50 | `Fibonacci_Pro_4.mq5` | original upload |

All versions read and write the same drawings file, the same presets and the same toolbar layout. Moving to a newer version keeps everything.

Moving back has limits:
- 1.60 opens files with up to 128 drawings.
- 1.50 opens files with up to 24 drawings.
- If a file holds more drawings than that, the older version falls back to its last backup.

## 1.70

- **Lines stick to the chart.** Fib levels, labels, the diagonal and the selection grips are now native MT5 chart objects anchored to time and price. The terminal draws them in the same pass as the candles, so they move with the chart while scrolling and zooming with no lag, and the indicator does no work while you pan.
  - The transparent or gradient fill still uses a background bitmap, only created when a fill is on, so it can still trail by one frame.
  - Floating labels pinned to the window edge of a rayed level also trail by one frame. All other labels are anchored.
  - Dashed and dotted styles draw solid at widths above 1; this is an MT5 limitation for native lines.
- **Drawings list.** A new List button on the toolbar opens a manager for all drawings:
  - Search by name or description.
  - Filter by All, This TF, Fibs or Lines.
  - Sort by creation (#), Name, Type, TF or Price; click a header again to reverse.
  - Each row has a colour swatch and buttons to show or hide the drawing on this timeframe, scroll the chart to it (Go), Edit it, or Delete it (click twice).
  - Click a row to select the drawing; double-click to open Properties.
  - "Show all here" and "Hide all here" act on every drawing in the filtered list.
  - Page with the < > buttons or the mouse wheel. The list follows the drawing selected on the chart.
- **Up to 1000 drawings per workspace** (`InpMaximumSetups`, default 1000).
  - Drawings outside the visible time window are skipped for hover, selection and fill.
  - While dragging, only the dragged drawing is updated.
- **Redraw interval** can now go down to 8 ms (`InpFrameMilliseconds`, default 16), for 120–144 Hz screens. With native objects it only affects the fill, edge-pinned labels and the hover tooltip.
- **Candle tooltip:** the instrument and timeframe now sit on their own line under the date, so the tooltip is narrower.
- The toolbar title shows the version number.
- The source is plain ASCII. Symbols such as × ● ○ ▲ ▼ → ■ are built from code points, so the file compiles the same whatever encoding MetaEditor assumes.
- **Self-repair** now also covers drawing objects deleted by another program; they are rebuilt within a second.

## 1.60

See `README.md`. In short:
- Attach and responsiveness fixes: timeframe-switch race, drawings invisible on their own timeframe, silent refusals.
- Synchronous object calls removed.
- New features: hover tooltips, opacity slider, preset delete, label position, single-click horizontal lines, higher-timeframe visibility.

## 1.50

Original version.
