package editor

// Body padding - from window edges (top-left)
PAD_X :: 12
PAD_Y :: 12

Rect :: struct {
    x, y, w, h: f32
}

View_Layout :: struct {
    pane:   Rect,
    gutter: Rect,
    text:   Rect
}

Layout :: struct {
    views:      [2]View_Layout,
    view_count: int,
    status:     Rect,
    overlay:    Rect
}

rect_contains :: proc(r: Rect, px, py: f32) -> bool {
    return px >= r.x && py >= r.y && px < r.x + r.w && py < r.y + r.h
}

layout_compute :: proc(win_w, win_h, lh, gutter_w, status_h: f32, view_count: int) -> Layout {
    lay: Layout
    n := clamp(view_count, 1, 2)
    lay.view_count = n

    status_h := max(status_h, 0)
    body_h := max(win_h - PAD_Y - status_h, 0)
    body := Rect{PAD_X, PAD_Y, max(win_w - PAD_X, 0), body_h}

    gap: f32 = 0
    if n == 2 {
        gap = 4
    }

    vw := (body.w - gap) / f32(n)
    for i in 0 ..< n {
        pane := Rect{body.x + f32(i) * (vw + gap), body.y, vw, body.h}
        gw := clamp(gutter_w, 0, pane.w)
        lay.views[i] = View_Layout{
            pane    = pane,
            gutter  = Rect{pane.x, pane.y, gw, pane.h},
            text    = Rect{pane.x + gw, pane.y, pane.w - gw, pane.h}
        }
    }

    lay.status = Rect{0, win_h - status_h, win_w, status_h}

    ow := min(win_w * 0.6, max(win_w - 16, 0))
    oh := lh + 16
    lay.overlay = Rect{(win_w - ow) * 0.5, PAD_Y + 8, ow, oh}
    return lay
}

line_digits :: proc(line_count: int) -> int {
    n := max(line_count, 1)
    d := 1
    for n >= 10 {
        n /= 10
        d += 1
    }
    return d
}