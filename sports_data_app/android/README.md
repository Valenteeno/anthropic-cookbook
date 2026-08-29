# Fact Warehouse — Android prototype

A working prototype of the two screens that carry the product in `../DEVELOPMENT_PLAN.md`:
the **today board** (fixtures ranked by how surprising their strongest streak is) and the
**screener** (compose predicates, get matching fixtures plus a walk-forward backtest).

Kotlin + Jetpack Compose, Material 3, no network calls.

## Build and run

```bash
# from this directory, with Android Studio Ladybug or newer, or the SDK on PATH
./gradlew :app:installDebug      # onto a connected device or emulator
./gradlew :app:assembleDebug     # APK at app/build/outputs/apk/debug/
```

Requires the Android SDK (compileSdk 35) and JDK 17+. Opening this directory in Android
Studio and pressing Run also works with no further setup.

## Verifying the engine without an Android SDK

All the statistics live in `:core`, a plain Kotlin JVM module with no Android dependency,
so CI can test it on a machine with no SDK at all:

```bash
./gradlew -c settings-core.gradle.kts :core:test   # 23 unit tests
./gradlew -c settings-core.gradle.kts :core:run    # headless board + screener dump
```

`:core:run` prints exactly the numbers the UI binds to, which is the fastest way to see
whether a change to the engine did what you meant.

## What is real and what is not

| Part | Status |
|---|---|
| Streak detection, Wilson intervals, notability scoring, regression-risk flagging | Real, unit-tested |
| Screener clause evaluation and walk-forward backtest | Real, unit-tested |
| Compose UI | Written but **not compiled** — it was authored in an environment without the Android SDK, so expect to fix small things on first build |
| Match data | **Synthetic.** Invented clubs, simulated results. Nothing here is real football data |

The synthetic data is seeded (`MockData.SEED`), so every run produces the same board and
the same backtest numbers — useful when comparing engine changes.

## Structure

```
core/                                   pure Kotlin, no Android
  model/Models.kt                       TeamMatchFact — the wide fact row everything reads
  model/Catalog.kt                      39 predicates and 18 metrics across six families
  engine/Stats.kt                       Wilson interval, run probability, break-even
  engine/StreakEngine.kt                baselines, run/drought detection, notability
  engine/Screener.kt                    clause evaluation and walk-forward backtest
  data/MockData.kt                      seeded match simulator
  data/FactRepository.kt                in-memory warehouse + today board
  Demo.kt                               headless smoke check

app/
  ui/theme/Theme.kt                     slate + gold tokens, light and dark
  ui/components/                        rate bars, streak rows, hit strips, comparisons
  ui/today/TodayScreen.kt               the board
  ui/fixture/FixtureScreen.kt           per-fixture detail
  ui/screener/ScreenerScreen.kt         clause builder + backtest panel
```

## The one design argument worth keeping

Competing sites show a streak length on a green tile and stop. Every streak here carries
four extra things, and the UI never shows the length without them:

- the team's **long-run rate** for that predicate,
- its **league baseline** — the tick on every bar,
- a **Wilson 95% interval**, so a small sample looks small,
- a **regression-risk flag** when the run is long but the team's rate is no better than
  its league's.

A `censored` flag marks runs that span the entire history: those did not start anywhere
observable, so the UI says "all 18" rather than implying an ongoing streak.

The screener applies the same discipline — it reports hit rate, sample size, interval and
the break-even price together, and shouts when `n < 30`.

## Swapping in real data

`FactRepository` takes its four collections as constructor parameters. Point them at a
Room DAO fed by the ingestion pipeline and nothing above it changes:

```kotlin
FactRepository(
    leagues = dao.leagues(),
    teams = dao.teams(),
    facts = dao.teamMatchFacts(),
    fixtures = dao.upcomingFixtures(),
)
```

The streak scan currently runs at construction. With real volume it moves to the nightly
job described in the plan, writing a materialised `streaks` table that the app reads.

## Known gaps

- No persistence, no networking, no DI — deliberately, so the engine stays the subject.
- The board recomputes `highlights()` on each league-filter change; fine at 15 fixtures,
  not at 15,000.
- Simulated shots-on-target run a little low against real-world rates.
- Slip check and code conversion are not in this prototype (Phases 5 and 6 of the plan).
