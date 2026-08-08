-- mullein.lua
--
-- Common mullein, Verbascum thapsus. A biennial.
--
-- Year one: a flat rosette of large felted leaves, hugging the ground.
-- Winter: the rosette persists and takes its cold. It cannot skip this.
-- Year two: a single unbranched spike to two metres, flowers bottom-to-top,
--           sets seed, and dies. Monocarpic -- it flowers once and that is it.
--
-- Three real facts about this plant do most of the design work:
--
--  1. Seeds stay viable in soil for DECADES. Up to a century is documented.
--     So the field remembers mullein long after the last plant died.
--  2. It needs BARE SOIL and light to germinate, and it is a poor competitor.
--     Grass closes in and mullein vanishes. It cannot dominate.
--  3. It requires VERNALIZATION -- real accumulated cold -- before it can
--     bolt. The player cannot see this plant's life without cranking through
--     a winter.
--
-- Growth is instruction-driven, not sprite-staged. There is no "juvenile"
-- artwork. Leaf count, rosette spread and spike height are numbers that
-- accumulate, and the shape is derived from them.

Mullein = {}

-- ===== Growth constants =====================================================
-- All lengths in centimetres. Providence delivers roughly 2800 GDD (base 5)
-- in a year, which is the number to hold in mind when reading thresholds.

local GDD_PER_LEAF   <const> = 175    -- a new leaf emerges per this much warmth
local MAX_LEAVES     <const> = 7      -- more than this and the fan is mush
local LEAF_TAU       <const> = 260    -- warmth for a leaf to approach full size
local ANGLE_TAU      <const> = 620    -- warmth for a leaf to be pushed flat
local FAN_SPREAD     <const> = 86     -- degrees either side of vertical
local ROSETTE_MAX_R  <const> = 21     -- cm, radius; ~40cm across a good rosette
local ROSETTE_GDD    <const> = 1500   -- warmth to reach full rosette spread

local CHILL_BASE     <const> = 5.0    -- days below this count as chilling
local CHILL_REQUIRED <const> = 45     -- vernalization threshold, days
local BOLT_MIN_LEAVES<const> = 4      -- too small a rosette cannot bolt
local BOLT_GDD       <const> = 190    -- spring warmth needed to start bolting

local SPIKE_MAX      <const> = 195    -- cm, whole second-year stem
local INFLOR_FRAC    <const> = 0.20   -- top fifth is the dense flower spike
local CAULINE_GAP    <const> = 11     -- cm between stem leaves
local GDD_PER_CM     <const> = 7.5    -- spike elongation rate
local FLOWER_START   <const> = 55     -- spike height at which flowering opens
local FLOWER_GDD     <const> = 900    -- warmth from first flower to seed set
local SEED_GDD       <const> = 380    -- warmth from seed set to death

local DROUGHT_MM     <const> = 3.0    -- daily water below this is stressful
local DROUGHT_LIMIT  <const> = 34     -- accumulated stress-days that kill it

-- ===== The model ============================================================
--
-- A pure function of (germinationDay, today). Walks the days, accumulates,
-- returns state. Same pattern as accumulateGDD in main.lua -- the caller
-- should cache per day rather than calling this every frame.

-- A fresh plant. All the accumulators live in the state table rather than as
-- locals, which is what lets a plant be advanced one day at a time instead of
-- being recomputed from birth.
function Mullein.new(germDay, seed)
    seed = seed or 1
    return {
        germDay = germDay, day = germDay - 1,
        seed = seed, tr = Mullein.traits(seed),
        stage = "seed", age = 0,
        gdd = 0, chill = 0, stress = 0,
        leaves = 0, rosetteR = 0, spike = 0,
        flowerLow = 0, flowerHigh = 0, inflorBase = 0,
        vernalized = false, alive = true, seedsSet = false,
        -- internals
        bolted = false, boltGDD = 0, flowerGDD = 0, seedGDD = 0,
        springGDD = 0, dieback = 0,
        -- Start at the running equilibrium, not zero. Starting dry means every
        -- seedling spends its first fortnight in a drought that never happened.
        waterRun = 30,
    }
end

