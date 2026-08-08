-- climate.lua
--
-- Providence, Rhode Island, in about two hundred lines.
--
-- Everything here is a PURE FUNCTION of (seed, dayIndex). No state, no
-- accumulation, no memory of yesterday. Ask for day 4,000 cold and you get
-- the same answer you'd get by walking there one day at a time. That
-- property is what lets the whole game be a function of the clock.
--
-- Fitted to NOAA 1991-2020 normals for Providence T.F. Green, cross-checked
-- against climate-data.org (annual mean 10.6 C, 1151 mm precipitation).

Climate = {}

-- ===== Fitted constants =====================================================

-- Least-squares Fourier fit to the twelve monthly means. A second harmonic
-- was tried and discarded: it carried 0.27 C of amplitude and improved the
-- worst-month residual from 0.49 C to 0.41 C. Not worth the multiply.
local T_MEAN      <const> = 10.95   -- annual mean, C
local T_AMPLITUDE <const> = 11.96   -- half the annual swing, C
local T_COLDEST   <const> = 21      -- day-of-year of the minimum (Jan 22)

-- Day-to-day scatter about the seasonal curve. Larger in winter: mid-latitude
-- winters have vigorous synoptic activity, summers are sluggish.
local SD_MEAN <const> = 4.3   -- C
local SD_SWING <const> = 1.3  -- winter is +1.3, summer is -1.3

-- Diurnal range (daily high minus daily low). Near-constant here; the ocean
-- keeps it modest compared with inland New England.
local DIURNAL <const> = 9.2   -- C

-- Precipitation. RI is famously even across the year -- there is no dry
-- season, which is why the seasonal term is so small.
-- Rhode Island has no dry season -- monthly TOTALS are famously flat. But the
-- STRUCTURE is not: winter delivers its rain as frequent light events off the
-- ocean, summer as fewer, heavier convective storms. Same total, different
-- shape. So wet-day frequency peaks in winter while amount-per-wet-day peaks
-- in summer, and the two swings roughly cancel in the monthly figures.
local WET_PROB      <const> = 0.34   -- annual mean fraction of wet days
local WET_PROB_SWING<const> = 0.035  -- +winter / -summer
local WET_MEAN_MM   <const> = 9.4    -- annual mean accumulation on a wet day
local WET_MEAN_SWING<const> = 0.10   -- fractional; summer storms are heavier
local WET_CUTOFF    <const> = 0.4079 -- measured percentile of the wet channel
local CUTOFF_SLOPE  <const> = 2.60   -- d(cutoff)/d(probability), measured
local SNOW_RATIO    <const> = 10.0   -- mm liquid -> mm snow depth

local LATITUDE <const> = 41.82       -- degrees north

-- Growing degree days. Base 5 C suits a temperate meadow; base 10 is for
-- warm-season crops and would under-count your spring.
local GDD_BASE <const> = 5.0

-- Floor brightness on a moonless night. Not zero: starlight alone casts
-- enough for silhouettes, which backlog item 7 depends on entirely.
local STARLIGHT <const> = 0.015

local DAYS_PER_YEAR <const> = 365
local TWO_PI <const> = math.pi * 2

-- ===== Deterministic noise ==================================================

-- A permutation table, Perlin-style. Built once at load from a fixed seed, so
-- it is identical on every launch and on every machine. Using a table rather
-- than an integer hash sidesteps any question about how wide Lua's integers
-- are on this hardware -- no overflow, no platform surprises.
local PERM_SIZE <const> = 512
local perm = {}
do
    -- Build an EXACTLY balanced ramp from -1 to +1, then shuffle it. Filling
    -- the table with random values instead leaves a small residual mean --
    -- which then shows up as a systematic warm or cold bias in every month.
    -- Cost you an hour if you skip it. This way the mean is zero by
    -- construction, whatever the seed.
    for i = 0, PERM_SIZE - 1 do
        perm[i] = (i / (PERM_SIZE - 1)) * 2 - 1
    end
    math.randomseed(0x5EED)
    for i = PERM_SIZE - 1, 1, -1 do          -- Fisher-Yates
        local j = math.random(0, i)
        perm[i], perm[j] = perm[j], perm[i]
    end
end

local function lattice(i, channel)
    -- Channel offsets keep independent signals (temperature, precipitation)
    -- from correlating, and keep octaves of the same signal from aligning.
    return perm[(i + channel * 149) % PERM_SIZE]
end

local function smoothstep(t)
    return t * t * (3 - 2 * t)
end

-- Value noise: smooth, deterministic, O(1) at any day.
local function valueNoise(x, channel)
    local i = math.floor(x)
    local f = smoothstep(x - i)
    local a = lattice(i, channel)
    local b = lattice(i + 1, channel)
    return a + (b - a) * f
end

