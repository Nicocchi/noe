package editor

import "../text"

undo_clear_redo :: proc(ed: ^Editor) {
    b := active_buffer(ed)
    for i in b.undo_head ..< len(b.undo) {
        delete(b.undo[i].text)
        delete(b.undo[i].before)
        delete(b.undo[i].after)
    }
    resize(&b.undo, b.undo_head)
}

undo_record_insert :: proc(ed: ^Editor, pos: int, s: string) {
    b := active_buffer(ed)
    if b.playing || len(s) == 0 {
        return
    }

    editor_mark_dirty(ed)

    if b.undo_head > 0 && b.undo_head == len(b.undo) {
        last := &b.undo[b.undo_head - 1]
        can_merge :=
            last.kind == .Insert &&
            last.pos + len(last.text) == pos &&
            !has_newline(s) &&
            !has_newline(last.text)
        if can_merge {
            n := len(last.text) + len(s)
            out := make([]u8, n)
            copy(out, last.text)
            copy(out[len(last.text):], s)
            delete(last.text)
            last.text = string(out)
            return
        }
    }

    undo_clear_redo(ed)
    if b.edit_depth == 0 {
        b.undo_group += 1
    }
    text_copy := make([]u8, len(s))
    copy(text_copy, s)
    append(&b.undo, Undo_Op{kind = .Insert, pos = pos, text = string(text_copy), group = b.undo_group})
    b.undo_head = len(b.undo)
    if len(b.pending_before) > 0 {
        b.undo[b.undo_head - 1].before = b.pending_before
        b.pending_before = {}
    }
}

undo_record_delete :: proc(ed: ^Editor, pos: int, s: string) {
    b := active_buffer(ed)
    if b.playing || len(s) == 0 {
        return
    }

    editor_mark_dirty(ed)

    if b.undo_head > 0 && b.undo_head == len(b.undo) {
        last := &b.undo[b.undo_head - 1]
        can_merge :=
            last.kind == .Delete &&
            pos + len(s) == last.pos &&
            !has_newline(s) &&
            !has_newline(last.text)
        if can_merge {
            n := len(s) + len(last.text)
            out := make([]u8, n)
            copy(out, s)
            copy(out[len(s):], last.text)
            delete(last.text)
            last.text = string(out)
            last.pos = pos
            return
        }
    }

    undo_clear_redo(ed)
    if b.edit_depth == 0 {
        b.undo_group += 1
    }
    append(&b.undo, Undo_Op{kind = .Delete, pos = pos, text = s, group = b.undo_group})
    b.undo_head = len(b.undo)
    if len(b.pending_before) > 0 {
        b.undo[b.undo_head - 1].before = b.pending_before
        b.pending_before = {}
    }
}

undo_reset :: proc(ed: ^Editor) {
    b := active_buffer(ed)
    for op in b.undo {
        delete(op.text)
        delete(op.before)
        delete(op.after)
    }
    clear(&b.undo)
    b.undo_head = 0
}

cmd_undo :: proc(ed: ^Editor) {
    v := active_view(ed)
    b := active_buffer(ed)
    if b.undo_head <= 0 {
        return
    }
    g := b.undo[b.undo_head - 1].group
    b.playing = true
    for b.undo_head > 0 && b.undo[b.undo_head - 1].group == g {
        b.undo_head -= 1
        op := b.undo[b.undo_head]
        switch op.kind {
            case .Insert:
            {
                text.buffer_delete(&b.doc, op.pos, len(op.text))
                b.scroll_x_dirty = true
                view_nudge(ed, v.buf_id, op.pos, -len(op.text))
            }
            case .Delete:
            {
                text.buffer_insert(&b.doc, op.pos, op.text)
                b.scroll_x_dirty = true
                view_nudge(ed, v.buf_id, op.pos, len(op.text))
            }
        }
    }
    b.playing = false
    if b.undo_head < len(b.undo) {
        op := b.undo[b.undo_head]
        if len(op.before) > 0 {
            caret_restore(ed, op.before)
        } else if op.kind == .Insert {
            set_cursor(ed, op.pos, false)
        } else {
            set_cursor(ed, op.pos + len(op.text), false)
        }
    }
    b.typing = false
    b.lex_dirty = true
}

cmd_redo :: proc(ed: ^Editor) {
    v := active_view(ed)
    b := active_buffer(ed)
    if b.undo_head >= len(b.undo) {
        return
    }
    g := b.undo[b.undo_head].group
    b.playing = true
    for b.undo_head < len(b.undo) && b.undo[b.undo_head].group == g {
        op := b.undo[b.undo_head]
        b.undo_head += 1
        switch op.kind {
            case .Insert:
            {
                text.buffer_insert(&b.doc, op.pos, op.text)
                b.scroll_x_dirty = true
                view_nudge(ed, v.buf_id, op.pos, +len(op.text))
            }
            case .Delete:
            {
                text.buffer_delete(&b.doc, op.pos, len(op.text))
                b.scroll_x_dirty = true
                view_nudge(ed, v.buf_id, op.pos, -len(op.text))
            }
        }
    }
    b.playing = false
    if b.undo_head > 0 {
        op := b.undo[b.undo_head - 1]
        if len(op.after) > 0 {
            caret_restore(ed, op.after)
        } else if op.kind == .Insert {
            set_cursor(ed, op.pos + len(op.text), false)
        } else {
            set_cursor(ed, op.pos, false)
        }
    }
    b.typing = false
    b.lex_dirty = true
}

has_newline :: proc(s: string) -> bool {
    for r in s {
        if r == '\n' {
            return true
        }
    }

    return false
}

begin_edit :: proc(ed: ^Editor, continue_group := false) {
    b := active_buffer(ed)
    if b.playing {
        return
    }
    if b.edit_depth == 0 {
        if !(continue_group && b.typing) {
            b.undo_group += 1
            b.typing = false
            delete(b.pending_before)
            b.pending_before = caret_snapshot(ed)
        }
    }
    b.edit_depth += 1
}

end_edit :: proc(ed: ^Editor) {
    b := active_buffer(ed)
    if b.playing {
        return
    }
    if b.edit_depth > 0 {
        b.edit_depth -= 1
    }

    if b.edit_depth == 0 && b.undo_head > 0 {
        last := &b.undo[b.undo_head - 1]
        if last.group == b.undo_group {
            delete(last.after)
            last.after = caret_snapshot(ed)
        }
    }

    if b.edit_depth == 0 {
        script_run_hooks(ed, "change", active_buffer(ed).path)
        b.lex_dirty = true
    }
}