-- Advance exactly one day. w is that day's Climate.day() table.
--
-- This is the whole performance story. Walking a 400-day plant from birth
-- costs about 28 ms on hardware; for 200 plants that is over five seconds.
-- Stepping forward one day costs a few microseconds. Same numbers, same
-- determinism -- the state is still entirely derivable from seed and date,
-- we simply stop rederiving what we already know.
function Mullein.step(st, w)
    st.day = st.day + 1
    if not st.alive or st.day < st.germDay then return st end
    st.age = st.age + 1

    local gdd = w.meanTemp - 5.0
    if gdd < 0 then gdd = 0 end
    st.gdd = st.gdd + gdd

    if w.meanTemp < CHILL_BASE then st.chill = st.chill + 1 end
    if st.chill >= CHILL_REQUIRED then st.vernalized = true end

    -- Water: a running balance, so a dry fortnight matters and a dry Tuesday
    -- does not.
    st.waterRun = st.waterRun * 0.90 + w.precipMM
    if st.waterRun < DROUGHT_MM then
        st.stress = st.stress + 1
    else
        st.stress = st.stress * 0.97
    end
    if st.stress > DROUGHT_LIMIT then
        st.alive = false; st.stage = "dead"; return st
    end

    if not st.bolted then
        local grown = math.min(MAX_LEAVES,
            math.floor(st.gdd / (GDD_PER_LEAF * st.tr.leafRate)) + 1)
        local spread = ROSETTE_MAX_R * st.tr.vigour
            * math.min(1, math.sqrt(st.gdd / ROSETTE_GDD))

        -- Winter dieback. Outer leaves rot off in hard cold, so the rosette
        -- shrinks through winter and rebuilds in spring. Without it the plant
        -- is visually frozen from August to May.
        if w.meanTemp < 2 then
            st.dieback = math.min(0.45, st.dieback + 0.006)
        elseif w.meanTemp > 8 then
            st.dieback = math.max(0, st.dieback - 0.010)
        end
        st.leaves = math.max(2, math.floor(grown * (1 - st.dieback) + 0.5))
        st.rosetteR = spread * (1 - st.dieback * 0.55)
    end

    -- Bolting needs cold behind it, a big enough rosette, and spring warmth in
    -- front of it. Miss any one and the plant waits another year.
    if not st.bolted and st.vernalized and st.leaves >= BOLT_MIN_LEAVES then
        st.springGDD = st.springGDD + gdd
        if st.springGDD >= BOLT_GDD then
            st.bolted = true; st.stage = "bolting"
        end
    elseif not st.bolted then
        st.springGDD = 0
    end

    if st.bolted and not st.seedsSet then
        st.boltGDD = st.boltGDD + gdd
        st.spike = math.min(SPIKE_MAX * st.tr.spikeBias, st.boltGDD / GDD_PER_CM)
        if st.spike >= FLOWER_START then
            st.stage = "flowering"
            st.flowerGDD = st.flowerGDD + gdd
            -- The open band migrates up the spike. Mullein does not flower all
            -- over at once; a ring of blooms creeps upward for weeks.
            -- The inflorescence is the TOP FIFTH of the stem, not everything
            -- above some fixed height. Below it the stem is leafy; the dense
            -- flowering club is a short terminal feature, which is what makes
            -- a real mullein read as a cone with a candle on top.
            local p = math.min(1, st.flowerGDD / FLOWER_GDD)
            local base = st.spike * (1 - INFLOR_FRAC)
            local span = st.spike - base
            st.inflorBase = base
            st.flowerLow = base + span * p * 0.86
            st.flowerHigh = math.min(st.spike, st.flowerLow + span * 0.32)
            if p >= 1 then st.seedsSet = true; st.stage = "seeding" end
        end
    elseif st.seedsSet then
        st.seedGDD = st.seedGDD + gdd
        if st.seedGDD >= SEED_GDD then
            st.alive = false; st.stage = "dead"; return st
        end
    end

    if not st.bolted then
        st.stage = (st.leaves < 3) and "seedling" or "rosette"
    end
    return st
end

-- Convenience: build a plant from scratch. Fine for one plant on a bench,
-- wrong for two hundred in a field -- use new() plus step() there.
function Mullein.grow(germDay, today, seed)
    local st = Mullein.new(germDay, seed)
    for d = germDay, today do
        Mullein.step(st, Climate.day(d))
    end
    return st
end

-- ===== Geometry =============================================================
--
-- Returns a list of polygons in centimetres, origin at the base of the plant,
-- +y upward. Renderer-agnostic on purpose: the Playdate drawing code and any
-- offline preview consume the same numbers, so what you validate is what ships.

