# Fallow — Backlog

Running list. Nothing here is scheduled; it's a place to put things so they
stop taking up head space.

---

## Sky & time

**1. ~~Hollow sun.~~ DONE (step 3).** Outline circle, unfilled centre. `drawCircleAtPoint`
instead of `fillCircleAtPoint`. Note that under night inversion an outlined
shape reads very differently from a filled one — check both.

**2a. Seasonal solar arc.** The sun currently traces the same arc all year.
It should ride low in winter and high in summer. Nearly free: the correct
elevation is ALREADY computed by `Climate.solarElevation` for the brightness
model. Feed real elevation into the arc drawing instead of the fixed
`ARC_PEAK_Y` and it is done. Providence noon elevation runs 26 degrees in
December against 70 in June.

**2b. Seasonal lunar arc.** Also nearly free, via one fact: a full moon sits
opposite the sun, so its declination is roughly the NEGATIVE of the sun's.
Winter full moons therefore ride high; summer full moons skulk along the
horizon. Real, correct, and worth discovering by cranking. General case:
declination = 23.4 deg * sin over the 27.3-day sidereal month.

**2. Independent lunar cycle.** The moon should run on its own period, not
locked to the sun's opposite. Consequences: daytime moons, moonless nights,
moonrise at odd hours. A synodic month of ~29.5 days against a 24h solar day
gives the drift for free — the moon rises ~50 min later each day (24h / 29.5).

Phase and rise time are the SAME quantity, so one number drives both:
new moon rises at sunrise, first quarter at noon, full moon exactly at sunset.
Never model them separately.

**3. Moon phases.** Illuminated fraction from position in the synodic cycle.
Currently drawn as a fixed crescent by punching an offset disc out of a filled
one — sliding that offset disc from full-overlap to no-overlap walks the whole
phase sequence, so the drawing code is nearly there already.

**4. ~~Lower horizon.~~ DONE (step 3) — now y=190. Lower still if wanted.** More sky, less ground.

**5. ~~24-hour clock.~~ DONE (step 3).** Drop the AM/PM formatting.

**6. ~~Calendar.~~ DONE (step 3).** "Day 1 of Spring, Year 2" — Stardew-style. Needs a season
length decision (real 91-day seasons are probably too long; Stardew uses 28).

**7. Lighting from celestial bodies.** ← the interesting one.

Days always look the same. Nights vary with moon phase, and the two things
that vary are *inversely coupled*:

| Moon      | Sky    | Stars      | Plants                          |
|-----------|--------|------------|---------------------------------|
| Full      | black  | none       | fully visible                   |
| New       | black  | bright     | invisible except as star-blotter|

At new moon the garden is defined by **negative space** — you read the plants
by the stars they occlude. This is the strongest visual idea in the project so
far and it is only possible on a 1-bit screen. Worth protecting: it means
plant silhouettes need to be solid, readable shapes at every growth stage, not
just wireframes.

**7b. Rotating stars.** The field currently has a fixed star field. It should
wheel about Polaris, which at this latitude sits 41.8 degrees above the
northern horizon — so stars near it circle tightly and never set, while stars
low in the south rise and set like the sun.

Rotation is 15 degrees per hour, which is just the same hour-angle term
already used for solar elevation. Give each star a fixed declination and right
ascension, rotate by hour angle, project. One matrix, no new theory.

The detail worth having: a sidereal day is 23h 56m, not 24h, so the stars
rise about 4 minutes earlier each day and the whole sky drifts a full extra
turn over a year. Same family of fact as the moon's 50 minutes. It means the
winter constellations genuinely differ from the summer ones, for free — and
since the catalogue is the progression spine, a sky that changes across the
year is worth having.

## Rendering

**8. ~~Twilight band.~~ DONE (step 5).** `playdate.display.setInverted()` is
gone entirely — a hard flip cannot be eased, because it is instantaneous by
nature. The sky is now a dithered fill (8x8 Bayer, 13 steps) whose density
follows the sun's ALTITUDE, ramping from +2 deg to -12 deg. That takes about
an hour of real dusk, and it varies correctly by season.

Two things fell out. Ink polarity switches at darkness 0.5, which is the least
visible moment to switch because a 50% dither inverts to another 50% dither.
And the ground now dithers against actual incident light, so a full moon shows
you the field and a new moon nearly hides it — half of backlog item 7 arrived
for free.

## Systems (not yet designed)

