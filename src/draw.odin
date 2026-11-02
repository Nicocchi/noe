package main

import "core:fmt"
import "core:math"
import "core:strings"
import "platform"
import "render"
import "text"
import "editor"

draw_gutter :: proc(queue: ^render.Render_Queue, dgr: editor.Rect,
                    dv: ^editor.View, db: ^editor.Buffer, dtr: editor.Rect, 
                    lh: f32, first, last: int, active: bool) {
    render.push_clip(queue, {dgr.x, dgr.y}, {dgr.w, dgr.h})
    cur_line := text.buffer_line_at(&db.doc, dv.cursor)
    for i in first ..< last {
        label := fmt.tprintf("%d", i + 1)
        tw := render.font_width(label)
        x := dgr.x + dgr.w - tw - 8
        y := line_top(dv, dtr, i, lh)
        color: [4]f32 = editor.settings.gutter
        if active && i == cur_line {
            color = editor.settings.gutter_current
        }
        render.push_text(queue, label, x, line_baseline(y, lh), color)
    }
    render.push_clip_disabled(queue)
}

draw_text_area :: proc(queue: ^render.Render_Queue, ed: ^editor.Editor,
                        window: ^platform.Window, dv: ^editor.View,
                        db: ^editor.Buffer, dtr: editor.Rect,
                        vi: int, lh: f32, caret_on: bool, first, last: int) {
    head := max(editor.settings.text_pad_y, 2)
    render.push_clip(queue, {dtr.x, dtr.y - head}, {dtr.w, dtr.h + head})
    
    // Current line highlight
    cur := text.buffer_line_at(&db.doc, dv.cursor)
    if cur >= first && cur < last {
        y := line_top(dv, dtr, cur, lh)
        render.push_quad(queue, {dtr.x, y}, {dtr.w, lh}, editor.settings.current_line)
    }

    sel := editor.settings.selection
    for pass in 0 ..< 1 + len(dv.extras) {
        cc, aa := dv.cursor, dv.sel_anchor
        if pass > 0 {
            e := dv.extras[pass - 1]
            cc, aa = e.cursor, e.sel_anchor
        }
        lo := min(cc, aa)
        hi := max(cc, aa)
        if lo == hi {
            continue
        }

        for i in first ..< last {
            ls := text.buffer_line_start(&db.doc, i)
            le := text.buffer_line_end(&db.doc, i)
            if hi <= ls || lo > le {
                continue
            }
            line := text.buffer_line_clone(&db.doc, i)
            defer delete(line)
            col_lo := clamp(lo - ls, 0, len(line))
            col_hi := clamp(hi - ls, 0, len(line))
            x0 := dtr.x + render.font_width(line[:col_lo]) - dv.scroll_x
            x1 := dtr.x + render.font_width(line[:col_hi]) - dv.scroll_x
            if hi > le && lo <= le {
                x1 += 8
            }
            y := line_top(dv, dtr, i, lh)
            if x1 > x0 {
                render.push_quad(queue, {x0, y}, {x1 - x0, lh}, sel)
            }
        }
    }

    for i in first ..< last {
        line := text.buffer_line_clone(&db.doc, i)
        defer delete(line)
        ls := text.buffer_line_start(&db.doc, i)
        le := text.buffer_line_end(&db.doc, i)
        y := line_top(dv, dtr, i, lh)
        baseline := line_baseline(y, lh)
        origin := dtr.x - dv.scroll_x
        col := 0
        for t in 0 ..< len(db.tokens) {
            tok := db.tokens[t]
            if tok.pos + tok.len <= ls {
                continue
            }
            if tok.pos >= le {
                break
            }
            a := max(tok.pos, ls) - ls
            b := min(tok.pos + tok.len, le) - ls
            if a > col {
                gap := line[col:a]
                render.push_text(queue, gap, origin + render.font_width(line[:col]), baseline, editor.settings.text)
                col = a
            }
            if b > col {
                piece := line[col:b]
                render.push_text(queue, piece, origin + render.font_width(line[:col]), baseline, editor.token_color(tok.kind))
                col = b
            }
        }
        if col < len(line) {
            rest := line[col:]
            render.push_text(queue, rest, origin + render.font_width(line[:col]), baseline, editor.settings.text)
        }
        
    }

    
    if editor.settings.show_brace_header || editor.settings.show_brace_guides {
        editor.brace_sync(dv, db)
    }
    if editor.settings.show_brace_guides {
        origin := dtr.x - dv.scroll_x
        tab_w := render.font_width("\t")
        dim := editor.settings.brace_guide
        dim.a *= 0.35
        if tab_w > 0 {
            for i in first ..< last {
                line := text.buffer_line_clone(&db.doc, i)
                indent := 0
                for indent < len(line) && (line[indent] == ' ' || line[indent] == '\t') {
                    indent += 1
                }
                vis := render.font_width(line[:indent])
                delete(line)
                y := line_top(dv, dtr, i, lh)
                col_x: f32 = 0
                for col_x < vis {
                    gx := math.round(origin + col_x)
                    render.push_quad(queue, {gx, y}, {1, lh}, dim)
                    col_x += tab_w
                }
            }
        }
        for bi in 0 ..< dv.brace_n {
            open_pos := dv.brace_open[bi]
            close_pos := dv.brace_close[bi]
            oi := text.buffer_line_at(&db.doc, open_pos)
            ci := text.buffer_line_at(&db.doc, close_pos)
            if ci <= oi {
                continue
            }
            cline := text.buffer_line_clone(&db.doc, ci)
            indent := 0
            for indent < len(cline) && (cline[indent] == ' ' || cline[indent] == '\t') {
                indent += 1
            }
            gx := math.round(origin + render.font_width(cline[:indent]))
            delete(cline)
            top := line_top(dv, dtr, oi + 1, lh)
            bot := line_top(dv, dtr, ci, lh)
            y0 := max(top, dtr.y - head)
            y1 := min(bot, dtr.y + dtr.h)
            if y1 > y0 {
                render.push_quad(queue, {gx, y0}, {1, y1 - y0}, editor.settings.brace_guide)
            }
        }
    }

    if vi == ed.active_view {
        if editor.settings.show_brace_header {
            for bi in 0 ..< dv.brace_n {
                open_pos := dv.brace_open[bi]
                close_pos := dv.brace_close[bi]
                ci := text.buffer_line_at(&db.doc, close_pos)
                oi := text.buffer_line_at(&db.doc, open_pos)
                if ci == oi || ci < first || ci >= last {
                    continue
                }
                ghost := editor.brace_header_clone(db, open_pos)
                if len(ghost) == 0 {
                    continue
                }
                cline := text.buffer_line_clone(&db.doc, ci)
                gy := line_top(dv, dtr, ci, lh)
                gx := math.round(dtr.x - dv.scroll_x + render.font_width(cline) + 12)
                render.push_text(queue, ghost, gx, line_baseline(gy, lh), editor.settings.comment)
                delete(cline)
                delete(ghost)
            }
        }
    }


    line_i := text.buffer_line_at(&db.doc, dv.cursor)
    line_start := text.buffer_line_start(&db.doc, line_i)
    line := text.buffer_line_clone(&db.doc, line_i)
    defer delete(line)
    prefix := line[:min(dv.cursor - line_start, len(line))]
    cx := dtr.x + render.font_width(prefix) - dv.scroll_x
    cy := line_top(dv, dtr, line_i, lh)
    baseline := line_baseline(cy, lh)
    if vi == ed.active_view {
        if window.ime_preview_len > 0 {
            preview := string(window.ime_preview[:window.ime_preview_len])
            render.push_text(queue, preview, cx, baseline, editor.settings.ime_preview)
            cx += render.font_width(preview)
        }
        if window.ime_preview_len > 0 {
            platform.ime_set_pos(window, i32(cx), i32(cy + lh))
        }
        if caret_on || window.ime_preview_len > 0 {
            render.push_quad(queue, {cx, cy}, {editor.settings.caret_w, lh}, editor.settings.caret)
        }
        for e in dv.extras {
            el := text.buffer_line_at(&db.doc, e.cursor)
            es := text.buffer_line_start(&db.doc, el)
            eline := text.buffer_line_clone(&db.doc, el)
            defer delete(eline)
            ep := eline[:min(e.cursor - es, len(eline))]
            ex := dtr.x + render.font_width(ep) - dv.scroll_x
            ey := line_top(dv, dtr, el, lh)
            col: [4]f32 = editor.settings.caret_inactive
            if caret_on {
                col = editor.settings.caret
            }
            render.push_quad(queue, {ex, ey}, {editor.settings.caret_w, lh}, col)
        }
    }

    
}

