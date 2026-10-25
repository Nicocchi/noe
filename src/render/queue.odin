package render

Entry_Kind :: enum u32 {
    Clear,
    Quads,
    Set_Clip,
}

Entry_Header :: struct {
    kind: Entry_Kind,
    size: u32
}

Entry_Clear :: struct {
    using header:   Entry_Header,
    color:          [4]f32
}

Quad :: struct {
    pos:    [2]f32,
    size:   [2]f32,
    uv_min: [2]f32,
    uv_max: [2]f32,
    color:  [4]f32
}

Entry_Quads :: struct {
    using header:   Entry_Header,
    count:          u32,
    _pad:           u32
}

Entry_Clip :: struct {
    using header: Entry_Header,
    pos: [2]f32,
    rect_size: [2]f32,
    enabled: b32
}

Render_Queue :: struct {
    data: []u8,
    used: int
}

ALIGN :: 8
ATLAS_SIZE :: 512

queue_init :: proc(q: ^Render_Queue, cap: int) {
    q.data = make([]u8, cap)
    q.used = 0
}

queue_destroy :: proc(q: ^Render_Queue) {
    delete(q.data)
    q.data = nil
    q.used = 0
}

queue_reset :: proc(q: ^Render_Queue) {
    q.used = 0
}

align_forward :: proc(value, align: int) -> int {
    return (value + align - 1) & ~(align -1)
}

queue_alloc :: proc(q: ^Render_Queue, size: int) -> rawptr {
    size := align_forward(size, ALIGN)
    if q.used + size > len(q.data) {
        return nil
    }
    ptr := rawptr(&q.data[q.used])
    q.used += size
    return ptr
}

push_clear :: proc(q: ^Render_Queue, color: [4]f32) -> bool {
    size := align_forward(size_of(Entry_Clear), ALIGN)
    ptr := queue_alloc(q, size)
    if ptr == nil {
        return false
    }

    entry := (^Entry_Clear)(ptr)
    entry.kind  = .Clear
    entry.size  = u32(size)
    entry.color = color
    return true
}

push_quad :: proc(q: ^Render_Queue, pos, size: [2]f32, color: [4]f32) -> bool {
    uv_min, uv_max := white_uv()
    one := [1]Quad{Quad{pos, size, uv_min, uv_max, color}}
    return push_quads(q, one[:])
}

push_quads :: proc(q: ^Render_Queue, quads: []Quad) -> bool {
    if len(quads) == 0 {
        return true
    }
    bytes := align_forward(size_of(Entry_Quads) + size_of(Quad) * len(quads), ALIGN)
    ptr := queue_alloc(q, bytes)
    if ptr == nil {
        return false
    }

    entry := (^Entry_Quads)(ptr)
    entry.kind  = .Quads
    entry.size  = u32(bytes)
    entry.count = u32(len(quads))
    entry._pad  = 0

    dst := ([^]Quad)(uintptr(ptr) + uintptr(size_of(Entry_Quads)))
    for quad, i in quads {
        dst[i] = quad
    }
    return true
}

push_border :: proc(q: ^Render_Queue, pos, size: [2]f32, t: f32, color: [4]f32) -> bool {
	if t <= 0 || size.x <= 0 || size.y <= 0 {
		return true
	}
	t := min(t, size.x * 0.5, size.y * 0.5)
	ok := push_quad(q, pos, {size.x, t}, color)
    ok &= push_quad(q, {pos.x, pos.y + size.y - t}, {size.x, t}, color)
    ok &= push_quad(q, pos, {t, size.y}, color)
    ok &= push_quad(q, {pos.x + size.x - t, pos.y}, {t, size.y}, color)
	return ok
}

push_clip :: proc(q: ^Render_Queue, pos, rect_size: [2]f32) -> bool {
    bytes := align_forward(size_of(Entry_Clip), ALIGN)
    ptr := queue_alloc(q, bytes)
    if ptr == nil {
        return false
    }

    entry               := (^Entry_Clip)(ptr)
    entry.kind          = .Set_Clip
    entry.size          = u32(bytes)
    entry.pos           = pos
    entry.rect_size     = rect_size
    entry.enabled       = true

    return true
}

push_clip_disabled :: proc(q: ^Render_Queue) -> bool {
    bytes := align_forward(size_of(Entry_Clip), ALIGN)
    ptr := queue_alloc(q, bytes)
    if ptr == nil {
        return false
    }

    entry               := (^Entry_Clip)(ptr)
    entry.kind          = .Set_Clip
    entry.size          = u32(bytes)
    entry.pos           = {}
    entry.rect_size     = {}
    entry.enabled       = false

    return true
}

white_uv :: proc() -> (uv_min, uv_max: [2]f32) {
    s := 1.0 / f32(ATLAS_SIZE)
    c := 0.5 * s
    return {c, c}, {c, c}
}