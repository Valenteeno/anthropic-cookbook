package com.factwarehouse.core.engine

import com.factwarehouse.core.model.Catalog
import com.factwarehouse.core.model.MetricFamily
import com.factwarehouse.core.model.Predicate
import com.factwarehouse.core.model.TeamMatchFact

enum class StreakKind { RUN, DROUGHT }

/**
 * A streak with the context needed to judge it. The plan's central complaint about
 * competing sites is that they show [length] and stop; everything after it here exists
 * so the user can tell a real edge from a coin that landed heads six times.
 */
data class Streak(
    val teamId: String,
    val predicateId: String,
    val label: String,
    val family: MetricFamily,
    val kind: StreakKind,
    val length: Int,
    /** The team's own rate for this predicate across its full available history. */
    val underlyingRate: Double,
    /** The same predicate's rate across the team's league. */
    val baselineRate: Double,
    val sampleSize: Int,
    val interval: Interval,
    val notability: Double,
    /**
     * True when the run is long but the team's long-run rate is no better than its
     * league's. The streak is then a property of the sample, not of the team.
     */
    val regressionRisk: Boolean,
    /**
     * True when the run covers every match on record. The streak did not start
     * anywhere observable, so it is really "all N matches" and its true length is
     * censored by how much history exists — the UI must not imply otherwise.
     */
    val censored: Boolean,
) {
    /** Percentage points by which the team beats its league on this predicate. */
    val edgeOverBaseline: Double get() = underlyingRate - baselineRate
}

object StreakEngine {

    /** Minimum consecutive matches before a run is worth surfacing at all. */
    const val MIN_RUN = 3

    /**
     * Per-league rate for every predicate — the `league_baselines` table from the plan.
     * Computed once over all facts, then read by every streak.
     */
    fun leagueBaselines(facts: List<TeamMatchFact>): Map<String, Map<String, Double>> =
        facts.groupBy { it.leagueId }.mapValues { (_, leagueFacts) ->
            Catalog.predicates.associate { predicate ->
                predicate.id to leagueFacts.count { predicate.test(it) }.toDouble() / leagueFacts.size
            }
        }

    /**
     * Current run or drought for [predicate], reading [history] most-recent-first.
     * Returns null when the most recent match breaks both ways at length zero, which
     * cannot happen, so the result is always non-null for a non-empty history.
     */
    fun currentStreak(history: List<TeamMatchFact>, predicate: Predicate): Pair<StreakKind, Int>? {
        if (history.isEmpty()) return null
        val holds = predicate.test(history.first())
        val length = history.takeWhile { predicate.test(it) == holds }.size
        return (if (holds) StreakKind.RUN else StreakKind.DROUGHT) to length
    }

    /** Hit rate for [predicate] over the most recent [window] matches. */
    fun rate(history: List<TeamMatchFact>, predicate: Predicate, window: Int = Int.MAX_VALUE): Double {
        val slice = history.take(window)
        if (slice.isEmpty()) return 0.0
        return slice.count { predicate.test(it) }.toDouble() / slice.size
    }

    /**
     * Every streak a team currently carries, scored and sorted by notability.
     * This is the nightly scan from the plan, run for one team.
     */
    fun streaksFor(
        teamId: String,
        history: List<TeamMatchFact>,
        baselines: Map<String, Double>,
    ): List<Streak> {
        if (history.size < MIN_RUN) return emptyList()

        return Catalog.predicates.mapNotNull { predicate ->
            val (kind, length) = currentStreak(history, predicate) ?: return@mapNotNull null
            if (length < MIN_RUN) return@mapNotNull null

            val leagueRate = baselines[predicate.id] ?: return@mapNotNull null
            // A drought of P is a run of NOT-P, so score it against the complement.
            val effectiveBaseline = if (kind == StreakKind.RUN) leagueRate else 1.0 - leagueRate
            val successes = history.count { predicate.test(it) }
            val underlying = successes.toDouble() / history.size

            Streak(
                teamId = teamId,
                predicateId = predicate.id,
                label = predicate.label,
                family = predicate.family,
                kind = kind,
                length = length,
                underlyingRate = underlying,
                baselineRate = leagueRate,
                sampleSize = history.size,
                interval = Stats.wilson(successes, history.size),
                notability = Stats.notability(effectiveBaseline, length),
                regressionRisk = isRegressionRisk(kind, length, underlying, leagueRate),
                censored = length == history.size,
            )
        }.sortedByDescending { it.notability }
    }

    /**
     * A run of four or more where the team's long-run rate sits no meaningfully higher
     * than its league's. The tile is green; the team is average.
     */
    private fun isRegressionRisk(
        kind: StreakKind,
        length: Int,
        underlying: Double,
        baseline: Double,
    ): Boolean = when (kind) {
        StreakKind.RUN -> length >= 4 && underlying <= baseline + 0.03
        StreakKind.DROUGHT -> length >= 4 && underlying >= baseline - 0.03
    }

    /** Rolling average of [metricId] over the most recent [window] matches. */
    fun average(history: List<TeamMatchFact>, metricId: String, window: Int): Double {
        val slice = history.take(window)
        if (slice.isEmpty()) return 0.0
        val metric = Catalog.metric(metricId)
        return slice.sumOf { metric.extract(it) } / slice.size
    }
}
