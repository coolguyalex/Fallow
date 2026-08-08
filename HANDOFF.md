# Fallow — Project Handoff

Everything settled so far, and why. Written so a fresh conversation can pick
up without re-litigating decisions already made.

**Status:** climate engine complete and validated. No plants yet.
**Platform:** Playdate. **Language:** Lua.
**Working title:** Fallow — land deliberately left uncultivated, resting
rather than neglected. Was "GardenMeditation". ("Windblown" was the better
instinct but is taken and trademarked by Motion Twin.)

---

## 1. What the game is

A simulation of an abandoned New England field undergoing ecological
succession. Seeds blow in, take root, and grow over time. Insects arrive once
there is plant life; birds follow insects and drop berry seeds; some species
only establish in particular conditions. The field slowly changes while the
player mostly watches.

Reference points: Viva Piñata, Viridi. The register is quiet meditation with
simulated nature, not management.

**The defining mechanic:** the crank advances time, but never past the real
clock. Every session, you crank from where you left off up to now. Play once a
month and you crank through a month of weather, seed dispersal and visits.

**Crucially, this is not playback.** It is rendering on demand. The field's
state at any moment is a deterministic function of `(fieldSeed, timestamp)`.
There is no background simulation and no saved world state, so a year of
absence costs nothing at runtime.

### The player can

- Watch. This is the primary verb and the game should reward it.
- Collect wind-blown seeds.
- Uproot plants.
- Bank specimens.

### The player cannot

- Obtain seeds by any means other than what arrives.
- Control weather or conditions.
- Rewind. **Any intervention locks that timeline branch permanently.**

That last rule is the source of all the game's tension. Every intervention is
a bet placed without seeing the rest of the timeline: uproot the thistle in
week two, or crank on and discover whether it crowded out the harebell? By the
time you know, it is too late to have acted. Stakes without a fail state.

Mechanically this means intervening must **re-roll the forward timeline from
that point** — a new branch seeded from the intervention — not merely edit the
frame currently on screen.

---

## 2. Design decisions settled

### Real species, with a strange tail — SETTLED

Real New England natives, roughly 95%, with the rare tail drifting toward
folklore. Reasoning: real succession is *already designed*, and the dependency
graph is load-bearing rather than decorative — little bluestem and goldenrod
first, then dogbane and milkweed bringing monarchs, then eastern red cedar and
gray birch as the field closes, then oak-hickory if disturbance stops. Every
rule is documented somewhere.

The payoff no invented bestiary can match: the player walks outside and
recognises a plant. A game about attention to nature that trains attention to
actual nature is doing something rare.

The cost is legibility — at 400×240 in 1-bit, half the asters are the same
fuzzy dot cluster. Solve it illustratively, not photographically: Victorian
botanical plate, exaggerate diagnostic features, draw the plant the way a
field guide draws it rather than the way it looks. This suits the scrapbook
framing anyway.

Mundane baseline is what makes the strange thing land. A field where anything
might happen is not eerie, just noisy.

### Progression is a catalogue — SETTLED

Beyond succession itself, the only progression is filling the catalogue.
Scrapbook / natural history collection: seeds, leaves, flowers, and photos of
organisms.

### Uprooting is disturbance management — PROPOSED, not explicitly confirmed

Real abandoned fields do not stay fields. Succession runs meadow → scrub →
woodland and stops. If plants only accumulate, the game has an ending it
probably does not want.

But meadows persist in reality *only because something disturbs them* —
grazing, fire, mowing, flooding. So reframe the uproot verb as disturbance
management: the player is not curating a garden, they are holding the field in
an early successional state against its will. Stop playing for two years and
return to bramble and birch saplings. A real consequence for absence that is
not a punishment.

### Photography, and what it does for the crank — PROPOSED, partially adopted

Person liked the photography idea. The proposal it came attached to:

Crank fast to skim months, slow to inspect, and **photography only works when
time is nearly stopped.** This gives slow cranking a purpose beyond precision
uprooting and makes the crank one coherent verb. It also solves the gearing
problem below.

The clean split: **you photograph animals, you collect plants.** Specimens are
destructive — pressing a flower means picking it, and that individual is gone
from the field. Animals you can only wait for. Two catalogue halves with
opposite moral weights, and the animal half inherits the no-rewind rule
beautifully: miss the bluebird at the cedar and that moment is gone from this
timeline forever.

---

## 3. Open questions

**What the seed bank is actually for.** Unresolved, and worth nailing down
early because it is the only thing that accumulates. If banked seeds can be
replanted, direct control has been quietly reintroduced and the "you cannot
obtain seeds" premise softens. If they cannot, they need another job —
herbarium/catalogue, or insurance that carries across fields when one succeeds
into woodland and you begin another. The second reading gives a long-arc
structure without bolting on a progression system.

