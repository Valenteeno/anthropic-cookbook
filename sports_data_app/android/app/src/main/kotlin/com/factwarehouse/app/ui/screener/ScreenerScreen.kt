package com.factwarehouse.app.ui.screener

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.factwarehouse.app.ui.components.Chip
import com.factwarehouse.app.ui.components.Eyebrow
import com.factwarehouse.app.ui.components.Panel
import com.factwarehouse.app.ui.components.RateBar
import com.factwarehouse.app.ui.components.SectionHeader
import com.factwarehouse.app.ui.components.pct
import com.factwarehouse.app.ui.theme.Fw
import com.factwarehouse.core.data.FactRepository
import com.factwarehouse.core.engine.Backtest
import com.factwarehouse.core.engine.Clause
import com.factwarehouse.core.engine.Comparator
import com.factwarehouse.core.engine.Subject
import com.factwarehouse.core.model.Catalog

/** Screens worth shipping preloaded, so a new user is never staring at an empty builder. */
private data class Preset(
    val name: String,
    val target: String,
    val clauses: List<Clause>,
)

private val presets = listOf(
    Preset(
        "Corner pressure", "corners_over_9_5",
        listOf(
            Clause(Subject.HOME, "corners_for", 6, Comparator.AT_LEAST, 5.0),
            Clause(Subject.AWAY, "corners_against", 6, Comparator.AT_LEAST, 4.5),
        ),
    ),
    Preset(
        "Card-heavy", "cards_over_3_5",
        listOf(Clause(Subject.EITHER, "cards_for", 6, Comparator.AT_LEAST, 2.0)),
    ),
    Preset(
        "Goal glut", "over_2_5",
        listOf(
            Clause(Subject.HOME, "xg_for", 6, Comparator.AT_LEAST, 1.4),
            Clause(Subject.AWAY, "goals_against", 6, Comparator.AT_LEAST, 1.3),
        ),
    ),
    Preset(
        "Slow starters", "no_goal_before_30",
        listOf(Clause(Subject.EITHER, "first_goal_minute", 6, Comparator.AT_LEAST, 35.0)),
    ),
)

