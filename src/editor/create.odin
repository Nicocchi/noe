package editor

import "core:os"
import "core:strings"
import "core:path/filepath"
import "core:fmt"

create_list :: proc(ed: ^Editor) {
	o := &ed.overlay
	for s in o.files {
		delete(s)
	}
	clear(&o.files)
	clear(&o.entry_dir)

	entries, err := os.read_all_directory_by_path(o.browse, context.allocator)
	if err != nil { return }
	defer os.file_info_slice_delete(entries, context.allocator)

	dirs: [dynamic]string
	files: [dynamic]string
	defer delete(dirs)
	defer delete(files)
	for e in entries {
		if e.name == "." || e.name == ".." || picker_skip_dir(ed, e.name) {
			continue
		}
		path, perr := filepath.join({o.browse, e.name})
		if perr != nil {
			continue
		}
		if e.type == .Directory {
			append(&dirs, path)
		} else {
			append(&files, path)
		}
	}

	for i in 0 ..< len(dirs) {
		for j in i + 1 ..< len(dirs) {
			if dirs[j] < dirs[i] {
				dirs[i], dirs[j] = dirs[j], dirs[i]
			}
		}
	}

	for i in 0 ..< len(files) {
		for j in i + 1 ..< len(files) {
			if files[j] < files[i] {
				files[i], files[j] = files[j], files[i]
			}
		}
	}

	for p in dirs {
		append(&o.files, p)
		append(&o.entry_dir, true)
	}

	for p in files {
		append(&o.files, p)
		append(&o.entry_dir, false)
	}
}

create_open :: proc(ed: ^Editor) {
	picker_clear(ed)
	overlay_open(ed, .New_File)
	root: string
	if ed.project.loaded {
		root = strings.clone(ed.project.dir)
	} else {
		cwd, err := os.get_working_directory(context.allocator)
		if err != nil { return }
		root = cwd
	}
	ed.overlay.root = root
	ed.overlay.browse = strings.clone(root)
	create_list(ed)
}

create_up :: proc(ed: ^Editor) {
	o := &ed.overlay
	if o.browse == o.root { return }
	parent := strings.clone(filepath.dir(o.browse))
	child := strings.clone(o.browse)
	defer delete(child)
	delete(o.browse)
	o.browse = parent
	create_list(ed)
	o.sel = 0
	for p, i in o.files {
		if p == child {
			o.sel = i
			break
		}
	}
	o.scroll = 0
}

create_into :: proc(ed: ^Editor) {
	o := &ed.overlay
	if o.sel < 0 || o.sel >= len(o.files) || !o.entry_dir[o.sel] {
		return
	}
	next := strings.clone(o.files[o.sel])
	delete(o.browse)
	o.browse = next
	o.sel = 0
	o.scroll = 0
	create_list(ed)
}

create_dest :: proc(ed: ^Editor, raw: string) -> (path: string, ok: bool) {
	s := lex_trim(raw)
	for len(s) > 0 && (s[len(s) - 1] == '/' || s[len(s) - 1] == '\\') {
		s = s[:len(s) - 1]
	}
	if len(s) == 0 { return }
	from_root := s[0] == '/' || s[0] == '\\'
	for len(s) > 0 && (s[0] == '/' || s[0] == '\\') {
		s = s[1:]
	}
	if len(s) == 0 { return }
	fixed := make([]u8, len(s))
	defer delete(fixed)
	for i in 0 ..< len(s) {
	    if s[i] == '/' || s[i] == '\\' {
	        fixed[i] = filepath.SEPARATOR
	    } else {
	        fixed[i] = s[i]
	    }
	}
	base := ed.overlay.browse
	if from_root { base = ed.overlay.root }
	joined, perr := filepath.join({base, string(fixed)})
	if perr != nil { return }
	path = joined
	ok = true
	return
}

view_open_path :: proc(ed: ^Editor, path: string) -> bool {
	for i in 0 ..< len(ed.buffers) {
		if ed.buffers[i].path == path {
			view_show_buffer(ed, i)
			return true
		}
	}
	prev := active_view(ed).buf_id
	append(&ed.buffers, Buffer{scroll_x_dirty = true})
	active_view(ed).buf_id = len(ed.buffers) - 1
	if !editor_load_path(ed, path) {
		active_view(ed).buf_id = prev
		pop(&ed.buffers)
		return false
	}
	b := active_buffer(ed)
	if b.undo == nil {
		b.undo = make([dynamic]Undo_Op)
	}
	return true
}

