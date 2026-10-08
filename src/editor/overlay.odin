package editor

import "core:unicode/utf8"
import "core:strings"
import "../platform"
import "../text"

overlay_is_open :: proc(ed: ^Editor) -> bool {
    return ed.overlay.kind != .None
}

overlay_open :: proc(ed: ^Editor, kind: Overlay_Kind) {
    clear(&ed.overlay.text)
    ed.overlay.cursor = 0
    ed.overlay.kind = kind
}

overlay_close :: proc(ed: ^Editor) {
    clear(&ed.overlay.text)
    ed.overlay.cursor = 0
    ed.overlay.kind = .None
}

overlay_insert_rune :: proc(ed: ^Editor, r: rune) {
    if !overlay_is_open(ed) || r < 32 {
        return
    }
    bytes, n := utf8.encode_rune(r)
    inject_at(&ed.overlay.text, ed.overlay.cursor, ..bytes[:n])
    ed.overlay.cursor += n

    if ed.overlay.kind == .Switcher {
        n := switcher_match_count(ed, string(ed.overlay.text[:]))
        if n <= 0 {
            ed.overlay.sel = 0
        } else {
            ed.overlay.sel = clamp(ed.overlay.sel, 0, n - 1)
        }
    }
}

overlay_backspace :: proc(ed: ^Editor) {
    o := &ed.overlay
    if o.cursor <= 0 {
        return
    }
    _, size := utf8.decode_last_rune(string(o.text[:o.cursor]))
	if size <= 0 {
		return
	}
    remove_range(&o.text, o.cursor - size, o.cursor)
    o.cursor -= size

    if ed.overlay.kind == .Switcher {
        n := switcher_match_count(ed, string(ed.overlay.text[:]))
        if n <= 0 {
            ed.overlay.sel = 0
        } else {
            ed.overlay.sel = clamp(ed.overlay.sel, 0, n - 1)
        }
    }
}

overlay_key :: proc(ed: ^Editor, key: platform.Key, mods: platform.Mods) {
    o := &ed.overlay
    #partial switch key {
        case .Escape:
        {
            overlay_close(ed)
        }
        case .Backspace:
        {
            overlay_backspace(ed)
        }
        case .Left:
        {
            if o.cursor > 0 {
                _, size := utf8.decode_last_rune(string(o.text[:o.cursor]))
                o.cursor -= max(size, 1)
            }
        }
        case .Right:
        {
            if o.cursor < len(o.text) {
                _, size := utf8.decode_last_rune(string(o.text[:o.cursor]))
                o.cursor += max(size, 1)
            }
        }
        case .Up:
        {
            if o.kind == .Switcher && o.sel > 0 {
                o.sel -= 1
            }
        }
        case .Down:
        {
            if o.kind == .Switcher {
                n := switcher_match_count(ed, string(o.text[:]))
                if o.sel + 1 < n {
                    o.sel += 1
                }
            }
        }
        case .Enter:
        {
            if o.kind == .Find {
                find_next(ed)
            } else if o.kind == .Switcher {
                switcher_accept(ed)
            }
        }
        case .F:
        {
            if .Ctrl in mods {
                find_next(ed)
            }
        }
    }
}

cmd_find :: proc(ed: ^Editor) {
    overlay_open(ed, .Find)
}

ascii_fold :: proc(b: u8) -> u8 {
    if b >= 'A' && b <= 'Z' {
        return b + 32
    }
    return b
}

find_in_buffer :: proc(b: ^text.Buffer, query: string, start, end: int) -> (pos: int, ok: bool) {
    q := len(query)
    if q == 0 {
        return 0, false
    }
    n := text.buffer_len(b)
    start := clamp(start, 0, n)
    end := clamp(end, 0, n)
    if end - start < q {
        return 0, false
    }
    for i := start; i + q <= end; i += 1 {
        matched := true
        for j in 0 ..< q {
            a := text.buffer_byte(b, i + j)
            c := query[j]
            if settings.find_case_sensitive {
                if a != c {
                    matched = false
                    break
                }
            } else if ascii_fold(a) != ascii_fold(c) {
                matched = false
                break
            }
        }
        if matched {
            return i, true
        }
    }
    return 0, false
}

find_next :: proc(ed: ^Editor) {
    q := string(ed.overlay.text[:])
    if len(q) == 0 {
        return
    }
    v := active_view(ed)
    b := active_buffer(ed)
    n := text.buffer_len(&b.doc)
    pos, ok := find_in_buffer(&b.doc, q, v.cursor, n)
    if !ok {
        pos, ok = find_in_buffer(&b.doc, q, 0, v.cursor)
    }
    if !ok {
        return
    }
    v.sel_anchor = pos
    set_cursor(ed, pos + len(q), true)
}

switcher_match_count :: proc(ed:^ Editor, query: string) -> int {
    n := 0
    for &b in ed.buffers {
        name := buffer_display_name(&b)
        if len(query) == 0 || strings.contains(name, query) {
            n += 1
        }
    }
    return n
}

switcher_accept :: proc(ed: ^Editor) {
    query := string(ed.overlay.text[:])
    row := 0
    for i in 0 ..< len(ed.buffers) {
        name := buffer_display_name(&ed.buffers[i])
        if len(query) != 0 && !strings.contains(name, query) {
            continue
        }
        if row == ed.overlay.sel {
            view_show_buffer(ed, i)
            overlay_close(ed)
            return
        }
        row += 1
    }
}