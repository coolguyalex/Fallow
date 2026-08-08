# Fallow

Playdate, Lua. A field left to itself. Currently: a sky, a calendar, and a
climate model fitted to Providence, Rhode Island.

Working title. Fallow land is ground deliberately left uncultivated -- resting
rather than neglected -- which is the premise exactly.

## One-time setup

1. Download the SDK from https://play.date/dev/ (current version is 3.1.1).
2. Install it. On macOS it lands in `~/Developer/PlaydateSDK`; on Windows,
   `C:\Users\<you>\Documents\PlaydateSDK`.
3. Put the SDK's `bin` folder on your PATH so you can run `pdc` from a terminal.
   Verify with:

   ```
   pdc --version
   ```

## Build and run

From this folder:

```
pdc Source Fallow.pdx
```

That produces `Fallow.pdx`, which is a folder that acts like a file.
Double-click it, or drag it onto the Playdate Simulator.

To put it on real hardware: with the Playdate plugged in and unlocked, use the
Simulator's **Device → Upload Game to Device** menu item.

## Folder layout

```
Fallow/
  Source/          <- pdc compiles this whole folder
    main.lua       <- entry point; must be named main.lua
    pdxinfo        <- metadata; no file extension; required
  Fallow.pdx   <- build output (don't edit, don't commit)
```

Anything you put in `Source/` gets bundled. Images go in as `.png` and are
converted to Playdate's 1-bit format automatically at build time.

## Notes

- `playdate.update()` is called once per frame. Default target is 30 fps.
- `playdate.datastore.write(table)` / `.read()` is the save system. It writes
  JSON and handles the file paths for you.
- Reference docs: https://sdk.play.date/
