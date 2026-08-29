package com.factwarehouse.app.ui.fixture

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.factwarehouse.app.ui.components.ComparisonRow
import com.factwarehouse.app.ui.components.Eyebrow
import com.factwarehouse.app.ui.components.HitStrip
import com.factwarehouse.app.ui.components.LabeledValue
import com.factwarehouse.app.ui.components.Panel
import com.factwarehouse.app.ui.components.ResultStrip
import com.factwarehouse.app.ui.components.SectionHeader
import com.factwarehouse.app.ui.components.StreakRow
import com.factwarehouse.app.ui.theme.Fw
import com.factwarehouse.core.data.FactRepository
import com.factwarehouse.core.engine.StreakEngine
import com.factwarehouse.core.model.Catalog
import com.factwarehouse.core.model.Outcome
import com.factwarehouse.core.model.Team
import com.factwarehouse.core.model.TeamMatchFact

private const val WINDOW = 6

/**
 * The fixture page: everything both teams bring into this match, with each number
 * shown against the league it happened in.
 */
@Composable
fun FixtureScreen(
    repo: FactRepository,
    fixtureId: String,
    onBack: () -> Unit,
) {
    val highlight = remember(fixtureId) { repo.highlight(fixtureId) }
    if (highlight == null) {
        Box(Modifier.fillMaxSize().background(Fw.colors.ground), contentAlignment = Alignment.Center) {
            Text("Fixture not found", color = Fw.colors.inkMuted)
        }
        return
    }

    val homeHistory = repo.history(highlight.homeTeam.id)
    val awayHistory = repo.history(highlight.awayTeam.id)
    val leagueFacts = remember(fixtureId) { repo.facts.filter { it.leagueId == highlight.league.id } }

    fun leagueAvg(metricId: String): Double {
        val metric = Catalog.metric(metricId)
        return leagueFacts.sumOf { metric.extract(it) } / leagueFacts.size
    }

    LazyColumn(
        Modifier.fillMaxSize().background(Fw.colors.ground),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Text(
                "‹  Back to board",
                fontSize = 13.sp,
                color = Fw.colors.accent,
                modifier = Modifier.clickable(onClick = onBack).padding(vertical = 4.dp),
            )
        }

        item {
            Column {
                Eyebrow("${highlight.league.name} · ${highlight.fixture.dayLabel} ${highlight.fixture.kickoff}")
                Spacer(Modifier.height(8.dp))
                Text(
                    highlight.homeTeam.name,
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = (-0.8).sp,
                    color = Fw.colors.ink,
                )
                Text(
                    highlight.awayTeam.name,
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = (-0.8).sp,
                    color = Fw.colors.ink,
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    "Referee ${highlight.fixture.referee}",
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Monospace,
                    color = Fw.colors.inkFaint,
                )
            }
        }

        item {
            Panel {
                SectionHeader("Form", "Last 8 results, most recent first")
                TeamFormRow(highlight.homeTeam, homeHistory)
                Spacer(Modifier.height(10.dp))
                TeamFormRow(highlight.awayTeam, awayHistory)
            }
        }

        item {
            Panel {
                SectionHeader(
                    "Streaks",
                    "Bar shows the team's long-run rate; the tick is its league. A run that " +
                        "does not clear the tick is a sample, not an edge.",
                )
                highlight.topStreaks.take(6).forEach { (team, streak) ->
                    StreakRow(team.short, streak)
                }
                if (highlight.topStreaks.isEmpty()) {
                    Text(
                        "Neither side carries a run of three or more.",
                        fontSize = 12.sp,
                        color = Fw.colors.inkFaint,
                    )
                }
            }
        }

        item {
            Panel {
                SectionHeader("Goal timing", "Averages over the last $WINDOW matches")
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    LabeledValue(
                        "Match 1st goal",
                        "${StreakEngine.average(homeHistory, "first_goal_minute", WINDOW).toInt()}'",
                    )
                    LabeledValue(
                        "${highlight.homeTeam.short} scores",
                        "${StreakEngine.average(homeHistory, "team_first_goal_minute", WINDOW).toInt()}'",
                    )
                    LabeledValue(
                        "${highlight.awayTeam.short} scores",
                        "${StreakEngine.average(awayHistory, "team_first_goal_minute", WINDOW).toInt()}'",
                    )
                }
                Spacer(Modifier.height(12.dp))
                ComparisonRow(
                    "First-half goals",
                    StreakEngine.average(homeHistory, "goals_ht", WINDOW),
                    StreakEngine.average(awayHistory, "goals_ht", WINDOW),
                    leagueAvg("goals_ht"),
                )
                ComparisonRow(
                    "Second-half goals",
                    StreakEngine.average(homeHistory, "goals_2h", WINDOW),
                    StreakEngine.average(awayHistory, "goals_2h", WINDOW),
                    leagueAvg("goals_2h"),
                )
            }
        }

        item {
            Panel {
                SectionHeader("Corners", "Home bar first, away bar second, tick is the league average")
                ComparisonRow(
                    "Corners won",
                    StreakEngine.average(homeHistory, "corners_for", WINDOW),
                    StreakEngine.average(awayHistory, "corners_for", WINDOW),
                    leagueAvg("corners_for"),
                )
                ComparisonRow(
                    "Corners conceded",
                    StreakEngine.average(homeHistory, "corners_against", WINDOW),
                    StreakEngine.average(awayHistory, "corners_against", WINDOW),
                    leagueAvg("corners_against"),
                )
                ComparisonRow(
                    "Match corners",
                    StreakEngine.average(homeHistory, "total_corners", WINDOW),
                    StreakEngine.average(awayHistory, "total_corners", WINDOW),
                    leagueAvg("total_corners"),
                )
            }
        }

        item {
            Panel {
                SectionHeader("Cards", "Booking points are 10 per yellow, 25 per red")
                ComparisonRow(
                    "Cards taken",
                    StreakEngine.average(homeHistory, "cards_for", WINDOW),
                    StreakEngine.average(awayHistory, "cards_for", WINDOW),
                    leagueAvg("cards_for"),
                )
                ComparisonRow(
                    "Booking points",
                    StreakEngine.average(homeHistory, "booking_points", WINDOW),
                    StreakEngine.average(awayHistory, "booking_points", WINDOW),
                    leagueAvg("booking_points"),
                )
            }
        }

        item {
            Panel {
                SectionHeader("Shots and xG", "Where the goals should have come from")
                ComparisonRow(
                    "Shots",
                    StreakEngine.average(homeHistory, "shots", WINDOW),
                    StreakEngine.average(awayHistory, "shots", WINDOW),
                    leagueAvg("shots"),
                )
                ComparisonRow(
                    "Shots on target",
                    StreakEngine.average(homeHistory, "shots_on_target", WINDOW),
                    StreakEngine.average(awayHistory, "shots_on_target", WINDOW),
                    leagueAvg("shots_on_target"),
                )
                ComparisonRow(
                    "xG created",
                    StreakEngine.average(homeHistory, "xg_for", WINDOW),
                    StreakEngine.average(awayHistory, "xg_for", WINDOW),
                    leagueAvg("xg_for"),
                )
                Spacer(Modifier.height(8.dp))
                val homeOver = homeHistory.take(WINDOW).sumOf { it.xgOverperformance }
                val awayOver = awayHistory.take(WINDOW).sumOf { it.xgOverperformance }
                Text(
                    "Goals minus xG over the last $WINDOW: " +
                        "${highlight.homeTeam.short} ${signed(homeOver)}, " +
                        "${highlight.awayTeam.short} ${signed(awayOver)}. " +
                        "A large positive number is finishing that may not repeat.",
                    fontSize = 11.sp,
                    color = Fw.colors.inkFaint,
                )
            }
        }

        item {
            Panel {
                SectionHeader("Market hit strips", "Last 10 matches, most recent on the left")
                listOf("over_2_5", "btts", "corners_over_9_5", "cards_over_3_5").forEach { predicateId ->
                    val predicate = Catalog.predicate(predicateId)
                    Column(Modifier.padding(vertical = 6.dp)) {
                        Text(predicate.label, fontSize = 12.sp, color = Fw.colors.inkMuted)
                        Spacer(Modifier.height(5.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                highlight.homeTeam.short,
                                fontSize = 10.sp,
                                fontFamily = FontFamily.Monospace,
                                color = Fw.colors.inkFaint,
                                modifier = Modifier.padding(end = 8.dp),
                            )
                            HitStrip(homeHistory.take(10).map { predicate.test(it) })
                        }
                        Spacer(Modifier.height(4.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                highlight.awayTeam.short,
                                fontSize = 10.sp,
                                fontFamily = FontFamily.Monospace,
                                color = Fw.colors.inkFaint,
                                modifier = Modifier.padding(end = 8.dp),
                            )
                            HitStrip(awayHistory.take(10).map { predicate.test(it) })
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TeamFormRow(team: Team, history: List<TeamMatchFact>) {
    Column {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(team.name, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = Fw.colors.ink)
            Text(
                history.take(WINDOW).let { slice ->
                    val gf = slice.sumOf { it.goalsFor }
                    val ga = slice.sumOf { it.goalsAgainst }
                    "$gf-$ga in last ${slice.size}"
                },
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace,
                color = Fw.colors.inkFaint,
            )
        }
        Spacer(Modifier.height(6.dp))
        ResultStrip(
            history.take(8).map {
                when (it.outcome) {
                    Outcome.WIN -> 'W'
                    Outcome.DRAW -> 'D'
                    Outcome.LOSS -> 'L'
                }
            },
        )
    }
}

private fun signed(v: Double): String =
    (if (v >= 0) "+" else "") + String.format("%.1f", v)
