-- wind.lua
--
-- Wind speed, direction and gusts. Shares Climate's noise channels, so it is
-- the same kind of object: a pure function of (dayIndex, hour), no state.
--
-- Three couplings to the weather, and deliberately only three. Storms are
-- windy; summer convective storms are preceded by a gust front; big cold-season
-- storms blow from the east. Everything else is left independent, because
-- correlating every signal collapses the variety -- you want cold bright windy
-- days and warm grey still ones to both remain possible.
--
-- Note what is NOT here: no pressure field, no advected fronts, no
-- convective energy. The gust front is not CAUSED by the storm in this code.
-- Both are consequences of the same day's noise. Correlate outputs, do not
-- simulate causes.

Wind = {}

local TWO_PI <const> = math.pi * 2
local DAYS_PER_YEAR <const> = 365
local T_COLDEST <const> = 21          -- matches Climate; keeps phases aligned

-- Providence runs about 4.7 m/s in the annual mean -- roughly 10.5 mph --
-- windier in winter (5.4) than summer (3.8). Wind speed is Weibull
-- distributed with shape near 2, NOT Gaussian, which is why calm days
-- outnumber windy ones instead of being equally common. For shape 2 the mean
-- is scale x 0.8862, so these scales are the target means divided by that.
local SCALE_MEAN  <const> = 5.30      -- Weibull scale, annual mean
local SCALE_SWING <const> = 1.00      -- + in winter, - in summer
local WEIBULL_K   <const> = 2.0

-- Afternoons are windier: the boundary layer mixes as the ground heats, and
-- momentum from aloft reaches the surface. Mornings are calm.
local DIURNAL_DEPTH <const> = 0.30
local DIURNAL_PEAK  <const> = 15.0    -- hour of maximum

-- Prevailing direction rotates through the year: northwest in winter,
-- southwest in summer. Real, and it does most of the design work here,
-- because it makes EASTERLIES RARE -- and east is the meadow's seed source.
local DIR_CENTRE <const> = 270        -- due west, the annual mean
local DIR_SWING  <const> = 45         -- -> 315 (NW) winter, 225 (SW) summer
local DIR_SPREAD <const> = 85         -- day-to-day scatter, degrees

local NOREASTER_DIR <const> = 55      -- ENE
local GUST_BASE <const> = 1.25

-- ===== The four neighbours ==================================================
--
-- Wind direction is meteorological: the direction it blows FROM. So a north
-- wind carries forest seed down onto the field.
--
-- Read by the dispersal system later. Each sector is a different KIND of
-- event, not four flavours of one -- which is what keeps this from being a
-- symmetric four-way dial.

Wind.SECTORS = {
    north = {
        name = "forest",
        detail = "woodland north through Lincoln and Smithfield",
        -- Succession-closing species. These seeds END the meadow.
        pool = { "red maple", "gray birch", "white pine", "eastern red cedar" },
    },
    east = {
        name = "farmland",
        detail = "open fields east into Rehoboth",
        -- The meadow pool. What holds the field in early succession.
        pool = { "little bluestem", "goldenrod", "common milkweed",
                 "New England aster", "Queen Anne's lace" },
        -- And this is the RARE wind. See DIR_CENTRE above.
    },
    south = {
        name = "bay",
        detail = "Narragansett Bay and open water",
        -- Barely a seed source at all: mostly moisture, fog and gulls. The
        -- asymmetry is deliberate.
        pool = { "seaside goldenrod", "switchgrass" },
    },
    west = {
        name = "city",
        detail = "Providence proper",
        -- Ruderals and introductions. Degradation pressure.
        pool = { "mugwort", "Japanese knotweed", "tree-of-heaven",
                 "chicory", "common mullein" },
    },
}

local COMPASS <const> = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

function Wind.compass(deg)
    local i = math.floor(((deg % 360) + 22.5) / 45) % 8
    return COMPASS[i + 1]
end

function Wind.sectorKey(deg)
    deg = deg % 360
    if deg >= 315 or deg < 45 then return "north"
    elseif deg < 135 then return "east"
    elseif deg < 225 then return "south"
    else return "west" end
end

-- ===== Helpers ==============================================================

-- Logistic approximation to the normal CDF. The noise is not exactly Gaussian
-- anyway, so a rational approximation would be false precision; this is
-- accurate to about 0.01 and the resulting speed distribution was validated
-- against the Weibull target directly.
local function toUniform(x)
    return 1 / (1 + math.exp(-1.702 * x))
end

local function seasonal(dayOfYear)
    return math.cos(TWO_PI * (dayOfYear - T_COLDEST) / DAYS_PER_YEAR)
end

-- ===== The model ============================================================

-- Pass in the table from Climate.day() so the couplings have something to
-- read. Returns speed and gust in m/s, direction in degrees.
function Wind.at(w, hour)
    local s = seasonal(w.dayOfYear)

    -- Base speed: correlated noise -> uniform -> inverse Weibull CDF. The
    -- noise supplies the windy-spell clustering; the Weibull supplies the
    -- right shape of distribution.
    local u = toUniform(Climate.fractalNoise(w.dayIndex, 61))
    if u > 0.9995 then u = 0.9995 end
    local scale = SCALE_MEAN + SCALE_SWING * s
    local speed = scale * (-math.log(1 - u)) ^ (1 / WEIBULL_K)

    -- Diurnal cycle.
    speed = speed * (1 + DIURNAL_DEPTH *
        math.cos(TWO_PI * (hour - DIURNAL_PEAK) / 24))

    -- COUPLING 1: storms are windy.
    local intensity = Climate.precipAtHour(w, hour)
    speed = speed * (1 + 0.55 * intensity)

    -- COUPLING 2: the gust front. Summer, warm, and a decent convective
    -- total -- the violent shove of air that arrives BEFORE the rain does.
    -- This is the thing you notice standing outside in July.
    local isConvective = w.isWet and w.precipMM > 8
        and w.meanTemp > 17 and not w.isSnow
    local gustFront = 0
    if isConvective then
        local lead = w.rainStart - hour       -- hours until onset
        if lead > 0 and lead < 0.8 then
            gustFront = 1 - lead / 0.8        -- 0 -> 1 as it closes
            speed = speed * (1 + 1.7 * gustFront)
        end
    end

    -- Direction: seasonal prevailing, plus scatter.
    local dir = DIR_CENTRE + DIR_SWING * s
        + DIR_SPREAD * Climate.fractalNoise(w.dayIndex, 67)

    -- COUPLING 3: big cold-season storms come from the east. This is the only
    -- thing that reliably brings the farmland's seed, and it arrives attached
    -- to the worst weather of the year.
    if w.precipMM > 14 and w.meanTemp < 12 then
        local pull = math.min(1, (w.precipMM - 14) / 16)
        -- shortest-arc blend toward ENE
        local delta = ((NOREASTER_DIR - dir + 540) % 360) - 180
        dir = dir + delta * pull * 0.85
    end
    dir = dir % 360

    -- Gusts. Factor rises with turbulence and spikes on a gust front.
    local gustFactor = GUST_BASE
        + 0.28 * math.abs(Climate.fractalNoise(w.dayIndex, 71))
        + 0.9 * gustFront
    local key = Wind.sectorKey(dir)

    return {
        speed     = speed,
        gust      = speed * gustFactor,
        direction = dir,
        compass   = Wind.compass(dir),
        sectorKey = key,
        sector    = Wind.SECTORS[key],
        gustFront = gustFront,
        isNoreaster = (w.precipMM > 14 and w.meanTemp < 12 and key == "east"),
    }
end

function Wind.mph(ms) return ms * 2.23694 end
