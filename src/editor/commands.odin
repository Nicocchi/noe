package editor

import "core:sync"
import "core:unicode"
import "core:unicode/utf8"
import "core:fmt"
import "core:slice"
import "../text"
import "../platform"

Command_Proc :: proc(ed: ^Editor)

commands: map[string]Command_Proc

register_command :: proc(name: string, p: Command_Proc) {
    commands[name] = p
}

run_command :: proc(ed: ^Editor, name: string) -> bool {
    if script_run_command(ed, name) {
        return true
    }
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
    register_command("view_left", cmd_view_left)
    register_command("view_right", cmd_view_right)
    register_command("view_up", cmd_view_up)
    register_command("view_down", cmd_view_down)
    register_command("window_prefix", cmd_window_prefix)
    register_command("buffer_switcher", cmd_buffer_switcher)
    register_command("select_all", cmd_select_all)
    register_command("add_next_match", cmd_add_next_match)
    register_command("carets_clear",   cmd_carets_clear)
    register_command("reload_config", cmd_reload_config)
    register_command("file_finder", cmd_file_finder)
    register_command("file_new", cmd_file_new)
    register_command("buffer_close", cmd_buffer_close)
    register_command("line_up", cmd_line_up)
    register_command("line_down", cmd_line_down)
    register_command("toggle_comment", cmd_toggle_comment)
    register_command("project_f1",  cmd_project_f1)
    register_command("project_f2",  cmd_project_f2)
    register_command("project_f3",  cmd_project_f3)
    register_command("project_f4",  cmd_project_f4)
    register_command("project_f5",  cmd_project_f5)
    register_command("project_f6",  cmd_project_f6)
    register_command("project_f7",  cmd_project_f7)
    register_command("project_f8",  cmd_project_f8)
    register_command("project_f9",  cmd_project_f9)
    register_command("project_f10", cmd_project_f10)
    register_command("project_f11", cmd_project_f11)
    register_command("project_f12", cmd_project_f12)
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

insert_text_multi :: proc(ed: ^Editor, s: string) {
    v := active_view(ed)
    b := active_buffer(ed)

    Work :: struct {
        c:          Caret,
        primary:    bool
    }
    cs: [dynamic]Work
    defer delete(cs)
    append(&cs, Work{Caret{v.cursor, v.sel_anchor, v.desired_col}, true})
    for e in v.extras {
        append(&cs, Work{e, false})
    }
    slice.sort_by(cs[:], proc(a, b: Work) -> bool {
        al, _ := caret_range(a.c)
        bl, _ := caret_range(b.c)
        return al > bl
    })

    begin_edit(ed, true)
    defer end_edit(ed)
    for i in 0 ..< len(cs) {
        lo, hi := caret_range(cs[i].c)
        del_n := hi - lo
        if del_n > 0 {
            del := text.buffer_clone_range(&b.doc, lo, del_n)
            text.buffer_delete(&b.doc, lo, del_n)
            view_nudge(ed, v.buf_id, lo, -del_n)
            undo_record_delete(ed, lo, del)
        }
        text.buffer_insert(&b.doc, lo, s)
        view_nudge(ed, v.buf_id, lo, len(s))
        undo_record_insert(ed, lo, s)
        cs[i].c.cursor = lo + len(s)
        cs[i].c.sel_anchor = cs[i].c.cursor
        net := len(s) - del_n
        if net != 0 {
            for j in 0 ..< len(cs) {
                if j == i {
                    continue
                }
                caret_shift(&cs[j].c, hi, net)
            }
        }
    }
    b.scroll_x_dirty = true
    clear(&v.extras)
    for w in cs {
        if w.primary {
            v.cursor = w.c.cursor
            v.sel_anchor = w.c.sel_anchor
            v.desired_col = sync_col(ed)
        } else {
            append(&v.extras, w.c)
        }
    }
    b.typing = true
}

insert_text :: proc(ed: ^Editor, s: string) {
	if len(s) == 0 {
		return
	}
    cleaned := strip_cr(s)
    defer if cleaned != s {
        delete(cleaned)
    }
    s := cleaned
    if len(s) == 0 {
        return
    }
    v := active_view(ed)
    if len(v.extras) > 0 {
        insert_text_multi(ed, s)
        return
    }

    begin_edit(ed, true)
    defer end_edit(ed)
	_ = delete_selection(ed)
    b := active_buffer(ed)
    pos := v.cursor
	text.buffer_insert(&b.doc, pos, s)
    b.scroll_x_dirty = true
    view_nudge(ed, v.buf_id, pos, len(s))
    undo_record_insert(ed, pos, s)
	set_cursor(ed, pos + len(s), false)
    b.typing = true
}

in_comment_or_string_at :: proc(b: ^Buffer, pos: int) -> bool {
    if b.lex_dirty { buffer_lex(b) }
    for t in b.tokens {
        if t.pos + t.len < pos { continue }
        if t.pos > pos { break }
        if t.kind == .Comment { return true }
        if t.kind == .String {
            if pos == t.pos {
                return false
            }
            if pos < t.pos + t.len { return true }
            if t.len < 2 { return true }
            first, _ := text.buffer_peek_rune(&b.doc, t.pos)
            last_i, _ := text.buffer_prev_rune(&b.doc, t.pos + t.len)
            last, _ := text.buffer_peek_rune(&b.doc, last_i)
            return first != last
        }
    }
    return false
}

in_comment_or_string :: proc(ed: ^Editor, pos: int) -> bool {
    return in_comment_or_string_at(active_buffer(ed), pos)
}

insert_rune :: proc(ed: ^Editor, r: rune) {
    v := active_view(ed)
    if len(v.extras) > 0 {
        bytes, n := utf8.encode_rune(r)
        insert_text(ed, string(bytes[:n]))
        return
    }

    b := active_buffer(ed)
    if settings.smart_brackets && !has_selection(ed) && is_quote(r) {
        nr, nsz := text.buffer_peek_rune(&b.doc, v.cursor)
        if nsz > 0 && nr == r {
            set_cursor(ed, v.cursor + nsz, false)
            return
        }
    }
    if in_comment_or_string(ed, v.cursor) {
        bytes, n := utf8.encode_rune(r)
        insert_text(ed, string(bytes[:n]))
        return
    }

    if rune_is_escaped(ed, v.cursor) {
        bytes, n := utf8.encode_rune(r)
        insert_text(ed, string(bytes[:n]))
        return
    }

    if settings.smart_brackets && !has_selection(ed) && is_closer(r) {
        nr, nsz := text.buffer_peek_rune(&b.doc, v.cursor)
        if nsz > 0 && nr == r {
            set_cursor(ed, v.cursor + nsz, false)
            return
        }
    }

    if closer, paired := pair_closer(r); paired && settings.smart_brackets {
        ob, on := utf8.encode_rune(r)
        cb, cn := utf8.encode_rune(closer)
        open_s := string(ob[:on])
        close_s := string(cb[:cn])

        if has_selection(ed) {
			lo, hi := selection_range(ed)
			begin_edit(ed)
			defer end_edit(ed)
			text.buffer_insert(&b.doc, hi, close_s)
			b.scroll_x_dirty = true
			view_nudge(ed, v.buf_id, hi, cn)
			undo_record_insert(ed, hi, close_s)
			text.buffer_insert(&b.doc, lo, open_s)
			view_nudge(ed, v.buf_id, lo, on)
			undo_record_insert(ed, lo, open_s)
			v.sel_anchor = lo + on
			set_cursor(ed, hi + on, true)
			return
		}

        pair := fmt.tprintf("%s%s", open_s, close_s)
        insert_text(ed, pair)
        set_cursor(ed, v.cursor - cn, false)
        return
    }

    bytes, n := utf8.encode_rune(r)
    insert_text(ed, string(bytes[:n]))
}

delete_selection :: proc(ed: ^Editor) -> bool {
    if !has_selection(ed) {
        return false
    }
    begin_edit(ed, true)
    defer end_edit(ed)
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

cmd_select_all :: proc(ed: ^Editor) {
    v := active_view(ed)
    b := active_buffer(ed)
    v.sel_anchor = 0
    set_cursor(ed, text.buffer_len(&b.doc), true)
}

cmd_delete_backward :: proc(ed: ^Editor) {
    v := active_view(ed)
    b := active_buffer(ed)
    begin_edit(ed, true)
    defer end_edit(ed)
    if delete_selection(ed) || v.cursor <= 0 {
        return
    }

    pr, psz := text.buffer_prev_rune(&b.doc, v.cursor)
    nr, nsz := text.buffer_peek_rune(&b.doc, v.cursor)
    if psz > 0 && nsz > 0 {
        open_r, _ := text.buffer_peek_rune(&b.doc, pr)
	    if closer, ok := pair_closer(open_r); settings.smart_brackets && ok && nr == closer && !in_comment_or_string(ed, v.cursor) {
            begin_edit(ed)
            defer end_edit(ed)
            cs := text.buffer_clone_range(&b.doc, v.cursor, nsz)
            text.buffer_delete(&b.doc, v.cursor, nsz)
            b.scroll_x_dirty = true
            view_nudge(ed, v.buf_id, v.cursor, -nsz)
            undo_record_delete(ed, v.cursor, cs)
            os := text.buffer_clone_range(&b.doc, pr, psz)
            text.buffer_delete(&b.doc, pr, psz)
            view_nudge(ed, v.buf_id, pr, -psz)
            undo_record_delete(ed, pr, os)
            set_cursor(ed, pr, false)
            return
        }
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
    begin_edit(ed, true)
    defer end_edit(ed)
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
    v := active_view(ed)
    b := active_buffer(ed)
    line := text.buffer_line_at(&b.doc, v.cursor)
    ls := text.buffer_line_start(&b.doc, line)
    le := text.buffer_line_end(&b.doc, line)

    n := 0
    for ls + n < le {
        ch := text.buffer_byte(&b.doc, ls + n)
        if ch != ' ' && ch != '\t' {
            break
        }
        n += 1
    }
    lead := text.buffer_clone_range(&b.doc, ls, n)
    defer delete(lead)

    extra := false
    p := v.cursor
    for p > ls {
        start, _ := text.buffer_prev_rune(&b.doc, p)
        r, _ := text.buffer_peek_rune(&b.doc, start)
        p = start
        if r == ' ' || r == '\t' {
            continue
        }
        extra = r == '{' || r == '[' || r == '('
        break
    }

    split := false
    closer: rune
    if extra {
        q := v.cursor
        for q < le {
            r, size := text.buffer_peek_rune(&b.doc, q)
            if size == 0 {
                break
            }
            if r == ' ' || r == '\t' {
                q += size
                continue
            }
            closer = r
            split = r == '}' || r == ']' || r == ')'
            break
        }
    }

    extra_s := ""
    if extra {
        extra_s = indent_unit()
    }

    begin_edit(ed)
    defer end_edit(ed)
    insert_text(ed, fmt.tprintf("\n%s%s", lead, extra_s))
    if split {
        mid := v.cursor
        insert_text(ed, fmt.tprintf("\n%s", lead))
        set_cursor(ed, mid, false)
    }
    _ = closer
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
    start := text.buffer_line_start(&b.doc, line)
    end := text.buffer_line_end(&b.doc, line)
    indent := start
    for indent < end {
    	r, sz := text.buffer_peek_rune(&b.doc, indent)
    	if sz <= 0 || (r != ' ' && r != '\t') { break }
    	indent += sz
    }
    if indent == end { indent = start }
    dest := indent
    if v.cursor == indent && indent != start { dest = start }
    set_cursor(ed, dest, keep_sel)
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
        insert_text(ed, indent_unit())
        return
    }
    begin_edit(ed)
    defer end_edit(ed)
    v := active_view(ed)
    b := active_buffer(ed)
    unit := indent_unit()
    n := len(unit)
    for i := last; i >= first; i -= 1 {
        ls := text.buffer_line_start(&b.doc, i)
        text.buffer_insert(&b.doc, ls, unit)
        b.scroll_x_dirty = true
        view_nudge(ed, v.buf_id, ls, 1)
        undo_record_insert(ed, ls, unit)
        if v.cursor >= ls {
            v.cursor += n
        }
        if v.sel_anchor >= ls {
            v.sel_anchor += n
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
            for n < settings.tab_width && ls + n < le && text.buffer_byte(&b.doc, ls + n) == ' ' {
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
        cur.extras = nil
        for e in active_view(ed).extras {
            append(&cur.extras, e)
        }
        append(&ed.views, cur)
        ed.active_view = 1
        return
    }
    ed.active_view = (ed.active_view + 1) % len(ed.views)
}

cmd_view_left :: proc(ed: ^Editor) {
    if len(ed.views) < 2 {
        return
    }
    ed.active_view = max(ed.active_view - 1, 0)
}

cmd_view_right :: proc(ed: ^Editor) {
    if len(ed.views) < 2 {
        return
    }
    ed.active_view = min(ed.active_view + 1, len(ed.views) - 1)
}

cmd_view_up :: proc(ed: ^Editor) {
    
}

cmd_view_down :: proc(ed: ^Editor) {
    
}

cmd_window_prefix :: proc(ed: ^Editor) {
    ed.window_chord = true
}

cmd_buffer_switcher :: proc(ed: ^Editor) {
    overlay_open(ed, .Switcher)
    ed.overlay.sel = 0
}

pair_closer :: proc(r: rune) -> (closer: rune, ok: bool) {
    switch r {
        case '(': return ')', true
        case '[': return ']', true
        case '{': return '}', true
        case '"': return '"', true
        case '\'': return '\'', true
        case '`': return '`', true
	}
	return 0, false
}

indent_unit :: proc() -> string {
    if settings.use_tabs {
        return "\t"
    }
    n := clamp(settings.tab_width, 1, 16)
    spaces := "                "
    return spaces[:n]
}

rune_is_escaped :: proc(ed: ^Editor, pos: int) -> bool {
    b := active_buffer(ed)
    n := 0
    p := pos
    for p > 0 {
        start, _ := text.buffer_prev_rune(&b.doc, p)
        r, _ := text.buffer_peek_rune(&b.doc, start)
        if r != '\\' {
            break
        }
        n += 1
        p = start
    }
    return n % 2 == 1
}

is_closer :: proc(r: rune) -> bool {
    switch r {
        case ')', ']', '}', '"', '\'', '`': return true
    }
    return false
}

is_quote :: proc(r: rune) -> bool {
    return r == '"' || r == '\'' || r == '`'
}

cmd_add_next_match :: proc(ed: ^Editor) {
    v := active_view(ed)
    b := active_buffer(ed)

    if !has_selection(ed) {
        lo, hi := word_range_at(ed, v.cursor)
        v.sel_anchor = lo
        v.cursor = hi
        v.desired_col = sync_col(ed)
        return
    }

    lo, hi := selection_range(ed)
    q := text.buffer_clone_range(&b.doc, lo, hi - lo)
    defer delete(q)

    n := text.buffer_len(&b.doc)
    from := hi
    wrapped := false
    for {
        pos, ok := find_in_buffer(&b.doc, q, from, n)
        if !ok {
            if wrapped {
                return
            }
            wrapped = true
            from = 0
            continue
        }
        taken := false
        plo, phi := selection_range(ed)
        if pos == plo && pos + len(q) == phi {
            taken = true
        }
        for e in v.extras {
            elo, ehi := caret_range(e)
            if pos == elo && pos + len(q) == ehi {
                taken = true
                break
            }
        }
        if taken {
            from = pos + 1
            continue
        }
        append(&v.extras, Caret{v.cursor, v.sel_anchor, v.desired_col})
        v.sel_anchor = pos
        v.cursor = pos + len(q)
        v.desired_col = sync_col(ed)
        return
    }
}

word_range_at :: proc(ed: ^Editor, pos: int) -> (lo, hi: int) {
    b := active_buffer(ed)
    lo = pos
    for lo > 0 {
        pr, sz := text.buffer_prev_rune(&b.doc, lo)
        if sz <= 0 {
            break
        }
        r, _ := text.buffer_peek_rune(&b.doc, pr)
        if !is_word(r) {
            break
        }
        lo = pr
    }
    hi = pos
    n := text.buffer_len(&b.doc)
    for hi < n {
        r, sz := text.buffer_peek_rune(&b.doc, hi)
        if sz <= 0 || !is_word(r) {
            break
        }
        hi += sz
    }
    if lo != hi {
        return
    }
    if hi < n {
        _, sz := text.buffer_peek_rune(&b.doc, hi)
        return hi, hi + sz
    }
    if lo > 0 {
        pr, sz := text.buffer_prev_rune(&b.doc, lo)
        return pr, lo
    }
    return 0, 0
}

cmd_carets_clear :: proc(ed: ^Editor) {
    caret_clear(ed)
}

cmd_reload_config :: proc(ed: ^Editor) {
    script_reload(ed)
}

line_indent :: proc(doc: ^text.Buffer, line: int) -> (cols, bytes: int) {
	ls := text.buffer_line_start(doc, line)
	le := text.buffer_line_end(doc, line)
	tw := max(settings.tab_width, 1)
	for ls + bytes < le {
		c := text.buffer_byte(doc, ls + bytes)
		if c == ' ' {
			cols += 1
			bytes += 1
		} else if c == '\t' {
			cols += tw
			bytes += 1
		} else { break }
	}
	return
}

indent_cols :: proc() -> int {
    return max(settings.tab_width, 1)
}

is_block_open :: proc(r: rune) -> bool {
    return r == '{' || r == '[' || r == '('
}

is_block_close :: proc(r: rune) -> bool {
    return r == '}' || r == ']' || r == ')'
}

line_edge_runes :: proc(doc: ^text.Buffer, line: int) -> (first, last: rune) {
    ls := text.buffer_line_start(doc, line)
    le := text.buffer_line_end(doc, line)
    p := ls
    for p < le {
        r, sz := text.buffer_peek_rune(doc, p)
        if sz <= 0 { break }
        if r != ' ' && r != '\t' {
            first = r
            break
        }
        p += sz
    }
    p = le
    for p > ls {
        start, _ := text.buffer_prev_rune(doc, p)
        r, _ := text.buffer_peek_rune(doc, start)
        p = start
        if r != ' ' && r != '\t' {
            last = r
            break
        }
    }
    return
}

move_indent_delta :: proc(doc: ^text.Buffer, first, neighbor, dir: int) -> int {
    base, _ := line_indent(doc, first)
    nb_cols, _ := line_indent(doc, neighbor)
    target := nb_cols
    left, right := line_edge_runes(doc, neighbor)
    if dir > 0 {
        if is_block_open(right) {
            target += indent_cols()
        }
    } else if is_block_close(left) {
        target += indent_cols()
    }
    return target - base
}

indent_bytes :: proc(cols: int) -> int {
	cols := max(cols, 0)
	if settings.use_tabs {
		tw := max(settings.tab_width, 1)
		return cols / tw + cols % tw
	}
	return cols
}

append_indent :: proc(out: ^[dynamic]u8, cols: int) {
	cols := max(cols, 0)
	if settings.use_tabs {
		tw := max(settings.tab_width, 1)
		for _ in 0 ..< cols / tw {
			append(out, u8('\t'))
		}
		for _ in 0 ..< cols % tw {
			append(out, u8(' '))
		}
	} else {
		for _ in 0 ..< cols {
			append(out, u8(' '))
		}
	}
}

reindent_lines :: proc(doc: ^text.Buffer, first, last, delta: int) -> string {
	out := make([dynamic]u8, context.temp_allocator)
	for line in first ..= last {
		if line > first {
			append(&out, u8('\n'))
		}
		cols, bytes := line_indent(doc, line)
		ls := text.buffer_line_start(doc, line)
		le := text.buffer_line_end(doc, line)
		if le == ls { continue }
		append_indent(&out, cols + delta)
		rest := le - (ls + bytes)
		if rest > 0 {
			tmp := make([]u8, rest, context.temp_allocator)
			text.buffer_read(doc, ls + bytes, rest, tmp)
			append(&out, ..tmp)
		}
	}
	return string(out[:])
}

replace_span :: proc(ed: ^Editor, pos: int, old, fresh: string) {
	b := active_buffer(ed)
	id := active_view(ed).buf_id
	if len(old) > 0 {
		text.buffer_delete(&b.doc, pos, len(old))
		view_nudge(ed, id, pos, -len(old))
		undo_record_delete(ed, pos, old)
	} else {
		delete(old)
	}
	
	if len(fresh) > 0 {
		text.buffer_insert(&b.doc, pos, fresh)
		view_nudge(ed, id, pos, len(fresh))
		undo_record_insert(ed, pos, fresh)
	}
}

move_lines :: proc(ed: ^Editor, dir: int) {
	v := active_view(ed)
	b := active_buffer(ed)
	doc := &b.doc
	n := text.buffer_line_count(doc)
	first, last: int
	if has_selection(ed) {
		first, last, _ = indent_line_range(ed)
	} else {
		line := text.buffer_line_at(doc, v.cursor)
		first, last = line, line
	}
	if dir < 0 && first == 0 { return }
	if dir > 0 && last + 1 >= n { return }
	focus := text.buffer_line_at(doc, v.cursor)
	focus_col := v.cursor - text.buffer_line_start(doc, focus)
	if focus < first || focus > last {
		anchor := v.sel_anchor
		focus = text.buffer_line_at(doc, anchor)
		focus_col = anchor - text.buffer_line_start(doc, focus)
		if focus < first || focus > last {
			focus = first
			focus_col = 0
		}
	}
	focus_cols, focus_bytes := line_indent(doc, focus)
	neighbor := last + 1
	if dir < 0 {
		neighbor = first - 1
	}
	delta := move_indent_delta(doc, first, neighbor, dir)
	block_lo := text.buffer_line_start(doc, first)
	block_hi := text.buffer_line_end(doc, last)
	nb_lo := text.buffer_line_start(doc, neighbor)
	nb_hi := text.buffer_line_end(doc, neighbor)
	lo := min(block_lo, nb_lo)
	hi := max(block_hi, nb_hi)
	old := text.buffer_clone_range(doc, lo, hi - lo)
	block_n := block_hi - block_lo
	neigh_n := nb_hi - nb_lo
	neigh := old[block_n + 1:]
	moved := old[:block_n]
	if dir < 0 {
		neigh = old[:neigh_n]
		moved = old[neigh_n + 1:]
	}
	if delta != 0 {
		moved = reindent_lines(doc, first, last, delta)
	}
	out := make([dynamic]u8)
	if dir > 0 {
		n := len(out)
		resize(&out, n + len(neigh))
		copy(out[n:], neigh)
		append(&out, u8('\n'))
		n = len(out)
		resize(&out, n + len(moved))
		copy(out[n:], moved)
	} else {
		n := len(out)
		resize(&out, n + len(moved))
		copy(out[n:], moved)
		append(&out, u8('\n'))
		n = len(out)
		resize(&out, n + len(neigh))
		copy(out[n:], neigh)
	}
	new_col := focus_col
	if delta != 0 {
		new_col = focus_col + (indent_bytes(focus_cols + delta) - focus_bytes)
		if new_col < 0 {
			new_col = 0
		}
	}
	had_sel := has_selection(ed)
	cursor_hi := v.cursor >= v.sel_anchor
	lo_line, hi_line, lo_col, hi_col := 0, 0, 0, 0
	if had_sel {
	    sel_lo, sel_hi := selection_range(ed)
	    lo_line = text.buffer_line_at(doc, sel_lo)
	    hi_line = text.buffer_line_at(doc, sel_hi)
	    lo_col = sel_lo - text.buffer_line_start(doc, lo_line)
	    hi_col = sel_hi - text.buffer_line_start(doc, hi_line)
	    if delta != 0 {
	        if lo_line >= first && lo_line <= last {
	            cols, bytes := line_indent(doc, lo_line)
	            lo_col += indent_bytes(cols + delta) - bytes
	            if lo_col < 0 { lo_col = 0 }
	        }
	        if hi_line >= first && hi_line <= last {
	            cols, bytes := line_indent(doc, hi_line)
	            hi_col += indent_bytes(cols + delta) - bytes
	            if hi_col < 0 { hi_col = 0 }
	        }
	    }
	}
	begin_edit(ed)
	defer end_edit(ed)
	replace_span(ed, lo, old, string(out[:]))
	delete(out)
	b.scroll_x_dirty = true
	if had_sel {
	    nlines := text.buffer_line_count(doc)
	    line_pos :: proc(doc: ^text.Buffer, line, col, nlines: int) -> int {
	        if line < 0 { return 0 }
	        if line >= nlines { return text.buffer_len(doc) }
	        return text.buffer_pos_at_line(doc, line, col)
	    }
	    a := line_pos(doc, lo_line + dir, lo_col, nlines)
	    c := line_pos(doc, hi_line + dir, hi_col, nlines)
	    if cursor_hi {
	        v.sel_anchor = a
	        set_cursor(ed, c, true)
	    } else {
	        v.sel_anchor = c
	        set_cursor(ed, a, true)
	    }
	} else {
        set_cursor(ed, text.buffer_pos_at_line(doc, focus + dir, new_col), false)
	}
	
}

cmd_line_up :: proc(ed: ^Editor) {
	move_lines(ed, -1)
}

cmd_line_down :: proc(ed: ^Editor) {
	move_lines(ed, 1)
}

line_comment_open :: proc(b: ^Buffer) -> string {
    lf := lex_file_of(b)
    if lf != nil {
        for m in lf.comments {
            if len(m.close) == 0 && len(m.open) > 0 { return m.open }
        }
    }

    return "//"
}

line_starts_at :: proc(doc: ^text.Buffer, pos, le: int, s: string) -> bool {
    if pos + len(s) > le { return false }
    for i in 0 ..< len(s) {
        if text.buffer_byte(doc, pos + i) != s[i] { return false }
    }
    return true
}

line_content_start :: proc(doc: ^text.Buffer, ls, le: int) -> int {
    p := ls
    for p < le {
        c := text.buffer_byte(doc, p)
        if c != ' ' && c != '\t' { break }
        p += 1
    }
    return p
}

cmd_toggle_comment :: proc(ed: ^Editor) {
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
    if !ok { return }
    mark := line_comment_open(b)
    if len(mark) == 0 { return }

    all_on := true
    any_code := false
    for i in first ..= last {
        ls := text.buffer_line_start(&b.doc, i)
        le := text.buffer_line_end(&b.doc, i)
        p := line_content_start(&b.doc, ls, le)
        if p == le { continue }
        any_code = true
        if !line_starts_at(&b.doc, p, le, mark) {
            all_on = false
            break
        }
    }
    if !any_code { all_on = false }

    prefix := mark
    if mark[len(mark) - 1] != ' ' {
        prefix = fmt.tprintf("%s ", mark)
    }

    begin_edit(ed)
    defer end_edit(ed)
    id := v.buf_id
    if all_on {
        for i := last; i >= first; i -= 1 {
            ls := text.buffer_line_start(&b.doc, i)
            le := text.buffer_line_end(&b.doc, i)
            p := line_content_start(&b.doc, ls, le)
            if p == le || !line_starts_at(&b.doc, p, le, mark) { continue }
            n := len(mark)
            if p + n < le && text.buffer_byte(&b.doc, p + n) == ' ' { n += 1}
            s := text.buffer_clone_range(&b.doc, p, n)
            text.buffer_delete(&b.doc, p, n)
            view_nudge(ed, id, p, -n)
            undo_record_delete(ed, p, s)
            if v.cursor > p {
                v.cursor = max(v.cursor - n, p)
            }
            if v.sel_anchor > p {
                v.sel_anchor = max(v.sel_anchor - n, p)
            }
        }
    } else {
        n := len(prefix)
        for i := last; i >= first; i -= 1 {
            ls := text.buffer_line_start(&b.doc, i)
            le := text.buffer_line_end(&b.doc, i)
            p := line_content_start(&b.doc, ls, le)
            if p == le && first != last { continue }
            text.buffer_insert(&b.doc, p, prefix)
            view_nudge(ed, id, p, n)
            undo_record_insert(ed, p, prefix)
            if v.cursor >= p {
                v.cursor += n
            }
            if v.sel_anchor >= p {
                v.sel_anchor += n
            }
        }
    }
    b.scroll_x_dirty = true
    v.desired_col = sync_col(ed)
}