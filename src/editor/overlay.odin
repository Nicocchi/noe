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
    ed.overlay.sel = 0
    ed.overlay.scroll = 0
}

overlay_close :: proc(ed: ^Editor) {
    clear(&ed.overlay.text)
    picker_clear(ed)
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

    if ed.overlay.kind == .Files {
        picker_clamp_sel(ed)
    }
}

overlay_insert_string :: proc(ed: ^Editor, s: string) {
    if !overlay_is_open(ed) || len(s) == 0 { return }
    cleaned := strip_cr(s)
    defer if cleaned != s {
        delete(cleaned)
    }
    line := cleaned
    for i in 0 ..< len(cleaned) {
        if cleaned[i] == '\n' {
            line = cleaned[:i]
            break
        }
    }
    if len(line) == 0 { return }
    inject_at(&ed.overlay.text, ed.overlay.cursor, ..transmute([]u8)line)
    ed.overlay.cursor += len(line)
    if ed.overlay.kind == .Switcher {
        n := switcher_match_count(ed, string(ed.overlay.text[:]))
        ed.overlay.sel = 0 if n <= 0 else clamp(ed.overlay.sel, 0, n - 1)
    }
    if ed.overlay.kind == .Files {
        picker_clamp_sel(ed)
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

    if ed.overlay.kind == .Files {
        picker_clamp_sel(ed)
    }
}

overlay_key :: proc(ed: ^Editor, key: platform.Key, mods: platform.Mods) {
    o := &ed.overlay
    #partial switch key {
        case .Escape:
        {
	        if o.kind == .New_File && len(o.rename_from) > 0 {
		        create_stop_rename(ed)
	        } else {
            	overlay_close(ed)
			}
        }
        case .Backspace:
        {
            overlay_backspace(ed)
        }
        case .Left:
        {
        	if o.kind == .New_File && len(o.rename_from) == 0 {
        		create_up(ed)
        	} else if o.cursor > 0 {
                _, size := utf8.decode_last_rune(string(o.text[:o.cursor]))
                o.cursor -= max(size, 1)
            }
        }
        case .Right:
        {
        	if o.kind == .New_File && len(o.rename_from) == 0 {
        		create_into(ed)
        	} else if o.kind == .New_File && o.cursor < len(o.text) {
                _, size := utf8.decode_last_rune(string(o.text[:o.cursor]))
                o.cursor += max(size, 1)
            } else if o.cursor < len(o.text) {
	            _, size := utf8.decode_last_rune(string(o.text[:o.cursor]))
	            o.cursor += max(size, 1)
            }
        }
        case .Up:
        {
            if (o.kind == .Switcher || o.kind == .Files || o.kind == .New_File) && o.sel > 0 {
                o.sel -= 1
                o.preview_sel = -1
            }
        }
        case .Down:
        {
            if (o.kind == .Switcher || o.kind == .Files || o.kind == .New_File) {
                n := 0
                if o.kind == .Switcher {
                    n = switcher_match_count(ed, string(o.text[:]))
                } else if o.kind == .New_File {
                	n = len(o.files)
                } else {
                    n = picker_match_count(ed, string(o.text[:]))
                }

                if o.sel + 1 < n {
                    o.sel += 1
                    o.preview_sel = -1
                }
            }
        }
        case .Enter:
        {
            if o.kind == .Find {
                find_next(ed)
            } else if o.kind == .Switcher {
                switcher_accept(ed)
            } else if o.kind == .Files {
                picker_accept(ed)
            } else if o.kind == .New_File {
            	if len(o.rename_from) > 0 {
	             	create_rename_accept(ed)
	             } else {
					create_accept(ed)
				}
            }
        }
        case .F:
        {
            if .Ctrl in mods {
                find_next(ed)
            }
        }
        case .C:
        {
            if .Ctrl in mods {
                q := string(o.text[:])
                if len(q) > 0 {
                    _ = platform.clipboard_set(ed.host, q)
                }
            }
        }
        case .V:
        {
            if .Ctrl in mods {
                s, ok := platform.clipboard_get(ed.host)
                if ok {
                    defer delete(s)
                    overlay_insert_string(ed, s)
                }
            }
        }
        case .X:
        {
            if .Ctrl in mods {
                q := string(o.text[:])
                if len(q) > 0 {
                    _ = platform.clipboard_set(ed.host, q)
                }
                clear(&o.text)
                o.cursor = 0
            }
        }
        case .R:
        {
        	if .Ctrl in mods && o.kind == .New_File {
         		create_rename_begin(ed)
         	}
        }
        case .D:
        {
        	if .Ctrl in mods && o.kind == .New_File {
	        	create_delete(ed)
	        }
        }
        case .W:
        {
            if .Ctrl in mods && o.kind == .Switcher {
                if id, ok := switcher_selected(ed); ok {
                    n := switcher_match_count(ed, string(o.text[:]))
                    if n <= 0 {
                        o.sel = 0
                    } else {
                        o.sel = clamp(o.sel, 0, n - 1)
                    }
                }
            }
        }
    }
}

cmd_find :: proc(ed: ^Editor) {
    overlay_open(ed, .Find)
    if !has_selection(ed) { return }
    lo, hi := selection_range(ed)
    if hi <= lo { return }
    b := active_buffer(ed)
    s := text.buffer_clone_range(&b.doc, lo, hi - lo)
    defer delete(s)
    overlay_insert_string(ed, s)
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

switcher_line :: proc(query: string) -> (line: int, ok: bool) {
	s := lex_trim(query)
	if len(s) == 0 { return }
	for i in 0 ..< len(s) {
		if s[i] < '0' || s[i] > '9' { return }
	}
	n := 0
	for i in 0 ..< len(s) {
		n = n * 10 + int(s[i] - '0')
		if n > 1_000_000_000 {
			n = 1_000_000_000
			break
		}
	}
	if n <= 0 { return }
	return n, true
}

switcher_goto_line :: proc(ed: ^Editor, line: int) {
	b := active_buffer(ed)
	n := text.buffer_line_count(&b.doc)
	if n <= 0 {
		overlay_close(ed)
		return
	}
	i := clamp(line, 1, n) - 1
	set_cursor(ed, text.buffer_pos_at_line(&b.doc, i, 0), false)
	overlay_close(ed)
}

switcher_match_count :: proc(ed:^ Editor, query: string) -> int {
	if _, ok := switcher_line(query); ok {
		return 1
	}
    n := 0
    for &b in ed.buffers {
        name := buffer_status_path(ed, &b)
        if len(query) == 0 || strings.contains(name, query) {
            n += 1
        }
    }
    return n
}

switcher_accept :: proc(ed: ^Editor) {
    query := string(ed.overlay.text[:])
    if line, ok := switcher_line(query); ok {
    	switcher_goto_line(ed, line)
    	return
    }
    row := 0
    for i in 0 ..< len(ed.buffers) {
        name := buffer_status_path(ed, &ed.buffers[i])
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

switcher_selected :: proc(ed: ^Editor) -> (id: int, ok: bool) {
    query := string(ed.overlay.text[:])
    if _, line_ok := switcher_line(query); line_ok { return }
    row := 0
    for i in 0 ..< len(ed.buffers) {
        name := buffer_status_path(ed, &ed.buffers[i])
        if len(query) != 0 && !strings.contains(name, query) { continue }
        if row == ed.overlay.sel { return i, true }
        row += 1
    }
    return
}