package editor

import "core:os"
import "core:strings"
import "core:path/filepath"
import "core:fmt"

import "../text"

Token_Kind :: enum {
    Ident,
    Keyword,
    Number,
    String,
    Comment,
    Punct,
    Operator,
    Directive,
    Function,
    Type
}

Token :: struct {
    kind:   Token_Kind,
    pos:    int,
    len:    int
}

Lex_Mark :: struct {
    open:   string,
    close:  string
}

Lex_File :: struct {
    name:       string,
    extensions: [dynamic]string,
    keywords:   [dynamic]string,
    ops:        [dynamic]string,
    comments:   [dynamic]Lex_Mark,
    directive:  string
}

lex_files: [dynamic]Lex_File

lex_file_of :: proc(b: ^Buffer) -> ^Lex_File {
    if b.lex_id >= 0 && b.lex_id < len(lex_files) {
        return &lex_files[b.lex_id]
    }
    return nil
}

lex_index_named :: proc(name: string) -> int {
    for f, i in lex_files {
        if f.name == name {
            return i
        }
    }
    if len(lex_files) > 0 {
        return 0
    }
    return -1
}

lex_index_from_path :: proc(path: string) -> int {
    i := len(path) - 1
    for i >= 0 && path[i] != '.' && path[i] != '/' && path[i] != '\\' {
        i -= 1
    }
    if i >= 0 && path[i] == '.' {
        ext := path[i + 1:]
        for f, fi in lex_files {
            for e in f.extensions {
                if eq_ext(ext, e) {
                    return fi
                }
            }
        }
    }
    return lex_index_named("odin")
}

lex_trim :: proc(s: string) -> string {
    lo, hi := 0, len(s)
    for lo < hi && (s[lo] == ' ' || s[lo] == '\t' || s[lo] == '\r') {
        lo += 1
    }
    for hi > lo && (s[hi - 1] == ' ' || s[hi - 1] == '\t' || s[hi - 1] == '\r') {
        hi -= 1
    }
    return s[lo:hi]
}

lex_clear :: proc() {
    for &f in lex_files {
        delete(f.name)
        for s in f.extensions { delete(s) }
        for s in f.keywords { delete(s) }
        for s in f.ops { delete(s) }
        delete(f.extensions)
        delete(f.keywords)
        delete(f.ops)
        for m in f.comments {
            if len(m.open) > 0 {
                delete(m.open)
            }
            if len(m.close) > 0 {
                delete(m.close)
            }
        }
        delete(f.comments)
        if len(f.directive) > 0 {
            delete(f.directive)
        }
    }

    delete(lex_files)
    lex_files = nil
}

lex_sort_ops :: proc(ops: ^[dynamic]string) {
    for i in 0 ..< len(ops) {
        for j in i + 1 ..< len(ops) {
            if len(ops[j]) > len(ops[i]) {
                ops[i], ops[j] = ops[j], ops[i]
            }
        }
    }
}

lex_split_mark :: proc(line: string) -> (open, close: string) {
    for k in 0 ..< len(line) {
        if line[k] == ' ' || line[k] == '\t' {
            return lex_trim(line[:k]), lex_trim(line[k + 1:])
        }
    }
    return line, ""
}

lex_sort_marks :: proc(marks: ^[dynamic]Lex_Mark) {
    for i in 0 ..< len(marks) {
        for j in i + 1 ..< len(marks) {
            if len(marks[j].open) > len(marks[i].open) {
                marks[i], marks[j] = marks[j], marks[i]
            }
        }
    }
}

lex_dir :: proc() -> (dir: string, ok: bool) {
    root, err := os.user_config_dir(context.allocator, true)
    if err != nil {
        return
    }
    defer delete(root)
    dir, err = filepath.join({root, "noe", "lex"})
    if err != nil {
        return
    }
    _ = os.make_directory_all(dir)
    ok = true
    return
}

