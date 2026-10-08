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
    Backslash,
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,
    Space,
    Insert,
    Digit_0,
    Digit_1,
    Digit_2,
    Digit_3,
    Digit_4,
    Digit_5,
    Digit_6,
    Digit_7,
    Digit_8,
    Digit_9,
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
    Minus,
    Equal,
    Comma,
    Period,
    Slash,
    Semicolon,
    Apostrophe,
    LBracket,
    RBracket,
    Grave,
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