-- Five octaves, EQUAL weight -- equal energy per octave, which is the
-- definition of pink noise. This was solved for, not guessed: sweeping a
-- weight exponent showed that equal weighting lands at a lag-1
-- autocorrelation of 0.693 against the 0.70 that real daily temperature
-- anomalies show at this latitude. Steeper weighting makes the weather too
-- smooth -- long lazy swings with no day-to-day bite.
--
-- The 1.0-day octave is important: sampled at integer days it IS white
-- noise, and it supplies all the short-term jitter. Drop it and lag-1 climbs
-- past 0.9 and every day feels like the one before.
local OCTAVE_PERIODS <const> = { 20.0, 10.0, 5.0, 2.5, 1.0 }
local NOISE_NORM <const> = 1.1345   -- measured over 200k days; gives unit variance

local function fractalNoise(day, channel)
    local sum = 0
    for k = 1, #OCTAVE_PERIODS do
        sum = sum + valueNoise(day / OCTAVE_PERIODS[k], channel + k * 11)
    end
    return sum / NOISE_NORM
end

-- A flat uniform draw in [0,1) for a given day. Straight off the permutation
-- table with no interpolation, so it is genuinely uniform -- verified.
local function uniform(day, channel)
    return (lattice(day, channel) + 1) * 0.5
end

-- Exposed so other modules (wind, dispersal, plants) share one noise source
-- rather than each rolling their own. Use a distinct channel number per
-- signal; channels are decorrelated by construction.
Climate.fractalNoise = fractalNoise
Climate.uniform = uniform

-- ===== Public model =========================================================

-- Seasonal curve. dayOfYear is 0-based from January 1.
function Climate.seasonalMean(dayOfYear)
    return T_MEAN - T_AMPLITUDE * math.cos(TWO_PI * (dayOfYear - T_COLDEST) / DAYS_PER_YEAR)
end

local function seasonalSD(dayOfYear)
    return SD_MEAN + SD_SWING * math.cos(TWO_PI * (dayOfYear - T_COLDEST) / DAYS_PER_YEAR)
end

-- Hours of daylight, and sunrise/sunset in decimal hours (solar time; the
-- equation of time is ignored, which costs at most about 15 minutes).
function Climate.daylight(dayOfYear)
    local decl = 0.4093 * math.sin(TWO_PI * (dayOfYear - 80.5) / DAYS_PER_YEAR)
    local phi = math.rad(LATITUDE)
    local cosH = -math.tan(phi) * math.tan(decl)
    if cosH > 1 then cosH = 1 elseif cosH < -1 then cosH = -1 end
    local H = math.deg(math.acos(cosH))          -- half-day arc, degrees
    local hours = 2 * H / 15
    return hours, 12 - H / 15, 12 + H / 15       -- length, sunrise, sunset
end

-- The whole day's weather, from the day index alone.
function Climate.day(dayIndex)
    -- Game day 0 is March 1. The seasonal curves are keyed to the CALENDAR
    -- day; the noise is keyed to the absolute day index so weather never
    -- repeats from one year to the next.
    local dayOfYear = Climate.calendarDay(dayIndex)

    local mean = Climate.seasonalMean(dayOfYear)
    local anomaly = fractalNoise(dayIndex, 1) * seasonalSD(dayOfYear)
    local meanTemp = mean + anomaly

    local high = meanTemp + DIURNAL / 2
    local low  = meanTemp - DIURNAL / 2

    -- Precipitation on its own noise channel, so wet spells cluster the same
    -- way warm spells do, but independently of them.
    local pNoise = fractalNoise(dayIndex, 7)
    -- Peaks at the coldest point of the year, same phase as the temperature
    -- minimum, which is why T_COLDEST appears here.
    local seasonal = math.cos(TWO_PI * (dayOfYear - T_COLDEST) / DAYS_PER_YEAR)
    local target = WET_PROB + WET_PROB_SWING * seasonal
    -- WET_CUTOFF is the empirical 66th percentile of this noise channel,
    -- measured over 400k days. CUTOFF_SLOPE converts a change in target
    -- probability into a shift of that threshold.
    local cutoff = WET_CUTOFF - CUTOFF_SLOPE * (target - WET_PROB)
    local wet = pNoise > cutoff

    local precipMM, snowMM = 0, 0
    if wet then
        -- Amount comes off a separate WHITE channel, inverse-transformed to
        -- an exponential. Whether it rains clusters (smooth channel); how
        -- hard it rains does not (white channel). Mean falls out exactly at
        -- WET_MEAN_MM, and the tail reaches ~50 mm, which is a nor'easter.
        local u = uniform(dayIndex, 23)
        local scale = WET_MEAN_MM * (1 - WET_MEAN_SWING * seasonal)
        precipMM = -scale * 1.061 * math.log(1 - u * 0.995)
        if meanTemp < 1.0 then
            snowMM = precipMM * SNOW_RATIO
        end
    end

    local gdd = meanTemp - GDD_BASE
    if gdd < 0 then gdd = 0 end

    local length, sunrise, sunset = Climate.daylight(dayOfYear)

    -- When in the day does it actually fall? Bigger totals last longer.
    local rainStart, rainHours = 0, 0
    if wet then
        rainHours = 2 + precipMM / 3
        if rainHours > 14 then rainHours = 14 end
        rainStart = uniform(dayIndex, 41) * (24 - rainHours)
    end

    return {
        rainStart  = rainStart,
        rainHours  = rainHours,
        dayIndex   = dayIndex,
        dayOfYear  = dayOfYear,
        meanTemp   = meanTemp,
        high       = high,
        low        = low,
        anomaly    = anomaly,
        precipMM   = precipMM,
        snowMM     = snowMM,
        isWet      = wet,
        isSnow     = snowMM > 0,
        gdd        = gdd,
        dayLength  = length,
        sunrise    = sunrise,
        sunset     = sunset,
    }
