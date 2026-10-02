package editor

import "../text"
import "../platform"

Undo_Kind :: enum {
    Insert,
    Delete
}

Undo_Op :: struct {
    kind: Undo_Kind,
    pos: int,
    text: string
}

Editor :: struct {
    doc:            text.Buffer,
    cursor:         int,
    sel_anchor:     int,
    desired_col:    int,
    scroll_y:       f32,
    undo:           [dynamic]Undo_Op,
    undo_head:      int,
    playing:        bool,
    path:           string,
    host:           ^platform.Window,
    page_lines:     int,
    dirty:          bool
}

editor_init :: proc(ed: ^Editor, starter: string) {
    text.buffer_init(&ed.doc, 4096)
    text.buffer_insert(&ed.doc, 0, starter)
    ed.cursor = text.buffer_len(&ed.doc)
    ed.sel_anchor = ed.cursor
    ed.desired_col = sync_col(ed)
    ed.undo = make([dynamic]Undo_Op)
    ed.undo_head = 0
}

editor_destroy :: proc(ed: ^Editor) {
    text.buffer_destroy(&ed.doc)
    for op in ed.undo {
        delete(op.text)
    }
    delete(ed.undo)
    delete(ed.path)
    ed^ = {}
}

sync_col :: proc(ed: ^Editor) -> int {
    line := text.buffer_line_at(&ed.doc, ed.cursor)
    return ed.cursor - text.buffer_line_start(&ed.doc, line)
}

selection_range :: proc(ed: ^Editor) -> (lo, hi: int) {
    lo = min(ed.cursor, ed.sel_anchor)
    hi = max(ed.cursor, ed.sel_anchor)
    return
}

has_selection :: proc(ed: ^Editor) -> bool {
    return ed.cursor != ed.sel_anchor
}

set_cursor :: proc(ed: ^Editor, pos: int, keep_sel: bool) {
    ed.cursor = clamp(pos, 0, text.buffer_len(&ed.doc))
    if !keep_sel {
        ed.sel_anchor = ed.cursor
    }
    ed.desired_col = sync_col(ed)
}

click_at :: proc(ed: ^Editor, pos: int) {
    set_cursor(ed, pos, false)
}

drag_to :: proc(ed: ^Editor, pos: int) {
    set_cursor(ed, pos, true)
}

scroll_by :: proc(ed: ^Editor, dy, max_y: f32) {
	ed.scroll_y = clamp(ed.scroll_y + dy, 0, max(max_y, 0))
}

ensure_cursor_visible :: proc(ed: ^Editor, origin_y, line_h, view_h, content_h: f32) {
	if line_h <= 0 {
		return
	}
	line := text.buffer_line_at(&ed.doc, ed.cursor)
	screen_y := origin_y + f32(line) * line_h - ed.scroll_y
	pad := line_h
	if screen_y < origin_y {
		ed.scroll_y += screen_y - origin_y
	} else if screen_y + line_h > view_h - pad {
		ed.scroll_y += screen_y + line_h - (view_h - pad)
	}
	ed.scroll_y = clamp(ed.scroll_y, 0, max(content_h, 0))
}