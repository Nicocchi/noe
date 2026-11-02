package editor

import "core:strings"

import "../text"

brace_curly :: proc(b: ^Buffer, t: Token) -> u8 {
	if t.len != 1 || (t.kind != .Punct && t.kind != .Operator) {
		return 0
	}
	c := lex_at(&b.doc, t.pos)
	if c == '{' || c == '}' {
		return c
	}
	return 0
}
brace_token_before :: proc(toks: []Token, pos: int) -> int {
	lo, hi := 0, len(toks)
	for lo < hi {
		mid := lo + (hi - lo) / 2
		if toks[mid].pos <= pos {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo - 1
}
brace_sync :: proc(v: ^View, b: ^Buffer) {
	if b.lex_dirty {
		buffer_lex(b)
	}
	n := text.buffer_len(&b.doc)
	if v.brace_cursor == v.cursor && v.brace_doc_len == n && v.brace_toks == len(b.tokens) {
		return
	}
	v.brace_cursor = v.cursor
	v.brace_doc_len = n
	v.brace_toks = len(b.tokens)
	v.brace_n = 0
	toks := b.tokens[:]
	if len(toks) == 0 { return }
	li := text.buffer_line_at(&b.doc, v.cursor)
	ls := text.buffer_line_start(&b.doc, li)
	le := text.buffer_line_end(&b.doc, li)
	close_i := -1
	i0 := max(brace_token_before(toks, ls), 0)
	for i in i0 ..< len(toks) {
		t := toks[i]
		if t.pos >= le { break }
		if t.pos >= ls && brace_curly(b, t) == '}' { close_i = i }
	}
	i := brace_token_before(toks, v.cursor)
	if close_i >= 0 {
		d := 1
		j := close_i - 1
		for j >= 0 {
			c := brace_curly(b, toks[j])
			if c == '}' {
				d += 1
			} else if c == '{' {
				d -= 1
				if d == 0 {
					v.brace_open[0] = toks[j].pos
					v.brace_close[0] = toks[close_i].pos
					v.brace_n = 1
					i = j - 1
					break
				}
			}
			j -= 1
		}
	}
	depth := 0
	for i >= 0 && v.brace_n < len(v.brace_open) {
		t := toks[i]
		i -= 1
		c := brace_curly(b, t)
		if c == '}' {
			depth += 1
		} else if c == '{' {
			if depth == 0 {
				v.brace_open[v.brace_n] = t.pos
				v.brace_n += 1
			} else {
				depth -= 1
			}
		}
	}
	k := 0
	scan := brace_token_before(toks, v.cursor) + 1
	if close_i >= 0 && v.brace_n > 0 {
		k = 1
		scan = close_i + 1
	}
	depth = 0
	for scan < len(toks) && k < v.brace_n {
		t := toks[scan]
		scan += 1
		c := brace_curly(b, t)
		if c == '{' {
			depth += 1
		} else if c == '}' {
			if depth == 0 {
				v.brace_close[k] = t.pos
				k += 1
			} else {
				depth -= 1
			}
		}
	}
	v.brace_n = k
}

brace_header_clone :: proc(b: ^Buffer, open_pos: int) -> string {
    li := text.buffer_line_at(&b.doc, open_pos)
    line := text.buffer_line_clone(&b.doc, li)
    head := lex_trim(strip_trailing_open_brace(line))
    if len(head) > 0 {
        out := strings.clone(head)
        delete(line)
        return out
    }
    delete(line)
    for li > 0 {
        li -= 1
        line = text.buffer_line_clone(&b.doc, li)
        head = lex_trim(line)
        if len(head) > 0 {
            out := strings.clone(head)
            delete(line)
            return out
        }
        delete(line)
    }
    return ""
}

strip_trailing_open_brace :: proc(s: string) -> string {
    hi := len(s)
    for hi > 0 && (s[hi - 1] == ' ' || s[hi - 1] == '\t') {
        hi -= 1
    }
    if hi > 0 && s[hi - 1] == '{' {
        hi -= 1
    }
    for hi > 0 && (s[hi - 1] == ' ' || s[hi - 1] == '\t') {
        hi -= 1
    }
    return s[:hi]
}