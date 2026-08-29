package com.factwarehouse.core.data

import com.factwarehouse.core.engine.Clause
import com.factwarehouse.core.engine.ScreenResult
import com.factwarehouse.core.engine.Screener
import com.factwarehouse.core.engine.Streak
import com.factwarehouse.core.engine.StreakEngine
import com.factwarehouse.core.model.Fixture
import com.factwarehouse.core.model.League
import com.factwarehouse.core.model.Team
import com.factwarehouse.core.model.TeamMatchFact

/** A fixture with the streaks both its teams carry, ready for the today board. */
data class FixtureHighlight(
    val fixture: Fixture,
    val league: League,
    val homeTeam: Team,
    val awayTeam: Team,
    val homeStreaks: List<Streak>,
    val awayStreaks: List<Streak>,
) {
    val topStreaks: List<Pair<Team, Streak>>
        get() = (homeStreaks.map { homeTeam to it } + awayStreaks.map { awayTeam to it })
            .sortedByDescending { it.second.notability }

    /** Ranking score for the board: the single most surprising thing about this fixture. */
    val notability: Double get() = topStreaks.firstOrNull()?.second?.notability ?: 0.0
}

/**
 * In-memory stand-in for the warehouse. Computes baselines and the streak scan once at
 * construction, exactly as the nightly job in the plan does, then serves reads from it.
 */
class FactRepository(
    val leagues: List<League> = MockData.leagues,
    val teams: List<Team> = MockData.teams,
    val facts: List<TeamMatchFact> = MockData.facts,
    val fixtures: List<Fixture> = MockData.fixtures,
) {
    private val teamsById = teams.associateBy { it.id }
    private val leaguesById = leagues.associateBy { it.id }

    /** Each team's history, most recent first. */
    private val historyByTeam: Map<String, List<TeamMatchFact>> =
        facts.groupBy { it.teamId }.mapValues { (_, v) -> v.sortedByDescending { it.matchDay } }

    val baselines: Map<String, Map<String, Double>> = StreakEngine.leagueBaselines(facts)

    private val streaksByTeam: Map<String, List<Streak>> = teams.associate { team ->
        team.id to StreakEngine.streaksFor(
            teamId = team.id,
            history = historyByTeam[team.id].orEmpty(),
            baselines = baselines[team.leagueId].orEmpty(),
        )
    }

    fun team(id: String): Team = teamsById.getValue(id)

    fun league(id: String): League = leaguesById.getValue(id)

    fun history(teamId: String): List<TeamMatchFact> = historyByTeam[teamId].orEmpty()

    fun streaks(teamId: String): List<Streak> = streaksByTeam[teamId].orEmpty()

    fun baseline(leagueId: String, predicateId: String): Double =
        baselines[leagueId]?.get(predicateId) ?: 0.0

    /** The today board: fixtures ranked by how surprising their strongest streak is. */
    fun highlights(): List<FixtureHighlight> = fixtures.map { fixture ->
        FixtureHighlight(
            fixture = fixture,
            league = league(fixture.leagueId),
            homeTeam = team(fixture.homeTeamId),
            awayTeam = team(fixture.awayTeamId),
            homeStreaks = streaks(fixture.homeTeamId),
            awayStreaks = streaks(fixture.awayTeamId),
        )
    }.sortedByDescending { it.notability }

    fun highlight(fixtureId: String): FixtureHighlight? = highlights().firstOrNull { it.fixture.id == fixtureId }

    fun screen(clauses: List<Clause>, targetPredicateId: String): ScreenResult =
        Screener.run(clauses, targetPredicateId, fixtures, facts)
            .let { result ->
                // Attach the best posted price for the target market, where one exists.
                val price = result.hits.mapNotNull { it.fixture.prices[targetPredicateId] }.maxOrNull()
                result.copy(backtest = result.backtest.copy(bestPrice = price))
            }
}
