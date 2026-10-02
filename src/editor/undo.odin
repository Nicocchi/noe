package editor

import "../text"

undo_clear_redo :: proc(ed: ^Editor) {
    for i in ed.undo_head ..< len(ed.undo) {
        delete(ed.undo[i].text)
    }
    resize(&ed.undo, ed.undo_head)
}

undo_record_insert :: proc(ed: ^Editor, pos: int, s: string) {
    if ed.playing || len(s) == 0 {
        return
    }

    editor_mark_dirty(ed)

    if ed.undo_head > 0 && ed.undo_head == len(ed.undo) {
        last := &ed.undo[ed.undo_head - 1]
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
    text_copy := make([]u8, len(s))
    copy(text_copy, s)
    append(&ed.undo, Undo_Op{.Insert, pos, string(text_copy)})
    ed.undo_head = len(ed.undo)
}

undo_record_delete :: proc(ed: ^Editor, pos: int, s: string) {
    if ed.playing || len(s) == 0 {
        return
    }

    editor_mark_dirty(ed)

    if ed.undo_head > 0 && ed.undo_head == len(ed.undo) {
        last := &ed.undo[ed.undo_head - 1]
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
    append(&ed.undo, Undo_Op{.Delete, pos, s})
    ed.undo_head = len(ed.undo)
}

undo_reset :: proc(ed: ^Editor) {
    for op in ed.undo {
        delete(op.text)
    }
    clear(&ed.undo)
    ed.undo_head = 0
}

cmd_undo :: proc(ed: ^Editor) {
    if ed.undo_head <= 0 {
        return
    }
    ed.undo_head -= 1
    op := ed.undo[ed.undo_head]
    ed.playing = true
    switch op.kind {
        case .Insert:
        {
            text.buffer_delete(&ed.doc, op.pos, len(op.text))
            set_cursor(ed, op.pos, false)
        }
        case .Delete:
        {
            text.buffer_insert(&ed.doc, op.pos, op.text)
            set_cursor(ed, op.pos + len(op.text), false)
        }
    }
    ed.playing = false
}

cmd_redo :: proc(ed: ^Editor) {
    if ed.undo_head >= len(ed.undo) {
        return
    }
    op := ed.undo[ed.undo_head]
    ed.undo_head += 1
    ed.playing = true
    switch op.kind {
        case .Insert:
        {
            text.buffer_insert(&ed.doc, op.pos, op.text)
            set_cursor(ed, op.pos + len(op.text), false)
        }
        case .Delete:
        {
            text.buffer_delete(&ed.doc, op.pos, len(op.text))
            set_cursor(ed, op.pos, false)
        }
    }
    ed.playing = false
}

has_newline :: proc(s: string) -> bool {
    for r in s {
        if r == '\n' {
            return true
        }
    }

    return false
}