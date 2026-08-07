-- Fallow -- step 3: the climate engine, made visible.
--
-- The crank drives a clock. The clock drives the calendar. The calendar
-- drives the weather. Nothing on this screen is stored -- it is all
-- recomputed, every frame, from a single number.

import "CoreLibs/graphics"
import "climate"

local gfx <const> = playdate.graphics

-- The one number that matters. 240 = a day costs six turns of the crank.
local MINUTES_PER_REVOLUTION <const> = 240

local SCREEN_W   <const> = 400
local SCREEN_H   <const> = 240
local HORIZON_Y  <const> = 190    -- lowered; backlog item 4
local BODY_R     <const> = 13
local ARC_PEAK_Y <const> = 30
local MINUTES_PER_DAY <const> = 1440

local totalMinutes = 0
local isNight = false

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
        stars[i] = { x = math.random(0, SCREEN_W), y = math.random(20, HORIZON_Y - 15) }
    end
end

local GROUND_PATTERN <const> = { 0x88, 0x22, 0x88, 0x22, 0x88, 0x22, 0x88, 0x22 }

local function accumulateGDD(gameDay)
    if gddDay == gameDay then return end
    local yearStart = math.floor(gameDay / 365) * 365
    if gddDay ~= nil and gameDay == gddDay + 1 and gameDay > yearStart then
        -- Common case: one day forward. Add one term.
        gddTotal = gddTotal + Climate.day(gameDay).gdd
    else
        -- Jumped, or crossed into a new year. Walk it. At most 365 steps,
        -- which costs a single dropped frame and happens once per day change.
        gddTotal = 0
        for d = yearStart, gameDay do
            gddTotal = gddTotal + Climate.day(d).gdd
        end
    end
    gddDay = gameDay
end

local function arcPosition(t)
    local x = -BODY_R + t * (SCREEN_W + BODY_R * 2)
    local y = HORIZON_Y - math.sin(t * math.pi) * (HORIZON_Y - ARC_PEAK_Y)
    return x, y
end

local function drawSun(x, y)
    -- Hollow now; backlog item 1.
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawCircleAtPoint(x, y, BODY_R)
    gfx.setLineWidth(1)
end

local function drawMoon(x, y)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(x, y, BODY_R)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(x + BODY_R * 0.55, y - BODY_R * 0.30, BODY_R)
end

-- Falling weather. Purely decorative, so it can use frame randomness --
-- nothing here feeds back into the simulation.
local function drawPrecip(intensity, snowing)
    if intensity <= 0 then return end
    gfx.setColor(gfx.kColorBlack)
    local n = math.floor(intensity * (snowing and 70 or 110))
    for i = 1, n do
        local x = math.random(0, SCREEN_W)
        local y = math.random(0, HORIZON_Y)
        if snowing then
            gfx.fillRect(x, y, 2, 2)
        else
            gfx.drawLine(x, y, x - 2, y + 7)
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

    totalMinutes = totalMinutes + (playdate.getCrankChange() / 360) * MINUTES_PER_REVOLUTION
    if totalMinutes < 0 then totalMinutes = 0 end   -- the field has a day one

    local gameDay     = math.floor(totalMinutes / MINUTES_PER_DAY)
    local minuteOfDay = totalMinutes % MINUTES_PER_DAY
    local hour        = minuteOfDay / 60

    if todayIndex ~= gameDay then
        todayIndex = gameDay
        today = Climate.day(gameDay)
        accumulateGDD(gameDay)
    end

    local nightNow = (hour < today.sunrise) or (hour >= today.sunset)
    if nightNow ~= isNight then
        isNight = nightNow
        playdate.display.setInverted(isNight)
    end

    local intensity = Climate.precipAtHour(today, hour)
    local overcast  = intensity > 0.25

    gfx.clear()

    if isNight then
        gfx.setColor(gfx.kColorBlack)
        if not overcast then
            for i = 1, #stars do
                gfx.fillRect(stars[i].x, stars[i].y, 1, 1)
            end
            local night = today.sunset
            local span  = 24 - today.sunset + today.sunrise
            local t = (hour >= today.sunset) and (hour - night) / span
                                             or (hour + 24 - night) / span
            drawMoon(arcPosition(t))
        end
    else
        if not overcast then
            local t = (hour - today.sunrise) / (today.sunset - today.sunrise)
            drawSun(arcPosition(t))
        end
    end

    drawPrecip(intensity, today.isSnow)

    gfx.setPattern(GROUND_PATTERN)
    gfx.fillRect(0, HORIZON_Y, SCREEN_W, SCREEN_H - HORIZON_Y)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(0, HORIZON_Y, SCREEN_W, HORIZON_Y)

    -- ===== readout (debug; not intended for the shipped game) =====
    local year, season, dayOfSeason = Climate.calendar(gameDay)
    local temp = Climate.tempAtHour(today, hour)

    panel(4, 4, 196, 86)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawText(string.format("Year %d   %s %d", year, season, dayOfSeason), 11, 10)
    gfx.drawText(string.format("%02d:%02d", math.floor(hour), math.floor(minuteOfDay % 60)), 11, 27)
    gfx.drawText(string.format("%.1fC   H%.0f L%.0f", temp, today.high, today.low), 11, 44)

    local sky
    if today.isSnow and intensity > 0 then
        sky = string.format("snow  %.1fcm", today.snowMM / 10)
    elseif intensity > 0 then
        sky = string.format("rain  %.1fmm", today.precipMM)
    elseif today.isWet then
        sky = "dry (rain later)"
    else
        sky = "clear"
    end
    gfx.drawText(sky, 11, 61)

    local bright = Climate.brightness(today, hour, 0.5)
    local elev   = Climate.solarElevation(today.dayOfYear, hour)

    panel(4, SCREEN_H - 57, 196, 53)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawText(string.format("GDD %.0f  today +%.1f", gddTotal, today.gdd), 11, SCREEN_H - 52)
    gfx.drawText(string.format("daylight %.1fh  sun %.0f", today.dayLength, elev), 11, SCREEN_H - 36)
    gfx.drawText(string.format("light %.0f%%", bright * 100), 11, SCREEN_H - 20)

    -- A bar is easier to read at a glance than a number, and this is the
    -- signal that will eventually decide whether plants are visible at all.
    gfx.drawRect(95, SCREEN_H - 18, 96, 9)
    gfx.fillRect(97, SCREEN_H - 16, math.floor(92 * bright), 5)

    playdate.drawFPS(378, 4)
end
