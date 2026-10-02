package editor

import "core:os"
import "core:strings"
import "core:fmt"
import "../text"
import "../platform"

editor_set_path :: proc(ed: ^Editor, path: string) {
    delete(ed.path)
    ed.path = strings.clone(path)
}

editor_load_path :: proc(ed: ^Editor, path: string) -> bool {
    data, err := os.read_entire_file(path, context.allocator)
    if err != nil {
        return false
    }
    defer delete(data)

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

    text.buffer_destroy(&ed.doc)
    text.buffer_init(&ed.doc, max(len(cleaned) + 64, 4096))
    text.buffer_insert(&ed.doc, 0, string(cleaned))
    undo_reset(ed)
    editor_set_path(ed, path)
    set_cursor(ed, 0, false)
    ed.scroll_y = 0
    ed.dirty = false
    editor_update_title(ed)
    return true
}

editor_save :: proc(ed: ^Editor) -> bool {
    if len(ed.path) == 0 {
        return editor_save_as(ed)
    }
    s := text.buffer_clone_string(&ed.doc)
    defer delete(s)
    if os.write_entire_file(ed.path, s) != nil {
        return false
    }
    ed.dirty = false
    editor_update_title(ed)
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

editor_display_name :: proc(ed: ^Editor) -> string {
    if len(ed.path) == 0 {
        return "untitled"
    }
    i := len(ed.path) - 1
    for i >= 0 && ed.path[i] != '/' && ed.path[i] != '\\' {
        i -= 1
    }
    return ed.path[i + 1:]
}

editor_update_title :: proc(ed: ^Editor) {
    star := ""
    if ed.dirty {
        star = " *"
    }
    title := fmt.tprintf("%s%s - NOE", editor_display_name(ed), star)
    platform.window_set_title(ed.host, title)
}

editor_mark_dirty :: proc(ed: ^Editor) {
    if ed.playing || ed.dirty {
        return
    }
    ed.dirty = true
    editor_update_title(ed)
}

cmd_file_open :: proc(ed: ^Editor) {
    path, ok := platform.dialog_open_path(ed.host)
    if !ok {
        return
    }
    defer delete(path)
    _ = editor_load_path(ed, path)
}

cmd_file_save :: proc(ed: ^Editor) {
    _ = editor_save(ed)
}

cmd_file_save_as :: proc(ed: ^Editor) {
    _ = editor_save_as(ed)
}