**9. ~~Seasons / climate.~~ DONE (step 3).** See `climate.lua`. Fitted to
Providence normals; validated against monthly means, daily standard
deviation, wet-day count and annual rainfall.
**10. Procedural plant growth — FIRST PLANT IN (step 6).** `mullein.lua`.
Growth is instruction-driven: leaf count, rosette spread and spike height are
numbers accumulated from real climate, and the shape is derived from them.
Validated life cycle: germinates mid-April, 42cm rosette by August, overwinters
taking 114 chill days, bolts mid-May of year two, flowers through summer, dead
by August. 499 days.

STILL OPEN: the leaf silhouette needs judging on the actual 1-bit screen at
actual size. The geometry is renderer-agnostic (`Mullein.geometry` returns
polygons in centimetres) precisely so this can be iterated without touching the
biology.

**10b. Species considerations, deferred deliberately.**

*Dispersal.* Mullein is not classically wind-dispersed — the capsule shakes
tiny seeds out within a few metres. Long-distance arrival is via soil and
disturbance. It sits in the WEST (city) pool in `wind.lua` as a Eurasian
ruderal, which is honest.

*Seed viability.* Mullein's is extraordinary: decades in soil, up to a century
documented. Should be a per-species parameter with an enormous range (willow is
days). This is the mechanism that lets the field REMEMBER a species long after
the last plant died.

*Germination.* Needs bare soil and light. Which means **uprooting summons
mullein** — the disturbance verb does not only suppress, it triggers the seed
bank. That is why real old fields are full of mullein, and it is a feedback loop
worth building deliberately.

*Competition and domination.* Mullein solves this itself: monocarpic (flowers
once and dies), a poor competitor, and dependent on bare ground. Grass closes
in and it vanishes. Prefer species-intrinsic limits like these over a global
density cap wherever possible.

*Overwintering.* Vernalization is a hard requirement — 45 chill days below 5C.
The player physically cannot see this plant's life without cranking through a
winter. Late-germinating rosettes stay under the 9-leaf bolting threshold and
must wait another year.

**10c. Scale, framing, and a bigger field.** The unresolved rendering question.
A 2m spike against a 240px screen forces a decision:

Fixed camera means the field is only ~8m wide, which is small. Scrolling means
a larger field and a reason to explore. A two-view split — wide field view plus
a close specimen view — is probably strongest, and echoes the spyglass/diorama
split that worked for the sailing project.

`main.lua` currently has a crude version: B toggles a specimen bench with one
plant drawn at 1.05 px/cm. That is scaffolding for judging growth, NOT a
proposal for the game's framing. Decide framing after the silhouette is right.
**11. Determinism harness.** A way to assert that the same
`(fieldSeed, timestamp)` always renders the same field. Build this *with* the
first plant, not after.

## Weather, later

**16. Clouds.** Occluding the sun, moon and stars. Wants its own smooth noise
channel for cover fraction, correlated with the precipitation channel but not
identical — most overcast days produce no rain. Feeds directly into
brightness (17), and is the missing term in `Climate.brightness`.

**17. ~~Brightness readout.~~ DONE (step 4).** `Climate.brightness` derives
scene light from true solar elevation, with a perceptual square-root squash so
a January noon reads dimmer than a June one (0.66 vs 0.97) rather than both
pinning at "daytime". Twilight ramp below the horizon, moonlight floor beneath
that, precipitation multiplies it down. Cloud occlusion still to come.

**12. ~~Wind.~~ DONE (step 5).** See `wind.lua`. Weibull-distributed speed
(shape 2, so calm days outnumber windy ones), seasonal prevailing rotation
NW-winter to SW-summer, diurnal afternoon peak, gust factor, and four
neighbour sectors. Validated: 4.79 m/s annual mean against a 4.7 target, wind
rose N 25 / E 14 / S 25 / W 35.

Three couplings to the weather and only three — storms are windy, summer
convective storms are preceded by a gust front, big cold-season storms blow
from the east. Wind deliberately does NOT affect temperature: wind chill is a
perception, not a temperature, and coupling it would break the validated
monthly means for nothing.

**12b. Named extreme events.** Nor'easters, severe convective storms,
hurricanes. Deliberately NOT emergent — extreme events are structurally
different from ordinary weather, not merely bigger, and giving the noise a fat
tail enough to produce hurricanes yields either one every other August or
never one at all.

So: a sparse event layer over the continuous model, seasonally gated, each with
an authored profile. Nor'easter Oct-Apr, multi-day, E/NE gale, a few a year.
Severe convective Jun-Aug, brief and violent, several a summer. Hurricane
Aug-Oct and RARE — Rhode Island gets a memorable one every 10-20 years (1938,
Carol, Bob, Irene, Sandy). Most playthroughs should never see one.

