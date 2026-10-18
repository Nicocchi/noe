package editor

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:path/filepath"
import lua "vendor:lua/5.4"
import "../platform"

script_ctx: runtime.Context
lua_cmds:       map[string]c.int
lua_hooks:      map[string][dynamic]c.int
lua_status_ref: c.int = lua.NOREF
script_ed:      ^Editor

script_init_path :: proc() -> (path: string, ok: bool) {
    root, err := os.user_config_dir(context.allocator, true)
    if err != nil {
        fmt.eprintln("Lua: no config dir:", err)
        return
    }
    defer delete(root)

    dir, derr := filepath.join({root, "noe"})
    if derr != nil {
        return
    }
    defer delete(dir)

    _ = os.make_directory_all(dir)
    perr: runtime.Allocator_Error
    path, perr = filepath.join({dir, "init.lua"})
    if perr != nil {
        return
    }
    ok = true

    return
}

script_init :: proc(ed: ^Editor) {
    lex_load_all()
    script_ctx = context
    L := lua.L_newstate()
    if L == nil {
        fmt.eprintln("Lua: Faield to create state")
        return
    }
    lua.L_openlibs(L)
    ed.lua = L

    lua.newtable(L)
    
    lua.pushcfunction(L, lua_api_bind)
    lua.setfield(L, -2, "bind")

    lua.pushcfunction(L, lua_api_set)
    lua.setfield(L, -2, "set")

    lua.pushcfunction(L, lua_api_command)
    lua.setfield(L, -2, "command")

    lua.pushcfunction(L, lua_api_run)
    lua.setfield(L, -2, "run")

    lua.pushcfunction(L, lua_api_unbind)
    lua.setfield(L, -2, "unbind")

    lua.pushcfunction(L, lua_api_hook)
    lua.setfield(L, -2, "hook")

    lua.pushcfunction(L, lua_api_get)
    lua.setfield(L, -2, "get")

    lua.pushcfunction(L, lua_api_status)
    lua.setfield(L, -2, "status")
    
    lua.setglobal(L, "noe")

    path, ok := script_init_path()
    if ok {
        defer delete(path)
        dir := filepath.dir(path)
        script_set_package_path((^lua.State)(ed.lua), dir)
        script_ed = ed
        if lua_cmds == nil {
            lua_cmds = make(map[string]c.int)
        }
        if lua_hooks == nil {
            lua_hooks = make(map[string][dynamic]c.int)
            lua_hooks["save"] = make([dynamic]c.int)
            lua_hooks["open"] = make([dynamic]c.int)
            lua_hooks["change"] = make([dynamic]c.int)
        }
        script_load_file(ed, path)
    }

    b := active_buffer(ed)
    if len(b.path) == 0 {
        b.newline = settings.newline
    }
    ed.split_t = settings.split_t
}

script_shutdown :: proc(ed: ^Editor) {
    if ed.lua == nil {
        return
    }
    lua.close((^lua.State)(ed.lua))
    ed.lua = nil
    clear(&lua_cmds)
    lua_status_ref = lua.NOREF
    script_ed = nil
}

script_load_file :: proc(ed: ^Editor, path: string) {
    if ed.lua == nil || !os.exists(path) {
        return
    }
    L := (^lua.State)(ed.lua)
    cpath := strings.clone_to_cstring(path)
    defer delete(cpath)
    if lua.L_loadfile(L, cpath) != .OK {
        fmt.eprintln("Lua:", lua.tostring(L, -1))
        lua.pop(L, 1)
        return
    }
    if lua.pcall(L, 0, lua.MULTRET, 0) != 0 {
        fmt.eprintln("Lua:", lua.tostring(L, -1))
        lua.pop(L, 1)
    }
}

lua_api_bind :: proc "c" (L: ^lua.State) -> c.int {
    context = script_ctx
    chord := string(lua.L_checkstring(L, 1))
    cmd := string(lua.L_checkstring(L, 2))
    mods, key, ok := parse_chord(chord)
    if !ok {
        lua.L_error(L, "bad chord")
        return 0
    }
    bind_chord(mods, key, cmd)
    return 0
}

