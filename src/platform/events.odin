package platform

EVENT_CAP :: 64

Key :: enum {
    Unknown,
    Backspace,
    Left,
    Right,
    Up,
    Down,
    Enter
}

Text_Event :: struct {
    ch: rune
}

Key_Event :: struct {
    key: Key
}

IME_Commit_Event :: struct {
    text:   [256]u8,
    len:    int
}

Event :: union {
    Text_Event,
    Key_Event,
    IME_Commit_Event
}

event_push :: proc(w: ^Window, ev: Event) {
    if w == nil || w.event_count >= EVENT_CAP {
        return
    }

    w.events[w.event_count] = ev
    w.event_count += 1
}

events_clear :: proc(w: ^Window) {
    w.event_count = 0
}