draw_view :: proc(queue: ^render.Render_Queue, ed: ^editor.Editor,
                    window: ^platform.Window, lay: editor.Layout,
                    vi: int, lh: f32, caret_on: bool) {
    dv := &ed.views[vi]
    db := &ed.buffers[dv.buf_id]
    dtr := lay.views[vi].text
    dgr := lay.views[vi].gutter

    n_lines := text.buffer_line_count(&db.doc)
    first := 0
    last := n_lines
    if lh > 0 {
        first = clamp(int((dv.scroll_y) / lh) - 1, 0, n_lines)
        last = clamp(int((dv.scroll_y + dtr.h) / lh) + 1, 0, n_lines)
    }

    if db.lex_dirty {
        editor.buffer_lex(db)
    }

    // Gutter
    if dgr.x > 0 {
        draw_gutter(queue, dgr, dv, db, dtr, lh, first, last, vi == ed.active_view)
    }

    // Text area
    draw_text_area(queue, ed, window, dv, db, dtr, vi, lh, caret_on, first, last)

    render.push_clip_disabled(queue)
}

draw_status :: proc(queue: ^render.Render_Queue, ed: ^editor.Editor, sr: editor.Rect, lh: f32) {
    b := editor.active_buffer(ed)
    v := editor.active_view(ed)
    render.push_clip(queue, {sr.x, sr.y}, {sr.w, sr.h})
    render.push_quad(queue, {sr.x, sr.y}, {sr.w, sr.h}, editor.settings.status_bg)
    line_i := text.buffer_line_at(&b.doc, v.cursor)
    col := v.cursor - text.buffer_line_start(&b.doc, line_i) + 1
    star := ""
    if b.dirty {
        star = " *"
    }
    left := fmt.tprintf("%s%s", editor.buffer_status_path(ed, b), star)
    eol := "LF"
    if b.newline == .CRLF {
        eol = "CRLF"
    }
    nlines := text.buffer_line_count(&b.doc)
    right := fmt.tprintf("Ln %d, Col %d    %d lines		%s", line_i + 1, col, nlines, eol)
    if sl, sr_status, sok := editor.script_status_line(ed); sok {
        left, right = sl, sr_status
    }
    sy := sr.y + (sr.h - lh) * 0.8 + render.font_ascent()
    render.push_text(queue, left, sr.x + 8, sy, editor.settings.status_text)
    rx := sr.x + sr.w - render.font_width(right) - 8
    render.push_text(queue, right, rx, sy, editor.settings.status_text)
    render.push_clip_disabled(queue)
}

