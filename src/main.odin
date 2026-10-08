package main

import "core:fmt"
import "core:time"
import "core:strings"
import "platform"
import "render"
import "text"
import "editor"

pos_at_xy :: proc(v: ^editor.View, b: ^editor.Buffer, pane: editor.Rect, x, y: f32) -> int {
	lh := render.font_line_height()
	n := text.buffer_line_count(&b.doc)
	line := 0
	doc_y := y - pane.y + v.scroll_y
	if doc_y >= 0 && lh > 0 {
		line = int(doc_y / lh)
	}
	line = clamp(line, 0, n - 1)
	s := text.buffer_line_clone(&b.doc, line)
	defer delete(s)
	col := render.font_index_at(s, x - pane.x + v.scroll_x)
	return text.buffer_line_start(&b.doc, line) + col
}

line_top :: proc(v: ^editor.View, pane: editor.Rect, line: int, lh: f32) -> f32 {
	return pane.y + f32(line) * lh - v.scroll_y
}

max_scroll_y :: proc(ed: ^editor.Editor, lh: f32) -> f32 {
    b := editor.active_buffer(ed)
	n := text.buffer_line_count(&b.doc)
	if n <= 1 {
		return 0
	}
	return f32(n - 1) * lh
}

max_scroll_x :: proc(ed: ^editor.Editor) -> f32 {
    b := editor.active_buffer(ed)
	if !b.scroll_x_dirty {
		return b.max_scroll_x
	}
	n := text.buffer_line_count(&b.doc)
	w: f32
	for i in 0 ..< n {
		line := text.buffer_line_clone(&b.doc, i)
		w = max(w, render.font_width(line))
		delete(line)
	}
	b.max_scroll_x = w
	b.scroll_x_dirty = false
	return w
}

apply_font :: proc(path, fallback: string, size: int) -> bool {
	render.pixel_height = f32(clamp(size, 8, 72))
	render.font_shutdown()
	if !render.font_init(path) {
		return false
	}
	if len(fallback) > 0 {
		_ = render.font_add_face(fallback)
	}
	render.font_clear_atlas()
	return true
}

font_path_of :: proc() -> string {
	if len(editor.settings.font_path) > 0 {
		return editor.settings.font_path
	}
	return "C:/Windows/Fonts/consola.ttf"
}

