package com.factwarehouse.core.engine

import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.sqrt

/** A binomial proportion confidence interval, as a fraction of 1. */
data class Interval(val low: Double, val high: Double) {
    val width: Double get() = high - low
}

object Stats {

    /**
     * Wilson score interval. Preferred over the normal approximation because it stays
     * inside [0, 1] and behaves sensibly at the small sample sizes that streak analysis
     * actually produces — which is the whole point of showing it.
     */
    fun wilson(successes: Int, n: Int, z: Double = 1.96): Interval {
        if (n == 0) return Interval(0.0, 1.0)
        val p = successes.toDouble() / n
        val z2 = z * z
        val denominator = 1 + z2 / n
        val centre = p + z2 / (2 * n)
        val margin = z * sqrt(p * (1 - p) / n + z2 / (4.0 * n * n))
        return Interval(
            low = ((centre - margin) / denominator).coerceIn(0.0, 1.0),
            high = ((centre + margin) / denominator).coerceIn(0.0, 1.0),
        )
    }

    /**
     * Probability of observing a run of [length] consecutive successes given [baseline],
     * used as the rarity score for a streak. Deliberately simple: it answers "how
     * surprising is this run if the league rate is all that is going on?", which is the
     * question a bettor looking at a green tile should be asking.
     */
    fun runProbability(baseline: Double, length: Int): Double {
        val p = baseline.coerceIn(0.0001, 0.9999)
        return p.pow(length)
    }

    /**
     * Rarity on a readable scale. 0 means "exactly what the league does anyway";
     * higher means the run is progressively harder to explain by the base rate alone.
     */
    fun notability(baseline: Double, length: Int): Double =
        (-ln(runProbability(baseline, length)) / ln(10.0)) * 10.0

    /** Decimal price at which a bet at [rate] breaks even, before any stake sizing. */
    fun breakEvenPrice(rate: Double): Double =
        if (rate <= 0.0) Double.POSITIVE_INFINITY else 1.0 / rate
}
