package com.factwarehouse.core

import com.factwarehouse.core.data.FactRepository
import com.factwarehouse.core.data.MockData
import com.factwarehouse.core.engine.Clause
import com.factwarehouse.core.engine.Comparator
import com.factwarehouse.core.engine.Stats
import com.factwarehouse.core.engine.StreakEngine
import com.factwarehouse.core.engine.StreakKind
import com.factwarehouse.core.engine.Subject
import com.factwarehouse.core.model.Catalog
import com.factwarehouse.core.model.TeamMatchFact
import com.factwarehouse.core.model.Venue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StatsTest {

    @Test
    fun `wilson interval brackets the observed rate`() {
        val interval = Stats.wilson(successes = 7, n = 10)
        assertTrue("low below rate", interval.low < 0.7)
        assertTrue("high above rate", interval.high > 0.7)
        assertTrue("stays in bounds", interval.low >= 0.0 && interval.high <= 1.0)
    }

    @Test
    fun `wilson interval narrows as the sample grows`() {
        val small = Stats.wilson(7, 10)
        val large = Stats.wilson(700, 1000)
        assertTrue("more data means a tighter interval", large.width < small.width)
    }

    @Test
    fun `wilson handles the degenerate cases without escaping bounds`() {
        assertEquals(Stats.wilson(0, 0), com.factwarehouse.core.engine.Interval(0.0, 1.0))
        val allHits = Stats.wilson(10, 10)
        assertTrue(allHits.high <= 1.0)
        assertTrue("ten from ten is still not certainty", allHits.low < 1.0)
    }

    @Test
    fun `a run against a low baseline is more notable than one against a high baseline`() {
        val rareRun = Stats.notability(baseline = 0.25, length = 5)
        val commonRun = Stats.notability(baseline = 0.75, length = 5)
        assertTrue("rarer base rate scores higher", rareRun > commonRun)
    }

    @Test
    fun `break-even price is the reciprocal of the hit rate`() {
        assertEquals(2.0, Stats.breakEvenPrice(0.5), 1e-9)
        assertEquals(1.25, Stats.breakEvenPrice(0.8), 1e-9)
    }
}

class StreakEngineTest {

    /** Builds a history, most-recent-first, from a list of match goal totals. */
    private fun historyWithTotals(totals: List<Int>): List<TeamMatchFact> =
        totals.mapIndexed { index, total ->
            fact(matchDay = totals.size - index, goalsFor = total, goalsAgainst = 0)
        }

    private fun fact(matchDay: Int, goalsFor: Int, goalsAgainst: Int) = TeamMatchFact(
        teamId = "t", opponentId = "o", leagueId = "l", matchDay = matchDay, venue = Venue.HOME,
        goalsFor = goalsFor, goalsAgainst = goalsAgainst, goalsForHt = 0, goalsAgainstHt = 0,
        cornersFor = 5, cornersAgainst = 5, yellowsFor = 1, yellowsAgainst = 1,
        redsFor = 0, redsAgainst = 0, shots = 10, shotsOnTarget = 4,
        xgFor = 1.2, xgAgainst = 1.0, firstGoalForMinute = 30, firstGoalAgainstMinute = null,
    )

    @Test
    fun `current run counts only the leading matches that hold`() {
        // Most recent first: three overs, then an under.
        val history = historyWithTotals(listOf(3, 4, 3, 1, 4))
        val (kind, length) = StreakEngine.currentStreak(history, Catalog.predicate("over_2_5"))!!
        assertEquals(StreakKind.RUN, kind)
        assertEquals(3, length)
    }

    @Test
    fun `a failing most-recent match makes it a drought, not a run`() {
        val history = historyWithTotals(listOf(1, 1, 4, 4, 4))
        val (kind, length) = StreakEngine.currentStreak(history, Catalog.predicate("over_2_5"))!!
        assertEquals(StreakKind.DROUGHT, kind)
        assertEquals(2, length)
    }

    @Test
    fun `rate respects the window`() {
        val history = historyWithTotals(listOf(3, 3, 3, 0, 0, 0))
        val over = Catalog.predicate("over_2_5")
        assertEquals(1.0, StreakEngine.rate(history, over, window = 3), 1e-9)
        assertEquals(0.5, StreakEngine.rate(history, over, window = 6), 1e-9)
    }

    @Test
    fun `a long run on a league-average team is flagged as regression risk`() {
        // Five overs on top, but the team is 50-50 across its full history.
        val history = historyWithTotals(listOf(3, 3, 3, 3, 3, 0, 0, 0, 0, 0))
        val streaks = StreakEngine.streaksFor("t", history, mapOf("over_2_5" to 0.50))
        val over = streaks.first { it.predicateId == "over_2_5" }

        assertEquals(5, over.length)
        assertEquals(0.5, over.underlyingRate, 1e-9)
        assertTrue("the run does not beat the baseline, so it should be flagged", over.regressionRisk)
    }

    @Test
    fun `a run on a genuinely strong team is not flagged`() {
        val history = historyWithTotals(listOf(3, 3, 3, 3, 3, 3, 3, 3, 0, 0))
        val streaks = StreakEngine.streaksFor("t", history, mapOf("over_2_5" to 0.50))
        val over = streaks.first { it.predicateId == "over_2_5" }

        assertEquals(0.8, over.underlyingRate, 1e-9)
        assertTrue("the team really is an over team", !over.regressionRisk)
        assertTrue("and it beats its league", over.edgeOverBaseline > 0.25)
    }

