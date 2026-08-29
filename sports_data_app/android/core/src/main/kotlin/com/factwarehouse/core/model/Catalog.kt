package com.factwarehouse.core.model

enum class MetricFamily(val label: String) {
    GOALS("Goals & results"),
    TIMING("Goal timing"),
    CORNERS("Corners"),
    CARDS("Cards"),
    SHOTS("Shots"),
    XG("Expected goals"),
}

/**
 * A boolean fact about one team's match. Streaks, screener targets and backtests are
 * all expressed as predicates, so adding a market means adding one entry here.
 */
data class Predicate(
    val id: String,
    val label: String,
    val family: MetricFamily,
    val test: (TeamMatchFact) -> Boolean,
)

/** A numeric fact, used for rolling averages and screener threshold clauses. */
data class Metric(
    val id: String,
    val label: String,
    val family: MetricFamily,
    val unit: String,
    val extract: (TeamMatchFact) -> Double,
)

/**
 * The predicate and metric library. In production this is generated from the column
 * list of `team_match_facts`; here it is written out so the prototype exercises every
 * metric family in the plan.
 */
object Catalog {

    val predicates: List<Predicate> = listOf(
        // --- Goals & results -------------------------------------------------
        Predicate("over_1_5", "Over 1.5 goals", MetricFamily.GOALS) { it.totalGoals > 1 },
        Predicate("over_2_5", "Over 2.5 goals", MetricFamily.GOALS) { it.totalGoals > 2 },
        Predicate("over_3_5", "Over 3.5 goals", MetricFamily.GOALS) { it.totalGoals > 3 },
        Predicate("under_2_5", "Under 2.5 goals", MetricFamily.GOALS) { it.totalGoals < 3 },
        Predicate("btts", "Both teams to score", MetricFamily.GOALS) { it.bothTeamsScored },
        Predicate("btts_no", "Both teams to score — no", MetricFamily.GOALS) { !it.bothTeamsScored },
        Predicate("team_scored", "Team scored", MetricFamily.GOALS) { !it.failedToScore },
        Predicate("clean_sheet", "Clean sheet", MetricFamily.GOALS) { it.cleanSheet },
        Predicate("team_over_1_5", "Team over 1.5 goals", MetricFamily.GOALS) { it.goalsFor > 1 },
        Predicate("win", "Win", MetricFamily.GOALS) { it.outcome == Outcome.WIN },
        Predicate("unbeaten", "Unbeaten", MetricFamily.GOALS) { it.outcome != Outcome.LOSS },
        Predicate("ht_over_0_5", "Over 0.5 goals in 1H", MetricFamily.GOALS) { it.totalGoalsHt > 0 },
        Predicate("ht_over_1_5", "Over 1.5 goals in 1H", MetricFamily.GOALS) { it.totalGoalsHt > 1 },
        Predicate("sh_over_0_5", "Over 0.5 goals in 2H", MetricFamily.GOALS) { it.totalGoalsSecondHalf > 0 },
        Predicate("sh_over_1_5", "Over 1.5 goals in 2H", MetricFamily.GOALS) { it.totalGoalsSecondHalf > 1 },
        Predicate("both_halves_over", "Goal in both halves", MetricFamily.GOALS) {
            it.totalGoalsHt > 0 && it.totalGoalsSecondHalf > 0
        },
        Predicate("team_scored_both_halves", "Team scored in both halves", MetricFamily.GOALS) {
            it.goalsForHt > 0 && it.goalsForSecondHalf > 0
        },

        // --- Goal timing -----------------------------------------------------
        Predicate("goal_before_15", "Goal before 15'", MetricFamily.TIMING) {
            (it.matchFirstGoalMinute ?: 999) < 15
        },
        Predicate("goal_before_30", "Goal before 30'", MetricFamily.TIMING) {
            (it.matchFirstGoalMinute ?: 999) < 30
        },
        Predicate("no_goal_before_30", "No goal before 30'", MetricFamily.TIMING) {
            (it.matchFirstGoalMinute ?: 999) >= 30
        },
        Predicate("team_scored_first", "Team scored first", MetricFamily.TIMING) {
            val f = it.firstGoalForMinute
            val a = it.firstGoalAgainstMinute
            f != null && (a == null || f < a)
        },
        Predicate("team_scores_before_30", "Team scores before 30'", MetricFamily.TIMING) {
            (it.firstGoalForMinute ?: 999) < 30
        },
        Predicate("scoreless_at_ht", "Scoreless at half time", MetricFamily.TIMING) { it.totalGoalsHt == 0 },

        // --- Corners ---------------------------------------------------------
        Predicate("corners_over_8_5", "Over 8.5 match corners", MetricFamily.CORNERS) { it.totalCorners > 8 },
        Predicate("corners_over_9_5", "Over 9.5 match corners", MetricFamily.CORNERS) { it.totalCorners > 9 },
        Predicate("corners_over_10_5", "Over 10.5 match corners", MetricFamily.CORNERS) { it.totalCorners > 10 },
        Predicate("team_corners_over_4_5", "Team over 4.5 corners", MetricFamily.CORNERS) { it.cornersFor > 4 },
        Predicate("team_corners_over_5_5", "Team over 5.5 corners", MetricFamily.CORNERS) { it.cornersFor > 5 },
        Predicate("won_corner_count", "Won the corner count", MetricFamily.CORNERS) { it.cornersFor > it.cornersAgainst },

        // --- Cards -----------------------------------------------------------
        Predicate("cards_over_3_5", "Over 3.5 match cards", MetricFamily.CARDS) { it.totalYellows + it.totalReds > 3 },
        Predicate("cards_over_4_5", "Over 4.5 match cards", MetricFamily.CARDS) { it.totalYellows + it.totalReds > 4 },
        Predicate("team_cards_over_1_5", "Team over 1.5 cards", MetricFamily.CARDS) { it.yellowsFor + it.redsFor > 1 },
        Predicate("booking_pts_over_45", "Over 45 booking points", MetricFamily.CARDS) { it.bookingPoints > 45 },
        Predicate("red_card", "Red card shown", MetricFamily.CARDS) { it.totalReds > 0 },

        // --- Shots -----------------------------------------------------------
        Predicate("team_sot_over_4_5", "Team over 4.5 shots on target", MetricFamily.SHOTS) { it.shotsOnTarget > 4 },
        Predicate("team_shots_over_12_5", "Team over 12.5 shots", MetricFamily.SHOTS) { it.shots > 12 },

        // --- Expected goals --------------------------------------------------
        Predicate("xg_for_over_1_5", "Team xG over 1.5", MetricFamily.XG) { it.xgFor > 1.5 },
        Predicate("xg_match_over_2_5", "Match xG over 2.5", MetricFamily.XG) { it.xgFor + it.xgAgainst > 2.5 },
        Predicate("outscored_xg", "Outscored its xG", MetricFamily.XG) { it.xgOverperformance > 0 },
    )

