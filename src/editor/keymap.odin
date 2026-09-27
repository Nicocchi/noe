package editor

import "../platform"

Chord :: struct {
    mods: platform.Mods,
    key: platform.Key
}

keymap: map[Chord]string

bind_key :: proc(key: platform.Key, command: string) {
    keymap[Chord{{}, key}] = command
}

bind_chord :: proc(mods: platform.Mods, key: platform.Key, command: string) {
    keymap[Chord{mods, key}] = command
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
}