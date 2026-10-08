package render

import gl "vendor:OpenGL"
import "../platform"
import win "core:sys/windows"

INSTANCE_CAP :: 4096

GL_Renderer :: struct {
    window:     ^platform.Window,
    program:    u32,
    vao:        u32,
    vbo:        u32,
    geo_vbo:    u32,
    inst_vbo:   u32,
    u_screen:   i32,
    instances:  []Quad,
    inst_used:  int,
    u_atlas:    i32,
    atlas:      Texture_Handle
}

gls: GL_Renderer

GL_VS :: `
#version 330 core
layout(location = 0) in vec2 a_corner;
layout(location = 1) in vec2 a_pos;
layout(location = 2) in vec2 a_size;
layout(location = 3) in vec2 a_uv_min;
layout(location = 4) in vec2 a_uv_max;
layout(location = 5) in vec4 a_color;
uniform vec2 u_screen;
out vec4 v_color;
out vec2 v_uv;
void main() {
	vec2 pixel = a_pos + a_corner * a_size;
	vec2 ndc = vec2(
		(pixel.x / u_screen.x) * 2.0 - 1.0,
		1.0 - (pixel.y / u_screen.y) * 2.0
	);
	gl_Position = vec4(ndc, 0.0, 1.0);
	v_color = a_color;
	v_uv = mix(a_uv_min, a_uv_max, a_corner);
}
`

GL_FS :: `
#version 330 core
in vec4 v_color;
in vec2 v_uv;
uniform sampler2D u_atlas;
out vec4 frag;
void main() {
	float coverage = texture(u_atlas, v_uv).r;
	frag = vec4(v_color.rgb, v_color.a * coverage);
}
`

backend_gl :: proc() -> Backend {
    return Backend {
        init        = gl_init,
        begin_frame = gl_begin_frame,
        execute     = gl_execute,
        end_frame   = gl_end_frame,
        shutdown    = gl_shutdown
    }
}

gl_init :: proc(w: ^platform.Window) -> bool {
    if w.hglrc == nil {
        return false
    }
    gls.window = w
    gls.instances = make([]Quad, INSTANCE_CAP)

    ok: bool
    gls.program, ok = gl.load_shaders_source(GL_VS, GL_FS)
    if !ok {
        delete(gls.instances)
        gls = {}
        return false
    }
    gls.u_screen = gl.GetUniformLocation(gls.program, "u_screen")
    gls.u_atlas = gl.GetUniformLocation(gls.program, "u_atlas")

    corners := [4][2]f32 {
        {0, 0},
        {1, 0},
        {0, 1},
        {1, 1},
    }

    gl.GenVertexArrays(1, &gls.vao)
    gl.GenBuffers(1, &gls.geo_vbo)
    gl.GenBuffers(1, &gls.inst_vbo)

    gl.BindVertexArray(gls.vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, gls.geo_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(corners), &corners[0], gl.STATIC_DRAW)
    gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(0, 2, gl.FLOAT, false, size_of([2]f32), 0)

	gl.BindBuffer(gl.ARRAY_BUFFER, gls.inst_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(Quad) * INSTANCE_CAP, nil, gl.STREAM_DRAW)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 2, gl.FLOAT, false, size_of(Quad), offset_of(Quad, pos))
	gl.EnableVertexAttribArray(2)
	gl.VertexAttribPointer(2, 2, gl.FLOAT, false, size_of(Quad), offset_of(Quad, size))
	gl.EnableVertexAttribArray(3)
    gl.VertexAttribPointer(3, 2, gl.FLOAT, false, size_of(Quad), offset_of(Quad, uv_min))
    gl.EnableVertexAttribArray(4)
    gl.VertexAttribPointer(4, 2, gl.FLOAT, false, size_of(Quad), offset_of(Quad, uv_max))
    gl.EnableVertexAttribArray(5)
    gl.VertexAttribPointer(5, 4, gl.FLOAT, false, size_of(Quad), offset_of(Quad, color))
    gl.VertexAttribDivisor(1, 1)
    gl.VertexAttribDivisor(2, 1)
    gl.VertexAttribDivisor(3, 1)
    gl.VertexAttribDivisor(4, 1)
    gl.VertexAttribDivisor(5, 1)

    gl.BindVertexArray(0)

    gls.atlas = gl_texture_create(ATLAS_SIZE, ATLAS_SIZE, .R8)
    pixels := make([]u8, ATLAS_SIZE * ATLAS_SIZE)
    defer delete(pixels)
    pixels[0] = 255
    gl_texture_update(gls.atlas, {0, 0, ATLAS_SIZE, ATLAS_SIZE}, pixels)

    return true
}

