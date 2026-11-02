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
    group:  int,
    before: []Caret,
    after:  []Caret
}

Overlay_Kind :: enum {
    None,
    Find,
    Switcher,
    Files,
    New_File
}

Overlay :: struct {
    kind:           Overlay_Kind,
    text:           [dynamic]u8,
    cursor:         int,
    sel:            int,
    scroll:         int,
    files:          [dynamic]string,
    entry_dir:	  [dynamic]bool,
    root:           string,
    browse: 		string,
    preview:        []u8,
    preview_tokens: [dynamic]Token,
    preview_path:   string,
    preview_sel:    int,
    rename_from:	string
}

Newline :: enum {
    LF,
    CRLF
}

Buffer :: struct {
    doc:            text.Buffer,
    undo:           [dynamic]Undo_Op,
    undo_head:      int,
    playing:        bool,
    undo_group:     int,
    edit_depth:     int,
    path:           string,
    dirty:          bool,
    newline:        Newline,
    max_scroll_x:   f32,
    scroll_x_dirty: bool,
    typing:         bool,
    pending_before: []Caret,
    tokens:         [dynamic]Token,
    lex_dirty:      bool,
    lex_id:         int
}

Caret :: struct {
    cursor:         int,
    sel_anchor:     int,
    desired_col:    int
}

View :: struct {
    buf_id:         int,
    cursor:         int,
    sel_anchor:     int,
    desired_col:    int,
    scroll_x:       f32,
    scroll_y:       f32,
    page_lines:     int,
    extras:         [dynamic]Caret,
    brace_cursor:   int,
    brace_doc_len: int,
    brace_toks:     int,
    brace_n:        int,
    brace_open:     [16]int,
    brace_close:    [16]int
}

Project_Cmd :: struct {
	name: string,
	cmd:  string
}

Project :: struct {
	loaded:	 bool,
	dir:		string,
	name:	   string,
	patterns:   [dynamic]string,
	blacklist:  [dynamic]string,
	commands:   [dynamic]Project_Cmd,
	fkey:	   [12]string
}

Editor :: struct {
    buffers:        [dynamic]Buffer,
    views:          [dynamic]View,
    active_view:    int,
    host:           ^platform.Window,
    overlay:        Overlay,
    eat_mouse:      bool,
    split_t:        f32,
    lua:            rawptr,
    font_dirty:     bool,
    project:		Project,
    window_chord:   bool,
    eat_text:       bool
}

Settings :: struct {
    tab_width:              int,
    blink_ms:               int,
    pad_x:                  f32,
    pad_y:                  f32,
    split_gap:              f32,
    bg:                     [4]f32,
    text:                   [4]f32,
    selection:              [4]f32,
    caret:                  [4]f32,
    caret_inactive:         [4]f32,
    gutter:                 [4]f32,
    gutter_current:         [4]f32,
    divider:                [4]f32,
    status_bg:              [4]f32,
    status_text:            [4]f32,
    overlay_bg:             [4]f32,
    overlay_label:          [4]f32,
    overlay_list:           [4]f32,
    overlay_sel_fg:         [4]f32,
    overlay_sel_bg:		 [4]f32,
    ime_preview:            [4]f32,
    keyword:                [4]f32,
    comment:                [4]f32,
    lit_string:             [4]f32,
    lit_number:             [4]f32,
    operator:               [4]f32,
    directive:              [4]f32,
    current_line:           [4]f32,
    function_name:		  [4]f32,
    type_name:			  [4]f32,
    gutter_min_digits:      int,
    gutter_pad:             f32,
    status_pad:             f32,
    caret_w:                f32,
    overlay_width:          f32,
    scroll_lines:           f32,
    use_tabs:               bool,
    newline:                Newline,
    smart_brackets:         bool,
    font_size:              int,
    font_path:              string,
    split_t:                f32,
    overlay_rows:           int,
    overlay_pad:            f32,
    overlay_border:		    f32,
    overlay_border_color:   [4]f32,
    overlay_gap:            f32,
    pane_min_w:             f32,
    pane_min_extra:         f32,
    font_fallback:          string,
    tofu:                   [4]f32,
    show_gutter:            bool,
    show_status:            bool,
    show_brace_header:      bool,
    find_case_sensitive:    bool,
    scroll_margin:          f32,
    text_pad_x:             f32,
    text_pad_y:             f32,
    show_brace_guides:      bool,
    brace_guide:            [4]f32
}

