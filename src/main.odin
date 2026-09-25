package main

import "core:fmt"
import "platform"

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

	for !window.should_close {
		platform.window_poll(&window)
		platform.frame_begin(&window)
		platform.frame_end(&window)
	}
}