lua_api_set :: proc "c" (L: ^lua.State) -> c.int {
    context = script_ctx
    name := string(lua.L_checkstring(L, 1))
    switch name {
        case "tab_width":
        {
            settings.tab_width = max(int(lua.L_checkinteger(L, 2)), 1)
        }
        case "blink_ms":
        {
            settings.blink_ms = max(int(lua.L_checkinteger(L, 2)), 1)
        }
        case "pad_x":
        {
            settings.pad_x = f32(lua.L_checknumber(L, 2))
        }
        case "pad_y":
        {
            settings.pad_y = f32(lua.L_checknumber(L, 2))
        }
        case "split_gap":
        {
            settings.split_gap = max(f32(lua.L_checknumber(L, 2)), 1)
        }
        case "bg":
        {
            r := f32(lua.L_checknumber(L, 2))
            g, b := r, r
            if lua.gettop(L) >= 4 {
                g = f32(lua.L_checknumber(L, 3))
                b = f32(lua.L_checknumber(L, 4))
            }
            settings.bg = lua_read_color(L)
        }
        case "text":            settings.text = lua_read_color(L)
        case "selection":       settings.selection = lua_read_color(L)
        case "caret":           settings.caret = lua_read_color(L)
        case "caret_inactive":  settings.caret_inactive = lua_read_color(L)
        case "gutter":          settings.gutter = lua_read_color(L)
        case "gutter_current":  settings.gutter_current = lua_read_color(L)
        case "divider":         settings.divider = lua_read_color(L)
        case "status_bg":       settings.status_bg = lua_read_color(L)
        case "status_text":     settings.status_text = lua_read_color(L)
        case "overlay_bg":      settings.overlay_bg = lua_read_color(L)
        case "overlay_label":   settings.overlay_label = lua_read_color(L)
        case "overlay_list":    settings.overlay_list = lua_read_color(L)
        case "overlay_sel_fg":  settings.overlay_sel_fg = lua_read_color(L)
        case "ime_preview":     settings.ime_preview = lua_read_color(L)
        case "keyword":         settings.keyword = lua_read_color(L)
        case "comment":         settings.comment = lua_read_color(L)
        case "string":          settings.lit_string = lua_read_color(L)
        case "number":          settings.lit_number = lua_read_color(L)
        case "directive":       settings.directive = lua_read_color(L)
        case "gutter_min_digits":
        {
            settings.gutter_min_digits = max(int(lua.L_checkinteger(L, 2)), 1)
        }
        case "gutter_pad":
        {
            settings.gutter_pad = f32(lua.L_checknumber(L, 2))
        }
        case "status_pad":
        {
            settings.status_pad = f32(lua.L_checknumber(L, 2))
        }
        case "caret_w":
        {
            settings.caret_w = max(f32(lua.L_checknumber(L, 2)), 1)
        }
        case "overlay_width":
        {
            settings.overlay_width = clamp(f32(lua.L_checknumber(L, 2)), 0.1, 1)
        }
        case "scroll_lines":
        {
            settings.scroll_lines = max(f32(lua.L_checknumber(L, 2)), 0.1)
        }
        case "use_tabs":
        {
            settings.use_tabs = bool(lua.toboolean(L, 2))
        }
        case "smart_brackets":
        {
            settings.smart_brackets = bool(lua.toboolean(L, 2))
        }
        case "newline":
        {
            s := strings.to_lower(string(lua.L_checkstring(L, 2)))
            defer delete(s)
            switch s {
            case "crlf", "cr":
                settings.newline = .CRLF
            case:
                settings.newline = .LF
            }
        }
        case "font_size":
        {
            settings.font_size = clamp(int(lua.L_checkinteger(L, 2)), 8, 72)
        }
        case "font_path":
        {
            delete(settings.font_path)
            settings.font_path = strings.clone(string(lua.L_checkstring(L, 2)))
        }
        case "split_t":
        {
            settings.split_t = clamp(f32(lua.L_checknumber(L, 2)), 0.05, 0.95)
        }
        case "overlay_rows":
        {
            settings.overlay_rows = max(int(lua.L_checkinteger(L, 2)), 2)
        }
        case "overlay_pad":
        {
            settings.overlay_pad = max(f32(lua.L_checknumber(L, 2)), 0)
        }
        case "pane_min_w":
        {
            settings.pane_min_w = max(f32(lua.L_checknumber(L, 2)), 1)
        }
        case "pane_min_extra":
        {
            settings.pane_min_extra = max(f32(lua.L_checknumber(L, 2)), 0)
        }
        case "font_fallback":
        {
            delete(settings.font_fallback)
            settings.font_fallback = strings.clone(string(lua.L_checkstring(L, 2)))
        }
        case "tofu":            settings.tofu = lua_read_color(L)
        case "show_gutter":
        {
            settings.show_gutter = bool(lua.toboolean(L, 2))
        }
        case "show_status":
        {
            settings.show_status = bool(lua.toboolean(L, 2))
        }
        case "find_case_sensitive":
        {
            settings.find_case_sensitive = bool(lua.toboolean(L, 2))
        }
        case "scroll_margin":
        {
            settings.scroll_margin = max(f32(lua.L_checknumber(L, 2)), 0)
        }
        case "text_pad_x":
        {
            settings.text_pad_x = max(f32(lua.L_checknumber(L, 2)), 0)
        }
        case "text_pad_y":
        {
            settings.text_pad_y = max(f32(lua.L_checknumber(L, 2)), 0)
        }
        case:
        {
            lua.L_error(L, "unknown setting")
        }
    }
    return 0
}