    val metrics: List<Metric> = listOf(
        Metric("goals_for", "Goals scored", MetricFamily.GOALS, "per match") { it.goalsFor.toDouble() },
        Metric("goals_against", "Goals conceded", MetricFamily.GOALS, "per match") { it.goalsAgainst.toDouble() },
        Metric("total_goals", "Match goals", MetricFamily.GOALS, "per match") { it.totalGoals.toDouble() },
        Metric("goals_ht", "First-half goals", MetricFamily.GOALS, "per match") { it.totalGoalsHt.toDouble() },
        Metric("goals_2h", "Second-half goals", MetricFamily.GOALS, "per match") { it.totalGoalsSecondHalf.toDouble() },
        Metric("first_goal_minute", "Match first-goal minute", MetricFamily.TIMING, "min") {
            (it.matchFirstGoalMinute ?: 95).toDouble()
        },
        Metric("team_first_goal_minute", "Team first-goal minute", MetricFamily.TIMING, "min") {
            (it.firstGoalForMinute ?: 95).toDouble()
        },
        Metric("corners_for", "Corners won", MetricFamily.CORNERS, "per match") { it.cornersFor.toDouble() },
        Metric("corners_against", "Corners conceded", MetricFamily.CORNERS, "per match") { it.cornersAgainst.toDouble() },
        Metric("total_corners", "Match corners", MetricFamily.CORNERS, "per match") { it.totalCorners.toDouble() },
        Metric("cards_for", "Cards taken", MetricFamily.CARDS, "per match") { (it.yellowsFor + it.redsFor).toDouble() },
        Metric("total_cards", "Match cards", MetricFamily.CARDS, "per match") { (it.totalYellows + it.totalReds).toDouble() },
        Metric("booking_points", "Booking points", MetricFamily.CARDS, "per match") { it.bookingPoints.toDouble() },
        Metric("shots", "Shots", MetricFamily.SHOTS, "per match") { it.shots.toDouble() },
        Metric("shots_on_target", "Shots on target", MetricFamily.SHOTS, "per match") { it.shotsOnTarget.toDouble() },
        Metric("xg_for", "xG created", MetricFamily.XG, "per match") { it.xgFor },
        Metric("xg_against", "xG conceded", MetricFamily.XG, "per match") { it.xgAgainst },
        Metric("xg_diff", "xG difference", MetricFamily.XG, "per match") { it.xgFor - it.xgAgainst },
    )

    private val predicateIndex = predicates.associateBy { it.id }
    private val metricIndex = metrics.associateBy { it.id }

    fun predicate(id: String): Predicate =
        predicateIndex[id] ?: error("Unknown predicate: $id")

    fun metric(id: String): Metric =
        metricIndex[id] ?: error("Unknown metric: $id")
}
