package editor

import "../text"
import "../platform"

Undo_Kind :: enum {
    Insert,
    Delete
}

Undo_Op :: struct {
    kind:   Undo_Kind,
    pos:    int,
    text:   string,
    group:   int
}

Overlay_Kind :: enum {
    None,
    Find,
    Switcher
}

Overlay :: struct {
    kind:   Overlay_Kind,
    text:   [dynamic]u8,
    cursor: int,
    sel:    int
}

Buffer :: struct {
    doc:        text.Buffer,
    undo:       [dynamic]Undo_Op,
    undo_head:  int,
    playing:    bool,
    undo_group: int,
    edit_depth: int,
    path:       string,
    dirty:      bool,
    max_scroll_x:   f32,
    scroll_x_dirty: bool
}

View :: struct {
    buf_id:         int,
    cursor:         int,
    sel_anchor:     int,
    desired_col:    int,
    scroll_x:       f32,
    scroll_y:       f32,
    page_lines:     int
}

Editor :: struct {
    buffers:        [dynamic]Buffer,
    views:          [dynamic]View,
    active_view:    int,
    host:           ^platform.Window,
    overlay:        Overlay,
    eat_mouse:      bool
}

active_view :: proc(ed: ^Editor) -> ^View {
    return &ed.views[ed.active_view]
}

active_buffer :: proc(ed: ^Editor) -> ^Buffer {
    v := active_view(ed)
    return &ed.buffers[v.buf_id]
}

editor_init :: proc(ed: ^Editor, starter: string) {
    ed.buffers = make([dynamic]Buffer)
    ed.views = make([dynamic]View)
    append(&ed.buffers, Buffer{})
    append(&ed.views, View{buf_id = 0})
    ed.active_view = 0
    ed.overlay.text = make([dynamic]u8)

    b := active_buffer(ed)
    v := active_view(ed)
    text.buffer_init(&b.doc, 4096)
    text.buffer_insert(&b.doc, 0, starter)
    b.undo = make([dynamic]Undo_Op)
    b.scroll_x_dirty = true
    v.cursor = text.buffer_len(&b.doc)
    v.sel_anchor = v.cursor
    v.desired_col = sync_col(ed)
}

editor_destroy :: proc(ed: ^Editor) {
    for &b in ed.buffers {
        text.buffer_destroy(&b.doc)
        for op in b.undo {
            delete(op.text)
        }
        delete(b.undo)
        delete(b.path)
    }
    delete(ed.buffers)
    delete(ed.views)
    delete(ed.overlay.text)
    ed^ = {}
}

sync_col :: proc(ed: ^Editor) -> int {
    v := active_view(ed)
    b := active_buffer(ed)
    line := text.buffer_line_at(&b.doc, v.cursor)
    return v.cursor - text.buffer_line_start(&b.doc, line)
}

selection_range :: proc(ed: ^Editor) -> (lo, hi: int) {
    v := active_view(ed)
    lo = min(v.cursor, v.sel_anchor)
    hi = max(v.cursor, v.sel_anchor)
    return
}

has_selection :: proc(ed: ^Editor) -> bool {
    v := active_view(ed)
    return v.cursor != v.sel_anchor
}

set_cursor :: proc(ed: ^Editor, pos: int, keep_sel: bool) {
    v := active_view(ed)
    b := active_buffer(ed)
    v.cursor = clamp(pos, 0, text.buffer_len(&b.doc))
    if !keep_sel {
        v.sel_anchor = v.cursor
    }
    v.desired_col = sync_col(ed)
}

click_at :: proc(ed: ^Editor, pos: int) {
    set_cursor(ed, pos, false)
}

drag_to :: proc(ed: ^Editor, pos: int) {
    set_cursor(ed, pos, true)
}

scroll_by :: proc(ed: ^Editor, dy, max_y: f32) {
    v := active_view(ed)
	v.scroll_y = clamp(v.scroll_y + dy, 0, max(max_y, 0))
}

scroll_by_x :: proc(ed: ^Editor, dx, max_x: f32) {
    v := active_view(ed)
	v.scroll_x = clamp(v.scroll_x + dx, 0, max(max_x, 0))
}

ensure_cursor_visible :: proc(ed: ^Editor, origin_x, origin_y, caret_x, line_h, view_w, view_h, max_x, max_y: f32) {
    v := active_view(ed)
    b := active_buffer(ed)
	if line_h <= 0 || view_w <= 0 || view_h <= 0 {
        return
    }
	line := text.buffer_line_at(&b.doc, v.cursor)
	screen_y := origin_y + f32(line) * line_h - v.scroll_y
	pad := line_h
	if screen_y < origin_y {
	    v.scroll_y += screen_y - origin_y
    } else if screen_y + line_h > origin_y + view_h - pad {
        v.scroll_y += screen_y + line_h - (origin_y + view_h - pad)
    }
    v.scroll_y = clamp(v.scroll_y, 0, max(max_y, 0))
    screen_x := origin_x + caret_x - v.scroll_x
    if screen_x < origin_x {
        v.scroll_x += screen_x - origin_x
    } else if screen_x + 2 > origin_x + view_w - pad {
        v.scroll_x += screen_x + 2 - (origin_x + view_w - pad)
    }
    v.scroll_x = clamp(v.scroll_x, 0, max(max_x, 0))
}

view_nudge :: proc(ed: ^Editor, buf_id, at, delta: int) {
    for i in 0 ..< len(ed.views) {
        if i == ed.active_view {
            continue
        }
        nv := &ed.views[i]
        if nv.buf_id != buf_id {
            continue
        }
        if nv.cursor >= at {
            nv.cursor = max(nv.cursor + delta, at)
        }
        if nv.sel_anchor >= at {
            nv.sel_anchor = max(nv.sel_anchor + delta, at)
        }
    }
}