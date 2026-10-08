package editor

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
    overlay:    Rect,
    split:      Rect
}

rect_contains :: proc(r: Rect, px, py: f32) -> bool {
    return px >= r.x && py >= r.y && px < r.x + r.w && py < r.y + r.h
}

pane_min_width :: proc(gutter_w, usable: f32) -> f32 {
    return min(max(gutter_w + settings.pane_min_extra, settings.pane_min_w), usable * 0.5)
}

layout_compute :: proc(win_w, win_h, lh, gutter_w, status_h: f32, view_count: int, split_t: f32) -> Layout {
    lay: Layout
    n := clamp(view_count, 1, 2)
    lay.view_count = n

    status_h := max(status_h, 0)
    body_h := max(win_h - settings.pad_y - status_h, 0)
    body := Rect{settings.pad_x, settings.pad_y, max(win_w - settings.pad_x, 0), body_h}

    gap: f32 = 0
    widths: [2]f32
    widths[0] = body.w
    if n == 2 {
        gap = settings.split_gap
        usable := max(body.w - gap, 0)
        min_w := pane_min_width(gutter_w, usable)
        left_w := clamp(usable * clamp(split_t, 0, 1), min_w, usable - min_w)
        widths[0] = left_w
        widths[1] = usable - left_w
        lay.split = Rect{body.x + left_w, body.y, gap, body.h}
    }

    x := body.x
    for i in 0 ..< n {
        pane := Rect{x, body.y, widths[i], body.h}
        gw := clamp(gutter_w, 0, pane.w)
        lay.views[i] = View_Layout{
            pane    = pane,
            gutter  = Rect{pane.x, pane.y, gw, pane.h},
            text    = Rect{
                pane.x + gw + settings.text_pad_x,
                pane.y + settings.text_pad_y,
                max(pane.w - gw - settings.text_pad_x, 0),
                max(pane.h - settings.text_pad_y * 2, 0),
            }
        }
        x += widths[i] + gap
    }

    lay.status = Rect{0, win_h - status_h, win_w, status_h}

    ow := min(win_w * settings.overlay_width, max(win_w - settings.overlay_pad * 2, 0))
    oh := lh + settings.overlay_pad * 2
    lay.overlay = Rect{(win_w - ow) * 0.5, settings.pad_y + settings.overlay_pad, ow, oh}
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