main :: proc() {
	window: platform.Window
	if !platform.window_create(&window, 1280, 720, "Nico's Own Editor") {
		fmt.eprintln("Failed to create window")
		return
	}
	defer platform.window_destroy(&window)

	if !platform.gl_context_create(&window) {
		fmt.eprintln("Failed to create GL context")
		return
	}
	defer platform.gl_context_destroy(&window)

	platform.window_show(&window)

	backend := render.backend_gl()
	if !backend.init(&window) {
		fmt.eprintln("Failed to init renderer")
		return
	}
	defer backend.shutdown()

	queue: render.Render_Queue
	render.queue_init(&queue, 1 << 20) // 1 MB
	defer render.queue_destroy(&queue)

	editor.register_default_commands()
	editor.bind_default_keys()
	defer delete(editor.commands)
	defer delete(editor.keymap)

	ed: editor.Editor
	editor.editor_init(&ed, "")
	editor.script_init(&ed)
	defer editor.script_shutdown(&ed)
	live_path := strings.clone(font_path_of())
	live_fallback := strings.clone(editor.settings.font_fallback)
	live_size := editor.settings.font_size
	if !apply_font(live_path, live_fallback, live_size) {
		fmt.eprintln("Failed to load font:", live_path)
		return
	}
	defer {
		delete(live_path)
		delete(live_fallback)
	}
	render.pixel_height = f32(editor.settings.font_size)
	render.tab_spaces = f32(editor.settings.tab_width)
	render.tofu = editor.settings.tofu
	ed.host = &window
	editor.editor_update_title(&ed)
	window.needs_redraw = true
	last_input := time.tick_now()
	caret_on := true
	dragging := false
	splitting := false
	defer editor.editor_destroy(&ed)

	for !window.should_close {
		platform.window_poll(&window)

		if window.should_close {
			if !editor.editor_confirm_close(&ed) {
				window.should_close = false
			} else {
				break
			}
		}

		render.tab_spaces = f32(editor.settings.tab_width)
		render.tofu = editor.settings.tofu
		blink := i64(editor.settings.blink_ms)
		if ed.font_dirty {
			ed.font_dirty = false
			path := font_path_of()
			fb := editor.settings.font_fallback
			size := editor.settings.font_size
			if apply_font(path, fb, size) {
				delete(live_path)
				delete(live_fallback)
				live_path = strings.clone(path)
				live_fallback = strings.clone(fb)
				live_size = size
				for &buf in ed.buffers {
					buf.scroll_x_dirty = true
				}
			} else {
				fmt.eprintln("Failed to load font:", path)
				_ = apply_font(live_path, live_fallback, live_size)
			}
		}
		
		v := editor.active_view(&ed)
		b := editor.active_buffer(&ed)
		lh_page := render.font_line_height()
		n_lines := text.buffer_line_count(&b.doc)
		digit_w := render.font_width("0")
		digits := max(editor.line_digits(n_lines), editor.settings.gutter_min_digits)
		gutter_w := f32(digits) * digit_w + editor.settings.gutter_pad
		if !editor.settings.show_gutter {
			gutter_w = 0
		}
		status_h := lh_page + editor.settings.status_pad
		if !editor.settings.show_status {
			status_h = 0
		}
		lay := editor.layout_compute(f32(window.width), f32(window.height), lh_page, gutter_w, status_h, len(ed.views), ed.split_t)
		// tr := lay.views[0].text
		// gr := lay.views[0].gutter
		tr := lay.views[ed.active_view].text
		gr := lay.views[ed.active_view].gutter
		sr := lay.status
		v.page_lines = 1
		if lh_page > 0 && tr.h > 0 {
			v.page_lines = max(int(tr.h / lh_page) - 1, 1)
		}

		follow := false
		had_events := window.event_count > 0
		for i in 0 ..< window.event_count {
			#partial switch ev in window.events[i] {
				case platform.IME_Commit_Event:
				{
					commit := ev
					s := string(commit.text[:commit.len])
					if editor.overlay_is_open(&ed) {
						for r in s {
							editor.overlay_insert_rune(&ed, r)
						}
					} else {
						editor.insert_text(&ed, s)
						follow = true
					}
				}
				case platform.Text_Event:
				{
					if editor.overlay_is_open(&ed) {
						editor.overlay_insert_rune(&ed, ev.ch)
					} else {
						editor.insert_rune(&ed, ev.ch)
						follow = true
					}
				}
				case platform.Key_Event:
				{
					if editor.overlay_is_open(&ed) {
						editor.overlay_key(&ed, ev.key, ev.mods)
						follow = true
						break
					}

					if name, ok := editor.lookup_key(ev.key, ev.mods); ok {
						editor.run_command(&ed, name)
						follow = true
					}
				}
				case platform.Mouse_Event:
				{
					if ev.button != .Left {
						break
					}
					if editor.overlay_is_open(&ed) {
						if ev.action == .Down && !editor.rect_contains(lay.overlay, ev.x, ev.y) {
							editor.overlay_close(&ed)
							ed.eat_mouse = true
						}
						break
					}
					if ed.eat_mouse {
						if ev.action == .Up {
							ed.eat_mouse = false
						}
						dragging = false
						break
					}
					if ev.action == .Up {
						dragging = false
						splitting = false
						break
					}
					hit := -1
					for i in 0 ..< lay.view_count {
						if editor.rect_contains(lay.views[i].text, ev.x, ev.y) {
							hit = i
							break
						}
					}

					split_hit := lay.split
					split_hit.x -= 3
					split_hit.w += 6

					if ev.action == .Down {
						if lay.view_count == 2 && editor.rect_contains(split_hit, ev.x, ev.y) {
							splitting = true
							dragging = false
							break
						}
						if hit < 0 {
							break
						}
						ed.active_view = hit
						dragging = true
						pv := editor.active_view(&ed)
						pb := editor.active_buffer(&ed)
						pos := pos_at_xy(pv, pb, lay.views[ed.active_view].text, ev.x, ev.y)
						if .Shift in ev.mods {
							editor.drag_to(&ed, pos)
						} else {
							editor.click_at(&ed, pos)
						}
						break
					}

					if ev.action == .Move && splitting {
						usable := lay.views[0].pane.w + lay.views[1].pane.w
						if usable > 0 {
							min_w := editor.pane_min_width(gutter_w, usable)
							left := clamp(ev.x - lay.views[0].pane.x, min_w, usable - min_w)
							ed.split_t = left / usable
						}
						break
					}

					if ev.action == .Move && dragging {
						tr := lay.views[ed.active_view].text
						mx, my := ev.x, ev.y
						lh := render.font_line_height()
						ch := render.font_width("0")
						if hit != ed.active_view {
							mx = clamp(mx, tr.x, tr.x + max(tr.w - 1, 0))
							my = clamp(my, tr.y, tr.y + max(tr.h - 1, 0))
						}
						pv := editor.active_view(&ed)
						pb := editor.active_buffer(&ed)
						pos := pos_at_xy(pv, pb, tr, mx, my)
						line := text.buffer_line_at(&pb.doc, pos)
						ls := text.buffer_line_start(&pb.doc, line)
						le := text.buffer_line_end(&pb.doc, line)
						if my < tr.y + lh {
							editor.scroll_by(&ed, -lh, max_scroll_y(&ed, lh))
						} else if my > tr.y + tr.h - lh {
							editor.scroll_by(&ed, lh, max_scroll_y(&ed, lh))
						}
						if mx < tr.x + ch && pos > ls {
							editor.scroll_by_x(&ed, -ch * 3, max_scroll_x(&ed))
						} else if mx > tr.x + tr.w - ch && pos < le {
							editor.scroll_by_x(&ed, ch * 3, max_scroll_x(&ed))
						}
						pos = pos_at_xy(pv, pb, tr, mx, my)
						editor.drag_to(&ed, pos)
					}
				}
				case platform.Scroll_Event:
				{
					lh := render.font_line_height()
					if .Shift in ev.mods {
						editor.scroll_by_x(&ed, -ev.notches * lh * editor.settings.scroll_lines, max_scroll_x(&ed))
					} else {
						editor.scroll_by(&ed, -ev.notches * lh * editor.settings.scroll_lines, max_scroll_y(&ed, lh))
					}
				}
			}
		}
		platform.events_clear(&window)
		lay = editor.layout_compute(f32(window.width), f32(window.height), 
			lh_page, gutter_w, status_h, len(ed.views), ed.split_t)
		sr = lay.status
		v = editor.active_view(&ed)
		b = editor.active_buffer(&ed)
		tr = lay.views[ed.active_view].text

		cur: platform.Cursor = .Arrow
		if splitting {
			cur = .Size_WE
		} else if lay.view_count == 2 && !editor.overlay_is_open(&ed) {
			split_hit := lay.split
			split_hit.x -= 3
			split_hit.w += 6
			if editor.rect_contains(split_hit, window.mouse_x, window.mouse_y) {
				cur = .Size_WE
			}
		}
		platform.window_set_cursor(&window, cur)
		
		if had_events {
			last_input = time.tick_now()
			caret_on = true
			window.needs_redraw = true
		}

		if follow {
			lh := render.font_line_height()
			
			line_i := text.buffer_line_at(&b.doc, v.cursor)
			ls := text.buffer_line_start(&b.doc, line_i)
			line := text.buffer_line_clone(&b.doc, line_i)
			defer delete(line)
			caret_x := render.font_width(line[:min(v.cursor - ls, len(line))])
			editor.ensure_cursor_visible(
				&ed,
				tr.x, tr.y, caret_x, lh,
				tr.w, tr.h,
				max_scroll_x(&ed), max_scroll_y(&ed, lh))
		}

		since := i64(time.duration_milliseconds(time.tick_since(last_input)))
		on := true
		if window.ime_preview_len == 0 && since >= blink {
			on = (since / blink) % 2 == 0
		}
		if on != caret_on {
			caret_on = on
			window.needs_redraw = true
		}

		if window.needs_redraw {
			window.needs_redraw = false
			
			render.queue_reset(&queue)
			render.push_clear(&queue, editor.settings.bg)
	
			lh := render.font_line_height()

			// Pan divider
			if lay.view_count == 2 {
				left := lay.views[0].pane
				right := lay.views[1].pane
				dx := right.x - (left.x + left.w)
				if dx > 0 {
					render.push_quad(
						&queue,
						{left.x + left.w, left.y},
						{dx, left.h},
						editor.settings.divider
					)
				}
			}
			
			for vi in 0 ..< lay.view_count {
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

				// Gutter
				if dgr.x > 0 {
					render.push_clip(&queue, {dgr.x, dgr.y}, {dgr.w, dgr.h})
					cur_line := text.buffer_line_at(&db.doc, dv.cursor)
					for i in first ..< last {
						label := fmt.tprintf("%d", i + 1)
						tw := render.font_width(label)
						x := dgr.x + dgr.w - tw - 8
						y := line_top(dv, dtr, i, lh)
						color: [4]f32 = editor.settings.gutter
						if i == cur_line {
							color = editor.settings.gutter_current
						}
						render.push_text(&queue, label, x, y + render.the_font.ascent, color)
					}
					render.push_clip_disabled(&queue)
				}
	
				// Text area
				render.push_clip(&queue, {dtr.x, dtr.y}, {dtr.w, dtr.h})

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
							render.push_quad(&queue, {x0, y}, {x1 - x0, lh}, sel)
						}
					}
				}
		
				for i in first ..< last {
					line := text.buffer_line_clone(&db.doc, i)
					defer delete(line)
					y := line_top(dv, dtr, i, lh)
					render.push_text(&queue, line, dtr.x - dv.scroll_x, y + render.the_font.ascent, editor.settings.text)
				}
	
				line_i := text.buffer_line_at(&db.doc, dv.cursor)
				line_start := text.buffer_line_start(&db.doc, line_i)
				line := text.buffer_line_clone(&db.doc, line_i)
				defer delete(line)
				prefix := line[:min(dv.cursor - line_start, len(line))]
				cx := dtr.x + render.font_width(prefix) - dv.scroll_x
				cy := line_top(dv, dtr, line_i, lh)
				baseline := cy + render.font_ascent()
				if vi == ed.active_view {
					if window.ime_preview_len > 0 {
						preview := string(window.ime_preview[:window.ime_preview_len])
						render.push_text(&queue, preview, cx, baseline, editor.settings.ime_preview)
						cx += render.font_width(preview)
					}
					platform.ime_set_pos(&window, i32(cx), i32(cy + lh))
					if caret_on || window.ime_preview_len > 0 {
						render.push_quad(&queue, {cx, cy}, {editor.settings.caret_w, lh}, editor.settings.caret)
					}
				} else {
					render.push_quad(&queue, {cx, cy}, {editor.settings.caret_w, lh}, editor.settings.caret_inactive)
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
					if vi == ed.active_view && caret_on {
						col = editor.settings.caret
					}
					render.push_quad(&queue, {ex, ey}, {editor.settings.caret_w, lh}, col)
				}

				render.push_clip_disabled(&queue)
			}


			// Status line
			if sr.h > 0 {
				render.push_clip(&queue, {sr.x, sr.y}, {sr.w, sr.h})
				render.push_quad(&queue, {sr.x, sr.y}, {sr.w, sr.h}, editor.settings.status_bg)
				line_i := text.buffer_line_at(&b.doc, v.cursor)
				col := v.cursor - text.buffer_line_start(&b.doc, line_i) + 1
				star := ""
				if b.dirty {
					star = " *"
				}
				left := fmt.tprintf("%s%s", editor.editor_display_name(&ed), star)
				eol := "LF"
				if b.newline == .CRLF {
					eol = "CRLF"
				}
				right := fmt.tprintf("Ln %d, Col %d		%s", line_i + 1, col, eol)
				if sl, sr_status, sok := editor.script_status_line(&ed); sok {
					left, right = sl, sr_status
				}
				sy := sr.y + (sr.h - lh) * 0.8 + render.font_ascent()
				render.push_text(&queue, left, sr.x + 8, sy, editor.settings.status_text)
				rx := sr.x + sr.w - render.font_width(right) - 8
				render.push_text(&queue, right, rx, sy, editor.settings.status_text)
				render.push_clip_disabled(&queue)
			}

			// Overlay
			if editor.overlay_is_open(&ed) {
				ov := lay.overlay
				if ed.overlay.kind == .Switcher {
					ov.h = lh * f32(editor.settings.overlay_rows)
				}
				render.push_clip(&queue, {ov.x, ov.y}, {ov.w, ov.h})
				render.push_quad(&queue, {ov.x, ov.y}, {ov.w, ov.h}, editor.settings.overlay_bg)
				label := "Find: "
				if ed.overlay.kind == .Switcher {
					label = "Buffer: "
				}
				lx := ov.x + 8
				ly := ov.y + render.font_ascent() + 8
				render.push_text(&queue, label, lx, ly, editor.settings.overlay_label)
				lx += render.font_width(label)
				q := string(ed.overlay.text[:])
				render.push_text(&queue, q, lx, ly, editor.settings.text)
				prefix := string(ed.overlay.text[:ed.overlay.cursor])
				cx := lx + render.font_width(prefix)
				cy := ov.y + 8
				if caret_on {
					render.push_quad(&queue, {cx, cy}, {editor.settings.caret_w, lh}, editor.settings.caret)
				}

				if ed.overlay.kind == .Switcher {
					qy := ly + lh
					row := 0
					query := string(ed.overlay.text[:])
					for i in 0 ..< len(ed.buffers) {
						name := editor.buffer_display_name(&ed.buffers[i])
						if len(query) != 0 && !strings.contains(name, query) {
							continue
						}
						color: [4]f32 = editor.settings.overlay_list
						if row == ed.overlay.sel {
							render.push_quad(&queue, {ov.x, qy - render.font_ascent()}, {ov.w, lh}, editor.settings.selection)
							color = editor.settings.overlay_sel_fg
						}
						render.push_text(&queue, name, ov.x + 8, qy, color)
						qy += lh
						row += 1
					}
				}

				render.push_clip_disabled(&queue)
			}
	
	
			backend.begin_frame()
			backend.execute(&queue)
			backend.end_frame()
		}

		wait_ms : u32 = u32(blink)
		since_wait := i64(time.duration_milliseconds(time.tick_since(last_input)))
		if since_wait < blink {
			wait_ms = u32(blink - since_wait)
		} else {
			into := since_wait % blink
			wait_ms = u32(blink - into)
		}
		if wait_ms < 1 {
			wait_ms = 1
		}

		free_all(context.temp_allocator)
		platform.window_wait(wait_ms)
	}
}