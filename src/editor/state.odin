package editor

import "../text"

Editor :: struct {
    doc:            text.Buffer,
    cursor:         int,
    desired_col:    int,
}

editor_init :: proc(ed: ^Editor, starter: string) {
    text.buffer_init(&ed.doc, 4096)
    text.buffer_insert(&ed.doc, 0, starter)
    ed.cursor = text.buffer_len(&ed.doc)
    ed.desired_col = sync_col(ed)
}

editor_destroy :: proc(ed: ^Editor) {
    text.buffer_destroy(&ed.doc)
    ed^ = {}
}

sync_col :: proc(ed: ^Editor) -> int {
    line := text.buffer_line_at(&ed.doc, ed.cursor)
    return ed.cursor - text.buffer_line_start(&ed.doc, line)
}