**Crank gearing across different absences.** A month and a year need different
gearing, but scaling gearing to the gap collapses intervention granularity —
you cannot precisely uproot something in week three of a year-long crank.
Options: fixed gearing with a "settle to summary" past roughly two months, or
player-controlled variable gearing with intervention gated below a speed
threshold. The second is more crank-y and makes *finding* the moment part of
the play.

**Whether watching is actually pleasant.** The thing most worth prototyping is
not ecology — it is ten minutes of cranking through two weeks of not much
happening, to find out whether observation at 1-bit holds attention. The whole
game stands or falls there.

**First plant.** Suggested: common mullein (*Verbascum thapsus*). It is a
biennial — year one a flat ground rosette, year two a two-metre spike that
flowers, seeds and dies. You cannot see its life without cranking through a
winter, so it *requires* the core mechanic to be understood rather than merely
decorating it. Classic Rhode Island old-field pioneer, unmistakable in 1-bit
silhouette (rosette vs spike), simple enough to grow from rules.

Also open: whether to define the general plant-architecture rule format first
and instantiate mullein into it, or build mullein directly and generalise
after.

**Plant growth is procedural, not sprite-staged.** Stated intent: plants grow
by a set of instructions that naturally produces juvenile/growing/elder
states, the way real plants do — not by swapping between authored sprites.

---

## 4. Architecture — the three load-bearing rules

### Everything is a function of the clock

There is one piece of state: elapsed game time. The sun's position, the
weather, the calendar, the light level — all recomputed every frame from that
single number and thrown away. Nothing is animated. Nothing is stored.

### Growth accumulates, so the day is the atomic unit

Growth is the first thing that cannot be evaluated in closed form — a plant's
size on day 300 depends on every day it lived through. The resolution:

Weather for day N is a **pure function of `(fieldSeed, N)`** with no continuity
between days. Evaluating any timestamp then means looping N cheap iterations.
Ten years of absence is 3,650 iterations over a few dozen plants — nothing on a
168MHz chip. Determinism and accumulation, at the cost of a loop nobody will
notice.

`accumulateGDD` in `main.lua` is the reference implementation of this pattern:
cache the answer, add one term when stepping a single day forward, walk the
full range only on a jump or a year boundary. Every plant should copy it.

### Store events, not state

Do not save "the field currently looks like this." Save the seed plus a sparse
list of interventions — uprooted X on day 88, collected Y on day 141. The field
is always *replayed* from seed with interventions applied as branch points.

Handful of kilobytes for a decade of play; makes the no-undo rule structural
rather than enforced; and a bug in the growth code cannot corrupt a save.

---

## 5. Current implementation

```
Fallow/
├── README.md          build + sideload instructions
├── BACKLOG.md         feature list, live document
├── HANDOFF.md         this file
└── Source/
    ├── main.lua       scene, UI, crank→clock, GDD accumulator
    ├── climate.lua    the climate model
    └── pdxinfo        metadata (no file extension — Windows will try to add .txt)
```

Build from the folder *containing* `Source`:

```
pdc Source Fallow.pdx
```

`pdc`'s first argument is whatever folder holds `main.lua`. `Source` is only
convention.

### What runs today

- Crank drives a clock. `MINUTES_PER_REVOLUTION` (currently 240, so a day is
  six turns) is **the single most important feel parameter.** Tune it first
  and often. Clamped so time cannot go before day one.
- Sun and moon on arcs, rising and setting behind the horizon (draw order is
  the only depth system).
- Hard day/night flip via `playdate.display.setInverted()` — a free
  hardware-level inversion of every pixel, so one set of drawing code yields
  both.
- Rain and snow, falling at the right time of day, hiding the sun and stars.
- Readout panel: year / season / day-of-season, 24h clock, temperature with
  daily high and low, sky state, accumulated GDD, daylight hours, solar
  elevation, and a brightness bar.

### Language choice

Lua, not C. The compute load is trivial — a few hundred plant records, no 3D,
no per-pixel work — and the crank-as-time trick means frames are *computed*,
not continuously simulated. Lua gives the sprite system, image tables and
`playdate.datastore` with no CMake, no ARM toolchain. If some inner loop
proves slow, that one function can drop to C without rewriting the game.

Note: Playdate's Lua is 5.4 with `+=`, `-=` etc. added. `<const>` works.

---

## 6. The climate model

Fitted to Providence, Rhode Island. NOAA 1991–2020 normals, cross-checked
against climate-data.org (annual mean 10.6 °C, 1151 mm precipitation).

### Seasonal temperature

A least-squares Fourier fit to the twelve monthly means. **One harmonic is
enough** — a second carried 0.27 °C of amplitude and improved the worst-month
residual only from 0.49 to 0.41 °C. Providence's annual cycle is very nearly a
pure sinusoid.

```
T(d) = 10.95 − 11.96 · cos(2π(d − 21) / 365)
```

Coldest day January 22, warmest July 26. The seasonal lag emerges from the fit
rather than being imposed.