create_accept :: proc(ed: ^Editor) {
	name := string(ed.overlay.text[:])
	if len(lex_trim(name)) == 0 {
		create_into(ed)
		return
	}
	path, ok := create_dest(ed, name)
	if !ok { return }
	defer delete(path)
	dir := filepath.dir(path)
	if len(dir) > 0 && os.make_directory_all(dir) != nil {
		fmt.eprintln("Could not create folder:", dir)
		return
	}
	if !os.exists(path) && os.write_entire_file(path, "") != nil {
		fmt.eprintln("Could not create file:", path)
		return
	}
	if !view_open_path(ed, path) {
		fmt.eprintln("Could not open file:", path)
		return
	}
	overlay_close(ed)
}

create_stop_rename :: proc(ed: ^Editor) {
	o := &ed.overlay
	delete(o.rename_from)
	o.rename_from = ""
	clear(&o.text)
	o.cursor = 0
}

create_rename_begin :: proc(ed: ^Editor) {
	o := &ed.overlay
	if o.sel < 0 || o.sel >= len(o.files) {
		return
	}
	delete(o.rename_from)
	o.rename_from = strings.clone(o.files[o.sel])
	name := filepath.base(o.rename_from)
	clear(&o.text)
	append(&o.text, ..transmute([]byte)name)
	o.cursor = len(o.text)
}

buffer_under :: proc(path, dir: string) -> bool {
	if len(path) <= len(dir) || !strings.has_prefix(path, dir) {
		return false
	}
	c := path[len(dir)]
	return c == '/' || c == '\\'
}

create_remap_buffers :: proc(ed: ^Editor, old, new: string) {
	for &b in ed.buffers {
		if len(b.path) == 0 { continue }
		if b.path == old {
			delete(b.path)
			b.path = strings.clone(new)
			b.lex_id = lex_index_from_path(b.path)
			b.lex_dirty = true
			continue
		}
		if buffer_under(b.path, old) {
			rest := b.path[len(old):]
			joined, jerr := strings.concatenate({new, rest})
			if jerr != nil { continue }
			delete(b.path)
			b.path = joined
		}
	}
	editor_update_title(ed)
}

create_drop_buffers :: proc(ed: ^Editor, old: string, as_dir: bool) {
	for &b in ed.buffers {
		if len(b.path) == 0 { continue }
		if b.path == old || (as_dir && buffer_under(b.path, old)) {
			delete(b.path)
			b.path = ""
			b.dirty = true
			b.lex_dirty = true
		}
	}
	editor_update_title(ed)
}

create_rename_accept :: proc(ed: ^Editor) {
	o := &ed.overlay
	name := lex_trim(string(o.text[:]))
	if len(name) == 0 || name == "." || name == ".." { return }
	for i in 0 ..< len(name) {
		if name[i] == '/' || name[i] == '\\' {
			return
		}
	}
	old_name := filepath.base(o.rename_from)
	if name == old_name {
		create_stop_rename(ed)
		return
	}
	dest, perr := filepath.join({o.browse, name})
	if perr != nil { return }
	defer delete(dest)
	if !strings.equal_fold(name, old_name) && os.exists(dest) {
		fmt.eprintln("Already exists:", name)
		return
	}
	if os.rename(o.rename_from, dest) != nil {
		fmt.eprintln("Could not rename: ", old_name)
		return
	}
	create_remap_buffers(ed, o.rename_from, dest)
	create_stop_rename(ed)
	create_list(ed)
	o.sel = 0
	for p, i in o.files {
		if p == dest {
			o.sel = i
			break
		}
	}
}

create_delete :: proc(ed: ^Editor) {
	o := &ed.overlay
	if o.sel < 0 || o.sel >= len(o.files) { return }
	path := strings.clone(o.files[o.sel])
	defer delete(path)
	as_dir := o.entry_dir[o.sel]
	err := os.remove(path)
	if err != nil && as_dir {
		err = os.remove_all(path)
	}
	if err != nil {
		fmt.eprintln("Could not delete:", filepath.base(path))
		return
	}
	create_drop_buffers(ed, path, as_dir)
	create_stop_rename(ed)
	create_list(ed)
	if o.sel >= len(o.files) {
		o.sel = max(len(o.files) - 1, 0)
	}
}

cmd_file_new :: proc(ed: ^Editor) {
	create_open(ed)
}