lua_api_get :: proc "c" (L: ^lua.State) -> c.int {
    context = script_ctx
    name := string(lua.L_checkstring(L, 1))
    switch name {
    case "tab_width":          lua.pushinteger(L, lua.Integer(settings.tab_width)); return 1
    case "blink_ms":           lua.pushinteger(L, lua.Integer(settings.blink_ms)); return 1
    case "pad_x":              lua.pushnumber(L, lua.Number(settings.pad_x)); return 1
    case "pad_y":              lua.pushnumber(L, lua.Number(settings.pad_y)); return 1
    case "split_gap":          lua.pushnumber(L, lua.Number(settings.split_gap)); return 1
    case "bg":                 lua_push_color(L, settings.bg); return 3
    case "text":               lua_push_color(L, settings.text); return 3
    case "selection":          lua_push_color(L, settings.selection); return 3
    case "caret":              lua_push_color(L, settings.caret); return 3
    case "caret_inactive":     lua_push_color(L, settings.caret_inactive); return 3
    case "gutter":             lua_push_color(L, settings.gutter); return 3
    case "gutter_current":     lua_push_color(L, settings.gutter_current); return 3
    case "divider":            lua_push_color(L, settings.divider); return 3
    case "status_bg":          lua_push_color(L, settings.status_bg); return 3
    case "status_text":        lua_push_color(L, settings.status_text); return 3
    case "overlay_bg":         lua_push_color(L, settings.overlay_bg); return 3
    case "overlay_label":      lua_push_color(L, settings.overlay_label); return 3
    case "overlay_list":       lua_push_color(L, settings.overlay_list); return 3
    case "overlay_sel_fg":     lua_push_color(L, settings.overlay_sel_fg); return 3
    case "ime_preview":        lua_push_color(L, settings.ime_preview); return 3
    case "keyword":            lua_push_color(L, settings.keyword); return 3
    case "comment":            lua_push_color(L, settings.comment); return 3
    case "string":             lua_push_color(L, settings.lit_string); return 3
    case "number":             lua_push_color(L, settings.lit_number); return 3
    case "directive":          lua_push_color(L, settings.directive); return 3
    case "gutter_min_digits":  lua.pushinteger(L, lua.Integer(settings.gutter_min_digits)); return 1
    case "gutter_pad":         lua.pushnumber(L, lua.Number(settings.gutter_pad)); return 1
    case "status_pad":         lua.pushnumber(L, lua.Number(settings.status_pad)); return 1
    case "caret_w":            lua.pushnumber(L, lua.Number(settings.caret_w)); return 1
    case "overlay_width":      lua.pushnumber(L, lua.Number(settings.overlay_width)); return 1
    case "scroll_lines":       lua.pushnumber(L, lua.Number(settings.scroll_lines)); return 1
    case "use_tabs":           lua.pushboolean(L, b32(settings.use_tabs)); return 1
    case "smart_brackets":     lua.pushboolean(L, b32(settings.smart_brackets)); return 1
    case "newline":
    {
        s: cstring = "lf"
        if settings.newline == .CRLF {
            s = "crlf"
        }
        lua.pushstring(L, s)
        return 1
    }
    case "font_size":          lua.pushinteger(L, lua.Integer(settings.font_size)); return 1
    case "font_path":
    {
        cs := strings.clone_to_cstring(settings.font_path)
        defer delete(cs)
        lua.pushstring(L, cs)
        return 1
    }
    case "split_t":            lua.pushnumber(L, lua.Number(settings.split_t)); return 1
    case "overlay_rows":       lua.pushinteger(L, lua.Integer(settings.overlay_rows)); return 1
    case "overlay_pad":        lua.pushnumber(L, lua.Number(settings.overlay_pad)); return 1
    case "pane_min_w":         lua.pushnumber(L, lua.Number(settings.pane_min_w)); return 1
    case "pane_min_extra":     lua.pushnumber(L, lua.Number(settings.pane_min_extra)); return 1
    case "font_fallback":
    {
        cs := strings.clone_to_cstring(settings.font_fallback)
        defer delete(cs)
        lua.pushstring(L, cs)
        return 1
    }
    case "tofu":               lua_push_color(L, settings.tofu); return 3
    case "show_gutter":        lua.pushboolean(L, b32(settings.show_gutter)); return 1
    case "show_status":        lua.pushboolean(L, b32(settings.show_status)); return 1
    case "find_case_sensitive": lua.pushboolean(L, b32(settings.find_case_sensitive)); return 1
    case "scroll_margin":      lua.pushnumber(L, lua.Number(settings.scroll_margin)); return 1
    case "text_pad_x": lua.pushnumber(L, lua.Number(settings.text_pad_x)); return 1
    case "text_pad_y": lua.pushnumber(L, lua.Number(settings.text_pad_y)); return 1
    case:
        lua.L_error(L, "unknown setting")
    }
    return 0
}