### Daily variability — the noise

Anomalies about the seasonal curve are generated by **five octaves of value
noise at 20, 10, 5, 2.5 and 1.0 day periods, with equal weight.**

Equal weight per octave is the definition of pink noise, and it was *solved
for*, not guessed. Sweeping a weight exponent against a target lag-1
autocorrelation of 0.70 (the real figure for daily temperature anomalies at
this latitude) landed on equal weighting, measuring 0.71.

Why it works, without needing Fourier theory: a slow wiggle physically cannot
change much in a day, because it needs its whole period to complete a swing.
So each band has its own stickiness set by its speed —

| Period | Its own lag-1 | What it is |
|---|---|---|
| 20 days | 0.996 | a month-long regime |
| 10 days | 0.985 | a spell |
| 5 days | 0.943 | one weather system passing |
| 2.5 days | 0.790 | the front arriving and leaving |
| 1 day | 0.063 | all sub-daily physics we don't model |

The sum's lag-1 is the **variance-weighted average** of that column: predicted
0.7141, measured 0.7167. There is no memory mechanism anywhere in the code.
Four sticky signals mixed with one non-sticky one produced the memory.

**Do not remove the 1.0-day octave.** Sampled at integer days it degenerates
to pure white noise and supplies all the short-term jitter. Without it lag-1
climbs past 0.9 and every day feels like the one before.

Mechanically each band is: sample-and-hold clocked at the band's period,
feeding a **constant-time** eased glide — not a slew limiter. Every transition
takes exactly one period regardless of distance, and the slope varies. The
easing curve is smoothstep (`3t² − 2t³`), which has zero slope at both ends so
consecutive segments join without a corner. Corners are broadband and would
spray energy up into the faster bands, wrecking the octave balance.

This construction is essentially the **Voss–McCartney pink noise algorithm**
from audio, clocked at one sample per day.

### Other constants

- Daily SD: 4.3 ± 1.3 °C, larger in winter (vigorous synoptic activity).
- Diurnal range: 9.2 °C, near-constant — the ocean moderates it.
- Precipitation: 34% of days wet ±4% seasonal, mean 9.4 mm per wet day.
  Whether it rains comes off a *smooth* channel so wet spells cluster; how hard
  comes off a *white* channel inverse-transformed to an exponential.
- Snow below 1 °C mean, at a 10:1 depth ratio.
- Latitude 41.82 °N. GDD base 5 °C (suits a temperate meadow; base 10 is the
  crop-science default and would under-count spring).
- Calendar: game day 0 is **March 1**, so play begins in spring. Meteorological
  seasons, 92/92/91/90 days.

### Validation results

| | Providence | Model |
|---|---|---|
| Annual mean | 10.6–10.9 °C | 10.95 |
| Worst monthly error | — | 0.80 °C |
| Daily scatter, winter | ~5.5 °C | 5.36 |
| Daily scatter, summer | ~3.0 °C | 3.06 |
| Wet days/year | ~123 | 125 |
| Rainfall | 1151 mm | 1183 |
| Solstice daylight | 15h 15m | 15h 03m |

Determinism verified: day 1234 queried before and after arbitrary other days
returns bit-identical values. Series does not repeat at 512, 5120 or 10240 days.

### Bugs found during development — worth not repeating

1. **Permutation table was not zero-mean.** Filling it with `math.random`
   leaves a residual offset that appears as a systematic ±0.9 °C bias in every
   month — and *widening the table made it worse*, because it is a lottery, not
   a convergence. Fixed by building an exact ramp from −1 to +1 and shuffling
   it (Fisher-Yates). Mean is zero by construction, whatever the seed.
2. **Game day 0 is March 1 but the model read it as January 1.** The seasonal
   curve was 59 days out of phase with the on-screen calendar. Silent, and it
   would have poisoned every growth number downstream.
3. Noise variance was off by 2.4×, which cascaded into precipitation running
   at a fifth of the real annual total.

Both (1) and (2) were caught by writing prose explaining what the code was
meant to do. Prose is a type checker for intent — an argument for the white
paper in the backlog.

---

## 7. Working practices

- **Validate against real statistics, not vibes.** The validation harness lives
  in the repo. Numbers in any document should be generated by it, not typed.
- **Solve for constants numerically where possible.** The octave weights, the
  precipitation cutoff and the noise normalisation were all measured, not
  chosen.
- Add `*.pdx` to `.gitignore` — the build output is a folder of generated files.
- The backlog is a live document. Nothing in it is scheduled.

---

## 8. Immediate next step

The first plant. It has GDD, daylight, temperature, precipitation and
brightness already waiting for it.

Before writing growth code, settle: general plant-architecture rule format
first, or build mullein directly and generalise afterwards?

Also worth building alongside the first plant, not after: a determinism
harness asserting that the same `(fieldSeed, timestamp)` always renders the
same field.
