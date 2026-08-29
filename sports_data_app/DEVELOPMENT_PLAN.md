# Football Stats & Prediction-Aid Platform — Development Plan

**Status:** Draft v1 · **Scope:** feasibility assessment + end-to-end build plan
**Primary product:** a derived-statistics engine that makes football data trivially easy to interrogate for prediction purposes.
**Secondary utility:** booking-code conversion and booking-code outcome checking.

---

## 1. Verdict

The idea splits into three components with very different feasibility profiles. Treating them as one project is the main risk.

| Component | Feasibility | Why |
|---|---|---|
| Stats + streak + screener engine | **High** — build it | Entirely solved by licensed data + your own derived layer. No third-party dependency you cannot replace. This is the product. |
| Booking-code load & outcome check | **Medium** — build it, carefully | Depends on parsing a code into selections. Doable via a converter vendor's parse response or manual entry. The settlement engine itself is deterministic and fully in your control. |
| Booking-code conversion | **Medium-low to build, high to buy** | Bookmakers publish no public booking-code API. Every working converter either has commercial arrangements or reverse-engineers private endpoints. Integrate a vendor; do not build. |

**The single decision that determines whether this works:** data coverage depth on the leagues your users actually bet. Corners, cards, half-splits, shot data and xG are well covered in the top ~50 leagues and thin-to-absent below that. Nigerian, Kenyan and wider African punters bet heavily on obscure leagues, e-football and simulated markets. Validate coverage against a real bet-slip sample **before writing application code** (Phase 0).

---

## 2. What you are actually building

Reframe: the app is not a stats website. It is a **football fact warehouse with a query surface**.

- **Ingestion** normalises vendor feeds into a canonical schema.
- **Derivation** computes one wide fact row per team per match (~200 columns).
- **The streak engine** runs every predicate against every team nightly and materialises notable runs.
- **The screener** lets a user compose predicates and get today's matching fixtures plus the historical hit rate.
- **The slip tools** (load, check, convert) are surfaces on the same warehouse.

Every feature the user asked for — corners, cards, half occurrences, xG, shots, team first-goal time, game first-goal time — is a *predicate over the fact table*, not a separate feature. Build the table right and the features are queries.

---

## 3. Competitive read

| Site | What it does well | The gap you exploit |
|---|---|---|
| **soccerstats.com** | Enormous league breadth; per-league form, over/under, BTTS, HT/FT, timing tables. Free. | Fixed tables only. No cross-league querying, no composability, no xG, dated UX, no persistence of your own picks. |
| **btfstats.com** | Green/red tile visualisation, tag filters (e.g. "home first half over 1.5"), team streaks, league stats across 1X2, O/U, GG/NG, corners, yellow cards. | Streaks are shown without base-rate context — a 7-match over run in a high-scoring league is not the same signal as one in a low-scoring league. No backtesting, no significance ranking. |
| **footystats.org** | Deepest betting-oriented dataset (~200 leagues), xG, goal timings, HT/FT, and a paid JSON API. | It is a data source you can buy. Its own UI is per-team/per-league browsing, not a cross-league screener with saved queries and alerts. |

**Your differentiators, ranked:**
1. **Composable screener** — arbitrary predicate combinations across all leagues at once.
2. **Base-rate honest streaks** — every streak ranked by rarity against its own league baseline, with the underlying rate shown next to it.
3. **Backtest-on-tap** — any filter set immediately reports its historical hit rate, sample size and confidence interval, with vig-adjusted break-even.
4. **Slip lifecycle** — book it, load it, auto-settle it, review why legs failed.

---

## 4. Data layer

### 4.1 Provider comparison