settings_defaults := Settings{
    tab_width           = 4,
    blink_ms            = 530,
    pad_x               = 12,
    pad_y               = 0,
    split_gap           = 6,
    bg                  = {35.0 / 255.0, 35.0 / 255.0, 35.0 / 255.0, 1.0},
    text                = {0.90, 0.90, 0.90, 1.0},
    selection           = {0.25, 0.40, 0.62, 1.0},
    caret               = {0.90, 0.90, 0.90, 1.0},
    caret_inactive      = {0.45, 0.45, 0.45, 1.0},
    gutter              = {0.50, 0.50, 0.50, 1.0},
    gutter_current      = {0.80, 0.80, 0.80, 1.0},
    divider             = {0.45, 0.45, 0.48, 1.0},
    status_bg           = {0.22, 0.22, 0.22, 1.0},
    status_text         = {0.75, 0.75, 0.75, 1.0},
    overlay_bg          = {0.16, 0.16, 0.18, 1.0},
    overlay_label       = {0.70, 0.80, 0.95, 1.0},
    overlay_list        = {0.70, 0.70, 0.70, 1.0},
    overlay_sel_fg      = {0.95, 0.95, 0.95, 1.0},
    overlay_sel_bg      = {0.25, 0.40, 0.62, 1.0},
    ime_preview         = {0.70, 0.85, 1.00, 1.0},
    keyword             = {0.34, 0.61, 0.84, 1.0},
    comment             = {0.42, 0.60, 0.33, 1.0},
    lit_string          = {0.81, 0.57, 0.47, 1.0},
    lit_number          = {0.71, 0.81, 0.66, 1.0},
    operator            = {212.0 / 255.0, 212.0 / 255.0, 170.0 / 255.0, 1.0},
    directive           = {0.78, 0.54, 0.90, 1.0},
    function_name       = {220.0 / 255.0, 220.0 / 255.0, 170.0 / 255.0, 1.0},
    type_name           = {78.0 / 255.0, 201.0 / 255.0, 176.0 / 255.0, 1.0},
	current_line        = {55.0 / 255.0, 55.0 / 255.0, 58.0 / 255.0, 1.0},
    gutter_min_digits   = 3,
    gutter_pad          = 12,
    status_pad          = 8,
    caret_w             = 2,
    overlay_width       = 0.6,
    scroll_lines        = 3,
    use_tabs            = true,
    newline             = .LF,
    smart_brackets      = true,
    font_size           = 18,
    font_path           = "",
    split_t              = 0.5,
    overlay_rows         = 8,
    overlay_pad          = 8,
    overlay_border       = 1,
    overlay_border_color = {0.40, 0.40, 0.45, 1.0},
    overlay_gap          = 6,
    pane_min_w           = 64,
    pane_min_extra       = 48,
    font_fallback        = "",
    tofu                 = {0.55, 0.55, 0.55, 1.0},
    show_gutter          = true,
    show_status          = true,
    show_brace_header    = true,
    find_case_sensitive  = true,
    scroll_margin        = 1,
    text_pad_x           = 8,
    text_pad_y           = 8,
    show_brace_guides    = true,
    brace_guide          = {0.40, 0.40, 0.44, 1.0}
}

settings := settings_defaults

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
    ed.split_t = settings.split_t
    ed.overlay.text = make([dynamic]u8)

    b := active_buffer(ed)
    v := active_view(ed)
    text.buffer_init(&b.doc, 4096)
    text.buffer_insert(&b.doc, 0, starter)
    b.undo = make([dynamic]Undo_Op)
    b.scroll_x_dirty = true
    b.lex_id = lex_index_named("odin")
    b.lex_dirty = true
    v.cursor = text.buffer_len(&b.doc)
    v.sel_anchor = v.cursor
    v.desired_col = sync_col(ed)
}

