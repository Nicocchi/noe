package main

import "core:sync"
import "core:fmt"
import "core:unicode/utf8"
import "platform"
import "render"
import "text"
import "editor"

bc :: 35.0 / 255.0

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

		for i in 0 ..< window.event_count {
			#partial switch ev in window.events[i] {
				case platform.IME_Commit_Event:
				{
					commit := ev
					editor.insert_text(&ed, string(commit.text[:commit.len]))
				}
				case platform.Text_Event:
				{
					editor.insert_rune(&ed, ev.ch)
				}
				case platform.Key_Event:
				{
					if name, ok := editor.lookup_key(ev.key, ev.mods); ok {
						editor.run_command(&ed, name)
					}
				}
			}
		}
		platform.events_clear(&window)

		render.queue_reset(&queue)
		render.push_clear(&queue, {bc, bc, bc, 1.0})

		lh := render.font_line_height()
		baseline0 := 64 + render.the_font.ascent
		for i in 0 ..< text.buffer_line_count(&ed.doc) {
			line := text.buffer_line_clone(&ed.doc, i)
			defer delete(line)
			render.push_text(&queue, line, 32, baseline0 + f32(i) * lh, {0.90, 0.90, 0.90, 1.0})
			
		}
		line_i := text.buffer_line_at(&ed.doc, ed.cursor)
		line_start := text.buffer_line_start(&ed.doc, line_i)
		prefix := text.buffer_line_clone(&ed.doc, line_i)
		defer delete(prefix)
		prefix = prefix[:min(ed.cursor - line_start, len(prefix))]

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