@Composable
fun ScreenerScreen(repo: FactRepository) {
    val clauses = remember { mutableStateListOf(*presets[0].clauses.toTypedArray()) }
    var target by remember { mutableStateOf(presets[0].target) }
    var editorOpen by remember { mutableStateOf(false) }

    val result = remember(clauses.toList(), target) { repo.screen(clauses.toList(), target) }

    LazyColumn(
        Modifier.fillMaxSize().background(Fw.colors.ground),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 20.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Column {
                Eyebrow("Screener")
                Spacer(Modifier.height(6.dp))
                Text(
                    "Build a screen",
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = (-0.6).sp,
                    color = Fw.colors.ink,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    "Every screen is backtested walk-forward: clauses are evaluated only " +
                        "on data that existed before each historical kickoff.",
                    fontSize = 12.sp,
                    color = Fw.colors.inkFaint,
                )
            }
        }

        item {
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                presets.forEach { preset ->
                    Text(
                        preset.name,
                        fontSize = 12.sp,
                        color = Fw.colors.accent,
                        modifier = Modifier
                            .clip(RoundedCornerShape(14.dp))
                            .border(1.dp, Fw.colors.rule, RoundedCornerShape(14.dp))
                            .background(Fw.colors.surface)
                            .clickable {
                                clauses.clear()
                                clauses.addAll(preset.clauses)
                                target = preset.target
                            }
                            .padding(horizontal = 12.dp, vertical = 7.dp),
                    )
                }
            }
        }

        item {
            Panel {
                SectionHeader("Market", "The bet this screen implies")
                Picker(
                    options = Catalog.predicates.map { it.id },
                    selected = target,
                    display = { Catalog.predicate(it).label },
                    onSelect = { target = it },
                )
            }
        }

        item {
            Panel {
                SectionHeader("Filters", if (clauses.isEmpty()) "Add a clause to run the screen" else null)
                clauses.forEachIndexed { index, clause ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .padding(vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            clause.describe(),
                            fontSize = 12.sp,
                            fontFamily = FontFamily.Monospace,
                            color = Fw.colors.ink,
                            modifier = Modifier.weight(1f).padding(end = 10.dp),
                        )
                        Text(
                            "remove",
                            fontSize = 11.sp,
                            color = Fw.colors.hard,
                            modifier = Modifier.clickable { clauses.removeAt(index) },
                        )
                    }
                }

                Spacer(Modifier.height(8.dp))
                if (editorOpen) {
                    ClauseEditor(
                        onCancel = { editorOpen = false },
                        onAdd = { clauses.add(it); editorOpen = false },
                    )
                } else {
                    Text(
                        "+ Add clause",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        color = Fw.colors.accent,
                        modifier = Modifier.clickable { editorOpen = true }.padding(vertical = 4.dp),
                    )
                }
            }
        }

        item { BacktestPanel(result.backtest, Catalog.predicate(target).label) }

        item {
            Panel {
                SectionHeader(
                    "Matching fixtures",
                    "${result.hits.size} of ${repo.fixtures.size} upcoming fixtures pass every clause",
                )
                if (result.hits.isEmpty()) {
                    Text("Nothing upcoming matches this screen.", fontSize = 12.sp, color = Fw.colors.inkFaint)
                } else {
                    result.hits.forEach { hit ->
                        Column(Modifier.fillMaxWidth().padding(vertical = 7.dp)) {
                            Text(
                                "${repo.team(hit.fixture.homeTeamId).name} v ${repo.team(hit.fixture.awayTeamId).name}",
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Medium,
                                color = Fw.colors.ink,
                            )
                            Spacer(Modifier.height(3.dp))
                            Text(
                                hit.evidence.joinToString("  ·  "),
                                fontSize = 11.sp,
                                fontFamily = FontFamily.Monospace,
                                color = Fw.colors.inkFaint,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun BacktestPanel(backtest: Backtest, marketLabel: String) {
    Panel {
        SectionHeader("Backtest", marketLabel)
        if (backtest.n == 0) {
            Text(
                "No historical fixture satisfied these clauses. Loosen a threshold.",
                fontSize = 12.sp,
                color = Fw.colors.inkFaint,
            )
            return@Panel
        }

        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                pct(backtest.rate),
                fontSize = 40.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace,
                letterSpacing = (-1.5).sp,
                color = Fw.colors.ink,
            )
            Spacer(Modifier.width(10.dp))
            Text(
                "${backtest.hits} of ${backtest.n}",
                fontSize = 13.sp,
                fontFamily = FontFamily.Monospace,
                color = Fw.colors.inkMuted,
                modifier = Modifier.padding(bottom = 7.dp),
            )
        }

        Spacer(Modifier.height(10.dp))
        RateBar(
            rate = backtest.rate,
            intervalLow = backtest.interval.low,
            intervalHigh = backtest.interval.high,
            baseline = if (backtest.bestPrice != null) 1.0 / backtest.bestPrice!! else backtest.rate,
            good = backtest.clearsMarket,
        )
        Spacer(Modifier.height(6.dp))
        Text(
            "95% interval ${pct(backtest.interval.low)} – ${pct(backtest.interval.high)}" +
                if (backtest.bestPrice != null) "  ·  tick is the price's implied rate" else "",
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace,
            color = Fw.colors.inkFaint,
        )

        Spacer(Modifier.height(14.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Column {
                Eyebrow("Break-even", Fw.colors.inkFaint)
                Spacer(Modifier.height(3.dp))
                Text(
                    String.format("%.2f", backtest.breakEven),
                    fontSize = 18.sp,
                    fontWeight = FontWeight.SemiBold,
                    fontFamily = FontFamily.Monospace,
                    color = Fw.colors.ink,
                )
            }
            Column {
                Eyebrow("Best price", Fw.colors.inkFaint)
                Spacer(Modifier.height(3.dp))
                Text(
                    backtest.bestPrice?.let { String.format("%.2f", it) } ?: "—",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.SemiBold,
                    fontFamily = FontFamily.Monospace,
                    color = if (backtest.clearsMarket) Fw.colors.good else Fw.colors.ink,
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Eyebrow("Verdict", Fw.colors.inkFaint)
                Spacer(Modifier.height(5.dp))
                if (backtest.bestPrice == null) {
                    Chip("no price", Fw.colors.inkMuted, Fw.colors.surfaceRaised)
                } else if (backtest.clearsMarket) {
                    Chip("clears", Fw.colors.good, Fw.colors.goodWash)
                } else {
                    Chip("short", Fw.colors.hard, Fw.colors.hardWash)
                }
            }
        }

        if (backtest.thinSample) {
            Spacer(Modifier.height(12.dp))
            Box(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(5.dp))
                    .background(Fw.colors.hardWash)
                    .padding(10.dp),
            ) {
                Text(
                    "Thin sample (n = ${backtest.n}). The interval spans " +
                        "${pct(backtest.interval.high - backtest.interval.low)} — that is too wide to bet on. " +
                        "Loosen the screen until n is comfortably above 30.",
                    fontSize = 11.sp,
                    color = Fw.colors.hard,
                )
            }
        }
    }
}

@Composable
private fun ClauseEditor(onCancel: () -> Unit, onAdd: (Clause) -> Unit) {
    var subject by remember { mutableStateOf(Subject.HOME) }
    var metricId by remember { mutableStateOf("corners_for") }
    var window by remember { mutableStateOf(6) }
    var comparator by remember { mutableStateOf(Comparator.AT_LEAST) }
    var threshold by remember { mutableStateOf(5f) }

    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(6.dp))
            .background(Fw.colors.surfaceRaised)
            .padding(12.dp),
    ) {
        Eyebrow("New clause")
        Spacer(Modifier.height(10.dp))

        Picker(Subject.entries.toList(), subject, { it.label }) { subject = it }
        Spacer(Modifier.height(8.dp))
        Picker(Catalog.metrics.map { it.id }, metricId, { Catalog.metric(it).label }) { metricId = it }
        Spacer(Modifier.height(8.dp))
        Picker(listOf(3, 6, 10, 18), window, { "Last $it matches" }) { window = it }
        Spacer(Modifier.height(8.dp))
        Picker(Comparator.entries.toList(), comparator, { it.label }) { comparator = it }

        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Threshold", fontSize = 12.sp, color = Fw.colors.inkMuted)
            Text(
                String.format("%.1f", threshold),
                fontSize = 13.sp,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold,
                color = Fw.colors.accent,
            )
        }
        Slider(
            value = threshold,
            onValueChange = { threshold = Math.round(it * 2f) / 2f },
            valueRange = 0f..40f,
            colors = SliderDefaults.colors(
                thumbColor = Fw.colors.accent,
                activeTrackColor = Fw.colors.accent,
                inactiveTrackColor = Fw.colors.rule,
            ),
        )

        Spacer(Modifier.height(6.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(
                "Add clause",
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = Fw.colors.accent,
                modifier = Modifier.clickable {
                    onAdd(Clause(subject, metricId, window, comparator, threshold.toDouble()))
                },
            )
            Text(
                "Cancel",
                fontSize = 13.sp,
                color = Fw.colors.inkMuted,
                modifier = Modifier.clickable(onClick = onCancel),
            )
        }
    }
}

/** Minimal dropdown; avoids the experimental exposed-dropdown API. */
@Composable
private fun <T> Picker(
    options: List<T>,
    selected: T,
    display: (T) -> String,
    onSelect: (T) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(5.dp))
                .background(Fw.colors.surface)
                .border(1.dp, Fw.colors.rule, RoundedCornerShape(5.dp))
                .clickable { expanded = true }
                .padding(horizontal = 11.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(display(selected), fontSize = 13.sp, color = Fw.colors.ink)
            Text("▾", fontSize = 12.sp, color = Fw.colors.inkFaint)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(display(option), fontSize = 13.sp) },
                    onClick = { onSelect(option); expanded = false },
                )
            }
        }
    }
}