end

-- Temperature at a moment inside the day. Minimum at sunrise, maximum in the
-- mid-afternoon; two cosine halves stitched together.
function Climate.tempAtHour(w, hour)
    local tMin = w.sunrise
    local tMax = w.sunrise + (w.sunset - w.sunrise) * 0.72
    local amp = (w.high - w.low) / 2
    local mid = (w.high + w.low) / 2

    local h = hour
    if h < tMin then h = h + 24 end     -- pre-dawn belongs to yesterday's fall

    if h <= tMax then
        local t = (h - tMin) / (tMax - tMin)
        return mid - amp * math.cos(math.pi * t)
    else
        local t = (h - tMax) / ((tMin + 24) - tMax)
        return mid + amp * math.cos(math.pi * t)
    end
end

-- ===== Calendar =============================================================
-- Game day 0 is March 1, so play begins in spring. Meteorological seasons.

local SEASONS <const> = {
    { name = "Spring", start =   0, len = 92 },   -- Mar 1
    { name = "Summer", start =  92, len = 92 },   -- Jun 1
    { name = "Autumn", start = 184, len = 91 },   -- Sep 1
    { name = "Winter", start = 275, len = 90 },   -- Dec 1
}

-- Game day 0 == March 1 == day 59 of the calendar year.
function Climate.calendarDay(gameDay)
    return (gameDay + 59) % DAYS_PER_YEAR
end

function Climate.calendar(gameDay)
    local year = math.floor(gameDay / DAYS_PER_YEAR) + 1
    local d = gameDay % DAYS_PER_YEAR
    for i = 1, #SEASONS do
        local s = SEASONS[i]
        if d < s.start + s.len then
            return year, s.name, d - s.start + 1
        end
    end
    return year, "Winter", 90
end

-- Precipitation intensity right now, 0 (dry) to 1 (heaviest). Ramps in and
-- out rather than switching, so weather arrives instead of appearing.
function Climate.precipAtHour(w, hour)
    if not w.isWet then return 0 end
    local t = (hour - w.rainStart) / w.rainHours
    if t < 0 or t > 1 then return 0 end
    local shape = math.sin(t * math.pi)          -- 0 -> 1 -> 0
    local strength = w.precipMM / 20
    if strength > 1 then strength = 1 end
    return shape * (0.35 + 0.65 * strength)
end

-- ===== Light ================================================================

-- Solar elevation above the horizon, in degrees. Negative before sunrise and
-- after sunset. This is the quantity brightness actually depends on -- not
-- the time of day, which is why a January noon is dimmer than a June one.
function Climate.solarElevation(dayOfYear, hour)
    local decl = 0.4093 * math.sin(TWO_PI * (dayOfYear - 80.5) / DAYS_PER_YEAR)
    local phi = math.rad(LATITUDE)
    local H = math.rad(15 * (hour - 12))
    local s = math.sin(phi) * math.sin(decl) + math.cos(phi) * math.cos(decl) * math.cos(H)
    if s > 1 then s = 1 elseif s < -1 then s = -1 end
    return math.deg(math.asin(s))
end

-- Scene brightness, 0 (pitch dark) to 1 (bright noon sun).
--
-- Deliberately NOT linear in illuminance -- real noon is thousands of times
-- brighter than twilight, and a linear scale would make the whole day look
-- identical. The square root is a perceptual squash, the same instinct as
-- putting a fader on a log taper.
--
function Climate.brightness(w, hour)
    local elev = Climate.solarElevation(w.dayOfYear, hour)

    local sky
    if elev > 0 then
        sky = math.sqrt(math.sin(math.rad(elev)))
    elseif elev > -6 then
        sky = 0.15 * (elev + 6) / 6        -- civil twilight
    else
        sky = 0
    end

    -- Real moonlight, from phase and altitude. A full moon riding high is
    -- genuinely enough to walk by; a new moon leaves only starlight.
    local moon = Climate.moonLight(w.dayIndex, hour) + STARLIGHT
    if sky < moon then sky = moon end

    -- Occlusion. Heavy rain takes about three quarters of the light; clouds
    -- will multiply in here too once backlog item 16 exists.
    local occ = 1 - 0.75 * Climate.precipAtHour(w, hour)
    return sky * occ
