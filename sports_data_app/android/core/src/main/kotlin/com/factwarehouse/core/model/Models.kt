package com.factwarehouse.core.model

enum class Venue { HOME, AWAY }

enum class Outcome { WIN, DRAW, LOSS }

data class League(
    val id: String,
    val name: String,
    val country: String,
)

data class Team(
    val id: String,
    val name: String,
    val short: String,
    val leagueId: String,
)

/**
 * One row per team per match — the `team_match_facts` table from the development plan,
 * narrowed to the columns this prototype exercises. Every streak, screener clause and
 * backtest in the app reads this type and nothing else.
 *
 * `matchDay` is a monotonic index within a league: higher is more recent.
 */
data class TeamMatchFact(
    val teamId: String,
    val opponentId: String,
    val leagueId: String,
    val matchDay: Int,
    val venue: Venue,
    val goalsFor: Int,
    val goalsAgainst: Int,
    val goalsForHt: Int,
    val goalsAgainstHt: Int,
    val cornersFor: Int,
    val cornersAgainst: Int,
    val yellowsFor: Int,
    val yellowsAgainst: Int,
    val redsFor: Int,
    val redsAgainst: Int,
    val shots: Int,
    val shotsOnTarget: Int,
    val xgFor: Double,
    val xgAgainst: Double,
    /** Minute of this team's first goal, or null if it never scored. */
    val firstGoalForMinute: Int?,
    /** Minute of the first goal this team conceded, or null if it kept a clean sheet. */
    val firstGoalAgainstMinute: Int?,
) {
    val totalGoals: Int get() = goalsFor + goalsAgainst
    val totalGoalsHt: Int get() = goalsForHt + goalsAgainstHt
    val goalsForSecondHalf: Int get() = goalsFor - goalsForHt
    val goalsAgainstSecondHalf: Int get() = goalsAgainst - goalsAgainstHt
    val totalGoalsSecondHalf: Int get() = totalGoals - totalGoalsHt
    val totalCorners: Int get() = cornersFor + cornersAgainst
    val totalYellows: Int get() = yellowsFor + yellowsAgainst
    val totalReds: Int get() = redsFor + redsAgainst

    /** Standard booking points: 10 per yellow, 25 per red. */
    val bookingPoints: Int get() = totalYellows * 10 + totalReds * 25

    /** Minute of the first goal in the match by either side, or null for a 0-0. */
    val matchFirstGoalMinute: Int?
        get() = listOfNotNull(firstGoalForMinute, firstGoalAgainstMinute).minOrNull()

    val bothTeamsScored: Boolean get() = goalsFor > 0 && goalsAgainst > 0
    val cleanSheet: Boolean get() = goalsAgainst == 0
    val failedToScore: Boolean get() = goalsFor == 0

    val outcome: Outcome
        get() = when {
            goalsFor > goalsAgainst -> Outcome.WIN
            goalsFor == goalsAgainst -> Outcome.DRAW
            else -> Outcome.LOSS
        }

    /** Goals scored minus expected goals: positive is finishing above the chances created. */
    val xgOverperformance: Double get() = goalsFor - xgFor
}

data class Fixture(
    val id: String,
    val leagueId: String,
    val homeTeamId: String,
    val awayTeamId: String,
    val kickoff: String,
    val dayLabel: String,
    val referee: String,
    /** Best available decimal price per predicate id, where the prototype has one. */
    val prices: Map<String, Double> = emptyMap(),
)
