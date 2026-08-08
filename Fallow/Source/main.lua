-- Fallow -- step 3: the climate engine, made visible.
--
-- The crank drives a clock. The clock drives the calendar. The calendar
-- drives the weather. Nothing on this screen is stored -- it is all
-- recomputed, every frame, from a single number.

import "CoreLibs/graphics"
import "climate"
import "wind"
import "mullein"

local gfx <const> = playdate.graphics

-- The one number that matters. 240 = a day costs six turns of the crank.
local MINUTES_PER_REVOLUTION <const> = 240

-- Hold A to skim. At 10x one revolution buys about a day and two thirds,
-- which is the gearing you want for crossing a long absence. Slow cranking
-- stays the default because that is where anything can be looked at.
local FAST_MULTIPLIER <const> = 10

local SCREEN_W   <const> = 400
local SCREEN_H   <const> = 240
local HORIZON_Y  <const> = 190    -- lowered; backlog item 4
-- The sun and moon really are the same angular size in the sky -- a famous
-- coincidence -- but on a 1-bit screen that makes a full moon and the sun
-- nearly indistinguishable. Legibility beats astronomy here.
local SUN_R      <const> = 14
local MOON_R     <const> = 9
local BODY_R     <const> = 14
local ARC_PEAK_Y <const> = 30
local MINUTES_PER_DAY <const> = 1440

local totalMinutes = 0

-- Weather for the current day, recomputed only when the day rolls over.
local today, todayIndex = nil, nil

-- Accumulated growing degree days for the year so far. This is the first
-- thing in the game that ACCUMULATES rather than being a pure function, and
-- it is the pattern every plant will use: walk the days, add them up, cache
-- the answer, and only step forward by one when you can.
local gddTotal, gddDay = 0, nil

local stars = {}
do
    math.randomseed(20260807)
    for i = 1, 60 do
        stars[i] = {
            x = math.random(0, SCREEN_W),
            y = math.random(20, HORIZON_Y - 15),
            -- fixed per-star, so the glare edge is ragged rather than a
            -- perfect circle, and the same stars always survive it
            j = math.random(),
        }
    end
end

-- An ordered-dither ramp, 8x8 Bayer, thirteen steps from empty to solid.
-- This replaces playdate.display.setInverted() entirely.
--
-- The hard inversion flip at sunrise and sunset was painful to look at, and
-- no amount of easing fixes it, because the flip is instantaneous by nature.
-- So: draw the sky as a dithered fill whose density follows the sun's
-- ALTITUDE, and let dusk take an hour. Nothing snaps.
--
-- Note it follows solar altitude, not overall brightness. A full moon still
-- rises in a black sky -- moonlight lights the GROUND, not the air.
-- An ordered-dither ramp, 8x8 Bayer, thirteen steps.
--
-- Indexed by LUMINANCE: 1 is black, 13 is white. In a Playdate pattern a SET
-- bit renders WHITE, so these run from all-zero (black) up to all-ones
-- (white). Getting this backwards paints the night sky brilliant white, which
-- is exactly what it did.
--
-- If patterns ever come out inverted on hardware, flip the one flag below
-- rather than rewriting the table.
local INVERT_PATTERNS <const> = false

local DITHER = {
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
    { 0x88, 0x00, 0x20, 0x00, 0x88, 0x00, 0x02, 0x00 },
    { 0xAA, 0x00, 0x22, 0x00, 0x8A, 0x00, 0x22, 0x00 },
    { 0xAA, 0x00, 0xAA, 0x00, 0xAA, 0x00, 0xAA, 0x00 },
    { 0xAA, 0x44, 0xAA, 0x10, 0xAA, 0x44, 0xAA, 0x01 },
    { 0xAA, 0x55, 0xAA, 0x11, 0xAA, 0x45, 0xAA, 0x11 },
    { 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55 },
    { 0xEE, 0x55, 0xBA, 0x55, 0xEE, 0x55, 0xAB, 0x55 },
    { 0xFF, 0x55, 0xBB, 0x55, 0xEF, 0x55, 0xBB, 0x55 },
    { 0xFF, 0x55, 0xFF, 0x55, 0xFF, 0x55, 0xFF, 0x55 },
    { 0xFF, 0xDD, 0xFF, 0x75, 0xFF, 0xDD, 0xFF, 0x57 },
    { 0xFF, 0xFF, 0xFF, 0x77, 0xFF, 0xDF, 0xFF, 0x77 },
    { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF },
}
if INVERT_PATTERNS then
    for i = 1, #DITHER do
        for j = 1, 8 do DITHER[i][j] = 255 - DITHER[i][j] end
    end
