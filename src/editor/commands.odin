package editor

import "core:sync"
import "core:unicode"
import "core:unicode/utf8"
import "../text"

Command_Proc :: proc(ed: ^Editor)

commands: map[string]Command_Proc

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
	register_command("delete_backward",    cmd_delete_backward)
	register_command("insert_newline",     cmd_insert_newline)
    register_command("cursor_word_left",     cmd_cursor_word_left)
    register_command("cursor_word_right",     cmd_cursor_word_right)
}

is_word :: proc(r: rune) -> bool {
    return unicode.is_letter(r) || unicode.is_digit(r) || r == '_'
}

insert_text :: proc(ed: ^Editor, s: string) {
    if len(s) == 0 {
        return
    }
    text.buffer_insert(&ed.doc, ed.cursor, s)
    ed.cursor += len(s)
    ed.desired_col = sync_col(ed)
}

insert_rune :: proc(ed: ^Editor, r: rune) {
    bytes, n := utf8.encode_rune(r)
    insert_text(ed, string(bytes[:n]))
}

cmd_cursor_left :: proc(ed: ^Editor) {
    start, _ := text.buffer_prev_rune(&ed.doc, ed.cursor)
    ed.cursor = start
    ed.desired_col = sync_col(ed)
}

cmd_cursor_right :: proc(ed: ^Editor) {
    end, _ := text.buffer_next_rune(&ed.doc, ed.cursor)
    ed.cursor = end
    ed.desired_col = sync_col(ed)
}

cmd_cursor_up :: proc(ed: ^Editor) {
    line := text.buffer_line_at(&ed.doc, ed.cursor)
    if line > 0 {
        ed.cursor = text.buffer_pos_at_line(&ed.doc, line - 1, ed.desired_col)
    }
}

cmd_cursor_down :: proc(ed: ^Editor) {
    line := text.buffer_line_at(&ed.doc, ed.cursor)
    if line + 1 < text.buffer_line_count(&ed.doc) {
        ed.cursor = text.buffer_pos_at_line(&ed.doc, line + 1, ed.desired_col)
    }
}

cmd_delete_backward :: proc(ed: ^Editor) {
    if ed.cursor <= 0 {
        return
    }

    start, size := text.buffer_prev_rune(&ed.doc, ed.cursor)
    text.buffer_delete(&ed.doc, start, size)
    ed.cursor = start
    ed.desired_col = sync_col(ed)
}

cmd_insert_newline :: proc(ed: ^Editor) {
    insert_text(ed, "\n")
}

cmd_cursor_word_left :: proc(ed: ^Editor) {
    pos := ed.cursor
    if pos == 0 {
        return
    }
    pos, _ = text.buffer_prev_rune(&ed.doc, pos)

    for pos > 0 {
        r, _ := text.buffer_peek_rune(&ed.doc, pos)
        if unicode.is_space(r) {
            pos, _ = text.buffer_prev_rune(&ed.doc, pos)
            continue
        }
        break
    }

    for pos > 0 {
        start, _ := text.buffer_prev_rune(&ed.doc, pos)
        r, _ := text.buffer_peek_rune(&ed.doc, start)
        if is_word(r) {
            pos = start
            continue
        }
        break
    }
    ed.cursor = pos
    ed.desired_col = sync_col(ed)
}

cmd_cursor_word_right :: proc(ed: ^Editor) {
    pos := ed.cursor
    n := text.buffer_len(&ed.doc)
    for pos < n {
        r, size := text.buffer_peek_rune(&ed.doc, pos)
        if size == 0 {
            break
        }
        if is_word(r) {
            pos += size
            continue
        }
        break
    }

    for pos < n {
        r, size := text.buffer_peek_rune(&ed.doc, pos)
        if size == 0 {
            break
        }
        if unicode.is_space(r) {
            pos += size
            continue
        }
        break
    }
    ed.cursor = pos
    ed.desired_col = sync_col(ed)
}