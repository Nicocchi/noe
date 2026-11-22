# Nico's Own Editor

A native Odin editor.

## Config

User files live in `%APPDATA%\noe\` (Roaming). The folder is created on first run. Missing files are fine — built-in defaults apply.

Reload without restart: **Ctrl+Shift+R** (`reload_config`). Save first.

```
%APPDATA%\noe\
  init.lua          Lua config (settings, binds, commands, hooks)
  themes\           optional modules, loaded with require("themes/name")
  lex\              syntax highlighters (*.lex)
```

### init.lua

Loaded once at startup. Extra `.lua` files in this folder (or subfolders) are modules; `package.path` includes `%APPDATA%\noe\?.lua`.

```lua
require("themes/amethyst")

noe.set("font_size", 18)
noe.set("tab_width", 4)
noe.bind("ctrl+shift+r", "reload_config")
```

`noe.set` / `noe.get` cover theme and behavior. `noe.bind` maps chords to command names. `noe.command` registers a Lua function. `noe.hook` is `save`, `open`, or `change`. `noe.status` replaces the bottom bar with two strings.

### lex\

One `*.lex` per language. Chosen by file extension (case-insensitive). Unknown extensions fall back to `odin`.

```
name: sh
extensions:
sh
bash
keywords:
if
then
ops:
&&
||
comments:
#
directive: $
```

- `comments:` with no close string is a line comment (`#`, `//`, `::`). A pair (`/* */`) is a block comment.
- A line that is only `#` is a comment *mark*. `# note` is a comment in the lex file itself.
- `directive:` is a prefix (`#` for Odin, `$` for shell, `%` for batch).
- Keywords match bytes exactly (batch lists both `if` and `IF`).

Shipped examples: `odin.lex`, `lua.lex`, `c.lex`, `sh.lex`, `bat.lex`.

## Project (not AppData)

`project.noe` sits in the folder you open (or a parent). It is the project name, file-picker patterns, blacklist, named commands, and F-key map — not editor settings.

```
name: noe
patterns:
odin
lua
commands:
build ./build.sh
fkey:
1 build
```

F1–F12 run the named command. Output goes to the parent terminal when NOE was started from one.

## Build

From this directory, with Odin on `PATH`:

```
./build.sh
./build.sh run
./build.sh release
```

Windowed `build/noe.exe` plus `lua54.dll`. `odin run src` keeps a console for `print`.

Explorer **Open with NOE** (current user):

```
powershell -File install-context-menu.ps1
powershell -File install-context-menu.ps1 -Uninstall
```