gl_begin_frame :: proc() {
    w := gls.window
    rect: win.RECT
    win.GetClientRect(w.hwnd, &rect)
    w.width = rect.right - rect.left
    w.height = rect.bottom - rect.top

    gl.Viewport(0, 0, w.width, w.height)
    gl.UseProgram(gls.program)
    gl.Uniform1i(gls.u_atlas, 0)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, u32(gls.atlas))
    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    gl.Uniform2f(gls.u_screen, f32(w.width), f32(w.height))
    gl.Disable(gl.SCISSOR_TEST)
}

gl_execute :: proc(q: ^Render_Queue) {
    offset := 0
    for offset < q.used {
        header := (^Entry_Header)(&q.data[offset])
        if header.size == 0 {
            break
        }

        switch header.kind {
            case .Clear:
            {
                gl_flush_quads()
                entry := (^Entry_Clear)(header)
                gl.ClearColor(entry.color.r, entry.color.g, entry.color.b, entry.color.a)
                gl.Clear(gl.COLOR_BUFFER_BIT)
            }
            case .Quads:
            {
                entry := (^Entry_Quads)(header)
                quads := ([^]Quad)(uintptr(header) + uintptr(size_of(Entry_Quads)))
                for i in 0 ..< entry.count {
                    gl_push_instance(quads[i])
                }
            }
            case .Set_Clip:
            {
                entry := (^Entry_Clip)(header)
                gl_apply_clip(entry)
            }
        }

        offset += int(header.size)
    }
    gl_flush_quads()
}

gl_end_frame :: proc() {
    win.SwapBuffers(gls.window.hdc)
}

gl_shutdown :: proc() {
    font_shutdown()
    gl_texture_destroy(gls.atlas)
    gl.DeleteBuffers(1, &gls.geo_vbo)
	gl.DeleteBuffers(1, &gls.inst_vbo)
	gl.DeleteVertexArrays(1, &gls.vao)
	gl.DeleteProgram(gls.program)
	delete(gls.instances)
	gls = {}
}

gl_flush_quads :: proc() {
    if gls.inst_used == 0 {
        return
    }

    gl.BindVertexArray(gls.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, gls.inst_vbo)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(Quad) * gls.inst_used, &gls.instances[0], gl.STREAM_DRAW)
	gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, i32(gls.inst_used))
	gls.inst_used = 0
}

gl_push_instance :: proc(q: Quad) {
    if gls.inst_used == len(gls.instances) {
        gl_flush_quads()
    }
    gls.instances[gls.inst_used] = q
    gls.inst_used += 1
}

gl_apply_clip :: proc(entry: ^Entry_Clip) {
    gl_flush_quads()

    if !entry.enabled {
        gl.Disable(gl.SCISSOR_TEST)
        return
    }

    x := i32(entry.pos.x)
    w := i32(entry.rect_size.x)
    h := i32(entry.rect_size.y)
    y := gls.window.height - i32(entry.pos.y) - h

    gl.Enable(gl.SCISSOR_TEST)
    gl.Scissor(x, y, w, h)
}

gl_texture_create :: proc(w, h: int, format: Texture_Format) -> Texture_Handle {
    tex: u32
    gl.GenTextures(1, &tex)
	gl.BindTexture(gl.TEXTURE_2D, tex)
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.NEAREST))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.NEAREST))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(gl.CLAMP_TO_EDGE))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(gl.CLAMP_TO_EDGE))

    internal: i32
    switch format {
        case .R8:
        {
            internal = i32(gl.R8)
        }
    }
    gl.TexImage2D(gl.TEXTURE_2D, 0, internal, i32(w), i32(h), 0, gl.RED, gl.UNSIGNED_BYTE, nil)
    return Texture_Handle(tex)
}

gl_texture_update :: proc(t: Texture_Handle, rect: Texture_Rect, pixels: []u8) {
    gl.BindTexture(gl.TEXTURE_2D, u32(t))
    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
    gl.TexSubImage2D(
        gl.TEXTURE_2D, 0,
        rect.x, rect.y, rect.w, rect.h,
        gl.RED, gl.UNSIGNED_BYTE,
        raw_data(pixels)
    )
}

gl_texture_destroy :: proc(t: Texture_Handle) {
    tex := u32(t)
    gl.DeleteTextures(1, &tex)
}

debug_h_uv :: proc() -> (uv_min, uv_max: [2]f32) {
    s := 1.0 / f32(ATLAS_SIZE)
    return {8.5 * s, 8.5 * s}, {23.5 * s, 55.5 * s}
}