Build this only after the ordinary weather's statistics are locked, so a bug
here cannot quietly corrupt the everyday numbers.

The design payoff: a hurricane is a massive disturbance event that flattens
saplings and knocks the field back toward early succession. The rare
catastrophe does for free what the player has been doing by hand for years.
The disturbance regime should not be the player alone.

**12c. The four neighbours as a seed geography.** Defined in
`wind.lua` as `Wind.SECTORS`, awaiting a dispersal system.

North is forest — maple, birch, pine, cedar — the seeds that END the meadow.
East is Rehoboth farmland — bluestem, goldenrod, milkweed, asters — the pool
that holds early succession. West is the city — mugwort, knotweed,
tree-of-heaven — invasives and degradation. South is the bay, and barely a seed
source at all: moisture, fog, gulls. That asymmetry is deliberate and stops it
reading as a symmetric four-way dial.

The pressure this creates was not designed, it falls out of real meteorology:
**easterlies are the rare wind here.** The field's default drift is forest seed
and city weeds, and the wind that reinforces the meadow is uncommon — and
arrives attached to the worst storm of the year, since east is also the
nor'easter quadrant. Uprooting is the counterweight, exactly as the
disturbance-management framing intended.

**13. Lightning.** Summer convective storms only. Gate on high temperature
AND heavy precipitation, which the model already gives for free. Full-screen
inversion flash is one line and will look extraordinary on this display.

**14. Fire.** Follows from 13. Also the ecologically correct disturbance for
holding a meadow in early succession — the counterweight to uprooting.
Needs a dryness accumulator: days since meaningful rain.

## Creatures

**18. Puckwudgies.** Wampanoag folklore, and native to exactly this ground —
southeastern New England. Fits the setting far better than generic fae would.

The design question to settle before implementing: the game is otherwise
strictly naturalistic, so a puckwudgie is a genre shift. The strongest version
is probably that they are never confirmed — glimpsed at the edge of a crank,
gone on the next frame, evidenced only by consequences (a trampled patch, a
seed that could not have blown in). That gives the catalogue a permanently
incomplete entry, which is a better prize than a completed one.

## Sound

**15. Generative soundtrack.** Synthesis-driven, keyed to the same climate
signals — wind speed to filtered noise, temperature to register, precipitation
to density. Deliberately parked until the game proper exists, but worth noting
that the climate model already emits every control signal such a system would
want, and emits them deterministically.

## Documentation

**19. White paper.** A written companion explaining the simulation theory —
the Fourier fit to Providence normals, why equal weight per octave is pink
noise, the Wiener-Khinchin duality that makes spectral shaping and weather
memory the same act, growing degree days, the determinism architecture, and
the validation results.

Worth doing properly and worth shipping with the game. Two arguments for it:
it is genuinely unusual for a game this small to be built on fitted data, and
writing it will catch errors — the calendar phase bug and the non-zero-mean
permutation table were both found by trying to state plainly what the code
was meant to do.

Keep the validation harness in the repo; the tables in the paper should be
generated by it, not typed.

## UI

**20. Naturalist's instruments as an opt-in overlay.** The current readout —
GDD, high/low, solar elevation, light percentage — is dev-facing and stays
that way by default. But it should not simply be deleted at ship: make it a
toggle in an options menu.

Two arguments for keeping it. It suits the fiction — a Victorian naturalist
would absolutely own a thermometer, a rain gauge and an almanac, so the
overlay is in-genre rather than a debug leak. And it gives the simulation
somewhere to be *seen*: a player who wants to know why the mullein bolted
early can look at the growing-degree total and find out.

Do not touch this until the game exists. Noted only so the panels are not
thrown away.

## Known limits

- Noise channels are built on a 512-entry table. Verified not to repeat within
  20 years; the true period is far longer but is not infinite.
- Monthly means run up to 0.8 C off target, which is well inside real
  year-to-year variability. Not worth chasing.
- The equation of time is ignored in the daylight calculation: sunrise and
  sunset can be up to ~15 minutes out from reality.

## Tuning

- `MINUTES_PER_REVOLUTION` — currently 240. The single most important feel
  parameter. Revisit constantly.
- Season length. Currently real: 92/92/91/90 days.
- Synodic month length (real 29.5 vs. something that divides evenly into the
  season).
- `GDD_BASE` in climate.lua, currently 5 C. Base 10 is the crop-science
  default and would roughly halve the season.
