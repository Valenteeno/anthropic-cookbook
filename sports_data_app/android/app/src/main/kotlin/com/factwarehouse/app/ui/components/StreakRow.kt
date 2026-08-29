package com.factwarehouse.app.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.factwarehouse.app.ui.theme.Fw
import com.factwarehouse.core.engine.Streak
import com.factwarehouse.core.engine.StreakKind

/**
 * One streak, with everything needed to judge it rather than just react to it.
 * The length is the headline; the rate bar underneath is the correction.
 */
@Composable
fun StreakRow(
    teamShort: String,
    streak: Streak,
    modifier: Modifier = Modifier,
    dense: Boolean = false,
) {
    val isRun = streak.kind == StreakKind.RUN
    val spanLabel = when {
        streak.censored -> "all ${streak.length}"
        else -> "${streak.length}"
    }
    val kindLabel = if (isRun) "in a row" else "without"

    Column(modifier.fillMaxWidth().padding(vertical = if (dense) 5.dp else 7.dp)) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Chip(teamShort, Fw.colors.accent, Fw.colors.accentWash)
                Spacer(Modifier.width(8.dp))
                Text(
                    streak.label,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    color = Fw.colors.ink,
                )
            }
            Text(
                "$spanLabel $kindLabel",
                fontSize = 12.sp,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold,
                color = if (isRun) Fw.colors.good else Fw.colors.inkMuted,
            )
        }

        Spacer(Modifier.height(6.dp))
        RateBar(
            rate = streak.underlyingRate,
            intervalLow = streak.interval.low,
            intervalHigh = streak.interval.high,
            baseline = streak.baselineRate,
            good = streak.edgeOverBaseline > 0,
        )
        Spacer(Modifier.height(5.dp))

        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "team ${pct(streak.underlyingRate)} · league ${pct(streak.baselineRate)} · n=${streak.sampleSize}",
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace,
                color = Fw.colors.inkFaint,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (streak.censored) {
                    Chip("no start", Fw.colors.inkMuted, Fw.colors.surfaceRaised)
                }
                if (streak.regressionRisk) {
                    Chip("regression risk", Fw.colors.hard, Fw.colors.hardWash)
                }
            }
        }
    }
}
