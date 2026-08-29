package com.factwarehouse.core.data

import com.factwarehouse.core.model.Fixture
import com.factwarehouse.core.model.League
import com.factwarehouse.core.model.Team
import com.factwarehouse.core.model.TeamMatchFact
import com.factwarehouse.core.model.Venue
import kotlin.math.exp
import kotlin.random.Random

/**
 * Seeded synthetic data.
 *
 * The competitions and clubs here are invented, and every number is simulated — nothing
 * in this prototype is real football data. It exists so the streak engine, the screener
 * and the backtest run against something with realistic shape and variance, and so a
 * reviewer can see them working before any provider contract is signed.
 *
 * Swap this object for a Room-backed repository fed by the ingestion pipeline and every
 * screen above it keeps working unchanged.
 */
object MockData {

    const val DISCLAIMER = "Synthetic data — invented clubs, simulated results"

    private const val SEED = 20260829L
    private const val MATCHDAYS_PLAYED = 18
    private const val CYCLES = 3

    val leagues = listOf(
        League("meridian", "Meridian League", "Tier 1"),
        League("coastal", "Coastal Championship", "Tier 2"),
        League("northern", "Northern Division", "Tier 1"),
    )

    private val clubNames = mapOf(
        "meridian" to listOf(
            "Harbour City", "Ashford Rovers", "Kingsmere", "Vale Athletic", "Blackthorn",
            "Regent Park", "Stonebridge", "Fairwater", "Eastgate United", "Mill Hill",
        ),
        "coastal" to listOf(
            "Saltmarsh", "Pier Road", "Brackenbay", "Cliffton Town", "Havenport",
            "Dunmore", "Westquay", "Tidewell", "Lomond Bay", "Cape Ferris",
        ),
        "northern" to listOf(
            "Ironworks FC", "Colliery Town", "Redhill", "Gatesmoor", "Pennine United",
            "Calderfield", "Loxley", "Hartwood", "Brindle Park", "Auldmoor",
        ),
    )

    private val referees = listOf(
        "A. Deverell", "M. Osei", "R. Kowalczyk", "T. Bramall", "S. Ibori", "J. Renwick",
    )

    /** Per-team simulation profile. Real spread across teams is what makes streaks meaningful. */
    private data class Profile(
        val attack: Double,
        val defence: Double,
        val cornerBias: Double,
        val cardBias: Double,
        val tempo: Double,
    )

    val teams: List<Team>
    private val profiles: Map<String, Profile>
    val facts: List<TeamMatchFact>
    val fixtures: List<Fixture>

    init {
        val random = Random(SEED)

        val builtTeams = mutableListOf<Team>()
        val builtProfiles = mutableMapOf<String, Profile>()

        leagues.forEach { league ->
            clubNames.getValue(league.id).forEachIndexed { index, name ->
                val id = "${league.id}_$index"
                builtTeams += Team(id, name, shortNameOf(name), league.id)
                builtProfiles[id] = Profile(
                    attack = 0.70 + random.nextDouble() * 0.95,
                    defence = 0.70 + random.nextDouble() * 0.95,
                    cornerBias = 0.72 + random.nextDouble() * 0.75,
                    cardBias = 0.60 + random.nextDouble() * 1.00,
                    tempo = 0.85 + random.nextDouble() * 0.40,
                )
            }
        }

        teams = builtTeams
        profiles = builtProfiles

        val builtFacts = mutableListOf<TeamMatchFact>()
        val builtFixtures = mutableListOf<Fixture>()

        leagues.forEach { league ->
            val leagueTeams = teams.filter { it.leagueId == league.id }
            val schedule = roundRobin(leagueTeams.map { it.id })

            schedule.take(MATCHDAYS_PLAYED).forEachIndexed { matchDay, round ->
                round.forEach { (homeId, awayId) ->
                    builtFacts += simulate(homeId, awayId, league.id, matchDay + 1, random)
                }
            }

            // The next unplayed round becomes the upcoming fixture list.
            schedule.getOrNull(MATCHDAYS_PLAYED)?.forEachIndexed { index, (homeId, awayId) ->
                builtFixtures += Fixture(
                    id = "${league.id}_fx_$index",
                    leagueId = league.id,
                    homeTeamId = homeId,
                    awayTeamId = awayId,
                    kickoff = listOf("15:00", "17:30", "20:00", "19:45", "13:30")[index % 5],
                    dayLabel = if (index % 3 == 0) "Today" else "Tomorrow",
                    referee = referees[random.nextInt(referees.size)],
                    prices = mapOf(
                        "over_2_5" to round2(1.62 + random.nextDouble() * 0.55),
                        "btts" to round2(1.68 + random.nextDouble() * 0.45),
                        "corners_over_9_5" to round2(1.75 + random.nextDouble() * 0.50),
                        "cards_over_3_5" to round2(1.80 + random.nextDouble() * 0.60),
                        "over_1_5" to round2(1.22 + random.nextDouble() * 0.25),
                    ),
                )
            }
        }

        facts = builtFacts
        fixtures = builtFixtures
    }