lex_load_file :: proc(path: string) {
    data, err := os.read_entire_file(path, context.allocator)
    if err != nil {
        return
    }
    defer delete(data)
    f: Lex_File
    section := 0 // 1 ext, 2 kw, 3 ops
    start := 0
    for i in 0 ..= len(data) {
        if i < len(data) && data[i] != '\n' {
            continue
        }
        line := lex_trim(string(data[start:i]))
        start = i + 1
        if len(line) == 0 {
            continue
        }
        if line[0] == '#' && len(line) > 1 {
        	continue
        }
        if strings.has_prefix(line, "name:") {
            f.name = strings.clone(lex_trim(line[5:]))
            continue
        }
        if strings.has_prefix(line, "directive:") {
            f.directive = strings.clone(lex_trim(line[len("directive:"):]))
            continue
        }
        if line == "extensions:" { section = 1; continue }
        if line == "keywords:"   { section = 2; continue }
        if line == "ops:"        { section = 3; continue }
        if line == "comments:"   { section = 4; continue }
        if section == 4 {
            open, close := lex_split_mark(line)
            m: Lex_Mark
            if len(open) > 0 {
                m.open = strings.clone(open)
            }
            if len(close) > 0 {
                m.close = strings.clone(close)
            }
            append(&f.comments, m)
        }
        word := strings.clone(line)
        switch section {
        case 1: append(&f.extensions, word)
        case 2: append(&f.keywords, word)
        case 3: append(&f.ops, word)
        case:   delete(word)
        }
    }
    lex_sort_ops(&f.ops)
    lex_sort_marks(&f.comments)
    append(&lex_files, f)
}

lex_load_all :: proc() {
    lex_clear()
    dir, ok := lex_dir()
    if !ok {
        return
    }
    defer delete(dir)
    entries, err := os.read_all_directory_by_path(dir, context.allocator)
    if err != nil {
        fmt.eprintln("lex:", err)
        return
    }
    defer os.file_info_slice_delete(entries, context.allocator)
    for e in entries {
        if e.type == .Directory || !strings.has_suffix(e.name, ".lex") {
            continue
        }
        path, perr := filepath.join({dir, e.name})
        if perr != nil {
            continue
        }
        lex_load_file(path)
        delete(path)
    }
}

eq_ext :: proc(ext, want: string) -> bool {
    if len(ext) != len(want) {
        return false
    }
    for i in 0 ..< len(ext) {
        a := ext[i]
        if a >= 'A' && a <= 'Z' {
            a += 32
        }
        if a != want[i] {
            return false
        }
    }
    return true
}

lex_at :: proc(doc: ^text.Buffer, i: int) -> u8 {
    if i < 0 || i >= text.buffer_len(doc) {
        return 0
    }
    return text.buffer_byte(doc, i)
}