| Provider | Coverage | Betting-relevant depth | Indicative price | Verdict |
|---|---|---|---|---|
| **FootyStats API** | ~200 leagues | Purpose-built: O/U, BTTS, results, goal timings, HT/FT, xG, possession, shots via `get_match_stats` | Credit-based, low | **Primary** for derived betting datasets — cheapest route to soccerstats-grade tables |
| **API-Football** | 1,100+ leagues; free tier 100 req/day | Shots (on/off/inside/outside/blocked), corners, cards, fouls, offsides, saves, possession; `/fixtures/events` gives goal & card minutes; per-season `coverage` flags | Free tier, ~$19–29/mo Pro | **Primary** for breadth + event minutes. Always check the season `coverage` booleans before calling downstream endpoints — many leagues return fixtures but no statistics |
| **Sportmonks** | 2,500+ competitions | Proprietary xG, pressure index, predictions; consistent stats coverage, 99.99% uptime, human support | €29 (5 leagues) / €99 (30) / €249 (120) | **Upgrade path** once revenue justifies. Per-league pricing makes early breadth expensive |
| **Understat** | Top 5 leagues + Russia | High-quality shot-level xG | Free, no official API | Enrichment only; scraping, ToS-check required |
| **StatsBomb Open Data** | Selected competitions | Event-level, free on GitHub | Free | Model training / validation set, not production |
| **FBref** | Historically the broadest free source | **Advanced stats were shut down in January 2026** | — | Do not architect around it |
| **Odds feed** (e.g. The Odds API) | Broad bookmaker coverage | Opening/closing prices | Usage-based | Needed for value framing and closing-line-value benchmarking |

### 4.2 Recommendation

Start with **API-Football (breadth + event minutes) + FootyStats API (betting-native aggregates)**, cross-validated against each other. Add an odds feed in Phase 3. Migrate the breadth tier to Sportmonks when paying users exceed the price delta.

### 4.3 The non-negotiable principle

**Never compute a user-facing stat by calling a vendor at request time.** Ingest raw → store canonical → derive your own. Reasons:
- Vendor-precomputed stats cannot be filtered arbitrarily; yours can.
- You control definitions (what counts as "first half", how a void match is handled).
- Switching vendors becomes a mapping change, not a rewrite.
- Request-time vendor calls make your latency and your bill hostage to user behaviour.

---

## 5. Canonical data model

### Core tables
- `competitions` — id, country, tier, type (league/cup), vendor_ids (JSONB)
- `seasons` — competition_id, year, start/end, coverage_flags
- `teams` — canonical id, names, aliases, country
- `team_aliases` — alias string, source, confidence (drives slip name-resolution)
- `venues`, `referees`
- `fixtures` — season_id, kickoff_utc, home/away team, status, round, vendor_ids
- `fixture_scores` — per period: HT, FT, AET, penalties
- `fixture_team_stats` — one row per fixture per team per period (FT/1H/2H): shots, on target, off target, blocked, inside/outside box, corners, yellows, reds, fouls, offsides, saves, possession, passes, pass accuracy, xG, xGA, xGOT, npxG
- `fixture_events` — minute, extra_minute, period, team, player, type (goal/own goal/pen scored/pen missed/yellow/second yellow/red/sub/var), detail
- `odds_snapshots` — fixture, bookmaker, market, selection, price, captured_at
- `shots` — optional shot-level enrichment: minute, xG, body part, situation, x/y

### The derived table that carries the product

`team_match_facts` — **one row per team per match**, materialised nightly. Wide, denormalised, indexed. Every column is a fact about that team in that match, pre-split by period. This is what every streak, filter and screener query reads. Target ~200 columns.

Alongside it, `match_facts` — one row per fixture for game-level facts (game first goal minute, total corners, both-teams-scored, etc.).

A `league_baselines` table stores per-league, per-season rates for every predicate, so any streak can be scored against its own population.

---

## 6. Metric & market taxonomy

Everything below becomes a boolean or numeric column on `team_match_facts` / `match_facts`, and therefore a filterable predicate.

### Goals & results
1X2 · double chance · draw-no-bet · Asian & European handicaps · over/under 0.5–6.5 (FT, 1H, 2H, team-specific) · BTTS (FT / 1H / 2H) · correct score · goal ranges (0–1, 2–3, 4–6, 7+) · odd/even total · HT/FT combinations · win to nil · clean sheet · failed to score · comeback win · led at HT and lost · winning margin · both halves over 0.5 · highest-scoring half · team scored in both halves

