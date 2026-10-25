package editor

import "core:os"
import "core:strings"
import "core:path/filepath"
import "../text"

PICKER_MAX :: 4000
PICKER_PREVIEW_MAX :: 32 * 1024

picker_skip_dir :: proc(ed: ^Editor, name: string) -> bool {
	if ed.project.loaded && len(ed.project.blacklist) > 0 {
		for s in ed.project.blacklist {
			if s == name {
				return true
			}
		}
		return false
	}
    return name == ".git" || name == ".history"
}

fuzzy_match :: proc(s, q: string) -> bool {
    if len(q) == 0 {
        return true
    }
    j := 0
    for i in 0 ..< len(s) {
        if ascii_fold(s[i]) == ascii_fold(q[j]) {
            j += 1
            if j == len(q) {
                return true
            }
        }
    }
    return false
}

picker_rel :: proc(root, path: string) -> string {
    if len(root) > 0 && strings.has_prefix(path, root) {
        r := path[len(root):]
        if len(r) > 0 && (r[0] == '/' || r[0] == '\\') {
            r = r[1:]
        }
        return r
    }
    return path
}

picker_clear :: proc(ed: ^Editor) {
    o := &ed.overlay
    for s in o.files {
        delete(s)
    }
    clear(&o.files)
    clear(&o.entry_dir)
    delete(o.entry_dir)
    o.entry_dir = {}
    delete(o.browse)
    o.browse = ""
    delete(o.rename_from)
    o.rename_from = ""
    delete(o.root)
    o.root = ""
    delete(o.preview)
    o.preview_tokens = {}
    o.preview = {}
    delete(o.preview_path)
    o.preview_path = ""
    o.preview_sel = -1
    o.scroll = 0
    o.sel = 0
}

picker_walk :: proc(ed: ^Editor, dir: string) {
    if len(ed.overlay.files) >= PICKER_MAX {
        return
    }
    entries, err := os.read_all_directory_by_path(dir, context.allocator)
    if err != nil {
        return
    }
    defer os.file_info_slice_delete(entries, context.allocator)
    for e in entries {
        if e.name == "." || e.name == ".." {
            continue
        }
        path, perr := filepath.join({dir, e.name})
        if perr != nil {
            continue
        }
        if e.type == .Directory {
            if picker_skip_dir(ed, e.name) {
                delete(path)
                continue
            }
            picker_walk(ed, path)
            delete(path)
        } else {
        	if ed.project.loaded && len(ed.project.patterns) > 0 {
        		ext := ""
        		for k := len(e.name) - 1; k >= 0; k -= 1 {
        			if e.name[k] == '.' {
        				ext = e.name[k + 1:]
        				break
        			}
        		}
        		ok := false
        		for pat in ed.project.patterns {
        			if eq_ext(ext, pat) {
        				ok = true
        				break
        			}
        		}
        		if !ok {
        			delete(path)
        			continue
        		}
        	}
            append(&ed.overlay.files, path)
        }
    }
}

picker_open :: proc(ed: ^Editor) {
    picker_clear(ed)
    overlay_open(ed, .Files)
    if ed.project.loaded {
    	ed.overlay.root = strings.clone(ed.project.dir)
    	picker_walk(ed, ed.project.dir)
    	ed.overlay.preview_sel = -1
    	return
    }
    root, err := os.get_working_directory(context.allocator)
    if err != nil {
        return
    }
    ed.overlay.root = root
    picker_walk(ed, root)
    ed.overlay.preview_sel = -1
}

picker_match_count :: proc(ed: ^Editor, query: string) -> int {
    n := 0
    for p in ed.overlay.files {
        if fuzzy_match(picker_rel(ed.overlay.root, p), query) {
            n += 1
        }
    }
    return n
}

picker_sel_path :: proc(ed: ^Editor) -> (path: string, ok: bool) {
    query := string(ed.overlay.text[:])
    row := 0
    for p in ed.overlay.files {
        if !fuzzy_match(picker_rel(ed.overlay.root, p), query) {
            continue
        }
        if row == ed.overlay.sel {
            return p, true
        }
        row += 1
    }
    return "", false
}

picker_clamp_sel :: proc(ed: ^Editor) {
    n := picker_match_count(ed, string(ed.overlay.text[:]))
    if n <= 0 {
        ed.overlay.sel = 0
    } else {
        ed.overlay.sel = clamp(ed.overlay.sel, 0, n - 1)
    }
    ed.overlay.preview_sel = -1
}

picker_sync_preview :: proc(ed: ^Editor) {
    o := &ed.overlay
    path, ok := picker_sel_path(ed)
    if !ok {
        delete(o.preview)
        o.preview = {}
        return
    }
    if o.preview_sel == o.sel && o.preview_path == path {
        return
    }
    delete(o.preview)
    delete(o.preview_path)
    delete(o.preview_tokens)
    o.preview_tokens = {}
    o.preview = {}
    o.preview_path = strings.clone(path)
    o.preview_sel = o.sel
    data, err := os.read_entire_file(path, context.allocator)
    if err != nil {
        return
    }
    for b in data[:min(len(data), 512)] {
        if b == 0 {
            delete(data)
            o.preview = {}
            return
        }
    }
    n := min(len(data), PICKER_PREVIEW_MAX)
    out := make([]u8, n)
    copy(out, data[:n])
    delete(data)
    o.preview = out
    scratch: Buffer
    text.buffer_init(&scratch.doc, n + 64)
    text.buffer_insert(&scratch.doc, 0, string(out))
    scratch.lex_id = lex_index_from_path(path)
    buffer_lex(&scratch)
    delete(o.preview_tokens)
    o.preview_tokens = scratch.tokens
    scratch.tokens = {}
    text.buffer_destroy(&scratch.doc)
}

picker_accept :: proc(ed: ^Editor) {
    path, ok := picker_sel_path(ed)
    if !ok {
        return
    }
    view_open_path(ed, path)
    overlay_close(ed)
}

cmd_file_finder :: proc(ed: ^Editor) {
    picker_open(ed)
}
