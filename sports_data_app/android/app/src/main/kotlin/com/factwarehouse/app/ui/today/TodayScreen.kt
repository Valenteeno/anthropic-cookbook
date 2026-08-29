package com.factwarehouse.app.ui.today

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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
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
import com.factwarehouse.app.ui.components.StreakRow
import com.factwarehouse.app.ui.theme.Fw
import com.factwarehouse.core.data.FactRepository
import com.factwarehouse.core.data.FixtureHighlight
import com.factwarehouse.core.data.MockData
import kotlin.math.roundToInt

/**
 * The today board. Fixtures are ranked by how surprising their strongest streak is
 * against its own league baseline, not by kickoff time and not by how green the tile
 * looks — which is the whole argument of the product.
 */
@Composable
fun TodayScreen(
    repo: FactRepository,
    onOpenFixture: (String) -> Unit,
) {
    var leagueFilter by remember { mutableStateOf<String?>(null) }
    val highlights = remember(leagueFilter) {
        repo.highlights().filter { leagueFilter == null || it.league.id == leagueFilter }
    }

    Column(Modifier.fillMaxSize().background(Fw.colors.ground)) {
        Header(repo)
        LeagueFilter(repo, leagueFilter) { leagueFilter = it }

        LazyColumn(
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(highlights, key = { it.fixture.id }) { highlight ->
                FixtureCard(highlight) { onOpenFixture(highlight.fixture.id) }
            }
        }
    }
}

@Composable
private fun Header(repo: FactRepository) {
    Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 20.dp, bottom = 12.dp)) {
        Eyebrow("Today's board")
        Spacer(Modifier.height(6.dp))
        Text(
            "Ranked by notability",
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = (-0.6).sp,
            color = Fw.colors.ink,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            "${repo.fixtures.size} fixtures · ${repo.facts.size} fact rows scanned across ${repo.leagues.size} leagues",
            fontSize = 12.sp,
            color = Fw.colors.inkFaint,
        )
        Spacer(Modifier.height(10.dp))
        Row(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(5.dp))
                .background(Fw.colors.accentWash)
                .padding(horizontal = 10.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                MockData.DISCLAIMER,
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace,
                color = Fw.colors.accent,
            )
        }
    }
}

@Composable
private fun LeagueFilter(repo: FactRepository, selected: String?, onSelect: (String?) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(bottom = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        FilterPill("All leagues", selected == null) { onSelect(null) }
        repo.leagues.forEach { league ->
            FilterPill(league.name, selected == league.id) { onSelect(league.id) }
        }
    }
}

@Composable
private fun FilterPill(label: String, active: Boolean, onClick: () -> Unit) {
    Text(
        label,
        fontSize = 12.sp,
        fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal,
        color = if (active) Fw.colors.ground else Fw.colors.inkMuted,
        modifier = Modifier
            .clip(RoundedCornerShape(14.dp))
            .background(if (active) Fw.colors.accent else Fw.colors.surface)
            .border(
                1.dp,
                if (active) Fw.colors.accent else Fw.colors.rule,
                RoundedCornerShape(14.dp),
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 7.dp),
    )
}

@Composable
private fun FixtureCard(highlight: FixtureHighlight, onClick: () -> Unit) {
    val top = highlight.topStreaks.take(3)
    val flagged = highlight.topStreaks.count { it.second.regressionRisk }

    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(Fw.colors.surface)
            .border(1.dp, Fw.colors.rule, RoundedCornerShape(10.dp))
            .clickable(onClick = onClick)
            .padding(14.dp),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "${highlight.league.name} · ${highlight.fixture.dayLabel} ${highlight.fixture.kickoff}",
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace,
                color = Fw.colors.inkFaint,
            )
            NotabilityMeter(highlight.notability)
        }

        Spacer(Modifier.height(9.dp))
        Text(
            highlight.homeTeam.name,
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = (-0.3).sp,
            color = Fw.colors.ink,
        )
        Text(
            highlight.awayTeam.name,
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = (-0.3).sp,
            color = Fw.colors.ink,
        )

        if (top.isNotEmpty()) {
            Spacer(Modifier.height(10.dp))
            Box(Modifier.fillMaxWidth().height(1.dp).background(Fw.colors.rule))
            top.forEach { (team, streak) ->
                StreakRow(team.short, streak, dense = true)
            }
        } else {
            Spacer(Modifier.height(10.dp))
            Text(
                "No run of three or more on either side.",
                fontSize = 12.sp,
                color = Fw.colors.inkFaint,
            )
        }

        if (flagged > 0) {
            Spacer(Modifier.height(6.dp))
            Chip(
                "$flagged of these look like noise",
                Fw.colors.hard,
                Fw.colors.hardWash,
            )
        }
    }
}

/** Compact rarity readout — how hard this fixture's best streak is to explain by chance. */
@Composable
private fun NotabilityMeter(score: Double) {
    val filled = (score / 12.0).roundToInt().coerceIn(0, 5)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            score.roundToInt().toString(),
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Bold,
            color = Fw.colors.accent,
        )
        Spacer(Modifier.width(4.dp))
        repeat(5) { index ->
            Box(
                Modifier
                    .width(4.dp)
                    .height((5 + index * 2).dp)
                    .clip(RoundedCornerShape(1.dp))
                    .background(if (index < filled) Fw.colors.accent else Fw.colors.surfaceRaised),
            )
        }
    }
}