### Goal timing
Game first goal minute · team first goal minute · team first conceded minute · last goal minute · goal before minute 10 / 15 / 20 / 30 · goal in each 15-minute band (0–15, 16–30, 31–45+, 46–60, 61–75, 76–90+) · goal in first 5 of each half · goal after 75' · goal after 85' · first team to score · first team to score won/lost/drew · time between goals · scoreless at HT

### Corners
Total corners FT / 1H / 2H · team corners · corner handicap · over/under at every line · race to 3/5/7/9 corners · first corner · last corner · corners conceded · corner differential · corners in 10-minute bands · corners after 80'

### Cards & discipline
Total cards · team cards · yellows / reds separately · booking points (10 per yellow, 25 per red) · first card · first card team · card before HT · card in each half · red card occurrence · second-yellow reds · fouls committed / drawn · fouls per card (referee strictness proxy) · referee-adjusted card baseline

### Shots & attacking volume
Total shots · shots on target · off target · blocked · inside box · outside box · shots per team per half · shot conversion rate · on-target ratio · shots on target over/under · big chances (where available) · attacks / dangerous attacks (where available) · touches in box

### Expected goals
xG for / against · xG differential · non-penalty xG · xGOT · xG per shot · goals minus xG (over/underperformance, both directions) · rolling 6-match xG trend · xG-implied result vs actual result ("deserved" flags) · xG by half · opponent-adjusted xG

### Other
Possession · pass accuracy · offsides · saves · penalties awarded / scored / missed / conceded · goalkeeper distribution · substitutions made and their minutes · players used · squad rotation index

### Contextual splits (apply to every metric above)
Home / away / overall · last N (3, 5, 6, 10, season, all) · versus opponent table-position bracket (top 6, mid, bottom 6) · versus promoted / relegation-threatened · rest days since last match · fixture congestion (matches in last 14 days) · travel distance · competition (league vs cup) · month · day of week · kickoff time band · referee · H2H (all-time, last 5, at this venue) · manager tenure · key-player availability (where injury data exists)

---

## 7. The streak engine

### Primitives
For any predicate `P` and any team:
- **Run** — consecutive matches where `P` held; report current run and longest historical run.
- **Drought** — consecutive matches where `P` failed.
- **Rate** — `X of last N` for N ∈ {3, 5, 6, 10, 20, season}.
- **Trend** — rolling mean of a numeric metric vs the team's season baseline (direction + magnitude).
- **Alternation** — patterns like win/loss alternation, or over/under alternation.
- **Fixture-level composite** — home-team streak ∧ away-team streak ∧ H2H pattern ∧ referee profile.

### Notability scoring — the part competitors skip
A raw streak is not information. For each candidate streak compute:
- the team's **underlying rate** for that predicate over a longer window,
- the **league baseline rate** for that predicate,
- a **binomial p-value / Wilson interval** for the run against that baseline.

Then rank by rarity, and always display the streak *next to* its underlying rate. A 7-match over 2.5 run built on 1.9 average xG is flagged as **regression risk**, not as a signal. This is the honesty layer that makes the product trustworthy — and it is a genuine differentiator over green/red tile sites.

### Nightly job
1. Refresh `team_match_facts` for finished fixtures.
2. Recompute `league_baselines`.
3. Scan all predicates × all teams → upsert `streaks` (predicate, team, type, length, underlying_rate, baseline_rate, p_value, notability_score).
4. Join `streaks` to today's and tomorrow's fixtures → materialise `fixture_highlights`.
5. Fire alerts for user-saved queries whose match set changed.

---

## 8. The screener

The feature that delivers "so much ease". A filter DSL over the fact tables, exposed as a builder UI.

**Composition:** subject (home team / away team / either / match) → metric → window → comparator → value. Clauses join with AND / OR / NOT.

**Example query:** `home.corners_for.last6.avg >= 6.5 AND away.corners_against.last6.avg >= 6.0 AND league.corner_baseline >= 10 AND h2h.last3.total_corners.avg >= 10`

**On every query, always return four things:**
1. Today's / this week's fixtures matching the filter.
2. Historical hit rate of the implied bet, with sample size.
3. Wilson 95% confidence interval on that hit rate.
4. Break-even price required, and whether current market odds clear it.