lua_api_command :: proc "c" (L: ^lua.State) -> c.int {
    context = script_ctx
    name := string(lua.L_checkstring(L, 1))
    if lua.type(L, 2) != .FUNCTION {
        lua.L_error(L, "command expects a function")
        return 0
    }
    lua.pushvalue(L, 2)
    ref := lua.L_ref(L, lua.REGISTRYINDEX)
    if old, exists := lua_cmds[name]; exists {
        lua.L_unref(L, lua.REGISTRYINDEX, old)
    } else {
        name = strings.clone(name)
    }
    lua_cmds[name] = ref
    return 0
}

lua_api_run :: proc "c" (L: ^lua.State) -> c.int {
    context = script_ctx
    if script_ed == nil {
        return 0
    }
    name := string(lua.L_checkstring(L, 1))
    if p, ok := commands[name]; ok {
        p(script_ed)
        return 0
    }
    if script_run_command(script_ed, name) {
        return 0
    }
    lua.L_error(L, "unknown command")
    return 0
}

lua_api_unbind :: proc "c" (L: ^lua.State) -> c.int {
    context = script_ctx
    chord := string(lua.L_checkstring(L, 1))
    mods, key, ok := parse_chord(chord)
    if !ok {
        lua.L_error(L, "bad chord")
        return 0
    }
    unbind_chord(mods, key)
    return 0
}

lua_read_color :: proc(L: ^lua.State) -> [4]f32 {
    r := f32(lua.L_checknumber(L, 2))
    g, b := r, r
    if lua.gettop(L) >= 4 {
        g = f32(lua.L_checknumber(L, 3))
        b = f32(lua.L_checknumber(L, 4))
    }
    return {r / 255.0, g / 255.0, b / 255.0, 1.0}
}

