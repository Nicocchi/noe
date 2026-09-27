package main

import "core:fmt"
import "platform"
import "render"
import "text"
import "editor"

bc :: 35.0 / 255.0

TEXT_X :: 32
TEXT_Y :: 64

pos_at_xy :: proc(ed: ^editor.Editor, x, y: f32) -> int {
	lh := render.font_line_height()
	n := text.buffer_line_count(&ed.doc)
	line := 0
	doc_y := y - f32(TEXT_Y) + ed.scroll_y
	if doc_y >= 0 && lh > 0 {
		line = int(doc_y / lh)
	}
	line = clamp(line, 0, n - 1)
	s := text.buffer_line_clone(&ed.doc, line)
	defer delete(s)
	col := render.font_index_at(s, x - f32(TEXT_X))
	return text.buffer_line_start(&ed.doc, line) + col
}

line_top :: proc(ed: ^editor.Editor, line: int, lh: f32) -> f32 {
	return f32(TEXT_Y) + f32(line) * lh - ed.scroll_y
}

max_scroll_y :: proc(ed: ^editor.Editor, lh: f32) -> f32 {
	n := text.buffer_line_count(&ed.doc)
	if n <= 1 {
		return 0
	}
	return f32(n - 1) * lh
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
	editor.editor_init(&ed, "Nico")
	defer editor.editor_destroy(&ed)

	for !window.should_close {
		platform.window_poll(&window)

		follow := false
		for i in 0 ..< window.event_count {
			#partial switch ev in window.events[i] {
				case platform.IME_Commit_Event:
				{
					commit := ev
					editor.insert_text(&ed, string(commit.text[:commit.len]))
					follow = true
				}
				case platform.Text_Event:
				{
					editor.insert_rune(&ed, ev.ch)
					follow = true
				}
				case platform.Key_Event:
				{
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
					pos := pos_at_xy(&ed, ev.x, ev.y)
					switch ev.action {
						case .Down:
						{
							editor.click_at(&ed, pos)
						}
						case .Move, .Up:
						{
							editor.drag_to(&ed, pos)
						}
					}
					follow = true
				}
				case platform.Scroll_Event:
				{
					lh := render.font_line_height()
					editor.scroll_by(&ed, -ev.notches * lh * 3, max_scroll_y(&ed, lh))
				}
			}
		}
		platform.events_clear(&window)

		if follow {
			lh := render.font_line_height()
			editor.ensure_cursor_visible(&ed, f32(TEXT_Y), lh, f32(window.height), max_scroll_y(&ed, lh))
		}

		render.queue_reset(&queue)
		render.push_clear(&queue, {bc, bc, bc, 1.0})

		lh := render.font_line_height()
		n_lines := text.buffer_line_count(&ed.doc)

		first := 0
		last := n_lines
		if lh > 0 {
			first = clamp(int((ed.scroll_y - f32(TEXT_Y)) / lh) - 1, 0, n_lines)
			last = clamp(int((ed.scroll_y + f32(window.height)) / lh) + 1, 0, n_lines)
		}

		lo, hi := editor.selection_range(&ed)
		if lo != hi {
			sel := [4]f32{0.25, 0.40, 0.62, 1.0}
			for i in first ..< last {
				ls := text.buffer_line_start(&ed.doc, i)
				le := text.buffer_line_end(&ed.doc, i)
				if hi <= ls || lo > le {
					continue
				}
				line := text.buffer_line_clone(&ed.doc, i)
				defer delete(line)
				a := clamp(lo - ls, 0, len(line))
				b := clamp(hi - ls, 0, len(line))
				x0 := f32(TEXT_X) + render.font_width(line[:a])
				x1 := f32(TEXT_X) + render.font_width(line[:b])
				if hi > le && lo <= le {
					x1 += 8
				}
				y := line_top(&ed, i, lh)
				if x1 > x0 {
					render.push_quad(&queue, {x0, y}, {x1 - x0, lh}, sel)
				}
			}
		}

		for i in first ..< last {
			line := text.buffer_line_clone(&ed.doc, i)
			defer delete(line)
			y := line_top(&ed, i, lh)
			render.push_text(&queue, line, TEXT_X, y + render.the_font.ascent, {0.90, 0.90, 0.90, 1.0})
		}

		line_i := text.buffer_line_at(&ed.doc, ed.cursor)
		line_start := text.buffer_line_start(&ed.doc, line_i)
		line := text.buffer_line_clone(&ed.doc, line_i)
		defer delete(line)
		prefix := line[:min(ed.cursor - line_start, len(line))]
		cx := TEXT_X + render.font_width(prefix)
		cy := line_top(&ed, line_i, lh)
		baseline := cy + render.font_ascent()
		if window.ime_preview_len > 0 {
			preview := string(window.ime_preview[:window.ime_preview_len])
			render.push_text(&queue, preview, cx, baseline, {0.70, 0.85, 1.00, 1.0})
			cx += render.font_width(preview)
		}
		platform.ime_set_pos(&window, i32(cx), i32(cy + lh))
		render.push_quad(&queue, {cx, cy}, {2, lh}, {0.90, 0.90, 0.90, 1.0})


		backend.begin_frame()
		backend.execute(&queue)
		backend.end_frame()
	}
}