end

local DUSK_TOP <const> = 2
local DUSK_BOTTOM <const> = -12

-- luminance: 0 black, 1 white.
local function tone(luminance)
    local i = math.floor(luminance * (#DITHER - 1) + 0.5) + 1
    if i < 1 then i = 1 elseif i > #DITHER then i = #DITHER end
    return DITHER[i]
end

-- Fill a rectangle at a given luminance. The extremes use setColor rather
-- than a pattern, so pure black and pure white are certain regardless of how
-- patterns behave.
local function fillTone(x, y, w, h, luminance)
    if luminance >= 0.985 then
        gfx.setColor(gfx.kColorWhite); gfx.fillRect(x, y, w, h)
    elseif luminance <= 0.015 then
        gfx.setColor(gfx.kColorBlack); gfx.fillRect(x, y, w, h)
    else
        gfx.setPattern(tone(luminance)); gfx.fillRect(x, y, w, h)
    end
    gfx.setColor(gfx.kColorBlack)   -- clears the pattern for whatever follows
end

-- 0 in full daylight, 1 in full night.
local function skyDarkness(sunAltitude)
    local t = (DUSK_TOP - sunAltitude) / (DUSK_TOP - DUSK_BOTTOM)
    if t < 0 then return 0 elseif t > 1 then return 1 end
    return t * t * (3 - 2 * t)      -- ease it, so onset and finish are gentle
end

-- ===== the specimen bench ===================================================
-- One plant, drawn large, so the growth model can be judged. B toggles.
-- This is scaffolding, not the game.

local GERM_DAY <const> = 40          -- mid-April of year one
-- The bench magnifies to fit. A 16cm rosette wants six times the scale of a
-- 176cm spike, and a fixed scale cannot serve both -- at one the rosette is an
-- illegible smudge, at the other the spike runs off the top.
--
-- This is a magnifier, not a proposal for the game's framing. The real answer
-- is backlog 10c: a wide field view plus a close specimen view, and probably
-- a scrolling field, because plants at true scale are small.
local BENCH_TARGET_PX <const> = 190
local BENCH_MAX_SCALE <const> = 6.0
local specimenView = false

-- 0 nothing, 1 a single line, 2 everything. Down cycles.
local uiMode = 1
local plant, plantDay = nil, nil

local function drawPlantPart(part, ox, oy, PX_PER_CM, ink)
    if part.kind == "flowers" or part.kind == "capsules" then
        -- A tapered quad, not a rounded rect: the two bands then meet flush
        -- and read as one club rather than two pills threaded on a wire.
        local wl = part.wLow * PX_PER_CM
        local wh = part.wHigh * PX_PER_CM
        local yl = oy - part.low * PX_PER_CM
        local yh = oy - part.high * PX_PER_CM
        local quad = { ox - wl, yl, ox + wl, yl, ox + wh, yh, ox - wh, yh }
        if part.kind == "flowers" then
            gfx.setColor(ink)
            gfx.fillPolygon(table.unpack(quad))
        else
            gfx.setPattern(tone(0.55))
            gfx.fillPolygon(table.unpack(quad))
            gfx.setColor(ink)
            quad[#quad + 1] = quad[1]; quad[#quad + 1] = quad[2]
            gfx.drawPolygon(table.unpack(quad))
        end
        gfx.setColor(gfx.kColorBlack)
        return
    end

    local flat = {}
    for i = 1, #part.points do
        flat[i * 2 - 1] = ox + part.points[i][1] * PX_PER_CM
        flat[i * 2]     = oy - part.points[i][2] * PX_PER_CM
    end
    -- Fill light, outline dark: overlapping leaves stay individually readable,
    -- which solid fills destroy and pure outlines turn into wire spaghetti.
    gfx.setPattern(tone(0.70))
    gfx.fillPolygon(table.unpack(flat))
    gfx.setColor(ink)
    flat[#flat + 1] = flat[1]
    flat[#flat + 1] = flat[2]
    gfx.drawPolygon(table.unpack(flat))
    gfx.setColor(gfx.kColorBlack)   -- never leave a pattern set
end

local function accumulateGDD(gameDay)
    if gddDay == gameDay then return end
    local yearStart = math.floor(gameDay / 365) * 365
    if gddDay ~= nil and gameDay > gddDay and gddDay >= yearStart then
        -- Moving forward inside the same year: add only the missing days.
        -- Handles a 10x skim crossing several days in one frame just as
        -- cheaply as a single step.
        for d = gddDay + 1, gameDay do
            gddTotal = gddTotal + Climate.day(d).gdd
        end
    else
        -- Went backwards, or crossed a year boundary. Walk it. At most 365
        -- steps, and only on the frame where that happens.
        gddTotal = 0
        for d = yearStart, gameDay do
            gddTotal = gddTotal + Climate.day(d).gdd
        end
    end
    gddDay = gameDay
end

-- Screen position from REAL sky coordinates: hour angle across, altitude up.
-- This is backlog items 2a and 2b -- the winter sun now genuinely traces a low
-- arc and the summer sun a high one, because altitude is no longer faked.
local function skyPosition(hourAngle, altitude)
    local x = SCREEN_W / 2 + (hourAngle / 115) * (SCREEN_W / 2 + BODY_R)
    local y = HORIZON_Y - (altitude / 90) * (HORIZON_Y - ARC_PEAK_Y)
    return x, y
end

local function drawSun(x, y, ink)
    gfx.setColor(ink)
    gfx.setLineWidth(2)
    gfx.drawCircleAtPoint(x, y, SUN_R)
    gfx.setLineWidth(1)
    -- Eight short ticks. Not cartoon rays -- this is the sun glyph from an
    -- almanac or an engraved chart, which is the register this game wants,
    -- and it separates sun from moon instantly at a glance.
    for i = 0, 7 do
        local a = i * math.pi / 4
        local ca, sa = math.cos(a), math.sin(a)
        gfx.drawLine(x + ca * (SUN_R + 4), y + sa * (SUN_R + 4),
                     x + ca * (SUN_R + 8), y + sa * (SUN_R + 8))
    end
end

-- Phase drawn by punching an equal-sized disc back out of the moon, offset
-- sideways. Offset 0 removes everything (new); offset 2R removes nothing
-- (full); in between you get a lune. Crude next to a real terminator ellipse,
-- but at thirteen pixels across nobody will ever know.
local function drawMoon(x, y, illum, waxing, skyTone)
    -- The lit face is always near-white -- the moon is a bright object
    -- whatever the sky is doing. By day that reads as a pale disc a shade
    -- off the white sky; by night it reads as a bright one against black.
    gfx.setPattern(tone(0.87))
    gfx.fillCircleAtPoint(x, y, MOON_R)

    -- Carve the unlit portion back to whatever the sky is, so the terminator
    -- is a true absence rather than a drawn shape.
    local offset = 2 * MOON_R * illum
    if offset < 2 * MOON_R - 0.5 then
        if skyTone >= 0.985 then gfx.setColor(gfx.kColorWhite)
        elseif skyTone <= 0.015 then gfx.setColor(gfx.kColorBlack)
        else gfx.setPattern(tone(skyTone)) end
        -- Lit side faces the sun: right when waxing, left when waning.
        gfx.fillCircleAtPoint(x + (waxing and -offset or offset), y, MOON_R)
    end
    gfx.setColor(gfx.kColorBlack)
end

-- Falling weather. Purely decorative, so it can use frame randomness --
-- nothing here feeds back into the simulation.
-- Slant follows the wind, which is the cheapest way to make wind visible
-- before there is any grass to bend.
local function drawPrecip(intensity, snowing, ink, slant)
    if intensity <= 0 then return end
    gfx.setColor(ink)
    local n = math.floor(intensity * (snowing and 70 or 110))
    for i = 1, n do
        local x = math.random(0, SCREEN_W)
        local y = math.random(0, HORIZON_Y)
        if snowing then
            gfx.fillRect(x, y, 2, 2)
        else
            gfx.drawLine(x, y, x + slant, y + 7)
        end
    end
end

local function panel(x, y, w, h)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(x, y, w, h)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(x, y, w, h)
end

function playdate.update()

    if playdate.buttonJustPressed(playdate.kButtonB) then
        specimenView = not specimenView
    end
    if playdate.buttonJustPressed(playdate.kButtonDown) then
        uiMode = (uiMode + 1) % 3
    end

    local fast = playdate.buttonIsPressed(playdate.kButtonA)
    local gearing = MINUTES_PER_REVOLUTION * (fast and FAST_MULTIPLIER or 1)
    totalMinutes = totalMinutes + (playdate.getCrankChange() / 360) * gearing
    if totalMinutes < 0 then totalMinutes = 0 end   -- the field has a day one

    local gameDay     = math.floor(totalMinutes / MINUTES_PER_DAY)
    local minuteOfDay = totalMinutes % MINUTES_PER_DAY
    local hour        = minuteOfDay / 60

    if todayIndex ~= gameDay then
        todayIndex = gameDay
        today = Climate.day(gameDay)
        accumulateGDD(gameDay)
    end

    local intensity = Climate.precipAtHour(today, hour)
    local overcast  = intensity > 0.25

    local phase   = Climate.moonPhase(gameDay, hour)
    local illum   = Climate.moonIllumination(phase)
    local moonAlt = Climate.moonAltitude(gameDay, hour)
    local moonLit = Climate.moonLight(gameDay, hour)
    local bright  = Climate.brightness(today, hour)
    local sunAlt  = Climate.solarElevation(today.dayOfYear, hour)
    local w       = Wind.at(today, hour)

    -- How dark the AIR is. Drives the whole palette.
    local dark = skyDarkness(sunAlt)

    -- Past the halfway point of dusk the sky is darker than mid-grey, so marks
    -- have to be light to read. Switching at exactly 0.5 is the least visible
    -- moment to switch, because a 50% dither inverts to another 50% dither.
    local nightInk = dark >= 0.5
    local ink   = nightInk and gfx.kColorWhite or gfx.kColorBlack
    local paper = nightInk and gfx.kColorBlack or gfx.kColorWhite

    gfx.clear(gfx.kColorWhite)

    -- The sky darkens through dusk. Luminance, not density -- 1 is white.
    fillTone(0, 0, SCREEN_W, HORIZON_Y, 1 - dark)

    -- Where the moon is on screen, needed before the stars so they can be
    -- washed out around it.
    local moonX, moonY
    if moonAlt > 0 then
        moonX, moonY = skyPosition(Climate.moonHourAngle(gameDay, hour), moonAlt)
    end

    if dark > 0.55 and not overcast then
        -- Moonlight does not dim the whole sky evenly -- it drowns the stars
        -- NEAR it first, and a bright moon's glare spreads outward from where
        -- it actually is. Only a full moon high overhead washes out the far
        -- corners of the sky.
        local duskFade = (dark - 0.55) / 0.45
        local ratio = moonLit / Climate.moonLightMax()
        local glare = (moonX and ratio > 0) and ((ratio ^ 0.6) * 520) or 0

        gfx.setColor(gfx.kColorWhite)
        for i = 1, #stars do
            local st = stars[i]
            local survives = true
            if glare > 0 then
                local dx, dy = st.x - moonX, st.y - moonY
                local d = math.sqrt(dx * dx + dy * dy)
                -- the per-star j ragged the edge so it is not a clean disc
                survives = d > glare * (0.55 + st.j * 0.75)
            end
            if survives and duskFade > st.j * 0.5 then
                gfx.fillRect(st.x, st.y, 1, 1)
            end
        end
    end

    if not overcast then
        -- Real sky coordinates, drawn only when actually above the horizon.
        -- A daytime moon is therefore possible, and correct.
        if moonX then
            drawMoon(moonX, moonY, illum, phase < 0.5, 1 - dark)
        end
        if sunAlt > 0 then
            -- Two locals, deliberately. skyPosition returns x AND y, but a
            -- Lua call only expands to multiple values when it is the LAST
            -- argument -- write drawSun(skyPosition(...), ink) and the y
            -- silently vanishes, ink lands in y, and ink becomes nil.
            local sx, sy = skyPosition(15 * (hour - 12), sunAlt)
            drawSun(sx, sy, ink)
        end
    end

    -- Rain leans with the wind. Westerlies slant it one way, easterlies the
    -- other, and a gust front lays it almost flat.
    local slant = -(w.speed / 4) * math.sin(math.rad(w.direction))
    drawPrecip(intensity, today.isSnow, ink, slant)

    -- The ground, lit by whatever light is actually falling on it. By day it
    -- sits mid-grey against a white sky; at night it is nearly black, but
    -- always a shade LIGHTER than the sky above it, by moonlight. So a full
    -- moon shows you the field and a new moon very nearly hides it.
    local groundTone
    if dark < 1 then
        groundTone = 0.62 - 0.22 * dark            -- daylight into dusk
    else
        groundTone = 0.06 + 0.62 * (moonLit / Climate.moonLightMax())
    end
    fillTone(0, HORIZON_Y, SCREEN_W, SCREEN_H - HORIZON_Y, groundTone)

    -- The horizon only needs a line while the ground is pale enough to need
    -- separating from the sky. At night the tone difference does the work,
    -- and a white line there reads as a stripe across the field.
    if dark < 0.6 then
        gfx.setColor(gfx.kColorBlack)
        gfx.drawLine(0, HORIZON_Y, SCREEN_W, HORIZON_Y)
    end

    -- The specimen, if we are looking at it.
    if specimenView then
        if plantDay ~= gameDay then
            plantDay = gameDay
            plant = Mullein.grow(GERM_DAY, gameDay)
        end
        local parts = Mullein.geometry(plant)

        local tall = math.max(plant.spike, plant.rosetteR * 0.9, 12)
        local scale = math.min(BENCH_MAX_SCALE, BENCH_TARGET_PX / tall)
        local baseY = SCREEN_H - 18

        for i = 1, #parts do
            drawPlantPart(parts[i], SCREEN_W / 2, baseY, scale, ink)
        end
        if uiMode > 0 then
            panel(232, 34, 164, 86)
            gfx.setColor(gfx.kColorBlack)
            gfx.drawText(plant.stage, 239, 40)
            gfx.drawText(string.format("age %d days", plant.age), 239, 57)
            gfx.drawText(string.format("%d leaves  %.0fcm",
                plant.leaves, plant.rosetteR * 2), 239, 74)
            if plant.spike > 0 then
                gfx.drawText(string.format("spike %.0fcm", plant.spike), 239, 91)
            else
                gfx.drawText(string.format("chill %d/45", plant.chill), 239, 91)
            end
        end
    end

    -- ===== readout (debug; not intended for the shipped game) =====
    -- Down cycles: nothing -> one line -> everything. The field needs room to
    -- be looked at, which is the entire point of the game.

    if uiMode > 0 then
        local year, season, dayOfSeason = Climate.calendar(gameDay)
        local temp = Climate.tempAtHour(today, hour)

        if uiMode == 1 then
            panel(4, 4, 218, 24)
            gfx.setColor(gfx.kColorBlack)
            gfx.drawText(string.format("Y%d %s %d   %02d:%02d   %.0fC",
                year, season, dayOfSeason,
                math.floor(hour), math.floor(minuteOfDay % 60), temp), 11, 8)
        else
            panel(4, 4, 218, 86)
            gfx.setColor(gfx.kColorBlack)
            gfx.drawText(string.format("Year %d   %s %d", year, season, dayOfSeason), 11, 10)
            gfx.drawText(string.format("%02d:%02d",
                math.floor(hour), math.floor(minuteOfDay % 60)), 11, 27)
            gfx.drawText(string.format("%.1fC  high %.0f  low %.0f",
                temp, today.high, today.low), 11, 44)

            local sky
            if today.isSnow and intensity > 0 then
                sky = string.format("snow  %.1fcm", today.snowMM / 10)
            elseif intensity > 0 then
                sky = string.format("rain  %.1fmm", today.precipMM)
            elseif today.isWet then
                sky = "dry (rain later today)"
            else
                sky = "clear"
            end
            gfx.drawText(sky, 11, 61)

            panel(4, 168, 274, 68)
            gfx.setColor(gfx.kColorBlack)
            gfx.drawText(string.format("growing degrees  %.0f   (+%.1f today)",
                gddTotal, today.gdd), 11, 173)
            gfx.drawText(string.format("light %.0f%%", bright * 100), 11, 190)
            gfx.drawRect(100, 192, 96, 9)
            gfx.fillRect(102, 194, math.floor(92 * bright), 5)
            gfx.drawText(string.format("moon  %s  %.0f%%",
                Climate.moonPhaseName(phase), illum * 100), 11, 213)

            panel(286, 168, 110, 68)
            gfx.setColor(gfx.kColorBlack)
            gfx.drawText(string.format("wind %.0f", Wind.mph(w.speed)), 293, 173)
            gfx.drawText(string.format("gust %.0f", Wind.mph(w.gust)), 293, 190)
            gfx.drawText(string.format("%s %s", w.compass, w.sector.name), 293, 207)
        end
    end

    if fast then
        panel(346, 34, 44, 22)
        gfx.setColor(gfx.kColorBlack)
        gfx.drawText("10x", 356, 38)
    end

    if uiMode > 0 then
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(372, 2, 26, 16)
        playdate.drawFPS(374, 4)
    end
end