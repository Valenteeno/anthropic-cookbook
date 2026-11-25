# Fibonacci Pro changelog

Each version is kept as its own source file, so any version can be installed or compared without git:

| Version | File | Status |
|---|---|---|
| 1.68 | `Fibonacci_Pro_14.mq5` + `Fibonacci_Pro_Calibrate.mq5` | **Current.** 1.67 with price point ray back to the chart's history, taken lines to the end of their day or week, quadrants and octants, bold labels and 120 days back. The calibration script is unchanged (1.66). |
| 1.67 | `Fibonacci_Pro_13.mq5` | Kept unchanged. Commit `491af21`. 1.66 with ICT price points and numbered drawing names. |
| 1.66 | `Fibonacci_Pro_12.mq5` | Kept unchanged. Commit `f3625ea`. 1.65 with a lot size & risk crosshair, and a calibration script for it. |
| 1.65 | `Fibonacci_Pro_11.mq5` | Kept unchanged. Commit `b9395f4`. Drawings typed automatically (FVG, VI, UFVG, SPB, OB, PW, DW, KH, KL, KR), coloured by timeframe. |
| 1.64 | `Fibonacci_Pro_10.mq5` | Kept unchanged. Commit `bece2ee`. Fib and zone shading blended, so killzones stay visible over Fib ranges. |
| 1.63 | `Fibonacci_Pro_9.mq5` | Kept unchanged. Commit `e083f0a`. Separate marker strips you can place, and tooltips on zone lines. |
| 1.62 | `Fibonacci_Pro_8.mq5` | Kept unchanged. Commit `cae310b`. 1.61 plus sessions, killzones & macros. |
| 1.61 | `Fibonacci_Pro_7.mq5` | Kept unchanged. Built on 1.60. |
| 1.70 | `Fibonacci_Pro_6.mq5` | Reverted. Recoverable from git history at commit `77f8a8d`; reverted in `cdcad53`. |
| 1.60 | `Fibonacci_Pro_5.mq5` | Kept unchanged. Commit `5d7bcca`. |
| 1.50 | `Fibonacci_Pro_4.mq5` | Original upload. |

All versions read and write the same drawings file, presets and toolbar layout. Moving back to an older version has limits:
- 1.60 opens files with up to 128 drawings.
- 1.50 opens files with up to 24 drawings.
- With more drawings than that, the older version falls back to its last backup.
- Zone settings and zone presets saved by 1.63 or 1.64 can't be read by 1.62 (details under 1.63).
- 1.63 reads zone settings saved by 1.64 and ignores the two settings 1.64 adds.
- Drawings saved by 1.65 open in every earlier version (details under 1.65).
- 1.66 keeps its risk settings in separate files, so 1.65 opens everything 1.66 saves.
- 1.67 keeps price point settings in separate files, so 1.66 opens everything 1.67 saves.
- Price point settings saved by 1.68 can't be read by 1.67 (details under 1.68).

## 1.68

**Ray back reaches the chart's history.** A rayed price point now runs back to the oldest candle the chart has on its timeframe.
- It stays drawn when you scroll back before the candle it formed on.
- In 1.67 it stopped at the left edge of the view, and disappeared once the view was before that candle.

**Taken lines can run to the end of their day or week.** In Parameters, **Taken lines run to** offers three choices:
- **The take** (as in 1.67).
- **The end of that day:** 17:00 New York of the trading day it was taken in.
- **The end of that week:** Friday 17:00 New York.

The choice applies to lines and zones. A taken level keeps its taken look (dimmed, hidden or kept). Per row, **Ends** now offers: as set in Parameters, at the take, the end of that day, the end of that week, or run on.

**Quadrants and octants.** The Parts column has two new switches for every row with a range: sessions, pre-sessions, opening ranges, gaps, FPFVG/FPOB, and day, week and month.
- **1/4** draws the 25% and 75% levels.
- **1/8** draws the 12.5%, 37.5%, 62.5% and 87.5% levels.
- **The range:** from its low to its high. For a gap, its close and open; for a zone, its bottom and top. The CE keeps its own switch.
- **Look:** dotted. Quadrants are a little lighter than the other lines, octants lighter still.
- **Labels** show just the share ("25%"); the hover info names the row ("London 25%").
- **Taken:** like the CE, each ends where price reaches it, and can alert when the row shows it.

