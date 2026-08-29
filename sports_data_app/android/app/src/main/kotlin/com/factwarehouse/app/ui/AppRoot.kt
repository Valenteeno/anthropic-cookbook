package com.factwarehouse.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.factwarehouse.app.ui.fixture.FixtureScreen
import com.factwarehouse.app.ui.screener.ScreenerScreen
import com.factwarehouse.app.ui.theme.Fw
import com.factwarehouse.app.ui.today.TodayScreen
import com.factwarehouse.core.data.FactRepository

private const val ROUTE_TODAY = "today"
private const val ROUTE_SCREENER = "screener"
private const val ROUTE_FIXTURE = "fixture/{fixtureId}"

@Composable
fun AppRoot() {
    val navController = rememberNavController()
    // One in-memory warehouse for the session. Swapping in a Room-backed repository
    // is the only change this layer needs when real ingestion lands.
    val repo = remember { FactRepository() }

    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route

    Scaffold(
        containerColor = Fw.colors.ground,
        bottomBar = {
            if (currentRoute == ROUTE_TODAY || currentRoute == ROUTE_SCREENER) {
                NavigationBar(containerColor = Fw.colors.surface) {
                    BottomItem("Board", "▤", currentRoute == ROUTE_TODAY) {
                        navController.navigate(ROUTE_TODAY) { launchSingleTop = true }
                    }
                    BottomItem("Screener", "⌗", currentRoute == ROUTE_SCREENER) {
                        navController.navigate(ROUTE_SCREENER) { launchSingleTop = true }
                    }
                }
            }
        },
    ) { padding ->
        Box(
            Modifier
                .fillMaxSize()
                .background(Fw.colors.ground)
                .padding(padding),
        ) {
            NavHost(navController = navController, startDestination = ROUTE_TODAY) {
                composable(ROUTE_TODAY) {
                    TodayScreen(repo) { fixtureId -> navController.navigate("fixture/$fixtureId") }
                }
                composable(ROUTE_SCREENER) {
                    ScreenerScreen(repo)
                }
                composable(
                    ROUTE_FIXTURE,
                    arguments = listOf(navArgument("fixtureId") { type = NavType.StringType }),
                ) { entry ->
                    FixtureScreen(
                        repo = repo,
                        fixtureId = entry.arguments?.getString("fixtureId").orEmpty(),
                        onBack = { navController.popBackStack() },
                    )
                }
            }
        }
    }
}

@Composable
private fun RowScope.BottomItem(
    label: String,
    glyph: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    NavigationBarItem(
        selected = selected,
        onClick = onClick,
        icon = { Text(glyph, fontSize = 16.sp) },
        label = {
            Text(
                label,
                fontSize = 11.sp,
                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            )
        },
        colors = NavigationBarItemDefaults.colors(
            selectedIconColor = Fw.colors.accent,
            selectedTextColor = Fw.colors.accent,
            unselectedIconColor = Fw.colors.inkFaint,
            unselectedTextColor = Fw.colors.inkFaint,
            indicatorColor = Fw.colors.accentWash,
        ),
    )
}
