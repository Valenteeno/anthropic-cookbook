package com.factwarehouse.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * Slate neutrals with a single gold accent. Green and red are reserved strictly for
 * hit/miss and risk semantics, so the accent never competes with the thing the user
 * is actually reading off the screen.
 */
@Immutable
data class FwColors(
    val ground: Color,
    val surface: Color,
    val surfaceRaised: Color,
    val ink: Color,
    val inkMuted: Color,
    val inkFaint: Color,
    val rule: Color,
    val accent: Color,
    val accentWash: Color,
    val good: Color,
    val goodWash: Color,
    val hard: Color,
    val hardWash: Color,
)

private val DarkColors = FwColors(
    ground = Color(0xFF10141A),
    surface = Color(0xFF171C24),
    surfaceRaised = Color(0xFF1E242E),
    ink = Color(0xFFE7EBF1),
    inkMuted = Color(0xFFA5AFC0),
    inkFaint = Color(0xFF7C8798),
    rule = Color(0xFF2A323D),
    accent = Color(0xFFE3AE3C),
    accentWash = Color(0xFF2A2213),
    good = Color(0xFF5CC48D),
    goodWash = Color(0xFF12291D),
    hard = Color(0xFFEF8492),
    hardWash = Color(0xFF2C1418),
)

private val LightColors = FwColors(
    ground = Color(0xFFF1F3F6),
    surface = Color(0xFFFFFFFF),
    surfaceRaised = Color(0xFFE8EBF0),
    ink = Color(0xFF151A21),
    inkMuted = Color(0xFF4C5666),
    inkFaint = Color(0xFF79839A),
    rule = Color(0xFFD5DAE3),
    accent = Color(0xFF8F6200),
    accentWash = Color(0xFFF6EEDC),
    good = Color(0xFF15683B),
    goodWash = Color(0xFFE2F0E8),
    hard = Color(0xFF9E2637),
    hardWash = Color(0xFFF7E4E7),
)

val LocalFwColors = staticCompositionLocalOf { DarkColors }

/** Shorthand so screens read `Fw.colors.accent` rather than threading the palette. */
object Fw {
    val colors: FwColors
        @Composable get() = LocalFwColors.current
}

/** Tabular figures for anything a user compares down a column. */
val NumberStyle = TextStyle(
    fontFamily = FontFamily.Monospace,
    fontSize = 13.sp,
    fontWeight = FontWeight.Medium,
)

val LabelStyle = TextStyle(
    fontFamily = FontFamily.Monospace,
    fontSize = 10.sp,
    fontWeight = FontWeight.Medium,
    letterSpacing = 1.2.sp,
)

private val FwTypography = Typography(
    titleLarge = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp),
    titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.2).sp),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 20.sp),
    bodySmall = TextStyle(fontSize = 12.sp, lineHeight = 17.sp),
)

@Composable
fun FactWarehouseTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colors = if (darkTheme) DarkColors else LightColors

    val scheme = if (darkTheme) {
        darkColorScheme(
            primary = colors.accent,
            onPrimary = colors.ground,
            background = colors.ground,
            onBackground = colors.ink,
            surface = colors.surface,
            onSurface = colors.ink,
            surfaceVariant = colors.surfaceRaised,
            onSurfaceVariant = colors.inkMuted,
            outline = colors.rule,
            error = colors.hard,
        )
    } else {
        lightColorScheme(
            primary = colors.accent,
            onPrimary = Color.White,
            background = colors.ground,
            onBackground = colors.ink,
            surface = colors.surface,
            onSurface = colors.ink,
            surfaceVariant = colors.surfaceRaised,
            onSurfaceVariant = colors.inkMuted,
            outline = colors.rule,
            error = colors.hard,
        )
    }

    CompositionLocalProvider(LocalFwColors provides colors) {
        MaterialTheme(colorScheme = scheme, typography = FwTypography, content = content)
    }
}