draw_files :: proc(queue: ^render.Render_Queue, ed: ^editor.Editor, ov: editor.Rect, lh: f32, 
                    caret_on: bool, bw: f32, bc: [4]f32) {
    editor.picker_sync_preview(ed)
    pad := editor.settings.overlay_pad
    g := editor.settings.overlay_gap
    input_h := lh + pad * 2
    left_w := (ov.w - g) * 0.42
    list := editor.Rect{ov.x, ov.y, left_w, ov.h - input_h - g}
    box  := editor.Rect{ov.x, ov.y + list.h + g, left_w, input_h}
    prev := editor.Rect{ov.x + left_w + g, ov.y, ov.w - left_w - g, ov.h}

    render.push_quad(queue, {list.x, list.y}, {list.w, list.h}, editor.settings.bg)
    render.push_quad(queue, {box.x, box.y}, {box.w, box.h}, editor.settings.bg)
    render.push_quad(queue, {prev.x, prev.y}, {prev.w, prev.h}, editor.settings.bg)

    render.push_border(queue, {list.x, list.y}, {list.w, list.h}, bw, bc)
    render.push_border(queue, {box.x, box.y}, {box.w, box.h}, bw, bc)
    render.push_border(queue, {prev.x, prev.y}, {prev.w, prev.h}, bw, bc)

    render.push_clip(queue, {ov.x, ov.y}, {ov.w, ov.h})

    query := string(ed.overlay.text[:])
    vis := max(int(list.h / lh), 1)
    if ed.overlay.sel < ed.overlay.scroll {
        ed.overlay.scroll = ed.overlay.sel
    }
    if ed.overlay.sel >= ed.overlay.scroll + vis {
        ed.overlay.scroll = ed.overlay.sel - vis + 1
    }

    render.push_clip(queue, {list.x, list.y}, {list.w, list.h})
    row := 0
    drawn := 0
    for p in ed.overlay.files {
        rel := editor.picker_rel(ed.overlay.root, p)
        if !editor.fuzzy_match(rel, query) {
            continue
        }
        if row < ed.overlay.scroll {
            row += 1
            continue
        }
        if drawn >= vis {
            break
        }
        row_y := math.round(list.y + pad + f32(drawn) * lh)
        qy := line_baseline(row_y, lh)
        color := editor.settings.text
        if editor.buffer_is_open(ed, p) {
            color = editor.settings.function_name
        }
        if row == ed.overlay.sel {
            render.push_quad(queue, {list.x, row_y}, {list.w, lh}, editor.settings.overlay_sel_bg)
            color = editor.settings.overlay_sel_fg
        }
        render.push_text(queue, rel, list.x + 8, qy, color)
        drawn += 1
        row += 1
    }
    render.push_clip(queue, {ov.x, ov.y}, {ov.w, ov.h})

    lx := box.x + 8
    caret_y := math.round(box.y + (box.h - lh) * 0.5)
    ly := line_baseline(caret_y, lh)
    render.push_text(queue, "> ", lx, ly, editor.settings.overlay_label)
    lx += render.font_width("> ")
    render.push_text(queue, query, lx, ly, editor.settings.text)
    prefix := string(ed.overlay.text[:ed.overlay.cursor])
    cx := lx + render.font_width(prefix)
    if caret_on {
        render.push_quad(queue, {cx, caret_y}, {editor.settings.caret_w, lh}, editor.settings.caret)
    }

    render.push_clip(queue, {prev.x, prev.y}, {prev.w, prev.h})
    top := math.round(prev.y + pad)

    py := line_baseline(top, lh)
    src := string(ed.overlay.preview)
    if len(src) == 0 {
        render.push_text(queue, "(no preview)", prev.x + 8, py, editor.settings.overlay_label)
    } else {
        start := 0
        for i in 0 ..= len(src) {
            if i < len(src) && src[i] != '\n' {
                continue
            }
            line := src[start:i]
            if len(line) > 0 && line[len(line) - 1] == '\r' {
                line = line[:len(line) - 1]
            }
            ls := start
            le := start + len(line)
            origin := prev.x + 8
            col := 0
            for t in 0 ..< len(ed.overlay.preview_tokens) {
                tok := ed.overlay.preview_tokens[t]
                if tok.pos + tok.len <= ls {
                    continue
                }
                if tok.pos >= le {
                    break
                }
                a := max(tok.pos, ls) - ls
                b := min(tok.pos + tok.len, le) - ls
                if a > col {
                    render.push_text(queue, line[col:a], origin + render.font_width(line[:col]), py, editor.settings.text)
                    col = a
                }
                if b > col {
                    render.push_text(queue, line[col:b], origin + render.font_width(line[:col]), py, editor.token_color(tok.kind))
                    col = b
                }
            }
            if col < len(line) {
                render.push_text(queue, line[col:], origin + render.font_width(line[:col]), py, editor.settings.text)
            }
            top += lh
            py = line_baseline(top, lh)
            if py > prev.y + prev.h {
                break
            }
            start = i + 1
        }
    }
    render.push_clip(queue, {ov.x, ov.y}, {ov.w, ov.h})
}

