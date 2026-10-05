package editor

import "core:sync"
import "core:unicode"
import "core:unicode/utf8"
import "../text"
import "../platform"

Command_Proc :: proc(ed: ^Editor)

commands: map[string]Command_Proc
TAB_WIDTH :: 4

register_command :: proc(name: string, p: Command_Proc) {
    commands[name] = p
}

run_command :: proc(ed: ^Editor, name: string) -> bool {
    p, ok := commands[name]
    if !ok {
        return false
    }
    p(ed)
    return true
}

register_default_commands :: proc() {
    if commands == nil {
        commands = make(map[string]Command_Proc)
    }
    register_command("cursor_left",        cmd_cursor_left)
	register_command("cursor_right",       cmd_cursor_right)
	register_command("cursor_up",          cmd_cursor_up)
	register_command("cursor_down",        cmd_cursor_down)
    register_command("select_left",        cmd_select_left)
    register_command("select_right",       cmd_select_right)
    register_command("select_up",          cmd_select_up)
    register_command("select_down",        cmd_select_down)
    register_command("select_word_left",   cmd_select_word_left)
    register_command("select_word_right",  cmd_select_word_right)
	register_command("delete_backward",    cmd_delete_backward)
	register_command("insert_newline",     cmd_insert_newline)
    register_command("cursor_word_left",     cmd_cursor_word_left)
    register_command("cursor_word_right",     cmd_cursor_word_right)
    register_command("undo", cmd_undo)
    register_command("redo", cmd_redo)
    register_command("file_open",    cmd_file_open)
    register_command("file_save",    cmd_file_save)
    register_command("file_save_as", cmd_file_save_as)
    register_command("edit_copy",  cmd_edit_copy)
    register_command("edit_cut",   cmd_edit_cut)
    register_command("edit_paste", cmd_edit_paste)
    register_command("cursor_home",      cmd_cursor_home)
    register_command("select_home",      cmd_select_home)
    register_command("cursor_end",       cmd_cursor_end)
    register_command("select_end",       cmd_select_end)
    register_command("cursor_doc_home",  cmd_cursor_doc_home)
    register_command("select_doc_home",  cmd_select_doc_home)
    register_command("cursor_doc_end",   cmd_cursor_doc_end)
    register_command("select_doc_end",   cmd_select_doc_end)
    register_command("cursor_page_up",   cmd_cursor_page_up)
    register_command("select_page_up",   cmd_select_page_up)
    register_command("cursor_page_down", cmd_cursor_page_down)
    register_command("select_page_down", cmd_select_page_down)
    register_command("delete_forward",   cmd_delete_forward)
    register_command("indent", cmd_indent)
    register_command("dedent", cmd_dedent)
    register_command("find", cmd_find)
    register_command("view_next", cmd_view_next)
    register_command("buffer_switcher", cmd_buffer_switcher)
}

is_word :: proc(r: rune) -> bool {
    return unicode.is_letter(r) || unicode.is_digit(r) || r == '_'
}

is_punct :: proc(r: rune) -> bool {
    return r != 0 && !unicode.is_space(r) && !is_word(r)
}

is_stop :: proc(r: rune) -> bool {
    switch r {
        case '"', '\'', '`',
             '(', ')', '[', ']', '{', '}':
        {
            return true
        }
    }
    return false
}

insert_text :: proc(ed: ^Editor, s: string) {
	if len(s) == 0 {
		return
	}
    begin_edit(ed)
    defer end_edit(ed)
	_ = delete_selection(ed)
    v := active_view(ed)
    b := active_buffer(ed)
    pos := v.cursor
	text.buffer_insert(&b.doc, pos, s)
    b.scroll_x_dirty = true
    view_nudge(ed, v.buf_id, pos, len(s))
    undo_record_insert(ed, pos, s)
	set_cursor(ed, pos + len(s), false)
}

insert_rune :: proc(ed: ^Editor, r: rune) {
    bytes, n := utf8.encode_rune(r)
    insert_text(ed, string(bytes[:n]))
}

delete_selection :: proc(ed: ^Editor) -> bool {
    if !has_selection(ed) {
        return false
    }
    lo, hi := selection_range(ed)
    v := active_view(ed)
    b := active_buffer(ed)
    s := text.buffer_clone_range(&b.doc, lo, hi - lo)
    text.buffer_delete(&b.doc, lo, hi - lo)
    b.scroll_x_dirty = true
    view_nudge(ed, v.buf_id, lo, -(hi - lo))
    undo_record_delete(ed, lo, s)
    set_cursor(ed, lo, false)
    return true
}

