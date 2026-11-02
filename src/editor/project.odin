package editor

import "core:os"
import "core:strings"
import "core:path/filepath"
import "core:fmt"

PROJECT_FILE :: "project.noe"

startup_dir :: proc() -> bool {
    if len(os.args) < 2 {
        return false
    }
    path := os.args[1]
    if !os.is_directory(path) {
        fmt.eprintln("not a folder:", path)
        return false
    }
    if os.set_working_directory(path) != nil {
        fmt.eprintln("could not open folder:", path)
        return false
    }
    return true
}

project_clear :: proc(ed: ^Editor) {
	p := &ed.project
	delete(p.dir)
	delete(p.name)
	for s in p.patterns { delete(s) }
	for s in p.blacklist { delete(s) }
	for c in p.commands {
		delete(c.name)
		delete(c.cmd)
	}
	delete(p.patterns)
	delete(p.blacklist)
	delete(p.commands)
	for i in 0 ..< 12 {
		delete(p.fkey[i])
		p.fkey[i] = ""
	}
	p^ = {}
}

project_split_cmd :: proc(line: string) -> (name, cmd: string) {
	for k in 0 ..< len(line) {
		if line[k] == ' ' || line[k] == '\t' {
			return lex_trim(line[:k]), lex_trim(line[k + 1:])
		}
	}
	return line, ""
}

project_parse :: proc(ed: ^Editor, dir: string, data: []u8) {
	project_clear(ed)
	p := &ed.project
	p.dir = strings.clone(dir)
	p.loaded = true
	section := 0 // 1 patterns, 2 blacklist, 3 commands, 4 fkey
	start := 0
	for i in 0 ..= len(data) {
		if i < len(data) && data[i] != '\n' {
			continue
		}
		line := lex_trim(string(data[start:i]))
		start = i + 1
		if len(line) == 0 || line[0] == '#' {
			continue
		}
		if strings.has_prefix(line, "name:") {
			p.name = strings.clone(lex_trim(line[5:]))
			continue
		}
		if line == "patterns:" { section = 1; continue }
		if line == "blacklist:" { section = 2; continue }
		if line == "commands:" { section = 3; continue }
		if line == "fkey:" { section = 4; continue }
		switch section {
			case 1:
			{
				append(&p.patterns, strings.clone(line))
			}
			case 2:
			{
				append(&p.blacklist, strings.clone(line))
			}
			case 3:
			{
				n, c := project_split_cmd(line)
				append(&p.commands, Project_Cmd{
					name = strings.clone(n),
					cmd = strings.clone(c)
				})
			}
			case 4:
			{
				n, c := project_split_cmd(line)
				idx := 0
				for ch in n {
					if ch >= '0' && ch <= '9' {
						idx = idx * 10 + int(ch - '0')
					}
				}
				if idx >= 1 && idx <= 12 {
					p.fkey[idx - 1] = strings.clone(c)
				}
			}
		}
	}
}

project_find_from :: proc(start_dir: string) -> (path, dir: string, ok: bool) {
	dir = start_dir
	for len(dir) > 0 {
		cand, err := filepath.join({dir, PROJECT_FILE})
		if err == nil {
			data, rerr := os.read_entire_file(cand, context.allocator)
			if rerr == nil {
				delete(data)
				return cand, dir, true
			}
			delete(cand)
		}
		parent := filepath.dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return
}

project_load :: proc(ed: ^Editor) {
	start, err := os.get_working_directory(context.allocator)
	if err != nil {
		return
	}
	defer delete(start)
	path, dir, ok := project_find_from(start)
	if !ok {
		b := active_buffer(ed)
		if len(b.path) > 0 {
			path, dir, ok = project_find_from(filepath.dir(b.path))
		}
	}
	defer delete(path)
	if !ok {
		project_clear(ed)
		return
	}
	file, jerr := filepath.join({dir, PROJECT_FILE})
	if jerr != nil {
		return
	}
	defer delete(file)
	data, rerr := os.read_entire_file(file, context.allocator)
	if rerr != nil {
		return
	}
	defer delete(data)
	project_parse(ed, dir, data)
}
