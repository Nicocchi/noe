package text

import "core:unicode/utf8"

GAP_MIN :: 64

Buffer :: struct {
    data:       []u8,
    gap_start:  int,
    gap_end:    int,
    lines:      [dynamic]int,
}

buffer_init :: proc(b: ^Buffer, cap: int) {
    cap := max(cap, GAP_MIN)
    b.data = make([]u8, cap)
    b.gap_start = 0
    b.gap_end = cap
    b.lines = make([dynamic]int)
    append(&b.lines, 0)
}

buffer_destroy :: proc(b: ^Buffer) {
    delete(b.data)
    delete(b.lines)
    b^ = {}
}

buffer_len :: proc(b: ^Buffer) -> int {
    return len(b.data) - (b.gap_end - b.gap_start)
}

buffer_gap_size :: proc(b: ^Buffer) -> int {
    return b.gap_end - b.gap_start
}

buffer_move_gap :: proc(b: ^Buffer, pos: int) {
    pos := clamp(pos, 0, buffer_len(b))
    if pos == b.gap_start {
        return
    }

    if pos < b.gap_start {
        n := b.gap_start - pos
        src := b.data[pos:][:n]
        dst := b.data[b.gap_end - n:][:n]
        copy(dst, src)
        b.gap_start -= n
        b.gap_end -= n
    } else {
        n := pos - b.gap_start
        src := b.data[b.gap_end:][:n]
        dst := b.data[b.gap_start:][:n]
        copy(dst, src)
        b.gap_start += n
        b.gap_end += n
    }
}

buffer_grow :: proc(b: ^Buffer, extra: int) {
    old_len := len(b.data)
    new_cap := max(old_len * 2, old_len + extra + GAP_MIN)
    new_data := make([]u8, new_cap)

    pre := b.data[:b.gap_start]
    post := b.data[b.gap_end:]
    copy(new_data, pre)
    copy(new_data[new_cap - len(post):], post)

    delete(b.data)
    b.data = new_data
    b.gap_start = len(pre)
    b.gap_end = new_cap - len(post)
}

buffer_insert :: proc(b: ^Buffer, pos: int, s: string) {
    if len(s) == 0 {
        return
    }

    buffer_move_gap(b, pos)
    if buffer_gap_size(b) < len(s) {
        buffer_grow(b, len(s))
    }
    copy(b.data[b.gap_start:], s)
    b.gap_start += len(s)

    n := len(s)
    for i in 0 ..< len(b.lines) {
        if b.lines[i] > pos {
            b.lines[i] += n
        }
    }

    for ch, idx in s {
        if ch == '\n' {
            lines_insert_start(b, pos + idx + 1)
        }
    }
}

buffer_delete :: proc(b: ^Buffer, pos, n: int) {
    if n <= 0 {
        return
    }

    pos := clamp(pos, 0, buffer_len(b))
    n := min(n, buffer_len(b) - pos)
    buffer_move_gap(b, pos)
    b.gap_end += n

    for i := len(b.lines) - 1; i >= 1; i -= 1 {
        ls := b.lines[i]
        if ls > pos && ls <= pos + n {
            ordered_remove(&b.lines, i)
        } else if ls > pos + n {
            b.lines[i] -= n
        }
    }
}

buffer_clone_string :: proc(b: ^Buffer, allocator := context.allocator) -> string {
    out := make([]u8, buffer_len(b), allocator)
    copy(out, b.data[:b.gap_start])
    copy(out[b.gap_start:], b.data[b.gap_end:])
    return string(out)
}

buffer_line_count :: proc(b: ^Buffer) -> int {
    return len(b.lines)
}

buffer_line_start :: proc(b: ^Buffer, i: int) -> int {
    return b.lines[i]
}

// Exclusive end of the text on line i, not including the '\n'
buffer_line_end :: proc(b: ^Buffer, i: int) -> int {
    if i + 1 < len(b.lines) {
        return b.lines[i + 1] - 1
    }
    return buffer_len(b)
}

buffer_read :: proc(b: ^Buffer, pos, n: int, dst: []u8) -> int {
    pos := clamp(pos, 0, buffer_len(b))
    n := min(n, buffer_len(b) - pos, len(dst))
    written := 0
    for written < n {
        logical := pos + written
        src: u8
        if logical < b.gap_start {
            src = b.data[logical]
        } else {
            src = b.data[logical + (b.gap_end - b.gap_start)]
        }
        dst[written] = src
        written += 1
    }
    return written
}

buffer_line_clone :: proc(b: ^Buffer, i: int, allocator := context.allocator) -> string {
    start := buffer_line_start(b, i)
    end := buffer_line_end(b, i)
    n := max(end - start, 0)
    out := make([]u8, n, allocator)
    buffer_read(b, start, n, out)
    return string(out)
}

lines_insert_start :: proc(b: ^Buffer, start: int) {
    i := 0
    for i < len(b.lines) && b.lines[i] < start {
        i += 1
    }
    inject_at(&b.lines, i, start)
}

buffer_line_at :: proc(b: ^Buffer, pos: int) -> int {
    pos := clamp(pos, 0, buffer_len(b))
    i := len(b.lines) - 1
    for i > 0 && b.lines[i] > pos {
        i -= 1
    }
    return i
}

buffer_prev_rune :: proc(b: ^Buffer, pos: int) -> (start: int, size: int) {
    pos := clamp(pos, 0, buffer_len(b))
    if pos == 0 {
        return 0, 0
    }
    n := min(4, pos)
    buf: [4]u8
    buffer_read(b, pos - n, n, buf[:n])
    _, size = utf8.decode_last_rune(buf[:n])
    return pos - size, size
}

buffer_next_rune :: proc(b: ^Buffer, pos: int) -> (end: int, size: int) {
    pos := clamp(pos, 0, buffer_len(b))
    if pos >= buffer_len(b) {
        return pos, 0
    }
    n := min(4, buffer_len(b) - pos)
    buf: [4]u8
    buffer_read(b, pos, n, buf[:n])
    _, size = utf8.decode_rune(buf[:n])
    return pos + size, size
}

buffer_line_col :: proc(b: ^Buffer, pos: int) -> (line, col: int) {
    line = buffer_line_at(b, pos)
    col = pos - buffer_line_start(b, line)
    return
}

buffer_pos_at_line :: proc(b: ^Buffer, line, col: int) -> int {
    line := clamp(line, 0, buffer_line_count(b) - 1)
    start := buffer_line_start(b, line)
    end := buffer_line_end(b, line)
    return start + clamp(col, 0, end - start)
}