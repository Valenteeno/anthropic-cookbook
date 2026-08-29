package com.factwarehouse.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.factwarehouse.app.ui.theme.Fw
import com.factwarehouse.app.ui.theme.LabelStyle
import kotlin.math.roundToInt

@Composable
fun Eyebrow(text: String, color: Color = Fw.colors.accent, modifier: Modifier = Modifier) {
    Text(text.uppercase(), style = LabelStyle, color = color, modifier = modifier)
}

@Composable
fun Chip(
    text: String,
    fg: Color,
    bg: Color,
    modifier: Modifier = Modifier,
) {
    Text(
        text = text.uppercase(),
        style = LabelStyle,
        color = fg,
        modifier = modifier
            .clip(RoundedCornerShape(3.dp))
            .background(bg)
            .padding(horizontal = 6.dp, vertical = 3.dp),
    )
}

@Composable
fun SectionHeader(title: String, subtitle: String? = null) {
    Column(Modifier.padding(bottom = 10.dp)) {
        Text(
            title,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = (-0.2).sp,
            color = Fw.colors.ink,
        )
        if (subtitle != null) {
            Text(subtitle, fontSize = 12.sp, color = Fw.colors.inkFaint, modifier = Modifier.padding(top = 2.dp))
        }
    }
}

@Composable
fun Panel(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Fw.colors.surface)
            .border(1.dp, Fw.colors.rule, RoundedCornerShape(8.dp))
            .padding(14.dp),
    ) { content() }
}

fun pct(v: Double): String = "${(v * 100).roundToInt()}%"

/**
 * The honest-stats bar. Shows three things at once, because showing only the first is
 * the thing this product exists to stop doing:
 *   - the team's rate (solid marker),
 *   - its Wilson confidence interval (the band, i.e. how much the rate is worth),
 *   - the league baseline (the tick it has to beat to mean anything).
 */
@Composable
fun RateBar(
    rate: Double,
    intervalLow: Double,
    intervalHigh: Double,
    baseline: Double,
    good: Boolean,
    modifier: Modifier = Modifier,
) {
    val accent = if (good) Fw.colors.good else Fw.colors.hard
    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .height(16.dp),
    ) {
        val full = maxWidth
        Box(
            Modifier
                .fillMaxWidth()
                .height(6.dp)
                .align(Alignment.CenterStart)
                .offset(y = 1.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(Fw.colors.surfaceRaised),
        )
        // Confidence band
        Box(
            Modifier
                .offset(x = full * intervalLow.toFloat())
                .width(full * (intervalHigh - intervalLow).toFloat().coerceAtLeast(0.005f))
                .height(6.dp)
                .align(Alignment.CenterStart)
                .offset(y = 1.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(accent.copy(alpha = 0.32f)),
        )
        // Team rate
        Box(
            Modifier
                .offset(x = full * rate.toFloat() - 3.dp)
                .size(width = 6.dp, height = 12.dp)
                .align(Alignment.CenterStart)
                .clip(RoundedCornerShape(2.dp))
                .background(accent),
        )
        // League baseline
        Box(
            Modifier
                .offset(x = full * baseline.toFloat() - 1.dp)
                .size(width = 2.dp, height = 16.dp)
                .align(Alignment.CenterStart)
                .background(Fw.colors.inkFaint),
        )
    }
}

/** Last-N results strip: the quickest read of form there is. */
@Composable
fun ResultStrip(results: List<Char>, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        results.forEach { r ->
            val (fg, bg) = when (r) {
                'W' -> Fw.colors.good to Fw.colors.goodWash
                'L' -> Fw.colors.hard to Fw.colors.hardWash
                else -> Fw.colors.inkMuted to Fw.colors.surfaceRaised
            }
            Box(
                Modifier
                    .size(20.dp)
                    .clip(RoundedCornerShape(3.dp))
                    .background(bg),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    r.toString(),
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold,
                    color = fg,
                )
            }
        }
    }
}

/** Hit/miss tiles for a predicate over recent matches, most recent on the left. */
@Composable
fun HitStrip(hits: List<Boolean>, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        hits.forEach { hit ->
            Box(
                Modifier
                    .size(width = 14.dp, height = 18.dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(if (hit) Fw.colors.good.copy(alpha = 0.75f) else Fw.colors.surfaceRaised),
            )
        }
    }
}

@Composable
fun LabeledValue(label: String, value: String, emphasis: Color = Fw.colors.ink) {
    Column {
        Eyebrow(label, Fw.colors.inkFaint)
        Spacer(Modifier.height(3.dp))
        Text(
            value,
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold,
            fontFamily = FontFamily.Monospace,
            color = emphasis,
        )
    }
}

/** Two averages compared against each other and their league baseline. */
@Composable
fun ComparisonRow(
    label: String,
    homeValue: Double,
    awayValue: Double,
    baseline: Double,
    modifier: Modifier = Modifier,
) {
    val max = maxOf(homeValue, awayValue, baseline) * 1.15 + 0.01
    Column(modifier.padding(vertical = 6.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(label, fontSize = 12.sp, color = Fw.colors.inkMuted)
            Text(
                "league ${String.format("%.2f", baseline)}",
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace,
                color = Fw.colors.inkFaint,
            )
        }
        Spacer(Modifier.height(5.dp))
        listOf(homeValue to true, awayValue to false).forEach { (value, isHome) ->
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 2.dp)) {
                Text(
                    String.format("%.2f", value),
                    style = LabelStyle,
                    color = Fw.colors.ink,
                    modifier = Modifier.width(38.dp),
                )
                BoxWithConstraints(Modifier.fillMaxWidth().height(8.dp)) {
                    val full = maxWidth
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(8.dp)
                            .clip(RoundedCornerShape(4.dp))
                            .background(Fw.colors.surfaceRaised),
                    )
                    Box(
                        Modifier
                            .width(full * (value / max).toFloat().coerceIn(0f, 1f))
                            .height(8.dp)
                            .clip(RoundedCornerShape(4.dp))
                            .background(if (isHome) Fw.colors.accent else Fw.colors.accent.copy(alpha = 0.5f)),
                    )
                    Box(
                        Modifier
                            .offset(x = full * (baseline / max).toFloat().coerceIn(0f, 1f) - 1.dp)
                            .size(width = 2.dp, height = 8.dp)
                            .background(Fw.colors.inkFaint),
                    )
                }
            }
        }
    }
}