parse_chord :: proc(s: string) -> (mods: platform.Mods, key: platform.Key, ok: bool) {
    lower := strings.to_lower(s)
    defer delete(lower)
    parts := strings.split(lower, "+")
    defer delete(parts)
    if len(parts) == 0 {
        return
    }
    for p in parts[:len(parts) - 1] {
        switch p {
            case "ctrl", "control": mods += {.Ctrl}
            case "shift":           mods += {.Shift}
            case "alt":             mods += {.Alt}
            case:                   return
        }
    }
    key, ok = key_from_name(parts[len(parts) - 1])
    return
}

key_from_name :: proc(name: string) -> (platform.Key, bool) {
    if len(name) == 1 {
        c := name[0]
        if c >= 'a' && c <= 'z' {
            return platform.Key(int(platform.Key.A) + int(c - 'a')), true
        }
        if c >= '0' && c <= '9' {
            return platform.Key(int(platform.Key.Digit_0) + int(c - '0')), true
        }
        switch c {
            case '-': return .Minus, true
            case '=': return .Equal, true
            case ',': return .Comma, true
            case '.': return .Period, true
            case '/': return .Slash, true
            case ';': return .Semicolon, true
            case '\'': return .Apostrophe, true
            case '[': return .LBracket, true
            case ']': return .RBracket, true
            case '`': return .Grave, true
        }
    }
    switch name {
        case "left":                return .Left, true
        case "right":               return .Right, true
        case "up":                  return .Up, true
        case "down":                return .Down, true
        case "enter":               return .Enter, true
        case "backspace":           return .Backspace, true
        case "escape", "esc":       return .Escape, true
        case "tab":                 return .Tab, true
        case "home":                return .Home, true
        case "end":                 return .End, true
        case "delete":              return .Delete, true
        case "page_up":             return .Page_Up, true
        case "page_down":           return .Page_Down, true
        case "backslash":           return .Backslash, true
        case "space":               return .Space, true
        case "insert":              return .Insert, true
        case "minus":               return .Minus, true
        case "equal":               return .Equal, true
        case "comma":               return .Comma, true
        case "period":              return .Period, true
        case "slash":               return .Slash, true
        case "semicolon":           return .Semicolon, true
        case "apostrophe", "quote": return .Apostrophe, true
        case "lbracket":            return .LBracket, true
        case "rbracket":            return .RBracket, true
        case "grave", "backtick":   return .Grave, true
        case "f1":                  return .F1, true
        case "f2":                  return .F2, true
        case "f3":                  return .F3, true
        case "f4":                  return .F4, true
        case "f5":                  return .F5, true
        case "f6":                  return .F6, true
        case "f7":                  return .F7, true
        case "f8":                  return .F8, true
        case "f9":                  return .F9, true
        case "f10":                 return .F10, true
        case "f11":                 return .F11, true
        case "f12":                 return .F12, true
    }
    return .Unknown, false
}

script_run_command :: proc(ed: ^Editor, name: string) -> bool {
    ref, ok := lua_cmds[name]
    if !ok || ed.lua == nil {
        return false
    }
    prev := script_ed
    script_ed = ed
    defer script_ed = prev

    L := (^lua.State)(ed.lua)
    lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(ref))
    if lua.pcall(L, 0, 0, 0) != 0 {
        fmt.eprintln("Lua:", lua.tostring(L, -1))
        lua.pop(L, 1)
    }
    return true
}

script_set_package_path :: proc(L: ^lua.State, dir: string) {
    slash, _ := strings.replace_all(dir, "\\", "/")
    defer delete(slash)
    lua.getglobal(L, "package")
    lua.getfield(L, -1, "path")
    old := string(lua.tostring(L, -1))
    lua.pop(L, 1)
    joined := fmt.tprintf("%s/?.lua;%s/?/init.lua;%s", slash, slash, old)
    cpath := strings.clone_to_cstring(joined)
    defer delete(cpath)
    lua.pushstring(L, cpath)
    lua.setfield(L, -2, "path")
    lua.pop(L, 1)
}

lua_api_hook :: proc "c" (L: ^lua.State) -> c.int {
    context = script_ctx
    kind := string(lua.L_checkstring(L, 1))
    if kind != "save" && kind != "open" && kind != "change" {
        lua.L_error(L, "hook must be save, open, or change")
        return 0
    }
    if lua.type(L, 2) != .FUNCTION {
        lua.L_error(L, "hook expects a function")
        return 0
    }
    lua.pushvalue(L, 2)
    ref := lua.L_ref(L, lua.REGISTRYINDEX)
    list := lua_hooks[kind]
    append(&list, ref)
    lua_hooks[kind] = list
    return 0
}