lex_is_space :: proc(c: u8) -> bool {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

lex_is_ident_start :: proc(c: u8) -> bool {
    return c == '_' ||
        (c >= 'A' && c <= 'Z') ||
        (c >= 'a' && c <= 'z') ||
        c >= 0x80
}

lex_is_ident :: proc(c: u8) -> bool {
    return lex_is_ident_start(c) || (c >= '0' && c <= '9')
}

lex_is_keyword :: proc(doc: ^text.Buffer, pos, n: int, kws: []string) -> bool {
    for kw in kws {
        if n != len(kw) {
            continue
        }
        ok := true
        for i in 0 ..< n {
            if lex_at(doc, pos + i) != kw[i] {
                ok = false
                break
            }
        }
        if ok {
            return true
        }
    }
    return false
}

lex_is_digit :: proc(c: u8) -> bool {
    return c >= '0' && c <= '9'
}

lex_is_hex :: proc(c: u8) -> bool {
    return lex_is_digit(c) ||
        (c >= 'a' && c <= 'f') ||
        (c >= 'A' && c <= 'F')
}

lex_eat_number :: proc(doc: ^text.Buffer, i: int) -> int {
    i := i
    x := lex_at(doc, i + 1)
    if lex_at(doc, i) == '0' && (x == 'x' || x == 'X') {
        i += 2
        for lex_is_hex(lex_at(doc, i)) || lex_at(doc, i) == '_' {
            i += 1
        }
        return i
    }

    if lex_at(doc, i) == '0' && (x == 'b' || x == 'B') {
        i += 2
        for c := lex_at(doc, i); c == '0' || c == '1' || c == '_'; c = lex_at(doc, i) {
            i += 1
        }
        return i
    }

    if lex_at(doc, i) == '0' && (x == 'o' || x == 'O') {
        i += 2
        for c := lex_at(doc, i); (c >= '0' && c <= '7') || c == '_'; c = lex_at(doc, i) {
            i += 1
        }
        return i
    }

    i += 1

    for lex_is_digit(lex_at(doc, i)) || lex_at(doc, i) == '_' {
        i += 1
    }

    if lex_at(doc, i) == '.' && lex_is_digit(lex_at(doc, i + 1)) {
        i += 1
        for lex_is_digit(lex_at(doc, i)) || lex_at(doc, i) == '_' {
            i += 1
        }
    }

    e := lex_at(doc, i)
    if e == 'e' || e == 'E' {
        i += 1
        s := lex_at(doc, i)
        if s == '+' || s == '-' {
            i += 1
        }
        for lex_is_digit(lex_at(doc, i)) || lex_at(doc, i) == '_' {
            i += 1
        }
    }

    if lex_is_ident_start(lex_at(doc, i)) {
        for lex_is_ident(lex_at(doc, i)) {
            i += 1
        }
    }
    return i
}

lex_eat_comment :: proc(doc: ^text.Buffer, i, n: int, marks: []Lex_Mark) -> (end: int, ok: bool) {
    for m in marks {
        if !lex_match(doc, i, m.open) {
            continue
        }
        i := i + len(m.open)
        if len(m.close) == 0 {
            for i < n && lex_at(doc, i) != '\n' {
                i += 1
            }
        } else {
            for i < n {
                if lex_match(doc, i, m.close) {
                    i += len(m.close)
                    break
                }
                i += 1
            }
        }
        return i, true
    }
    return i, false
}

lex_match :: proc(doc: ^text.Buffer, i: int, s: string) -> bool {
	for k in 0 ..< len(s) {
		if lex_at(doc, i + k) != s[k] {
			return false
		}
	}
	return true
}

lex_eat_op :: proc(doc: ^text.Buffer, i: int, ops: []string) -> int {
	for op in ops {
		if lex_match(doc, i, op) {
			return len(op)
		}
	}
	return 0
}

lex_hspace :: proc(doc: ^text.Buffer, t: Token) -> bool {
	if t.kind != .Punct || t.len == 0 { return false }
	for k in 0 ..< t.len {
		c := lex_at(doc, t.pos + k)
		if c != ' ' && c != '\t' {
			return false
		}
	}
	return true
}

lex_token_is :: proc(doc: ^text.Buffer, t: Token, s: string) -> bool {
	if t.len != len(s) {
		return false
	}
	return lex_match(doc, t.pos, s)
}

lex_next_sig :: proc(doc: ^text.Buffer, toks: []Token, i: int) -> int {
	j := i + 1
	for j < len(toks) && (toks[j].kind == .Comment || lex_hspace(doc, toks[j])) {
		j += 1
	}
	if j < len(toks) {
		return j
	}
	return -1
}

lex_is_type_keyword :: proc(doc: ^text.Buffer, t: Token) -> bool {
	return lex_token_is(doc, t, "struct") ||
		lex_token_is(doc, t, "enum") ||

        lex_token_is(doc, t, "union") ||

        lex_token_is(doc, t, "bit_set") ||

        lex_token_is(doc, t, "bit_field") ||

        lex_token_is(doc, t, "distinct")
}

lex_tag_names :: proc(b: ^Buffer) {
    doc := &b.doc
    funcs := make([dynamic]string)
    types := make([dynamic]string)
    defer {
        for s in funcs {
            delete(s)
        }
        delete(funcs)
        for s in types {
            delete(s)
        }
        delete(types)
    }
    for i in 0 ..< len(b.tokens) {
        t := b.tokens[i]
        if t.kind != .Ident { continue }
        j := lex_next_sig(doc, b.tokens[:], i)
        if j < 0 { continue }
        op := b.tokens[j]
        if op.kind != .Operator { continue }
        if !lex_token_is(doc, op, "::") && !lex_token_is(doc, op, ":=") {
            continue
        }
        k := lex_next_sig(doc, b.tokens[:], j)
        for k >= 0 && b.tokens[k].kind == .Directive {
            k = lex_next_sig(doc, b.tokens[:], k)
        }
        if k < 0 || b.tokens[k].kind != .Keyword {
            continue
        }
        kw := b.tokens[k]
        kind: Token_Kind = .Ident
        if lex_token_is(doc, kw, "proc") {
            kind = .Function
        } else if lex_is_type_keyword(doc, kw) {
            kind = .Type
        }
        if kind == .Ident { continue }
        b.tokens[i].kind = kind
        name := text.buffer_clone_range(doc, t.pos, t.len)
        if kind == .Function {
            append(&funcs, name)
        } else {
            append(&types, name)
        }
    }
    for i in 0 ..< len(b.tokens) {
        t := b.tokens[i]
        if t.kind != .Ident { continue }
        j := lex_next_sig(doc, b.tokens[:], i)
        if j >= 0 && b.tokens[j].kind == .Punct && lex_token_is(doc, b.tokens[j], "(") {
            b.tokens[i].kind = .Function
            continue
        }
        hit: Token_Kind = .Ident
        for name in types {
            if lex_token_is(doc, t, name) {
                hit = .Type
                break
            }
        }
        if hit == .Ident {
            for name in funcs {
                if lex_token_is(doc, t, name) {
                    hit = .Function
                    break
                }
            }
        }
        if hit != .Ident {
            b.tokens[i].kind = hit
        }
    }
}

buffer_lex :: proc(b: ^Buffer) {
    clear(&b.tokens)
    doc := &b.doc
    n := text.buffer_len(doc)
    i := 0
    lf := lex_file_of(b)
    kws: []string
    ops: []string
    marks: []Lex_Mark
    dir_pfx := ""
    if lf != nil {
        kws = lf.keywords[:]
        ops = lf.ops[:]
        marks = lf.comments[:]
        dir_pfx = lf.directive
    }
    for i < n {
        c := lex_at(doc, i)
        if lex_is_space(c) {
            if c == '\n' || c == '\r' {
                i += 1
                continue
            }
            start := i
            for lex_at(doc, i) == ' ' || lex_at(doc, i) == '\t' {
                i += 1
            }
            append(&b.tokens, Token{kind = .Punct, pos = start, len = i - start})
            continue
        }
        start := i
        kind: Token_Kind = .Punct
        if lex_is_ident_start(c) {
            i += 1
            for lex_is_ident(lex_at(doc, i)) {
                i += 1
            }
            kind = .Ident
            if lex_is_keyword(doc, start, i - start, kws) {
                kind = .Keyword
            }
        } else if lex_is_digit(c) {
            i = lex_eat_number(doc, i)
            kind = .Number
        } else if c == '"' || c == '\'' || c == '`' {
            quote := c
            i += 1
            for i < n {
                ch := lex_at(doc, i)
                if ch == quote {
                    i += 1
                    break
                }
                if quote != '`' && (ch == '\n' || ch == '\r') {
                    break
                }
                if ch == '\\' && quote != '`' {
                    i += 1
                }
                i += 1
            }
            kind = .String
        } else if end, cok := lex_eat_comment(doc, i, n, marks); cok {
            i = end
            kind = .Comment
        } else if len(dir_pfx) > 0 && lex_match(doc, i, dir_pfx) {
            i += len(dir_pfx)
            for lex_is_ident(lex_at(doc, i)) {
                i += 1
            }
            kind = .Directive
        } else if n := lex_eat_op(doc, i, ops); n > 0 {
            i += n
            kind = .Operator
        } else {
            i += 1
        }
        append(&b.tokens, Token{kind = kind, pos = start, len = i - start})
    }
    lex_tag_names(b)
    b.lex_dirty = false
}

token_color :: proc(kind: Token_Kind) -> [4]f32 {
    switch kind {
        case .Keyword: return settings.keyword
        case .Comment: return settings.comment
        case .String:  return settings.lit_string
        case .Number:  return settings.lit_number
        case .Ident, .Punct: return settings.text
        case .Operator: return settings.operator
        case .Directive: return settings.directive
        case .Function:  return settings.function_name

		case .Type:     return settings.type_name
    }
    return settings.text
}
