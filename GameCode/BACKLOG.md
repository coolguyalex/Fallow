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

**8. Twilight band.** The invert currently cuts hard at 06:00/18:00. Dither
the sky through a few density steps over ~20 min either side. Also the natural
place to learn `setDitherPattern`.

## Systems (not yet designed)

**9. ~~Seasons / climate.~~ DONE (step 3).** See `climate.lua`. Fitted to
Providence normals; validated against monthly means, daily standard
deviation, wet-day count and annual rainfall.
**10. Procedural plant growth.** Instruction-driven, not sprite-stage-driven.
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

**12. Wind.** Speed and direction. Direction wants its own slow noise
channel; speed correlates with the temperature-anomaly channel in reality
(fronts bring both). Drives seed dispersal, so it is not merely decorative —
this is the mechanism that stocks the field.

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