**Bold labels.** Visualization → **Bold labels** sets every row's labels in bold. A row's ... options can set its own labels bold or regular instead.

**Look back up to 120 trading days** (was 60).
- Many terminals keep only about 70 trading days of M1 candles (MT5's "Max bars in chart" setting).
- Where M1 candles are missing, windows, opens, gaps and the minute refinement of day, week and month levels read M5 candles instead. Those older days still draw, anchored to the 5-minute candle rather than the minute.
- FPFVG and FPOB need M1 candles, so they don't appear on those older days.

**Window:** the Price points window is wider (700 px) to fit the new switches.

**Files:** the price point settings file stores the new settings (schema 2). 1.68 reads the files 1.67 saved, but 1.67 can't read the ones 1.68 saves; it falls back to its backup or its defaults.

## 1.67

**Price points.** The ICT price points, drawn for every day, week or month of a look-back, in their own window: **Points** on the toolbar, and Ctrl+Shift+L (input `InpPointsHotkey`) shows or hides them. All 55 levels are in 30 rows, plus NWOG:

| Group | Rows | Lines |
|---|---|---|
| Gaps | ORG, NDOG, NWOG | open, close, CE, and the gap as a zone |
| Pre-sessions | MN, LN and NY pre-sessions, London Close, NY Lunch | high, low |
| Opening ranges | Midnight open; the MN, LN, NY AM, LC and NY PM opening ranges | open; high, low |
| FPFVG & FPOB | The first M1 FVG and order block of the MN, LN, NY AM, LC and NY PM windows | the zone and its CE |
| Sessions | Asia, London, New York | high, low |
| OHLC | Day, week, month | high, low (open, close and CE as options) |

At first only the Asia, London and New York highs and lows, and NDOG, are switched on.

**How they anchor:**
- **Clock:** times are New York times, converted with the broker clock set in the Zones window, so daylight-saving weeks stay right.
- **To the minute:** each high and low starts at the M1 candle that made it, even on an H1 or H4 chart.
- **Trading days:** a trading day runs from 17:00 to 17:00 New York. The look-back counts trading days (Monday to Friday), not calendar days.
- **Window ends:** a window ends before its end minute (09:30 - 10:00 reads the 09:30 to 09:59 candles).
- **ORG and NDOG:** the ORG close is the regular session's close of the session day before; a holiday is skipped. Monday has no NDOG, because its gap is the NWOG.
- **Week opens with** (Parameters) sets NWOG and the weekly open, and is your choice:
  - the first candle after the weekend: the Sunday candle if your broker has one, otherwise Monday's (the default);
  - always Monday's first candle.
- **FPFVG:** the FVG's middle candle opens inside the window.
- **FPOB:** the last opposite candle before the first close beyond a swing that formed in the window (or within 10 minutes after it).
- **Day, week and month levels** come from H1 candles, refined to the minute.

**Lines end where price takes them** (Parameters, on by default):
- **Highs and lows:** a high ends at the first candle trading above it, a low below it.
- **Opens, closes and CEs** end when price comes back to them after leaving them.
- **Zones:** a gap, FVG or order block ends when it is filled, that is when price reaches its far edge. Its CE and near edge end where price reaches them.
- **Taken levels** are dimmed (the default), hidden, or kept as drawn.
- **Off:** every line runs to the right edge.
- **Per row:** **Ends** follows Parameters, or always ends where taken, or always runs on.
- **Alerts** are set per row: a sound and/or a push notification when price takes one of its levels, once per level across every chart of the workspace.

**On the chart:**
- **Style by role:** opens dashed, closes solid, highs dash-dot-dot, lows dash-dot and CEs dotted; the edges of gaps and zones are solid.
- **Colours** follow the Zones window's session colours.
- **Labels** sit at the line ends, stacked so they never overlap. Names at the same price merge into one label ("LSH / NYH").
  - A label shows the name, the name and day, or the name and price, for every row or per row.
- **Zones** are shaded behind the candles (order blocks lighter, FVGs darker) and blend with Fib and session shading.
- **Off-screen levels:** arrows at the top or bottom edge show untaken levels above or below the visible prices.
- **Pinned names** (an option): a line that starts off screen also shows its name at the left edge.
- **Hover info:** the name, price, when it formed, and whether and when it was taken. For zones: the top, bottom, CE and size.

**Select one** by clicking it. Three buttons appear:
- **Ray back:** extends it to the left edge of the chart.
- **Hide:** hides it.
- **Row:** opens its row in the window.

Ray back and Hide apply to this chart only and are remembered. Esc or a click elsewhere deselects it. A row can ray back by default, and its ... options show hidden levels again.

**The window,** laid out like the Zones window:
- **Parameters:** groups, look-back (days, weeks, months), lines end where taken, week open, alerts.
- **Visualization:** the highest timeframe for each group, labels, label size, merged labels, pinned names, arrows, hover info.
- **Fill:** zone shading, opacity (with a slider), OB and FVG shades, range boxes.
- **Price points:** a table with a filter for each group.
  - Click **Name** or **Start / End** to sort; click again to reverse.
  - Each row sets on/off, name, times, parts (O, H, L, C, CE, Box), style (by role, or one style), width, colour, label and ends.
  - Its ... options set the group, the type (range, open, FVG, order block), line names, Mondays only, ray back, the alert, and show hidden levels again.
- **Presets:** save and load, with two built in (ICT price points, All off).
- **Shared:** settings are shared by every chart of the workspace.

**Fib drawings are numbered** per timeframe and type: "H1 FVG 1 ▲", "H1 FVG 2 ▼", "H1 KH 3".
- Both directions share one count, and each timeframe counts separately.
- The next number is one more than the highest in use.
- Existing names are left alone. A 1.66 name without a number counts as 1.
- A duplicate of a typed drawing gets the next number.

**Toolbar:** the title is now ":: Fibonacci Pro 1.67" (drag it to move the toolbar), to make room for the Points button.

**Files:**
- **Price point settings:** `FibonacciPro\<server>_<login>_<workspace>.points`.
- **Levels hidden or rayed back on a chart:** next to that chart's drawings, in `<drawings file>.pts`.
- **Presets:** `FibonacciPro\Presets\*.fpt`.
- **Everything else** is unchanged, and 1.66 ignores the new files.

## 1.66

**Lot size from your risk.** Press on the chart, drag to your stop and release. The box shows the volume whose loss at the stop matches your risk per trade, commission included.

**Making a measurement:**
- Click **Risk** on the toolbar, or press Ctrl+Shift+R (input `InpRiskHotkey`). Until you've saved risk settings, the first measurement of a session opens the Risk window so you can check your risk per trade.
- **Market entry** (the default): press anywhere, drag to your stop and release.
  - The entry is the live ask for a buy and the bid for a sell. It moves with every tick, so the size stays right until you place the order.
  - A stop below the bid makes it a buy; a stop above the ask makes it a sell.
- **A price you choose** (limit or stop order): press at your entry, drag to your stop and release. Or click the entry, then click the stop.
  - The tag names the order to place: BUY LIMIT, BUY STOP, SELL LIMIT or SELL STOP.
- **Market / Limit** on the risk bar under the toolbar switches between the two. The choice is remembered.
- **No magnet:** the stop and entry stay where you put them, rounded only to the symbol's tick size.

**On the chart:**
- **Lines:** a grey entry line (dashed while it follows the market), a red stop line and green target lines, with red and green areas behind the candles.
- **Price tags** at the right edge, for example:
  - "BUY 0.47 lots at market 1.10010"
  - "SL 1.09800  -21.0 pips  -98.70 USD (0.99%)"
  - "TP1  2R  1.10430  +42.0 pips  +197.40 USD"
- **Distances** are in pips on forex, and a price difference elsewhere.
- **Before you press,** the crosshair already shows the size for a stop at the pointer.

**Adjusting:**
- Drag the stop, a target or (for a price you choose) the entry. A plain click moves nothing.
- Targets set as an R multiple follow the stop; a dragged target keeps its price.
- Double-click a target line to remove it.

**Targets:**
- New measurements start with the targets set in the Risk window (2R by default; "1 2 3" gives three).
- **+TP** on the risk bar adds targets at the R multiples typed next to it: one (3) or several (1.5 3 5).
- **-TP** removes the farthest target. A measurement holds up to 8 targets.

**One-off:** the measurement isn't saved. Esc, × on the risk bar or a new measurement removes it.

**Risk window** (the "Risk ..." button on the risk bar):
- **Risk per trade:** a fixed amount, % of balance, % of equity, or % of a fixed base (for example a prop firm's starting balance).
- **Commission per lot,** round turn, set per symbol. It adds to the loss at the stop and comes off target profits.
- **Defaults:** the entry type and the starting targets.
- **Value of 1.00 lot** on the chart's symbol, from each method below, with a field for your own value.
- **Saving:** settings are saved per trading account and shared by every chart and workspace of that account.
- **Preview:** while the window is open, the box on the chart shows its settings before you press OK.

**The value of a lot.** Index CFDs differ between brokers (US100 can be 1, 10 or 20 USD per point per lot), and some brokers publish a wrong tick value. The tool takes the value from, in order:
1. **Your own value** for the symbol, from your broker's contract specification. It's typed per pip on forex and per 1.0 move elsewhere.
2. **The calibration** from the new script, `Fibonacci_Pro_Calibrate.mq5` (below).
3. **The contract size checked against the tick value.**
   - When the two agree within 2%, the larger is used, so the volume errs small.
   - When they disagree, there is no size. The Risk window shows both, with buttons to use either one, and suggests calibrating.

**Volume rules:**
- Lots are always rounded down to the volume step.
- Below the minimum volume, the tag says so and shows what the minimum would lose.
- Above the maximum volume, the size is capped.

**Calibration script** (`Fibonacci_Pro_Calibrate.mq5`, installed in `MQL5/Scripts`). MT5 doesn't let indicators call its profit calculation, but scripts can. Drop the script on any chart:
- **What it measures:** for every Market Watch symbol (or only the chart's symbol, an input), how much 1.00 lot gains or loses over a price move. It uses the same calculation the terminal uses for your positions.
- **Where it saves:** one file per trade server, which every chart picks up within seconds.
  - Values for symbols no longer in Market Watch are kept.
  - A readable copy (`.csv`) is written next to it.
- **What it reports:** each symbol in the Experts log, with whether the contract size and tick value agree, and a summary of the symbols where they don't.
- **Two sources outvote one:** if the contract size and the tick value agree with each other but not with the terminal's calculation, the symbol isn't calibrated (and an older calibration of it is dropped), so the tool uses the two that agree.
- **No orders:** it sends none. Run it again if your broker changes contract sizes; a changed contract size voids the old value.

**Currency conversion.** When the symbol's profit currency differs from the account currency, the value is converted at the current rate of a symbol that quotes the two. That symbol is looked for in Market Watch, then in the full symbol list; one found only in the full list is added to Market Watch, because MT5 only streams quotes for Market Watch symbols.

**Files.**
- **Risk settings:** `FibonacciPro\<server>_<login>.risk`.
- **Calibration:** `FibonacciPro\<server>.calib`, plus the readable `.calib.csv`.
- **Everything else:** drawings, presets and zone settings are unchanged.

## 1.65

**Drawings are typed automatically.** When you release the mouse, the tool reads the candles under the two anchors and recognises what you drew:

| You draw | Type |
|---|---|
| One click on a high, or on a low | KH (key high), KL (key low) |
| One candle, from the high to the top of the body | PW (premium wick) |
| One candle, from the low to the bottom of the body | DW (discount wick) |
| One candle, high to low; a wick tip to the far side of the body; or open to close | OB (order block) |
| Neighbouring candles, body edge to body edge, with the bodies apart | VI (volume imbalance) |
| Candle 1 to candle 3 across a fair value gap | FVG |
| The same, extended to take in one volume imbalance beside the middle candle | UFVG |
| From the far edge of the volume imbalance below the middle candle to the far edge of the one above it | SPB (no FVG needed) |
| A low and a high on different candles, the low below the high | KR (key range) |

- **Style:** each drawing gets its type's style, its timeframe's colour and width, and a name such as "H4 FVG ▲" (▲ bullish, ▼ bearish).
- **Your edits stay:** detection runs once, when the drawing is created, so renaming or restyling later is never overridden.
- **Snapping:** anchors must snap to candle prices (`InpSnapOHLC`). A drawing that matches no type gets the KR style and is named "H4 Fib" (or "H4 Line" for a single click).

**Colour shows the timeframe.** The eight colours were chosen by measurement for dark charts:
- Every pair is clearly different, including for red-green colour-blind viewers.
- None is close to green or red candles or to the default zone colours.
- White is left free for OTE lines.

| Timeframe | Colour | Width |
|---|---|---|
| MN | Pink #FF66B8 | 2 |
| W1 | Yellow #FFFF19 | 2 |
| D1 | Cyan #19FFFF | 2 |
| H4 (also H6, H8, H12) | Orange #FF8800 | 1 |
| H1 (also H2, H3) | Periwinkle #8C8CFF | 1 |
| M15 (also M20, M30) | Sand #E6C37E | 1 |
| M5 (also M6, M10, M12) | Sky blue #66CCFF | 1 |
| M1 (also M2, M3, M4) | Grey #8C8C8C | 1 |

The colours and the two widths are inputs (`InpColorMN` to `InpColorM1`, `InpWidthHigh`, `InpWidthLow`).

**Levels.** Every drawing starts unfilled, with twelve levels: 0, 12.5, 25, 37.5, 50, 62, 62.5, 70.5, 75, 79, 87.5 and 100.
- **Boundaries:** dashed for gaps (FVG, VI, UFVG, SPB, PW, DW), solid for OB and KR.
- **Inner levels:** quadrants (25, 75) are dash-dot, octants (12.5, 37.5, 62.5, 87.5) dash-dot-dot, and the CE (50) dotted.
- **OTE (62, 70.5, 79):** white, thin and solid, each labelled with its number.
- **On by default:** boundaries, quadrants and the CE. Octants and OTE are in the list but off.
- **Name tag:** the drawing's name sits above its upper boundary. In label text, `%n` now shows the drawing's name.

**Fibo levels tab:**
- A ≡ handle at the end of each row: drag it up or down to move that level.
- Sort: the first click sorts low to high, the next high to low.
- An "All" width button under the Width column, like the "All" colour button.
- One-click switches for Quadrants, Octants and OTE.
- Defaults restores the type's own level set.

**Used.** A "Used (stop extending)" checkbox on the Common tab, and a Used column in the drawings list:
- **Ticking it** stops the drawing at the first candle that traded into it and fades it. A key range stops at the latest candle.
- **Unticking it** makes the drawing extend again.
- **Adjusting:** you can still drag its end to a different candle.

**Built-in presets.** FVG, VI, UFVG, SPB, OB, PW, DW, KH, KL, KR and "KR + OTE" are installed on first run:
- They're ordinary presets, so you can edit, re-save or delete them. "Restore built-ins" in the Load dialog (click twice) writes them again.
- A preset named after a type is the style new drawings of that type get. Style an FVG the way you like, then save it as "FVG".
- A preset saved from a drawing in its timeframe colour stays coloured by timeframe when loaded onto other drawings.

**Drawings list:** the Type column shows the detected type, and a Used column has the switch. The list is 28 px wider.

**Compatibility.** The type, direction and used state are stored in spare bits of the drawings file:
- Every earlier version still opens drawings saved by 1.65. Used drawings show stopped but not faded, and the name tag shows as `%n`.

## 1.64

**Killzones stay visible over Fib ranges.** Up to 1.63, each shaded Fib range was painted over everything beneath it. Zone shading disappeared wherever a Fib range was shaded, and overlapping Fib ranges erased each other where they overlapped.

**All shading blends.** Fib fills and zone fills are now combined in one pass, so every shaded area stays visible where it overlaps another:
- Ranges drawn on higher timeframes go underneath, then ranges drawn on lower timeframes. Among Fibs drawn on the same timeframe, the selected one is on top.
- Zone shading goes on top, so killzones keep their own colour.
- Fib fills with a vertical gradient look the same as before.

**Two new settings on the Zones window's Fill tab:**
- **Zones cut through Fib shading:** Off, Half (the default) or Clear. Inside each shaded zone, Fib shading is reduced by that much, so killzones show as clear coloured windows even through heavy range shading. Fib levels and labels aren't affected.
- **Fib shading on lower timeframes:** Full (the default), Faint or Off. On charts below the timeframe a Fib was drawn on, its shading is drawn as set, at a third of its opacity, or not at all. The Fib's levels and labels stay as they are.

Like the other zone settings, both are shared by all charts of the workspace. Loading a zone preset keeps them, as it keeps the broker-time setting.

**Settings compatibility.** The two settings are stored in spare bits of the zone settings file, which keeps the 1.63 format:
- 1.63 can read zone settings and presets saved by 1.64; it ignores the two new settings.
- Settings from 1.63 open in 1.64 with Half and Full.

**Speed.** All shading still goes into the one background image, so there is no extra image upload per frame. Gradients are drawn in steps too small to see, which keeps redraws quick even with many shaded ranges on screen.

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
