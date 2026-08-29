package com.factwarehouse.core

import com.factwarehouse.core.data.FactRepository
import com.factwarehouse.core.data.MockData
import com.factwarehouse.core.engine.Clause
import com.factwarehouse.core.engine.Comparator
import com.factwarehouse.core.engine.StreakKind
import com.factwarehouse.core.engine.Subject

/**
 * Headless smoke check for the engine — prints what the today board and the screener
 * would render, without needing an emulator. Useful in CI and when tuning the
 * simulation, since it surfaces the same numbers the UI binds to.
 *
 *     gradle -c settings-core.gradle.kts :core:run
 */
fun main() {
    val repo = FactRepository()
    val pct = { v: Double -> "${Math.round(v * 100)}%" }

    println("=== ${MockData.DISCLAIMER} ===\n")
    println("Leagues ${repo.leagues.size} · teams ${repo.teams.size} · fact rows ${repo.facts.size} · upcoming ${repo.fixtures.size}\n")

    println("--- TODAY'S BOARD (top 5 by notability) ---")
    repo.highlights().take(5).forEach { h ->
        println("${h.homeTeam.name} v ${h.awayTeam.name}  (${h.league.name}, ${h.fixture.dayLabel} ${h.fixture.kickoff})")
        h.topStreaks.take(3).forEach { (team, s) ->
            val kind = if (s.kind == StreakKind.RUN) "run" else "without"
            val span = if (s.censored) "all ${s.length}" else "${s.length}-match"
            val flag = if (s.regressionRisk) "  [REGRESSION RISK]" else ""
            println(
                "    ${team.short}  ${s.label}: $span $kind" +
                    " · team ${pct(s.underlyingRate)} vs league ${pct(s.baselineRate)}" +
                    " · CI ${pct(s.interval.low)}-${pct(s.interval.high)}" +
                    " · notability ${Math.round(s.notability)}$flag"
            )
        }
        println()
    }

    println("--- SCREENER: corner pressure ---")
    val clauses = listOf(
        Clause(Subject.HOME, "corners_for", 6, Comparator.AT_LEAST, 5.0),
        Clause(Subject.AWAY, "corners_against", 6, Comparator.AT_LEAST, 4.5),
    )
    clauses.forEach { println("  ${it.describe()}") }

    val result = repo.screen(clauses, "corners_over_9_5")
    val b = result.backtest
    println("  -> ${result.hits.size} upcoming fixtures match")
    result.hits.forEach { println("     ${repo.team(it.fixture.homeTeamId).name} v ${repo.team(it.fixture.awayTeamId).name}") }
    println("  -> backtest ${b.hits}/${b.n} = ${pct(b.rate)}  CI ${pct(b.interval.low)}-${pct(b.interval.high)}")
    println("  -> break-even ${String.format("%.2f", b.breakEven)} · best price ${b.bestPrice ?: "n/a"} · clears market: ${b.clearsMarket}")
    if (b.thinSample) println("  -> THIN SAMPLE (n < 30): interval too wide to act on")
}