draw_new_file :: proc(queue: ^render.Render_Queue, ed: ^editor.Editor, ov: editor.Rect, lh: f32,
                        caret_on: bool, bw: f32, bc: [4]f32) {
    pad := editor.settings.overlay_pad
    g := editor.settings.overlay_gap
    input_h := lh + pad * 2
    list := editor.Rect{ov.x, ov.y, ov.w, ov.h - input_h - g}
    box := editor.Rect{ov.x, ov.y + list.h + g, ov.w, input_h}
    render.push_quad(queue, {list.x, list.y}, {list.w, list.h}, editor.settings.bg)
    render.push_quad(queue, {box.x, box.y}, {box.w, box.h}, editor.settings.bg)
    
    render.push_border(queue, {list.x, list.y}, {list.w, list.h}, bw, bc)
    render.push_border(queue, {box.x, box.y}, {box.w, box.h}, bw, bc)
    render.push_clip(queue, {ov.x, ov.y}, {ov.w, ov.h})

    here := editor.picker_rel(ed.overlay.root, ed.overlay.browse)
    if len(here) == 0 { here = "." }
    render.push_text(queue, here, list.x + 8, line_baseline(math.round(list.y + pad), lh), editor.settings.overlay_label)

    vis := max(int((list.h - lh) / lh), 1)
    if ed.overlay.sel < ed.overlay.scroll {
        ed.overlay.scroll = ed.overlay.sel
    }
    if ed.overlay.sel >= ed.overlay.scroll + vis {
        ed.overlay.scroll = ed.overlay.sel - vis + 1
    }
    render.push_clip(queue, {list.x, list.y + lh}, {list.w, list.h - lh})
    drawn := 0
    for row in 0 ..< len(ed.overlay.files) {
        if row < ed.overlay.scroll { continue }
        if drawn >= vis { break }
        name := editor.picker_rel(ed.overlay.browse, ed.overlay.files[row])
        label := name
        if ed.overlay.entry_dir[row] {
            label = fmt.tprintf("%s/", name)
        }
        row_y := math.round(list.y + lh + pad + f32(drawn) * lh)
        qu := line_baseline(row_y, lh)
        color := editor.settings.text

        if ed.overlay.entry_dir[row] {
            color = editor.settings.overlay_label
        }

        if row == ed.overlay.sel {

            render.push_quad(queue, {list.x, row_y}, {list.w, lh}, editor.settings.overlay_sel_bg)
            color = editor.settings.overlay_sel_fg
        }
        render.push_text(queue, label, list.x + 8, qu, color)
        drawn += 1
    }
    render.push_clip(queue, {ov.x, ov.y}, {ov.w, ov.h})

    lx := box.x + 8
    caret_y := math.round(box.y + (box.h - lh) * 0.5)

    ly := line_baseline(caret_y, lh)
    mark := "> "
    if len(ed.overlay.rename_from) > 0 {
        mark = "rename: "
    }
    render.push_text(queue, mark, lx, ly, editor.settings.overlay_label)
    lx += render.font_width(mark)
    query := string(ed.overlay.text[:])
    render.push_text(queue, query, lx, ly, editor.settings.text)
    prefix := string(ed.overlay.text[:ed.overlay.cursor])
    cx := lx + render.font_width(prefix)
    if caret_on {
        render.push_quad(queue, {cx, caret_y}, {editor.settings.caret_w, lh}, editor.settings.caret)
    }
}