    @Test
    fun `a run covering the whole history is marked censored`() {
        val history = historyWithTotals(listOf(3, 3, 3, 3, 3))
        val streaks = StreakEngine.streaksFor("t", history, mapOf("over_2_5" to 0.5))
        val over = streaks.first { it.predicateId == "over_2_5" }
        assertEquals(5, over.length)
        assertTrue("the run has no observable start", over.censored)
    }

    @Test
    fun `a run with an observable start is not censored`() {
        val history = historyWithTotals(listOf(3, 3, 3, 0, 0))
        val streaks = StreakEngine.streaksFor("t", history, mapOf("over_2_5" to 0.5))
        val over = streaks.first { it.predicateId == "over_2_5" }
        assertTrue(!over.censored)
    }

    @Test
    fun `runs shorter than the minimum are not surfaced`() {
        val history = historyWithTotals(listOf(3, 3, 0, 0, 0, 0))
        val streaks = StreakEngine.streaksFor("t", history, mapOf("over_2_5" to 0.5))
        assertTrue(streaks.none { it.predicateId == "over_2_5" && it.length == 2 })
    }
}

class RepositoryTest {

    private val repo = FactRepository()

    @Test
    fun `every team has a full simulated history`() {
        repo.teams.forEach { team ->
            assertEquals("history length for ${team.name}", 18, repo.history(team.id).size)
        }
    }

    @Test
    fun `fact rows are mirrored between the two sides of a match`() {
        val homeFact = MockData.facts.first { it.venue == Venue.HOME }
        val awayFact = MockData.facts.first {
            it.teamId == homeFact.opponentId && it.matchDay == homeFact.matchDay
        }
        assertEquals(homeFact.goalsFor, awayFact.goalsAgainst)
        assertEquals(homeFact.goalsAgainst, awayFact.goalsFor)
        assertEquals(homeFact.cornersFor, awayFact.cornersAgainst)
    }

    @Test
    fun `league baselines sit in a plausible range`() {
        repo.leagues.forEach { league ->
            val overRate = repo.baseline(league.id, "over_2_5")
            assertTrue("$league over 2.5 rate $overRate", overRate in 0.25..0.80)
            val bttsRate = repo.baseline(league.id, "btts")
            assertTrue("$league btts rate $bttsRate", bttsRate in 0.25..0.80)
        }
    }

    @Test
    fun `the board is ranked by notability and every fixture resolves`() {
        val highlights = repo.highlights()
        assertTrue("board is populated", highlights.isNotEmpty())
        val scores = highlights.map { it.notability }
        assertEquals("board is sorted", scores.sortedDescending(), scores)
        highlights.forEach { assertNotNull(it.homeTeam); assertNotNull(it.awayTeam) }
    }

    @Test
    fun `at least one fixture carries a surfaced streak`() {
        assertTrue(repo.highlights().any { it.topStreaks.isNotEmpty() })
    }
}

class ScreenerTest {

    private val repo = FactRepository()

    private val cornerScreen = listOf(
        Clause(Subject.HOME, "corners_for", window = 6, Comparator.AT_LEAST, threshold = 5.0),
        Clause(Subject.AWAY, "corners_against", window = 6, Comparator.AT_LEAST, threshold = 4.5),
    )

    @Test
    fun `an empty screen returns nothing rather than everything`() {
        val result = repo.screen(emptyList(), "over_2_5")
        assertTrue(result.hits.isEmpty())
        assertEquals(0, result.backtest.n)
    }

    @Test
    fun `a screen produces a walk-forward sample and a rate inside its own interval`() {
        val result = repo.screen(cornerScreen, "corners_over_9_5")
        val backtest = result.backtest

        assertTrue("the screen matched some history", backtest.n > 0)
        assertTrue("hits cannot exceed the sample", backtest.hits <= backtest.n)
        assertTrue(
            "rate ${backtest.rate} should sit inside [${backtest.interval.low}, ${backtest.interval.high}]",
            backtest.rate >= backtest.interval.low - 1e-9 && backtest.rate <= backtest.interval.high + 1e-9,
        )
    }

    @Test
    fun `break-even is consistent with the reported rate`() {
        val backtest = repo.screen(cornerScreen, "corners_over_9_5").backtest
        assertEquals(1.0 / backtest.rate, backtest.breakEven, 1e-6)
    }

    @Test
    fun `a stricter threshold never returns more upcoming fixtures`() {
        val loose = repo.screen(
            listOf(Clause(Subject.HOME, "corners_for", 6, Comparator.AT_LEAST, 3.0)), "corners_over_9_5",
        )
        val strict = repo.screen(
            listOf(Clause(Subject.HOME, "corners_for", 6, Comparator.AT_LEAST, 7.5)), "corners_over_9_5",
        )
        assertTrue(strict.hits.size <= loose.hits.size)
    }

    @Test
    fun `thin samples are flagged so the UI can say so`() {
        val strict = repo.screen(
            listOf(
                Clause(Subject.HOME, "corners_for", 6, Comparator.AT_LEAST, 8.0),
                Clause(Subject.AWAY, "corners_against", 6, Comparator.AT_LEAST, 8.0),
            ),
            "corners_over_10_5",
        )
        assertTrue("a near-impossible screen must report a thin sample", strict.backtest.thinSample)
    }
}