end

-- ===== The moon ============================================================
--
-- Low-precision but structurally honest. The orbital inclination of 5.1 deg
-- is ignored, which is what makes eclipses impossible here and costs a few
-- degrees of altitude. Everything else is real.

local SYNODIC <const> = 29.53059      -- new moon to new moon, days
local MOON_EPOCH <const> = 0          -- game day of a new moon; tunable

-- Phase as a fraction: 0 and 1 are new, 0.5 is full.
function Climate.moonPhase(dayIndex, hour)
    local t = (dayIndex + (hour or 12) / 24 - MOON_EPOCH) / SYNODIC
    return t - math.floor(t)
end

-- Illuminated fraction of the disc, 0 to 1.
function Climate.moonIllumination(phase)
    return (1 - math.cos(TWO_PI * phase)) / 2
end

local PHASE_NAMES <const> = {
    "new", "waxing crescent", "first quarter", "waxing gibbous",
    "full", "waning gibbous", "last quarter", "waning crescent",
}

function Climate.moonPhaseName(phase)
    -- Eight bins centred on the named phases, so "full" covers the days
    -- either side of exact full rather than a single instant.
    local i = math.floor(phase * 8 + 0.5) % 8
    return PHASE_NAMES[i + 1]
end

-- Altitude above the horizon, degrees. Negative means below.
--
-- Two facts do all the work here. First: the moon's hour angle lags the sun's
-- by exactly its phase, which is why a new moon rises at sunrise and a full
-- moon rises at sunset -- phase and rise time are the same quantity. Second:
-- the moon sits opposite the sun on the ecliptic by that same phase, so a
-- full moon in winter takes the summer sun's high path, and a full moon in
-- summer skulks along the horizon.
function Climate.moonAltitude(dayIndex, hour)
    local dayOfYear = Climate.calendarDay(dayIndex)
    local phase = Climate.moonPhase(dayIndex, hour)

    -- Sun's position on the ecliptic, then the moon's, offset by the phase.
    local sunLon  = TWO_PI * (dayOfYear - 80.5) / DAYS_PER_YEAR
    local moonLon = sunLon + TWO_PI * phase
    local decl = math.asin(math.sin(0.4093) * math.sin(moonLon))

    local phi = math.rad(LATITUDE)
    -- MINUS, not plus. The moon drifts eastward against the stars, so it
    -- LAGS the sun -- rising ~50 min later each day. Getting this sign wrong
    -- still gives a correct new moon and full moon (0 and 180 are symmetric)
    -- and only betrays itself at the quarters, which is a nasty way to be
    -- wrong. First quarter must rise at noon and set at midnight.
    local H = math.rad(15 * (hour - 12) - 360 * phase)
    local s = math.sin(phi) * math.sin(decl) + math.cos(phi) * math.cos(decl) * math.cos(H)
    if s > 1 then s = 1 elseif s < -1 then s = -1 end
    return math.deg(math.asin(s))
end

-- Light the moon actually contributes, on the same 0-1 scale as daylight.
--
-- The exponent is not decoration. Moonlight is strongly non-linear in
-- illuminated fraction: a half moon gives roughly a TENTH of a full moon's
-- light, not a half, because of shadowing across the terminator and the
-- opposition surge at full. 0.5^3.32 = 0.1, hence 3.32.
local MOON_MAX <const> = 0.13

function Climate.moonLight(dayIndex, hour)
    local phase = Climate.moonPhase(dayIndex, hour)
    local frac = Climate.moonIllumination(phase)
    local alt = Climate.moonAltitude(dayIndex, hour)
    if alt <= 0 then return 0 end
    return MOON_MAX * (frac ^ 3.32) * math.sin(math.rad(alt))
end

-- Hour angle of the moon, degrees, normalised to -180..+180. Zero means the
-- moon is due south and at its highest for that night.
function Climate.moonHourAngle(dayIndex, hour)
    local phase = Climate.moonPhase(dayIndex, hour)
    local H = 15 * (hour - 12) - 360 * phase
    H = H % 360
    if H > 180 then H = H - 360 end
    return H
end

-- Peak moonlight, exposed so the renderer can scale star visibility against it.
function Climate.moonLightMax() return 0.13 end