editor_destroy :: proc(ed: ^Editor) {
    for &b in ed.buffers {
        text.buffer_destroy(&b.doc)
        for op in b.undo {
            delete(op.text)
            delete(op.before)
            delete(op.after)
        }
        delete(b.undo)
        delete(b.pending_before)
        delete(b.path)
        delete(b.tokens)
    }
    delete(ed.buffers)
    for &v in ed.views {
        delete(v.extras)
    }
    delete(ed.views)
    delete(ed.overlay.text)
    picker_clear(ed)
    project_clear(ed)
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

caret_range :: proc(c: Caret) -> (lo, hi: int) {
    return min(c.cursor, c.sel_anchor), max(c.cursor, c.sel_anchor)
}

caret_shift :: proc(c: ^Caret, at, delta: int) {
    if c.cursor >= at {
        c.cursor = max(c.cursor + delta, at)
    }
    if c.sel_anchor >= at {
        c.sel_anchor = max(c.sel_anchor + delta, at)
    }
}

caret_clear :: proc(ed: ^Editor) {
    clear(&active_view(ed).extras)
}

caret_snapshot :: proc(ed: ^Editor) -> []Caret {
    v := active_view(ed)
    out := make([]Caret, 1 + len(v.extras))
    out[0] = Caret{v.cursor, v.sel_anchor, v.desired_col}
    for e, i in v.extras {
        out[i + 1] = e
    }
    return out
}

caret_restore :: proc(ed: ^Editor, cs: []Caret) {
    if len(cs) == 0 {
        return
    }
    v := active_view(ed)
    b := active_buffer(ed)
    n := text.buffer_len(&b.doc)
    v.cursor = clamp(cs[0].cursor, 0, n)
    v.sel_anchor = clamp(cs[0].sel_anchor, 0, n)
    v.desired_col = cs[0].desired_col
    clear(&v.extras)
    for c in cs[1:] {
        e := c
        e.cursor = clamp(e.cursor, 0, n)
        e.sel_anchor = clamp(e.sel_anchor, 0, n)
        append(&v.extras, e)
    }
}

has_selection :: proc(ed: ^Editor) -> bool {
    v := active_view(ed)
    return v.cursor != v.sel_anchor
}

set_cursor :: proc(ed: ^Editor, pos: int, keep_sel: bool) {
    v := active_view(ed)
    b := active_buffer(ed)
    clear(&v.extras)
    v.cursor = clamp(pos, 0, text.buffer_len(&b.doc))
    if !keep_sel {
        v.sel_anchor = v.cursor
    }
    v.desired_col = sync_col(ed)
    if b.edit_depth == 0 {
        b.typing = false
    }
}

click_at :: proc(ed: ^Editor, pos: int) {
    set_cursor(ed, pos, false)
}

select_word_at :: proc(ed: ^Editor, pos: int) {
	lo, hi := word_range_at(ed, pos)
	if lo == hi {
		click_at(ed, pos)
		return
	}
	b := active_buffer(ed)
	r, _ := text.buffer_peek_rune(&b.doc, lo)
	if !is_word(r) {
		click_at(ed, pos)
		return
	}
	v := active_view(ed)
	v.sel_anchor = lo
	set_cursor(ed, hi, true)
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
	pad := line_h * settings.scroll_margin
	if screen_y < origin_y + pad {
	    v.scroll_y += screen_y - (origin_y + pad)
    } else if screen_y + line_h > origin_y + view_h - pad {
        v.scroll_y += screen_y + line_h - (origin_y + view_h - pad)
    }
    v.scroll_y = clamp(v.scroll_y, 0, max(max_y, 0))
    screen_x := origin_x + caret_x - v.scroll_x
    if screen_x < origin_x + pad {
        v.scroll_x += screen_x - (origin_x + pad)
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

        for &e in nv.extras {
            if e.cursor >= at {
                e.cursor = max(e.cursor + delta, at)
            }
            if e.sel_anchor >= at {
                e.sel_anchor = max(e.sel_anchor + delta, at)
            }
        }
    }
}