script_run_hooks :: proc(ed: ^Editor, kind, path: string) {
    list := lua_hooks[kind]
    if len(list) == 0 || ed.lua == nil {
        return
    }
    prev := script_ed
    script_ed = ed
    defer script_ed = prev
    L := (^lua.State)(ed.lua)
    cpath := strings.clone_to_cstring(path)
    defer delete(cpath)
    for ref in list {
        lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(ref))
        lua.pushstring(L, cpath)
        if lua.pcall(L, 1, 0, 0) != 0 {
            fmt.eprintln("Lua:", lua.tostring(L, -1))
            lua.pop(L, 1)
        }
    }
}

lua_push_color :: proc(L: ^lua.State, col: [4]f32) {
    lua.pushinteger(L, lua.Integer(col.r * 255.0 + 0.5))
    lua.pushinteger(L, lua.Integer(col.g * 255.0 + 0.5))
    lua.pushinteger(L, lua.Integer(col.b * 255.0 + 0.5))
}

lua_api_status :: proc "c" (L: ^lua.State) -> c.int {
    context = script_ctx
    if lua.type(L, 1) != .FUNCTION {
        lua.L_error(L, "status expects a function")
        return 0
    }
    if lua_status_ref != lua.NOREF {
        lua.L_unref(L, lua.REGISTRYINDEX, lua_status_ref)
    }
    lua.pushvalue(L, 1)
    lua_status_ref = lua.L_ref(L, lua.REGISTRYINDEX)
    return 0
}

script_status_line :: proc(ed: ^Editor) -> (left, right: string, ok: bool) {
    if lua_status_ref == lua.NOREF || ed.lua == nil {
        return
    }
    L := (^lua.State)(ed.lua)
    lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(lua_status_ref))
    if lua.pcall(L, 0, 2, 0) != 0 {
        fmt.eprintln("Lua:", lua.tostring(L, -1))
        lua.pop(L, 1)
        return
    }
    lua.gc(L, .STEP, 200)
    left = strings.clone(string(lua.tostring(L, -2)), context.temp_allocator)
    right = strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
    lua.pop(L, 2)
    ok = true
    return
}

script_reload :: proc(ed: ^Editor) {
    if ed.lua == nil {
        return
    }
    L := (^lua.State)(ed.lua)

    lua.settop(L, 0)

    for name, ref in lua_cmds {
        lua.L_unref(L, lua.REGISTRYINDEX, ref)
        delete(name)
    }
    clear(&lua_cmds)

    for kind, list in lua_hooks {
        for ref in list {
            lua.L_unref(L, lua.REGISTRYINDEX, ref)
        }
        list := list
        clear(&list)
        lua_hooks[kind] = list
    }

    if lua_status_ref != lua.NOREF {
        lua.L_unref(L, lua.REGISTRYINDEX, lua_status_ref)
        lua_status_ref = lua.NOREF
    }

    for _, s in keymap {
        delete(s)
    }
    clear(&keymap)
    bind_default_keys()

    delete(settings.font_path)
    delete(settings.font_fallback)
    settings = settings_defaults

    lua.settop(L, 0)
    lua.pushstring(L, lua.LOADED_TABLE)
    lua.newtable(L)
    lua.rawset(L, lua.REGISTRYINDEX)
    lua.getglobal(L, "package")
    lua.getfield(L, lua.REGISTRYINDEX, lua.LOADED_TABLE)
    lua.setfield(L, -2, "loaded")
    lua.pop(L, 1)

    path, ok := script_init_path()
    if ok {
        defer delete(path)
        script_load_file(ed, path)
    }
    b := active_buffer(ed)
    if len(b.path) == 0 {
        b.newline = settings.newline
    }
    ed.split_t = settings.split_t
    lex_load_all()
    for &buf in ed.buffers {
        buf.lex_id = lex_index_from_path(buf.path)
        buf.lex_dirty = true
    }
    ed.font_dirty = true
}