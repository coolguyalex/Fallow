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

local GDD_PER_LEAF   <const> = 205    -- one new leaf per this much warmth
local MAX_LEAVES     <const> = 6      -- more than this and the fan is mush
local ROSETTE_MAX_R  <const> = 21     -- cm, radius; ~40cm across a good rosette
local ROSETTE_GDD    <const> = 1500   -- warmth to reach full rosette spread

local CHILL_BASE     <const> = 5.0    -- days below this count as chilling
local CHILL_REQUIRED <const> = 45     -- vernalization threshold, days
local BOLT_MIN_LEAVES<const> = 4      -- too small a rosette cannot bolt
local BOLT_GDD       <const> = 190    -- spring warmth needed to start bolting

local SPIKE_MAX      <const> = 195    -- cm
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

function Mullein.grow(germDay, today)
    local st = {
        stage = "seed", age = 0,
        gdd = 0, chill = 0, stress = 0,
        leaves = 0, rosetteR = 0, spike = 0,
        flowerLow = 0, flowerHigh = 0,   -- the band of open flowers, cm
        vernalized = false, alive = true, seedsSet = false,
    }
    if today < germDay then return st end

    local bolted, boltGDD, flowerGDD, seedGDD = false, 0, 0, 0
    local dieback = 0
    local springGDD = 0
    -- Start at the running equilibrium, not zero. Starting dry means every
    -- seedling spends its first fortnight in a drought that never happened.
    local waterRun = 30

    for d = germDay, today do
        local w = Climate.day(d)
        st.age = st.age + 1

        -- Warmth. The engine that drives everything.
        local gdd = w.meanTemp - 5.0
        if gdd < 0 then gdd = 0 end
        st.gdd = st.gdd + gdd

        -- Cold. Counted separately, and only useful in winter.
        if w.meanTemp < CHILL_BASE then
            st.chill = st.chill + 1
        end
        if st.chill >= CHILL_REQUIRED then st.vernalized = true end

        -- Water. A running balance rather than a per-day check, so a dry
        -- fortnight matters and a dry Tuesday does not.
        waterRun = waterRun * 0.90 + w.precipMM
        if waterRun < DROUGHT_MM then
            st.stress = st.stress + 1
        else
            st.stress = st.stress * 0.97
        end
        if st.stress > DROUGHT_LIMIT then
            st.alive = false
            st.stage = "dead"
            return st
        end

        -- Rosette: leaves and spread, both from accumulated warmth. Note the
        -- square root -- growth decelerates, as it does in life.
        if not bolted then
            local grown = math.min(MAX_LEAVES, math.floor(st.gdd / GDD_PER_LEAF))
            local spread = ROSETTE_MAX_R * math.min(1, math.sqrt(st.gdd / ROSETTE_GDD))

            -- Winter dieback. Outer leaves rot off in hard cold, so the
            -- rosette shrinks through winter and rebuilds in spring. Without
            -- this the plant is visually frozen from August to May, which is
            -- eight months of nothing to look at.
            if w.meanTemp < 2 then
                dieback = math.min(0.45, dieback + 0.006)
            elseif w.meanTemp > 8 then
                dieback = math.max(0, dieback - 0.010)
            end
            st.leaves = math.max(2, math.floor(grown * (1 - dieback) + 0.5))
            st.rosetteR = spread * (1 - dieback * 0.55)
        end

        -- Bolting. Needs cold behind it, a big enough rosette, and spring
        -- warmth in front of it. Miss any one and the plant waits another year.
        if not bolted and st.vernalized and st.leaves >= BOLT_MIN_LEAVES then
            springGDD = springGDD + gdd
            if springGDD >= BOLT_GDD then
                bolted = true
                st.stage = "bolting"
            end
        elseif not bolted then
            springGDD = 0
        end

        if bolted and not st.seedsSet then
            boltGDD = boltGDD + gdd
            st.spike = math.min(SPIKE_MAX, boltGDD / GDD_PER_CM)

            if st.spike >= FLOWER_START then
                st.stage = "flowering"
                flowerGDD = flowerGDD + gdd
                -- The open band migrates up the spike. Mullein does not flower
                -- all over at once; a ring of blooms creeps upward for weeks.
                local p = math.min(1, flowerGDD / FLOWER_GDD)
                st.flowerHigh = FLOWER_START + (st.spike - FLOWER_START) * p + 14
                st.flowerLow = st.flowerHigh - 46
                if st.flowerLow < FLOWER_START * 0.6 then
                    st.flowerLow = FLOWER_START * 0.6
                end
                if p >= 1 then
                    st.seedsSet = true
                    st.stage = "seeding"
                end
            end
        elseif st.seedsSet then
            seedGDD = seedGDD + gdd
            if seedGDD >= SEED_GDD then
                st.alive = false
                st.stage = "dead"
                return st
            end
        end

        if not bolted then
            st.stage = (st.leaves < 3) and "seedling" or "rosette"
        end
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

    return { points = pts }
end

function Mullein.geometry(st)
    local parts = {}
    if st.stage == "seed" then return parts end

    -- Oldest leaves are longest and lie nearly flat; the newest stand up in
    -- the middle. Drawn oldest first so the young centre sits on top, which
    -- is the one bit of depth a flat fan actually needs.
    local n = st.leaves
    for i = 1, n do
        local age = (n > 1) and (1 - (i - 1) / (n - 1)) or 1   -- 1 = oldest
        local mag = 18 + 66 * age + jitter(i, 9)
        local side = (i % 2 == 0) and 1 or -1
        local length = st.rosetteR * (0.45 + 0.55 * age)
        if st.spike > 0 then
            -- Rosette leaves wither back once the spike takes over.
            local decline = math.min(1, st.spike / SPIKE_MAX * 1.4)
            length = length * (1 - 0.55 * decline)
        end
        parts[#parts + 1] = leafPolygon(side * mag, length, length * 0.34)
    end

    if st.spike > 0 then
        local halfW = 1.6
        parts[#parts + 1] = { kind = "stem", points = {
            { -halfW, 0 }, { halfW, 0 },
            { halfW * 0.55, st.spike }, { -halfW * 0.55, st.spike } } }

        -- Stem leaves, decreasing up the spike.
        local n = math.floor(st.spike / 22)
        for i = 1, n do
            local h = 14 + (i - 1) * 22
            if h < st.spike * 0.82 then
                local len = st.rosetteR * 0.55 * (1 - h / st.spike)
                local side = (i % 2 == 0) and 1 or -1
                parts[#parts + 1] = { kind = "stemleaf", points = {
                    { 0, h + 2 }, { side * len, h + len * 0.22 },
                    { side * len * 0.9, h - len * 0.1 }, { 0, h - 2 } } }
            end
        end

        if st.flowerHigh > 0 then
            -- Two bands: the open flowers, and the spent capsules below them,
            -- which are what actually carries the seed. The club shape is the
            -- diagnostic feature at a distance.
            -- One continuous club: spent capsules below, open flowers above,
            -- both tapering into the stem so it does not read as two pills
            -- floating on a wire.
            local top = math.min(st.flowerHigh, st.spike)
            parts[#parts + 1] = { kind = "capsules",
                low = FLOWER_START * 0.5, high = st.flowerLow,
                wLow = 2.2, wHigh = 6.4 }
            parts[#parts + 1] = { kind = "flowers",
                low = st.flowerLow, high = top,
                wLow = 6.4, wHigh = 2.4 }
        end
    end

    return parts
end