**Supporting features:** save a query · name it · get alerts when new fixtures match · share a query by link · fork someone else's · a library of prebuilt screens (corner pressure, card-heavy referees, late-goal teams, first-half specialists, xG overperformers due regression).

**Guardrail:** every saved query is scored for multiple-comparisons risk. If a user has tested 40 variants, say so.

---

## 9. Booking-code subsystem

### 9.1 Pipeline
```
code + bookmaker
   → parse       (vendor API response, or manual/OCR entry)
   → normalise   (bookmaker market string → canonical market_id)
   → resolve     (bookmaker fixture string → canonical fixture_id)
   → persist     (slip + legs)
   → settle      (canonical market_id + match facts → won / lost / void)
   → review      (why each leg failed, with xG and stat context)
```

### 9.2 The two hard parts (and they are your moat, not the converter)

**Market normalisation.** Every bookmaker names markets differently — "GG", "BTTS", "Both Teams To Score", "Goal/Goal". Build a `market_map` table: (bookmaker, raw_string) → canonical_market_id + parameters. Seed it from real slips; grow it with a review queue for unmatched strings. Treat it as a curated asset.

**Fixture resolution.** "Man Utd" vs "Manchester United" vs "Man United FC". Pipeline: exact alias hit → normalised-string hit → fuzzy match (token-set ratio) constrained by kickoff date window and competition → confidence score. Above threshold auto-accept; below it, human review queue that feeds back into `team_aliases`. Expect ~95% auto-resolution once seeded.

### 9.3 Settlement engine
Pure, deterministic, exhaustively unit-tested: `settle(canonical_market_id, params, match_facts) → WON | LOST | VOID | PENDING`. One test case per market per edge case (postponed, abandoned, extra time, penalty shootout, Asian handicap quarter-lines, void on late team change). This is where correctness bugs destroy trust — a wrong settlement is worse than no feature.

### 9.4 The "did it pan out" feature
Load a code → settle every leg → show:
- leg-by-leg outcome with the final scoreline,
- **which single leg killed the slip**,
- post-hoc context: was the failed leg unlucky (xG said otherwise) or badly reasoned?
- the user's rolling record by market type, league and stake size,
- closing-line-value where odds data exists — the only honest long-run skill metric.

This history feature is a genuine retention engine. Bettors have no good record-keeping tool.

### 9.5 Conversion — buy, don't build
Bookmakers publish no public booking-code API. Working converters (Betpaddi, convertbetcodes, Betloy, and similar) either hold commercial arrangements or drive private endpoints. Integrate one behind an adapter interface, with a second vendor as failover.

```
POST https://betpaddi.com/api/v1/conversion/convert-code
GET  https://convertbetcodes.com/api/conversion?from=...&to=...&booking_code=...&api_key=...
```

Wrap both behind your own `ConversionProvider` interface so a vendor outage or price change is a config change. Cache conversions by (from, to, code). Never let conversion sit on the critical path of the stats product.

**Do not** attempt to reverse-engineer bookmaker endpoints yourself: it is against every bookmaker's terms of service, exposes you to CFAA-style unauthorised-access claims in some jurisdictions, and breaks constantly against JS-heavy frontends, CAPTCHAs, rate limits and bot fingerprinting. The engineering cost is permanent and the legal exposure is asymmetric.

---

## 10. Architecture & stack

| Layer | Choice | Rationale |
|---|---|---|
| Language | Python 3.12 (FastAPI) | Data ecosystem; the same language ingests, derives and models |
| Primary store | PostgreSQL 16 | Canonical + derived tables; partition `fixtures` and `team_match_facts` by season |
| Analytical scans | DuckDB over Parquet exports (add at Phase 3 if needed) | Fast screener scans without a second server |
| Cache / queue | Redis | Screener result cache, rate-limit tokens, Celery broker |
| Orchestration | Prefect (or plain cron + Celery beat to start) | Ingestion DAGs with retries, backfill and observability |
| Web | Next.js (App Router) + TanStack Query | SEO on team/league pages drives free acquisition |
| Mobile | Expo / React Native, sharing the API | Mobile-first market; ship a PWA first, native second |
| Charts | Recharts or visx | Timeline, xG race, streak strips |
| Auth | Clerk or Supabase Auth | Do not build auth |
| Payments | Paystack / Flutterwave (Africa) + Stripe (international) | Local rails matter for conversion |
| Infra | Single Hetzner/Contabo VPS + managed Postgres, Docker Compose | ~$60/mo. Kubernetes is not warranted before real traffic |
| Observability | Sentry + Grafana/Prometheus + a data-freshness dashboard | The freshness dashboard is the one that matters |