draw_command :: proc(queue: ^render.Render_Queue, ed: ^editor.Editor, ov: editor.Rect, lh: f32, caret_on: bool) {
    label := "Find: "
    if ed.overlay.kind == .Switcher {
        label = "Command: "
    }
    lx := ov.x + 8
    cy := math.round(ov.y + 8)
    ly := line_baseline(cy, lh)
    render.push_text(queue, label, lx, ly, editor.settings.overlay_label)
    lx += render.font_width(label)
    q := string(ed.overlay.text[:])
    render.push_text(queue, q, lx, ly, editor.settings.text)
    prefix := string(ed.overlay.text[:ed.overlay.cursor])
    cx := lx + render.font_width(prefix)
    if caret_on {
        render.push_quad(queue, {cx, cy}, {editor.settings.caret_w, lh}, editor.settings.caret)
    }

    if ed.overlay.kind == .Switcher {
        row_top := cy + lh
        row := 0
        query := string(ed.overlay.text[:])
        if line, ok := editor.switcher_line(query); ok {
            n := text.buffer_line_count(&editor.active_buffer(ed).doc)
            shown := line
            if n > 0 {
                shown = clamp(line, 1, n)
            }
            label := fmt.tprintf("Line %d", shown)
            render.push_quad(queue, {ov.x, row_top}, {ov.w, lh}, editor.settings.overlay_sel_bg)
            render.push_text(queue, label, ov.x + 8, line_baseline(row_top, lh), editor.settings.overlay_sel_fg)
        } else {
            list_h := max(ov.y + ov.h - row_top, lh)
            vis := max(int(list_h / lh), 1)
            if ed.overlay.sel < ed.overlay.scroll {
                ed.overlay.scroll = ed.overlay.sel
            }
            if ed.overlay.sel >= ed.overlay.scroll + vis {
                ed.overlay.scroll = ed.overlay.sel - vis + 1
            }
            render.push_clip(queue, {ov.x, row_top}, {ov.w, list_h})
            drawn := 0
            for i in 0 ..< len(ed.buffers) {
                name := editor.buffer_status_path(ed, &ed.buffers[i])
                if len(query) != 0 && !strings.contains(name, query) {
                    continue
                }

                if row < ed.overlay.scroll {
                    row += 1
                    continue
                }

                if drawn >= vis { break }
                color: [4]f32 = editor.settings.overlay_list

                if row == ed.overlay.sel {
                    render.push_quad(queue, {ov.x, row_top}, {ov.w, lh}, editor.settings.overlay_sel_bg)
                    color = editor.settings.overlay_sel_fg
                }

                render.push_text(queue, name, ov.x + 8, line_baseline(row_top, lh), color)
                row_top += lh
                row += 1
                drawn += 1
            }
            render.push_clip_disabled(queue)
        }

    }
}