-- Pure 2D front elevation. No projection, no foreshortening -- a leaf is
-- defined by three numbers and that is all: LENGTH, ANGLE from vertical, and
-- THICKNESS. Anything cleverer collapses leaves pointing at the camera into
-- vertical slivers, which is exactly what the first attempt did.

-- Half-width profile along the leaf. Obovate: widest past the middle,
-- tapering to a point at both base and tip.
local function leafHalfWidth(t, width)
    local b = math.sin(math.pi * (t ^ 0.62))
    return width * (b ^ 0.62) * (0.55 + 0.45 * t)
end

-- Deterministic per-leaf jitter, so a rosette is not a perfect symmetric fan
-- but is the same rosette every time it is drawn.
local function jitter(i, spread)
    local x = math.sin(i * 12.9898) * 43758.5453
    return ((x - math.floor(x)) * 2 - 1) * spread
end

-- angle is measured from vertical: 0 stands straight up, +90 lies flat right.
local function leafPolygon(angleDeg, length, width)
    local a = math.rad(angleDeg)
    local ca, sa = math.cos(a), math.sin(a)
    local pts = {}
    local n = 10

    -- The base and the tip are each emitted ONCE. Emitting them twice --
    -- which happens naturally if you walk t=0..1 up one edge and 1..0 back
    -- down the other -- leaves coincident vertices with zero-area spans
    -- between them, and a scanline polygon fill reads those as an extra
    -- crossing. The result is a stripe running off to the edge of the screen.
    local function spine(t)
        return sa * length * t, ca * length * t
    end

    local bx, by = spine(0)
    pts[#pts + 1] = { bx, by }

    for i = 1, n - 1 do
        local t = i / n
        local hw = leafHalfWidth(t, width)
        local px, py = spine(t)
        pts[#pts + 1] = { px + ca * hw, py - sa * hw }
    end

    local tx, ty = spine(1)
    pts[#pts + 1] = { tx, ty }

    for i = n - 1, 1, -1 do
        local t = i / n
        local hw = leafHalfWidth(t, width)
        local px, py = spine(t)
        pts[#pts + 1] = { px - ca * hw, py + sa * hw }
    end

    -- The midrib. On a 1-bit screen overlapping leaves collapse into a single
    -- silhouette; one line down the centre of each is what separates them
    -- again, and it is also the first thing a botanical plate draws.
    return { points = pts, midrib = { bx, by, tx, ty } }
end

-- Two deterministic pseudo-randoms per leaf, so every leaf has its own
-- terminal size, proportions and lean -- but the SAME ones every time it is
-- drawn. Two cheap sin-fract hashes; no state, no table of stored values.
local function leafRand(i, salt, seed)
    local x = math.sin(i * 78.233 + salt * 12.9898 + seed * 3.7351) * 43758.5453
    return x - math.floor(x)
end

-- Per-plant constitution, derived once from the seed. Two mulleins in the
-- same field get the same weather and the same rules, and still grow into
-- visibly different plants -- one squat and broad, another lanky, another
-- lopsided. Without this every plant in the field is a clone.
function Mullein.traits(seed)
    local function r(salt)
        local x = math.sin(seed * 91.7 + salt * 27.13) * 24634.6345
        return x - math.floor(x)
    end
    return {
        vigour    = 0.74 + 0.52 * r(1),   -- overall size, rosette and spike
        leafRate  = 0.84 + 0.32 * r(2),   -- how fast new leaves emerge
        fanPhase  = r(3),                 -- rotates the whole fan
        widthBias = 0.82 + 0.36 * r(4),   -- narrow-leaved or broad-leaved
        lean      = (r(5) - 0.5) * 22,    -- the whole rosette tips a little
        spikeBias = 0.80 + 0.40 * r(6),
    }
end

function Mullein.geometry(st)
    local parts = {}
    if st.stage == "seed" or st.leaves < 1 then return parts end

    -- Each leaf grows from its OWN age, not from its rank in the list.
    -- Ranking was the bug: the instant a second leaf appeared, the first
    -- jumped to a new size and angle. Now a leaf emerges at effectively zero
    -- size, swells toward its own terminal size, and is pushed progressively
    -- flatter as it ages -- which is what a rosette actually does.
    local tr = st.tr or Mullein.traits(1)
    for i = 1, st.leaves do
        local born = (i - 1) * GDD_PER_LEAF * tr.leafRate
        local ageGDD = st.gdd - born
        if ageGDD > 0 then
            local grow = 1 - math.exp(-ageGDD / LEAF_TAU)      -- size, 0 -> 1
            local flat = 1 - math.exp(-ageGDD / ANGLE_TAU)     -- lean, 0 -> 1

            -- Each leaf owns a FIXED slot in the fan, from the golden-ratio
            -- sequence. That sequence is low-discrepancy: successive values
            -- fill the interval evenly wherever you stop, so three leaves are
            -- already spread across the arc, and so are seven. It is the same
            -- property that makes real phyllotaxis use the golden angle --
            -- optimal packing at every stage of growth.
            --
            -- Deriving the angle from AGE instead gives a slowly opening V,
            -- because young leaves all bunch upright and old ones all lie
            -- flat with nothing between them.
            -- fanPhase rotates the sequence. A rotation of a low-discrepancy
            -- sequence is still low-discrepancy, so the fan stays evenly
            -- spread while landing in different places on every plant.
            local slot = (i * 0.618034 + tr.fanPhase) % 1
            local target = -FAN_SPREAD + 2 * FAN_SPREAD * slot

            local terminal = st.rosetteR * (0.72 + 0.38 * leafRand(i, 1, st.seed or 1))
            local length = terminal * grow
            if st.spike > 0 then
                local decline = math.min(1, st.spike / SPIKE_MAX * 1.4)
                length = length * (1 - 0.55 * decline)
            end
            local width = length * tr.widthBias
                * (0.145 + 0.05 * leafRand(i, 2, st.seed or 1))

            -- Age only opens the leaf OUT toward its slot. A new leaf starts
            -- half-raised in the middle and settles outward as it matures,
            -- which keeps the age cue without collapsing the fan.
            local angle = target * (0.5 + 0.5 * flat) + tr.lean
                        + (leafRand(i, 3, st.seed or 1) - 0.5) * 13

            if length > 0.4 then
                parts[#parts + 1] = leafPolygon(angle, length, width)
            end
        end
    end

    if st.spike > 0 then
        local base = (st.inflorBase > 0) and st.inflorBase or st.spike
        local halfW = 1.7 * tr.vigour

        -- A tapered stem. Thicker at the ground than at the tip.
        parts[#parts + 1] = { kind = "stem", points = {
            { -halfW, 0 }, { halfW, 0 },
            { halfW * 0.45, st.spike }, { -halfW * 0.45, st.spike } } }

        -- Cauline leaves: the same spiral continuing up the stem, each one
        -- smaller than the last and held more upright. That decreasing series
        -- is what produces the cone -- broad at the bottom, narrowing to the
        -- flower spike. They are not decoration; they ARE the silhouette.
        local leafy = base
        local n = math.floor(leafy / CAULINE_GAP)
        for k = 1, n do
            local h = (k - 0.4) * CAULINE_GAP
            if h < leafy then
                local up = h / leafy                       -- 0 base, 1 top
                local len = st.rosetteR * tr.vigour * 0.78 * ((1 - up) ^ 0.85)
                if len > 0.6 then
                    local slot = (k * 0.618034 + tr.fanPhase) % 1
                    local side = (slot >= 0.5) and 1 or -1
                    -- Ascending: nearly horizontal low down, hugging the stem
                    -- near the top.
                    local ang = side * (68 - 44 * up
                        + (leafRand(k, 7, st.seed or 1) - 0.5) * 16)
                    local leaf = leafPolygon(ang, len, len * 0.20 * tr.widthBias)
                    for _, pt in ipairs(leaf.points) do pt[2] = pt[2] + h end
                    leaf.midrib[2] = leaf.midrib[2] + h
                    leaf.midrib[4] = leaf.midrib[4] + h
                    parts[#parts + 1] = leaf
                end
            end
        end

        if st.flowerHigh > 0 then
            local w = 4.6 * tr.vigour
            -- Three bands up the terminal spike: spent capsules below, the
            -- open ring, unopened buds above. The ring creeps upward for
            -- weeks, which is how mullein actually flowers.
            if st.flowerLow > base then
                parts[#parts + 1] = { kind = "capsules",
                    low = base, high = st.flowerLow,
                    wLow = w * 0.85, wHigh = w }
            end
            parts[#parts + 1] = { kind = "flowers",
                low = st.flowerLow, high = st.flowerHigh,
                wLow = w, wHigh = w * 0.95 }
            if st.flowerHigh < st.spike then
                parts[#parts + 1] = { kind = "buds",
                    low = st.flowerHigh, high = st.spike,
                    wLow = w * 0.95, wHigh = w * 0.35 }
            end
        end
    end

    return parts
end