**Low-bandwidth is a feature, not a nice-to-have.** Target sub-150KB initial payload, aggressive caching, offline-readable last-fetched state, and a data-saver mode. The core audience is on metered mobile data.

### Ingestion design notes
- Idempotent upserts keyed on `(vendor, vendor_id)`; ingestion must be safely re-runnable.
- Store the **raw vendor payload** in a `raw_responses` table before parsing. When you find a derivation bug two months in, you reprocess instead of re-buying.
- Poll live fixtures at 1 call/minute; finished fixtures once, then a re-check at +2h for stat corrections (vendors amend).
- A `data_quality` job asserts invariants nightly: shots ≥ shots on target, HT goals ≤ FT goals, event minutes reconcile with the scoreline, corner counts present where the coverage flag claims them.

---

## 11. Roadmap

### Phase 0 — Data validation spike (2 weeks) — *gate*
Buy one month of API-Football and FootyStats. Pull 3 seasons for 25 leagues spanning tier-1 to obscure. Measure per-league, per-field completeness for: corners, cards, half splits, shot detail, xG, goal minutes. Assemble a sample of 50 real booking slips and check every fixture is resolvable.
**Exit criteria:** ≥90% field completeness on your target 30 leagues for goals/corners/cards/timing; ≥60% for xG. **If not met, change league scope or provider before proceeding.**

### Phase 1 — Ingestion & canonical store (5–6 weeks)
Schema, migrations, vendor adapters, raw-payload archive, 5-season backfill, live poller, data-quality assertions, freshness dashboard.
**Deliverable:** a database that is correct and current, with no UI.

### Phase 2 — Derivation & streak engine (4 weeks)
`team_match_facts` + `match_facts` + `league_baselines` materialisers. Full predicate library. Nightly streak scan with notability scoring. Backfilled and reconciled against a hand-checked sample of 200 matches.