cmd_cursor_left         :: proc(ed: ^Editor) { move_left(ed, false) }
cmd_select_left         :: proc(ed: ^Editor) { move_left(ed, true) }
cmd_cursor_right        :: proc(ed: ^Editor) { move_right(ed, false) }
cmd_select_right        :: proc(ed: ^Editor) { move_right(ed, true) }
cmd_cursor_up           :: proc(ed: ^Editor) { move_up(ed, false) }
cmd_select_up           :: proc(ed: ^Editor) { move_up(ed, true) }
cmd_cursor_down         :: proc(ed: ^Editor) { move_down(ed, false) }
cmd_select_down         :: proc(ed: ^Editor) { move_down(ed, true) }
cmd_cursor_word_left    :: proc(ed: ^Editor) { move_word_left(ed, false) }
cmd_select_word_left    :: proc(ed: ^Editor) { move_word_left(ed, true) }
cmd_cursor_word_right   :: proc(ed: ^Editor) { move_word_right(ed, false) }
cmd_select_word_right   :: proc(ed: ^Editor) { move_word_right(ed, true) }
cmd_cursor_home         :: proc(ed: ^Editor) { move_home(ed, false) }
cmd_select_home         :: proc(ed: ^Editor) { move_home(ed, true) }
cmd_cursor_end          :: proc(ed: ^Editor) { move_end(ed, false) }
cmd_select_end          :: proc(ed: ^Editor) { move_end(ed, true) }
cmd_cursor_doc_home     :: proc(ed: ^Editor) { move_doc_home(ed, false) }
cmd_select_doc_home     :: proc(ed: ^Editor) { move_doc_home(ed, true) }
cmd_cursor_doc_end      :: proc(ed: ^Editor) { move_doc_end(ed, false) }
cmd_select_doc_end      :: proc(ed: ^Editor) { move_doc_end(ed, true) }
cmd_cursor_page_up      :: proc(ed: ^Editor) { move_page(ed, -1, false) }
cmd_select_page_up      :: proc(ed: ^Editor) { move_page(ed, -1, true) }
cmd_cursor_page_down    :: proc(ed: ^Editor) { move_page(ed,  1, false) }
cmd_select_page_down    :: proc(ed: ^Editor) { move_page(ed,  1, true) }

cmd_delete_backward :: proc(ed: ^Editor) {
    v := active_view(ed)
    b := active_buffer(ed)
    if delete_selection(ed) || v.cursor <= 0 {
        return
    }

    start, size := text.buffer_prev_rune(&b.doc, v.cursor)
    s := text.buffer_clone_range(&b.doc, start, size)
    text.buffer_delete(&b.doc, start, size)
    b.scroll_x_dirty = true
    view_nudge(ed, v.buf_id, start, -size)
    undo_record_delete(ed, start, s)
    set_cursor(ed, start, false)
}

cmd_delete_forward :: proc(ed: ^Editor) {
    v := active_view(ed)
    b := active_buffer(ed)
    if delete_selection(ed) || v.cursor >= text.buffer_len(&b.doc) {
        return
    }

    end, size := text.buffer_next_rune(&b.doc, v.cursor)
    s := text.buffer_clone_range(&b.doc, v.cursor, size)
    text.buffer_delete(&b.doc, v.cursor, size)
    b.scroll_x_dirty = true
    view_nudge(ed, v.buf_id, v.cursor, -size)
    undo_record_delete(ed, v.cursor, s)
    set_cursor(ed, v.cursor, false)
    _ = end
}

cmd_insert_newline :: proc(ed: ^Editor) {
    insert_text(ed, "\n")
}

cmd_edit_copy :: proc(ed: ^Editor) {
    if !has_selection(ed) {
        return
    }
    lo, hi := selection_range(ed)
    b := active_buffer(ed)
    s := text.buffer_clone_range(&b.doc, lo, hi - lo)
    defer delete(s)
    _ = platform.clipboard_set(ed.host, s)
}

