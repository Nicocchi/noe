package editor

import "core:os"
import "core:strings"
import "core:fmt"
import "../text"
import "../platform"

editor_set_path :: proc(ed: ^Editor, path: string) {
    b := active_buffer(ed)
    delete(b.path)
    b.path = strings.clone(path)
    b.lex_id = lex_index_from_path(b.path)
    b.lex_dirty = true
}

editor_load_path :: proc(ed: ^Editor, path: string) -> bool {
    data, err := os.read_entire_file(path, context.allocator)
    if err != nil {
        return false
    }
    defer delete(data)

    nl: Newline = .LF
    for ch in data {
        if ch == '\r' {
            nl = .CRLF
            break
        }
    }
    n := 0
    for b in data {
        if b != '\r' {
            n += 1
        }
    }
    cleaned := make([]u8, n)
    i := 0
    for b in data {
        if b != '\r' {
            cleaned[i] = b
            i += 1
        }
    }
    defer delete(cleaned)

    v := active_view(ed)
    b := active_buffer(ed)

    text.buffer_destroy(&b.doc)
    text.buffer_init(&b.doc, max(len(cleaned) + 64, 4096))
    text.buffer_insert(&b.doc, 0, string(cleaned))
    b.newline = nl
    b.scroll_x_dirty = true
    b.lex_dirty = true
    undo_reset(ed)
    editor_set_path(ed, path)
    set_cursor(ed, 0, false)
    v.scroll_x = 0
    v.scroll_y = 0
    b.dirty = false
    editor_update_title(ed)
    script_run_hooks(ed, "open", path)
    return true
}

strip_cr :: proc(s: string) -> string {
	n := 0
	for i in 0 ..< len(s) {
		if s[i] != '\r' {
			n += 1
		}
	}
	if n == len(s) {
		return s
	}
	out := make([]u8, n)
	i := 0
	for j in 0 ..< len(s) {
		if s[j] != '\r' {
			out[i] = s[j]
			i += 1
		}
	}
	return string(out)
}

editor_save :: proc(ed: ^Editor) -> bool {
    b := active_buffer(ed)
    if len(b.path) == 0 {
        return editor_save_as(ed)
    }
    raw := text.buffer_clone_string(&b.doc)
    defer delete(raw)
    s := strip_cr(raw)
    out := s
    crlf: []u8
    if b.newline == .CRLF {
        extra := 0
        for ch in s {
            if ch == '\n' {
                extra += 1
            }
        }
        crlf = make([]u8, len(s) + extra)
        j := 0
        for i in 0 ..< len(s) {
            if s[i] == '\n' {
                crlf[j] = '\r'
                j += 1
            }
            crlf[j] = s[i]
            j += 1
        }
        out = string(crlf[:j])
    }
    defer if len(crlf) > 0 {
        delete(crlf)
    }

    if os.write_entire_file(b.path, out) != nil {
        return false
    }
    b.dirty = false
    editor_update_title(ed)
    script_run_hooks(ed, "save", b.path)
    return true
}

editor_save_as :: proc(ed: ^Editor) -> bool {
    path, ok := platform.dialog_save_path(ed.host)
    if !ok {
        return false
    }
    defer delete(path)
    editor_set_path(ed, path)
    return editor_save(ed)
}

buffer_display_name :: proc(b: ^Buffer) -> string {
    if len(b.path) == 0 {
        return "untitled"
    }
    i := len(b.path) - 1
    for i >= 0 && b.path[i] != '/' && b.path[i] != '\\' {
        i -= 1
    }
    return b.path[i + 1:]
}

editor_display_name :: proc(ed: ^Editor) -> string {
    return buffer_display_name(active_buffer(ed))
}

editor_update_title :: proc(ed: ^Editor) {
    b := active_buffer(ed)
    star := ""
    if b.dirty {
        star = " *"
    }
    title := fmt.tprintf("%s%s - NOE", editor_display_name(ed), star)
    platform.window_set_title(ed.host, title)
}