    /** Both fact rows for one simulated match. */
    private fun simulate(
        homeId: String,
        awayId: String,
        leagueId: String,
        matchDay: Int,
        random: Random,
    ): List<TeamMatchFact> {
        val home = profiles.getValue(homeId)
        val away = profiles.getValue(awayId)

        // Per-match form. Without this, a team's profile alone decides every predicate
        // and some markets become structurally impossible for it — which shows up as
        // fake season-long "streaks" rather than the real within-team variance football
        // actually has.
        val homeForm = 0.68 + random.nextDouble() * 0.72
        val awayForm = 0.68 + random.nextDouble() * 0.72

        val homeXg = (1.38 * (home.attack * homeForm) / (away.defence * awayForm)).coerceIn(0.20, 3.8)
        val awayXg = (1.05 * (away.attack * awayForm) / (home.defence * homeForm)).coerceIn(0.18, 3.4)

        val homeGoals = poisson(homeXg, random)
        val awayGoals = poisson(awayXg, random)

        val homeMinutes = goalMinutes(homeGoals, random)
        val awayMinutes = goalMinutes(awayGoals, random)

        val tempo = (home.tempo + away.tempo) / 2
        val homeCorners = poisson(5.2 * home.cornerBias * tempo, random)
        val awayCorners = poisson(4.4 * away.cornerBias * tempo, random)

        val refStrictness = 0.8 + random.nextDouble() * 0.5
        val homeYellows = poisson(1.35 * home.cardBias * refStrictness, random)
        val awayYellows = poisson(1.55 * away.cardBias * refStrictness, random)
        val homeReds = if (random.nextDouble() < 0.035 * home.cardBias) 1 else 0
        val awayReds = if (random.nextDouble() < 0.045 * away.cardBias) 1 else 0

        val homeShots = poisson(homeXg * 7.4, random).coerceAtLeast(homeGoals)
        val awayShots = poisson(awayXg * 7.0, random).coerceAtLeast(awayGoals)
        val homeSot = poisson(homeShots * 0.36, random).coerceIn(homeGoals, homeShots)
        val awaySot = poisson(awayShots * 0.34, random).coerceIn(awayGoals, awayShots)

        fun fact(
            teamId: String, opponentId: String, venue: Venue,
            gf: Int, ga: Int, forMinutes: List<Int>, againstMinutes: List<Int>,
            cf: Int, ca: Int, yf: Int, ya: Int, rf: Int, ra: Int,
            shots: Int, sot: Int, xgF: Double, xgA: Double,
        ) = TeamMatchFact(
            teamId = teamId,
            opponentId = opponentId,
            leagueId = leagueId,
            matchDay = matchDay,
            venue = venue,
            goalsFor = gf,
            goalsAgainst = ga,
            goalsForHt = forMinutes.count { it <= 45 },
            goalsAgainstHt = againstMinutes.count { it <= 45 },
            cornersFor = cf,
            cornersAgainst = ca,
            yellowsFor = yf,
            yellowsAgainst = ya,
            redsFor = rf,
            redsAgainst = ra,
            shots = shots,
            shotsOnTarget = sot,
            xgFor = round2(xgF * (0.86 + random.nextDouble() * 0.30)),
            xgAgainst = round2(xgA * (0.86 + random.nextDouble() * 0.30)),
            firstGoalForMinute = forMinutes.minOrNull(),
            firstGoalAgainstMinute = againstMinutes.minOrNull(),
        )

        return listOf(
            fact(
                homeId, awayId, Venue.HOME, homeGoals, awayGoals, homeMinutes, awayMinutes,
                homeCorners, awayCorners, homeYellows, awayYellows, homeReds, awayReds,
                homeShots, homeSot, homeXg, awayXg,
            ),
            fact(
                awayId, homeId, Venue.AWAY, awayGoals, homeGoals, awayMinutes, homeMinutes,
                awayCorners, homeCorners, awayYellows, homeYellows, awayReds, homeReds,
                awayShots, awaySot, awayXg, homeXg,
            ),
        )
    }

    /** Goal minutes skewed towards the second half, as real distributions are. */
    private fun goalMinutes(count: Int, random: Random): List<Int> =
        List(count) {
            val u = random.nextDouble()
            (1 + (90 * u.let { x -> x * x * 0.45 + x * 0.55 })).toInt().coerceIn(1, 90)
        }.sorted()

    private fun poisson(lambda: Double, random: Random): Int {
        if (lambda <= 0) return 0
        val limit = exp(-lambda)
        var k = 0
        var p = 1.0
        do {
            k++
            p *= random.nextDouble()
        } while (p > limit)
        return k - 1
    }

    /**
     * Circle-method round robin, home/away alternated so venues stay balanced.
     * Three cycles, which for a ten-team league yields 27 rounds: the first
     * [MATCHDAYS_PLAYED] become history and the next one becomes the fixture list.
     */
    private fun roundRobin(teamIds: List<String>): List<List<Pair<String, String>>> {
        val ids = teamIds.toMutableList()
        val n = ids.size
        val rounds = mutableListOf<List<Pair<String, String>>>()

        repeat(CYCLES) { cycle ->
            val rotating = ids.toMutableList()
            repeat(n - 1) { round ->
                val pairs = mutableListOf<Pair<String, String>>()
                for (i in 0 until n / 2) {
                    val a = rotating[i]
                    val b = rotating[n - 1 - i]
                    val homeFirst = (round + i + cycle) % 2 == 0
                    pairs += if (homeFirst) a to b else b to a
                }
                rounds += pairs
                val last = rotating.removeAt(n - 1)
                rotating.add(1, last)
            }
        }
        return rounds
    }

    private fun shortNameOf(name: String): String {
        val words = name.split(" ")
        return if (words.size == 1) name.take(3).uppercase()
        else words.take(3).joinToString("") { it.first().uppercase() }
    }

    private fun round2(v: Double): Double = Math.round(v * 100.0) / 100.0
}
