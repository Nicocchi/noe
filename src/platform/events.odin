package platform

EVENT_CAP :: 64

Key :: enum {
    Unknown,
    Backspace,
    Escape,
    Left,
    Right,
    Up,
    Down,
    Enter,
    Home,
    End,
    Delete,
    Page_Up,
    Page_Down,
    Tab,
    Z,
    Y,
    O,
    S,
    C,
    X,
    V,
    F,
    P
}

Text_Event :: struct {
    ch: rune
}

Mod :: enum {
    Ctrl,
    Shift,
    Alt
}

Mods :: bit_set[Mod]

Key_Event :: struct {
    key: Key,
    mods: Mods
}

IME_Commit_Event :: struct {
    text:   [256]u8,
    len:    int
}

Mouse_Button :: enum {
    Left,
    Right,
    Middle
}

Mouse_Action :: enum {
    Down,
    Up,
    Move
}

Mouse_Event :: struct {
    x, y:   f32,
    button: Mouse_Button,
    action: Mouse_Action,
    mods:   Mods
}

Scroll_Event :: struct {
    notches:    f32,
    mods:       Mods
}

Event :: union {
    Text_Event,
    Key_Event,
    IME_Commit_Event,
    Mouse_Event,
    Scroll_Event
}

event_push :: proc(w: ^Window, ev: Event) {
    if w == nil || w.event_count >= EVENT_CAP {
        return
    }

    w.needs_redraw = true

    w.events[w.event_count] = ev
    w.event_count += 1
}

events_clear :: proc(w: ^Window) {
    w.event_count = 0
}