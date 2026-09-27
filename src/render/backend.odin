package render

import "../platform"

Texture_Handle :: distinct u32

Texture_Format :: enum {
    R8
}

Texture_Rect :: struct {
    x, y, w, h: i32
}

Backend :: struct {
    init:               proc(w: ^platform.Window) -> bool,
    begin_frame:        proc(),
    execute:            proc(q: ^Render_Queue),
    end_frame:          proc(),
    shutdown:           proc(),
    texture_create:     proc(w, h: int, format: Texture_Format) -> Texture_Handle,
    texture_update:     proc(t: Texture_Handle, rect: Texture_Rect, pixels: []u8),
    texture_destroy:    proc(t: Texture_Handle)
}