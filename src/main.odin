package main

import "core:fmt"
import "platform"

main :: proc() {
	window: platform.Window
	if !platform.window_create(&window, 1280, 720, "Runic") {
		fmt.eprintln("failed to create window")
		return
	}
	defer platform.window_destroy(&window)

	for !window.should_close {
		platform.window_poll(&window)
	}
}
