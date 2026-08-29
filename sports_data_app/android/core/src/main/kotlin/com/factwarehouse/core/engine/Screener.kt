package com.factwarehouse.core.engine

import com.factwarehouse.core.model.Catalog
import com.factwarehouse.core.model.Fixture
import com.factwarehouse.core.model.TeamMatchFact

enum class Subject(val label: String) {
    HOME("Home team"),
    AWAY("Away team"),
    EITHER("Either team"),
}

enum class Comparator(val label: String, val symbol: String) {
    AT_LEAST("at least", ">="),
    AT_MOST("at most", "<="),
}

/**
 * One line of a screen: subject, metric, window, comparator, threshold.
 * The plan's filter DSL, narrowed to the shape a phone screen can actually build.
 */
data class Clause(
    val subject: Subject,
    val metricId: String,
    val window: Int,
    val comparator: Comparator,
    val threshold: Double,
) {
    fun describe(): String {
        val metric = Catalog.metric(metricId)
        return "${subject.label} · ${metric.label} · last $window · ${comparator.symbol} ${format(threshold)}"
    }

    private fun format(v: Double): String =
        if (v == v.toInt().toDouble()) v.toInt().toString() else String.format("%.1f", v)
}

/**
 * What the screen would have returned historically. [n] is the number of past fixtures
 * that satisfied the clauses using only data available before kickoff, so it is a
 * walk-forward result rather than a fit.
 */
data class Backtest(
    val hits: Int,
    val n: Int,
    val rate: Double,
    val interval: Interval,
    val breakEven: Double,
    val bestPrice: Double?,
) {
    val clearsMarket: Boolean get() = bestPrice != null && bestPrice > breakEven
    /** Fewer than this and the interval is too wide to act on; the UI says so out loud. */
    val thinSample: Boolean get() = n < 30
}

data class ScreenHit(
    val fixture: Fixture,
    /** Metric values that made this fixture qualify, keyed by clause index. */
    val evidence: List<String>,
)

data class ScreenResult(
    val hits: List<ScreenHit>,
    val backtest: Backtest,
)

object Screener {

    /** Matches needed before a historical fixture can enter the backtest sample. */
    private const val MIN_HISTORY = 6

    /**
     * Evaluate [clauses] against upcoming [fixtures], and backtest the implied bet on
     * [targetPredicateId] over [facts].
     *
     * `historyBefore` supplies each team's facts strictly before a given matchday, which
     * is what keeps the backtest honest — a clause is never evaluated against a match it
     * is also being scored on.
     */
    fun run(
        clauses: List<Clause>,
        targetPredicateId: String,
        fixtures: List<Fixture>,
        facts: List<TeamMatchFact>,
    ): ScreenResult {
        val byTeam = facts.groupBy { it.teamId }
            .mapValues { (_, v) -> v.sortedByDescending { it.matchDay } }

        val hits = if (clauses.isEmpty()) emptyList() else fixtures.mapNotNull { fixture ->
            val home = byTeam[fixture.homeTeamId].orEmpty()
            val away = byTeam[fixture.awayTeamId].orEmpty()
            val evidence = clauses.map { clause -> evaluate(clause, home, away) }
            if (evidence.all { it.passed }) {
                ScreenHit(fixture, evidence.map { it.description })
            } else {
                null
            }
        }

        return ScreenResult(hits, backtest(clauses, targetPredicateId, facts, byTeam))
    }

    private data class ClauseResult(val passed: Boolean, val description: String)

    private fun evaluate(
        clause: Clause,
        homeHistory: List<TeamMatchFact>,
        awayHistory: List<TeamMatchFact>,
    ): ClauseResult {
        val homeValue = StreakEngine.average(homeHistory, clause.metricId, clause.window)
        val awayValue = StreakEngine.average(awayHistory, clause.metricId, clause.window)

        val homeOk = homeHistory.isNotEmpty() && compare(homeValue, clause)
        val awayOk = awayHistory.isNotEmpty() && compare(awayValue, clause)

        val passed = when (clause.subject) {
            Subject.HOME -> homeOk
            Subject.AWAY -> awayOk
            Subject.EITHER -> homeOk || awayOk
        }

        val shown = when (clause.subject) {
            Subject.HOME -> homeValue
            Subject.AWAY -> awayValue
            Subject.EITHER -> if (homeOk) homeValue else awayValue
        }

        val metric = Catalog.metric(clause.metricId)
        return ClauseResult(passed, "${metric.label} ${String.format("%.2f", shown)}")
    }

    private fun compare(value: Double, clause: Clause): Boolean = when (clause.comparator) {
        Comparator.AT_LEAST -> value >= clause.threshold
        Comparator.AT_MOST -> value <= clause.threshold
    }

    /**
     * Replay every historical match as if it were upcoming: build both teams' histories
     * from matchdays strictly earlier, test the clauses against those, and if they pass,
     * score the target predicate on what actually happened.
     */
    private fun backtest(
        clauses: List<Clause>,
        targetPredicateId: String,
        facts: List<TeamMatchFact>,
        byTeam: Map<String, List<TeamMatchFact>>,
    ): Backtest {
        val target = Catalog.predicate(targetPredicateId)
        if (clauses.isEmpty()) {
            return Backtest(0, 0, 0.0, Interval(0.0, 1.0), Double.POSITIVE_INFINITY, null)
        }

        var hits = 0
        var n = 0

        // One row per match from the home side's perspective, so each match counts once.
        facts.filter { it.venue == com.factwarehouse.core.model.Venue.HOME }.forEach { homeFact ->
            val homeHistory = byTeam[homeFact.teamId].orEmpty().filter { it.matchDay < homeFact.matchDay }
            val awayHistory = byTeam[homeFact.opponentId].orEmpty().filter { it.matchDay < homeFact.matchDay }
            if (homeHistory.size < MIN_HISTORY || awayHistory.size < MIN_HISTORY) return@forEach

            val qualifies = clauses.all { evaluate(it, homeHistory, awayHistory).passed }
            if (qualifies) {
                n++
                if (target.test(homeFact)) hits++
            }
        }

        val rate = if (n == 0) 0.0 else hits.toDouble() / n
        return Backtest(
            hits = hits,
            n = n,
            rate = rate,
            interval = Stats.wilson(hits, n),
            breakEven = Stats.breakEvenPrice(rate),
            bestPrice = null,
        )
    }
}
