package main

import "core:sync"
import "core:fmt"
import "core:unicode/utf8"
import "platform"
import "render"
import "text"

bc :: 35.0 / 255.0

sync_col :: proc(doc: ^text.Buffer, cursor: int) -> int {
	line := text.buffer_line_at(doc, cursor)
	return cursor - text.buffer_line_start(doc, line)
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

	doc: text.Buffer
	text.buffer_init(&doc, 4096)
	defer text.buffer_destroy(&doc)
	text.buffer_insert(&doc, 0, "Nico")
	cursor := text.buffer_len(&doc)
	desired_col := cursor - text.buffer_line_start(&doc, text.buffer_line_at(&doc, cursor))

	for !window.should_close {
		platform.window_poll(&window)

		for i in 0 ..< window.event_count {
			#partial switch ev in window.events[i] {
				case platform.IME_Commit_Event:
				{
					commit := ev
					s := string(commit.text[:commit.len])
					text.buffer_insert(&doc, cursor, s)
					cursor += commit.len
					desired_col = sync_col(&doc, cursor)
				}
				case platform.Text_Event:
				{
					bytes, n := utf8.encode_rune(ev.ch)
					text.buffer_insert(&doc, cursor, string(bytes[:n]))
					cursor += n
					desired_col = sync_col(&doc, cursor)
				}
				case platform.Key_Event:
				{
					switch ev.key {
						case .Backspace:
						{
							if cursor > 0 {
								start, size := text.buffer_prev_rune(&doc, cursor)
								text.buffer_delete(&doc, start, size)
								cursor = start
								desired_col = sync_col(&doc, cursor)
							}
						}
						case .Left:
						{
							start, _ := text.buffer_prev_rune(&doc, cursor)
							cursor = start
							desired_col = sync_col(&doc, cursor)
						}
						case .Right:
						{
							end, _ := text.buffer_next_rune(&doc, cursor)
							cursor = end
							desired_col = sync_col(&doc, cursor)
						}
						case .Up:
						{
							line := text.buffer_line_at(&doc, cursor)
							if line > 0 {
								cursor = text.buffer_pos_at_line(&doc, line - 1, desired_col)
							}
						}
						case .Down:
						{
							line := text.buffer_line_at(&doc, cursor)
							if line + 1 < text.buffer_line_count(&doc) {
								cursor = text.buffer_pos_at_line(&doc, line + 1, desired_col)
							}
						}
						case .Enter:
						{
							text.buffer_insert(&doc, cursor, "\n")
							cursor += 1
							desired_col = sync_col(&doc, cursor)
						}
						case .Unknown:
						{
							
						}
					}
				}
			}
		}
		platform.events_clear(&window)

		render.queue_reset(&queue)
		render.push_clear(&queue, {bc, bc, bc, 1.0})

		lh := render.font_line_height()
		baseline0 := 64 + render.the_font.ascent
		for i in 0 ..< text.buffer_line_count(&doc) {
			line := text.buffer_line_clone(&doc, i)
			defer delete(line)
			render.push_text(&queue, line, 32, baseline0 + f32(i) * lh, {0.90, 0.90, 0.90, 1.0})
			
		}
		line_i := text.buffer_line_at(&doc, cursor)
		line_start := text.buffer_line_start(&doc, line_i)
		prefix := text.buffer_line_clone(&doc, line_i)
		defer delete(prefix)
		prefix = prefix[:min(cursor - line_start, len(prefix))]

		cx := 32 + render.font_width(prefix)
		cy := baseline0 + f32(line_i) * lh - render.font_ascent()
		if window.ime_preview_len > 0 {
			preview := string(window.ime_preview[:window.ime_preview_len])
			render.push_text(&queue, preview, cx, baseline0 + f32(line_i) * lh, {0.70, 0.85, 1.00, 1.0})
			cx += render.font_width(preview)
		}
		platform.ime_set_pos(&window, i32(cx), i32(cy + lh))
		render.push_quad(&queue, {cx, cy}, {2, lh}, {0.90, 0.90, 0.90, 1.0})


		backend.begin_frame()
		backend.execute(&queue)
		backend.end_frame()
	}
}