cmd_edit_cut :: proc(ed: ^Editor) {
    if !has_selection(ed) {
        return
    }
    lo, hi := selection_range(ed)
    b := active_buffer(ed)
    s := text.buffer_clone_range(&b.doc, lo, hi - lo)
    defer delete(s)
    if !platform.clipboard_set(ed.host, s) {
        return
    }
    _ = delete_selection(ed)
}

cmd_edit_paste :: proc(ed: ^Editor) {
    s, ok := platform.clipboard_get(ed.host)
    if !ok {
        return
    }
    defer delete(s)
    insert_text(ed, s)
}

move_left :: proc(ed: ^Editor, keep_sel: bool) {
    if !keep_sel && has_selection(ed) {
        lo, _ := selection_range(ed)
        set_cursor(ed, lo, false)
        return
    }
    v := active_view(ed)
    b := active_buffer(ed)
    start, _ := text.buffer_prev_rune(&b.doc, v.cursor)
    set_cursor(ed, start, keep_sel)
}

move_right :: proc(ed: ^Editor, keep_sel: bool) {
    if !keep_sel && has_selection(ed) {
        _, hi := selection_range(ed)
        set_cursor(ed, hi, false)
        return
    }
    v := active_view(ed)
    b := active_buffer(ed)
    end, _ := text.buffer_next_rune(&b.doc, v.cursor)
    set_cursor(ed, end, keep_sel)
}

move_up :: proc(ed: ^Editor, keep_sel: bool) {
    v := active_view(ed)
    b := active_buffer(ed)
    col := v.desired_col
    line := text.buffer_line_at(&b.doc, v.cursor)
    pos := v.cursor
    if line > 0 {
        pos = text.buffer_pos_at_line(&b.doc, line - 1, col)
    }
    set_cursor(ed, pos, keep_sel)
    v.desired_col = col
}

move_down :: proc(ed: ^Editor, keep_sel: bool) {
    v := active_view(ed)
    b := active_buffer(ed)
    col := v.desired_col
    line := text.buffer_line_at(&b.doc, v.cursor)
    pos := v.cursor
    if line + 1 < text.buffer_line_count(&b.doc) {
        pos = text.buffer_pos_at_line(&b.doc, line + 1, col)
    }
    set_cursor(ed, pos, keep_sel)
    v.desired_col = col
}

move_word_left :: proc(ed: ^Editor, keep_sel: bool) {
    v := active_view(ed)
    b := active_buffer(ed)
    pos := v.cursor
    
    if pos > 0 {
        pos, _ = text.buffer_prev_rune(&b.doc, pos)
        
        for pos > 0 {
            r, _ := text.buffer_peek_rune(&b.doc, pos)
            if unicode.is_space(r) {
                pos, _ = text.buffer_prev_rune(&b.doc, pos)
                continue
            }
            break
        }

        r, _ := text.buffer_peek_rune(&b.doc, pos)
        if !is_stop(r) {
            for pos > 0 {
                start, _ := text.buffer_prev_rune(&b.doc, pos)
                r, _ = text.buffer_peek_rune(&b.doc, start)
                if is_stop(r) {
                    break
                } else if is_word(r) {
                    pos = start
                    continue
                } else if is_punct(r) {
                    pos = start
                }
                break
            }
        }
    }
    set_cursor(ed, pos, keep_sel)
}

move_word_right :: proc(ed: ^Editor, keep_sel: bool) {
    v := active_view(ed)
    b := active_buffer(ed)
    pos := v.cursor
    n := text.buffer_len(&b.doc)

    r, size := text.buffer_peek_rune(&b.doc, pos)
    if is_stop(r) {
        pos += size
    } else {
        for pos < n {
            r, size := text.buffer_peek_rune(&b.doc, pos)
            if size == 0 {
                break
            }
            if is_stop(r) {
                break
            } else if is_word(r) {
                pos += size
                continue
            } else if is_punct(r) {
                pos += size
            }
            break
        }
    }

    for pos < n {
        r, size := text.buffer_peek_rune(&b.doc, pos)
        if size == 0 {
            break
        }
        if unicode.is_space(r) {
            pos += size
            continue
        }
        break
    }
    set_cursor(ed, pos, keep_sel)
}

move_home :: proc(ed: ^Editor, keep_sel: bool) {
    v := active_view(ed)
    b := active_buffer(ed)
    line := text.buffer_line_at(&b.doc, v.cursor)
    set_cursor(ed, text.buffer_line_start(&b.doc, line), keep_sel)
}

