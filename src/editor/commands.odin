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
    register_command("buffer_switcher", cmd_buffer_switcher)
    register_command("select_all", cmd_select_all)
    register_command("add_next_match", cmd_add_next_match)
    register_command("carets_clear",   cmd_carets_clear)
    register_command("reload_config", cmd_reload_config)
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

insert_rune :: proc(ed: ^Editor, r: rune) {
    v := active_view(ed)
    if len(v.extras) > 0 {
        bytes, n := utf8.encode_rune(r)
        insert_text(ed, string(bytes[:n]))
        return
    }

    b := active_buffer(ed)

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
    if delete_selection(ed) || v.cursor <= 0 {
        return
    }

    pr, psz := text.buffer_prev_rune(&b.doc, v.cursor)
    nr, nsz := text.buffer_peek_rune(&b.doc, v.cursor)
    if psz > 0 && nsz > 0 {
        open_r, _ := text.buffer_peek_rune(&b.doc, pr)
	    if closer, ok := pair_closer(open_r); settings.smart_brackets && ok && nr == closer {
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