editor_mark_dirty :: proc(ed: ^Editor) {
    b := active_buffer(ed)
    if b.playing || b.dirty {
        return
    }
    b.dirty = true
    editor_update_title(ed)
}

editor_confirm_close :: proc(ed: ^Editor) -> bool {
    b := active_buffer(ed)
    if !b.dirty {
        return true
    }
    switch platform.dialog_unsaved(ed.host, editor_display_name(ed)) {
        case .Discard:
        {
            return true
        }
        case .Cancel:
        {
            return false
        }
        case .Save:
        {
            return editor_save(ed)
        }
    }
    return false
}

cmd_file_open :: proc(ed: ^Editor) {
    path, ok := platform.dialog_open_path(ed.host)
    if !ok {
        return
    }
    defer delete(path)
    view_open_path(ed, path)
    // for i in 0 ..< len(ed.buffers) {
    //     if ed.buffers[i].path == path {
    //         view_show_buffer(ed, i)
    //         return
    //     }
    // }
    // append(&ed.buffers, Buffer{scroll_x_dirty = true})
    // active_view(ed).buf_id = len(ed.buffers) - 1
    // _ = editor_load_path(ed, path)
}

cmd_file_save :: proc(ed: ^Editor) {
    _ = editor_save(ed)
}

cmd_file_save_as :: proc(ed: ^Editor) {
    _ = editor_save_as(ed)
}

view_show_buffer :: proc(ed: ^Editor, buf_id: int) {
    v := active_view(ed)
    v.buf_id = clamp(buf_id, 0, len(ed.buffers) - 1)
    v.cursor = 0
    v.sel_anchor = 0
    v.desired_col = 0
    v.scroll_x = 0
    v.scroll_y = 0
    clear(&v.extras)
    editor_update_title(ed)
}

buffer_free :: proc(b: ^Buffer) {
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
    b^ = {}
}

buffer_status_path :: proc(ed: ^Editor, b: ^Buffer) -> string {
    if len(b.path) == 0 {
        return "untitled"
    }
    if ed.project.loaded && len(ed.project.dir) > 0 {
        rel := picker_rel(ed.project.dir, b.path)
        if len(rel) > 0 && len(rel) < len(b.path) {
            return rel
        }
    }
    return buffer_display_name(b)
}

buffer_is_open :: proc(ed: ^Editor, path: string) -> bool {
    for &b in ed.buffers {
        if len(b.path) > 0 && b.path == path {
            return true
        }
    }
    return false
}

buffer_close_at :: proc(ed: ^Editor, id: int) {
    if id < 0 || id >= len(ed.buffers) { return }
    if ed.buffers[id].dirty {
        name := buffer_status_path(ed, &ed.buffers[id])
        switch platform.dialog_unsaved(ed.host, name) {
            case .Cancel:
            {
                return
            }
            case .Save:
            {
                v := active_view(ed)
                prev := v.buf_id
                ok := editor_save(ed)
                v.buf_id = prev
                if !ok { return }
            }
            case .Discard: {}
        }
    }

    buffer_free(&ed.buffers[id])
    ordered_remove(&ed.buffers, id)

    if len(ed.buffers) == 0 {
        append(&ed.buffers, Buffer{})
        b := &ed.buffers[0]
        text.buffer_init(&b.doc, 4096)
        b.undo = make([dynamic]Undo_Op)
        b.scroll_x_dirty = true
        b.lex_id = lex_index_named("odin")
        b.lex_dirty = true
        b.newline = settings.newline
    }

    for &v in ed.views {
        if v.buf_id == id {
            v.buf_id = clamp(id, 0, len(ed.buffers) - 1)
            v.cursor = 0
            v.sel_anchor = 0
            v.desired_col = 0
            v.scroll_x = 0
            v.scroll_y = 0
            clear(&v.extras)
        } else if v.buf_id > id {
            v.buf_id -= 1
        }
    }
    editor_update_title(ed)
}

cmd_buffer_close :: proc(ed: ^Editor) {
    buffer_close_at(ed, active_view(ed).buf_id)
}