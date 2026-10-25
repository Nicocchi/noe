package editor

import "core:strings"
import "../platform"

Chord :: struct {
    mods: platform.Mods,
    key: platform.Key
}

keymap: map[Chord]string

bind_key :: proc(key: platform.Key, command: string) {
    bind_chord({}, key, command)
}

bind_chord :: proc(mods: platform.Mods, key: platform.Key, command: string) {
    chord := Chord{mods, key}
    if old, ok := keymap[chord]; ok {
        delete(old)
    }
    keymap[chord] = strings.clone(command)
}

unbind_chord :: proc(mods: platform.Mods, key: platform.Key) {
    chord := Chord{mods, key}
    if old, ok := keymap[chord]; ok {
        delete(old)
        delete_key(&keymap, chord)
    }
}

lookup_key :: proc(key: platform.Key, mods: platform.Mods) -> (string, bool) {
    if name, ok := keymap[Chord{mods, key}]; ok {
        return name, true
    }
    if mods != {} {
        return keymap[Chord{{}, key}]
    }
    return "", false
}

bind_default_keys :: proc() {
    if keymap == nil {
        keymap = make(map[Chord]string)
    }
    bind_key(.Left,      "cursor_left")
	bind_key(.Right,     "cursor_right")
	bind_key(.Up,        "cursor_up")
	bind_key(.Down,      "cursor_down")
	bind_key(.Backspace, "delete_backward")
	bind_key(.Enter,     "insert_newline")
    bind_chord({.Ctrl}, .Left,  "cursor_word_left")
	bind_chord({.Ctrl}, .Right, "cursor_word_right")
    bind_chord({.Ctrl}, .Z, "undo")
    bind_chord({.Ctrl}, .Y, "redo")
    bind_chord({.Ctrl, .Shift}, .Z, "redo")
    bind_chord({.Ctrl}, .O, "file_open")
    bind_chord({.Ctrl}, .S, "file_save")
    bind_chord({.Ctrl, .Shift}, .S, "file_save_as")
    bind_chord({.Ctrl}, .C, "edit_copy")
    bind_chord({.Ctrl}, .X, "edit_cut")
    bind_chord({.Ctrl}, .V, "edit_paste")
    bind_chord({.Shift}, .Left,  "select_left")
    bind_chord({.Shift}, .Right, "select_right")
    bind_chord({.Shift}, .Up,    "select_up")
    bind_chord({.Shift}, .Down,  "select_down")
    bind_chord({.Ctrl, .Shift}, .Left,  "select_word_left")
    bind_chord({.Ctrl, .Shift}, .Right, "select_word_right")
    bind_key(.Home,     "cursor_home")
    bind_key(.End,      "cursor_end")
    bind_key(.Delete,   "delete_forward")
    bind_key(.Page_Up,  "cursor_page_up")
    bind_key(.Page_Down,"cursor_page_down")
    bind_chord({.Shift}, .Home,      "select_home")
    bind_chord({.Shift}, .End,       "select_end")
    bind_chord({.Shift}, .Page_Up,   "select_page_up")
    bind_chord({.Shift}, .Page_Down, "select_page_down")
    bind_chord({.Ctrl}, .Home,      "cursor_doc_home")
    bind_chord({.Ctrl}, .End,       "cursor_doc_end")
    bind_chord({.Ctrl, .Shift}, .Home, "select_doc_home")
    bind_chord({.Ctrl, .Shift}, .End,  "select_doc_end")
    bind_key(.Tab, "indent")
    bind_chord({.Shift}, .Tab, "dedent")
    bind_chord({.Ctrl}, .F, "find")
    bind_chord({.Ctrl}, .Backslash, "view_next")
    bind_chord({.Ctrl}, .H, "view_left")
    bind_chord({.Ctrl}, .L, "view_right")
    bind_chord({.Ctrl}, .P, "buffer_switcher")
    bind_chord({.Ctrl}, .A, "select_all")
    bind_chord({.Ctrl}, .D, "add_next_match")
    bind_key(.Escape, "carets_clear")
    bind_chord({.Ctrl, .Shift}, .R,  "reload_config")
    bind_chord({.Ctrl, .Shift}, .P, "file_finder")
    bind_chord({.Ctrl}, .N, "file_new")
}