### Phase 3 — Read surfaces (4–5 weeks)
Team page, league page, fixture preview page (the money page: both teams' streaks, H2H, timing profiles, corner/card baselines, referee). Today's board with `fixture_highlights`. SEO-indexable.

### Phase 4 — Screener & backtest (4 weeks)
Filter DSL, builder UI, saved queries, alerts, prebuilt screens, hit-rate + confidence-interval reporting, break-even calculation. Odds feed integrated.

### Phase 5 — Slip tracker & settlement (3–4 weeks)
Market map, fixture resolver, review queue, settlement engine with exhaustive tests, slip history, per-market performance, failure post-mortems.

### Phase 6 — Conversion utility (1–2 weeks)
Vendor adapter, failover, caching, UI. Deliberately last — it is a retention hook, not the product.

### Phase 7 — Monetisation & model layer (ongoing)
Free tier (limited leagues, delayed data, 3 saved queries) → paid tier (all leagues, live data, unlimited queries, alerts, API access). Then calibrated probability models — only after the fact warehouse has proven itself, and only ever presented as probabilities with intervals.

**Realistic timeline:** ~6–7 months solo at a sustained pace; ~3.5–4 months with two engineers plus a part-time designer.

---

## 12. Cost model (monthly, early stage)

| Item | Cost |
|---|---|
| API-Football Pro | ~$25 |
| FootyStats API | ~$30–60 (credit-based) |
| Odds feed | ~$30–100 depending on call volume |
| VPS + managed Postgres + backups | ~$60–90 |
| Sentry, transactional email, monitoring | ~$25 |
| Conversion vendor | usage-based, pass through or absorb |
| **Total pre-revenue** | **~$170–300** |

Scaling to Sportmonks Pro (€249) and a larger DB moves this to roughly $600–900/mo — a decision to make on evidence of paying demand, not ambition.

---

## 13. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Coverage gaps on the leagues users actually bet | **Critical** | Phase 0 gate. Show coverage badges per league in-product rather than silently rendering empty tables |
| Vendor changes schema, pricing or shuts down | High | Adapter pattern, raw-payload archive, two-vendor cross-validation from day one |
| Converter vendor dependency | Medium | Second vendor behind the same interface; feature is isolated and degradable |
| Settlement bugs destroy trust | High | Pure function, exhaustive per-market test matrix, shadow-settle against known results before launch |
| Statistical over-claiming / cherry-picking | High | Base-rate scoring, confidence intervals, multiple-comparisons warnings, no "sure bet" language anywhere |
| App-store gambling policy | Medium | Ship a PWA first. Native stores require licensing for real-money gambling; a stats/analysis tool that neither takes stakes nor links to unlicensed operators is generally acceptable, but geo-restrict, age-gate, and get the listing reviewed |
| Advertising / gambling-marketing regulation | Medium | Jurisdiction-specific: age gating, responsible-gambling links, no guaranteed-return claims. Take local legal advice before paid marketing |
| Scraping-based enrichment (Understat etc.) | Medium | Keep it optional and out of the critical path; review each source's terms; do not resell scraped data |
| Compute cost of full predicate scans | Low-medium | Materialise nightly rather than at request time; partition by season; cache screener results in Redis |

---

## 14. Responsible design (also good product)

- Never present a streak without its base rate and sample size.
- Never use "guaranteed", "sure", "banker" or "fixed" in copy.
- Show break-even price alongside every hit rate, so the margin is visible.
- Give every user their honest running record, including losses.
- Ship deposit-free: you are a data tool, not an operator.
- Age gate, geo-restrict, and link a responsible-gambling resource on every page that shows a market.

---

## 15. Definition of done for v1

- [ ] 30+ leagues ingested with ≥90% completeness on goals, corners, cards, timing
- [ ] 5 seasons backfilled and reconciled against a hand-checked sample
- [ ] `team_match_facts` covering every metric family in §6
- [ ] Nightly streak scan with notability scoring, running under 15 minutes
- [ ] Fixture preview page for every upcoming fixture
- [ ] Screener with ≥40 predicates, saved queries and alerts
- [ ] Backtest returning hit rate + interval + break-even on every query
- [ ] Settlement engine passing a per-market edge-case test matrix
- [ ] Slip load, settle and post-mortem working end to end on 50 real codes
- [ ] Conversion behind an adapter with one failover vendor
- [ ] Data-freshness dashboard and alerting
- [ ] Sub-150KB initial payload, data-saver mode

---

## 16. Immediate next actions

1. Buy one month of API-Football and FootyStats; run the Phase 0 coverage audit.
2. Collect 50 real booking codes across the bookmakers you intend to support; use them to seed the market map and alias table.
3. Fix the target league list from the coverage audit, not from ambition.
4. Write the canonical schema migration and the `team_match_facts` column list before any UI work.
5. Register with one conversion vendor and confirm bookmaker coverage matches your audience.

---

## Sources

- BTFStats — https://www.btfstats.com/ · league stats, team streaks
- FootyStats — https://footystats.org/ · API: https://footystats.org/api
- API-Football documentation — https://www.api-football.com/documentation-v3
- Sportmonks pricing — https://www.sportmonks.com/football-api/plans-pricing/
- Football API comparisons — https://www.thestatsapi.com/blog/best-football-api
- Betpaddi developer API — https://betpaddi.com/developers
- ConvertBetCodes API — https://documenter.getpostman.com/view/8286091/UVXonE6K
- Building a Bet Code Converter App — https://dev.to/betpaddi/building-a-bet-code-converter-app-a-complete-guide-55ic
- Free football data sources — https://originalxg.com/blog/free-football-data-sources/
- Google Play gambling policy changes — https://crustlab.com/blog/google-allows-gambling-apps-in-multiple-countries/