draw_overlay :: proc(queue: ^render.Render_Queue, ed: ^editor.Editor, window: ^platform.Window, lay: editor.Layout, lh: f32, caret_on: bool) {
    if editor.overlay_is_open(ed) {
    ov := lay.overlay
    if ed.overlay.kind == .Switcher {
        ov.h = lh * f32(editor.settings.overlay_rows)
    }
    if ed.overlay.kind == .Files || ed.overlay.kind == .New_File {
        ov.w = f32(window.width) * 0.8
        ov.h = f32(window.height) * 0.7
        ov.x = (f32(window.width) - ov.w) * 0.5
        ov.y = (f32(window.height) - ov.h) * 0.5
    }

    fill := editor.settings.overlay_bg
    if ed.overlay.kind == .Files {
        fill = editor.settings.bg
    }
    render.push_quad(queue, {ov.x, ov.y}, {ov.w, ov.h}, fill)

    bw := editor.settings.overlay_border
    bc := editor.settings.overlay_border_color
    if ed.overlay.kind != .Files {
        render.push_quad(queue, {ov.x, ov.y}, {ov.w, ov.h}, editor.settings.bg)
        render.push_border(queue, {ov.x, ov.y}, {ov.w, ov.h}, bw, bc)
    }

    if ed.overlay.kind == .Files {
        draw_files(queue, ed, ov, lh, caret_on, bw, bc)
    } else if ed.overlay.kind == .New_File {
        draw_new_file(queue, ed, ov, lh, caret_on, bw, bc)

    } else {
        draw_command(queue, ed, ov, lh, caret_on)
    }

    
    }
}