move_end :: proc(ed: ^Editor, keep_sel: bool) {
    v := active_view(ed)
    b := active_buffer(ed)
    line := text.buffer_line_at(&b.doc, v.cursor)
    set_cursor(ed, text.buffer_line_end(&b.doc, line), keep_sel)
}

move_doc_home :: proc(ed: ^Editor, keep_sel: bool) {
    set_cursor(ed, 0, keep_sel)
}

move_doc_end :: proc(ed: ^Editor, keep_sel: bool) {
    b := active_buffer(ed)
    set_cursor(ed, text.buffer_len(&b.doc), keep_sel)
}

move_page :: proc(ed: ^Editor, dir: int, keep_sel: bool) {
    v := active_view(ed)
    b := active_buffer(ed)
    col := v.desired_col
    line := text.buffer_line_at(&b.doc, v.cursor)
    n := text.buffer_line_count(&b.doc)
    target := clamp(line + dir * max(v.page_lines, 1), 0, n - 1)
    pos := text.buffer_pos_at_line(&b.doc, target, col)
    set_cursor(ed, pos, keep_sel)
    v.desired_col = col
}

indent_line_range :: proc(ed: ^Editor) -> (first, last: int, ok: bool) {
    if !has_selection(ed) {
        return 0, 0, false
    }

    lo, hi := selection_range(ed)
    b := active_buffer(ed)
    first = text.buffer_line_at(&b.doc, lo)
    last = text.buffer_line_at(&b.doc, hi)
    if last > first && hi == text.buffer_line_start(&b.doc, last) {
        last -= 1
    }
    return first, last, true
}

cmd_indent :: proc(ed: ^Editor) {
    first, last, ok := indent_line_range(ed)
    if !ok {
        insert_text(ed, "\t")
        return
    }
    begin_edit(ed)
    defer end_edit(ed)
    v := active_view(ed)
    b := active_buffer(ed)
    for i := last; i >= first; i -= 1 {
        ls := text.buffer_line_start(&b.doc, i)
        text.buffer_insert(&b.doc, ls, "\t")
        b.scroll_x_dirty = true
        view_nudge(ed, v.buf_id, ls, 1)
        undo_record_insert(ed, ls, "\t")
        if v.cursor >= ls {
            v.cursor += 1
        }
        if v.sel_anchor >= ls {
            v.sel_anchor += 1
        }
    }
    v.desired_col = sync_col(ed)
}

cmd_dedent :: proc(ed: ^Editor) {
    v := active_view(ed)
    b := active_buffer(ed)
    first, last: int
    ok: bool
    if has_selection(ed) {
        first, last, ok = indent_line_range(ed)
    } else {
        line := text.buffer_line_at(&b.doc, v.cursor)
        first, last, ok = line, line, true
    }
    if !ok {
        return
    }
    begin_edit(ed)
    defer end_edit(ed)
    for i := last; i >= first; i -= 1 {
        ls := text.buffer_line_start(&b.doc, i)
        le := text.buffer_line_end(&b.doc, i)
        n := 0
        if ls < le && text.buffer_byte(&b.doc, ls) == '\t' {
            n = 1
        } else {
            for n < TAB_WIDTH && ls + n < le && text.buffer_byte(&b.doc, ls + n) == ' ' {
                n += 1
            }
        }
        if n == 0 {
            continue
        }
        s := text.buffer_clone_range(&b.doc, ls, n)
        text.buffer_delete(&b.doc, ls, n)
        b.scroll_x_dirty = true
        view_nudge(ed, v.buf_id, ls, -n)
        undo_record_delete(ed, ls, s)
        if v.cursor > ls {
            v.cursor = max(v.cursor - n, ls)
        }
        if v.sel_anchor > ls {
            v.sel_anchor = max(v.sel_anchor - n, ls)
        }
    }
    v.desired_col = sync_col(ed)
}

cmd_view_next :: proc(ed: ^Editor) {
    if len(ed.views) < 2 {
        cur := active_view(ed)^
        append(&ed.views, cur)
        ed.active_view = 1
        return
    }
    ed.active_view = (ed.active_view + 1) % len(ed.views)
}

cmd_buffer_switcher :: proc(ed: ^Editor) {
    overlay_open(ed, .Switcher)
    ed.overlay.sel = 0
}