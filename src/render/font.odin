package render

import "core:os"
import tt "vendor:stb/truetype"
import "core:unicode/utf8"

PAD             :: 1
MAX_FACES       :: 8    // How many font files are loaded at once
pixel_height: f32       = 18
tab_spaces:   f32       = 4
tofu:         [4]f32    = {0.55, 0.55, 0.55, 1.0}

Glyph :: struct {
    uv_min, uv_max: [2]f32,
    size:           [2]f32,
    xoff, yoff:     f32,
    xadvance:       f32,
    ok:             bool
}

Font_Face :: struct {
    info:   tt.fontinfo,
    ttf:    []u8,
    scale:  f32
}

Font :: struct {
    faces:          [MAX_FACES]Font_Face,
    face_count:     int,
    glyphs:         map[rune]Glyph,
    pack_x:         int,
    pack_y:         int,
    pack_row_h:     int,
    ascent:         f32,
    line_height:    f32
}

the_font: Font

font_init :: proc(path: string) -> bool {
    the_font.glyphs = make(map[rune]Glyph)
    the_font.pack_x = 1
    the_font.pack_y = 0
    the_font.pack_row_h = 1

    if !font_add_face(path) {
        return false
    }

    a, d, g: i32
    tt.GetFontVMetrics(&the_font.faces[0].info, &a, &d, &g)
    s := the_font.faces[0].scale
    the_font.ascent = f32(a) * s
    the_font.line_height = f32(a - d + g) * s
    return true
}

font_shutdown :: proc() {
    for i in 0 ..< the_font.face_count {
        delete(the_font.faces[i].ttf)
    }
    delete(the_font.glyphs)
    the_font = {}
}

push_text :: proc(q: ^Render_Queue, text: string, x, y: f32, color: [4]f32) {
    pen_x, pen_y := x, y
    for r in text {
        if r == '\n' || r == '\r' {
            continue
        }

        if r == '\t' {
            pen_x += font_glyph(' ').xadvance * tab_spaces
            continue
        }

        g := font_glyph(r)
        if g.ok && (g.size.x > 0 || g.size.y > 0) {
            push_quads(q, {Quad{
                {pen_x + g.xoff, pen_y + g.yoff},
                g.size,
                g.uv_min,
                g.uv_max,
                color
            }})
        } else if !g.ok {
            push_quad(q, {pen_x, pen_y - the_font.ascent}, {max(g.xadvance, 8) * 0.6, the_font.ascent * 0.8}, tofu)
        }
        pen_x += g.xadvance
    }
}

font_line_height :: proc() -> f32 {
    return the_font.line_height
}

font_width :: proc(s: string) -> f32 {
	w: f32
	for r in s {
		if r == '\n' || r == '\r' {
			continue
		}
        if r == '\t' {
            w += font_glyph(' ').xadvance * tab_spaces
            continue
        }
		w += font_glyph(r).xadvance
	}
	return w
}

font_ascent :: proc() -> f32 {
    return the_font.ascent
}

font_add_face :: proc(path: string, ttc_index: i32 = 0) -> bool {
    if the_font.face_count >= MAX_FACES {
        return false
    }
    data, err := os.read_entire_file(path, context.allocator)
    if err != nil {
        return false
    }
    offset := tt.GetFontOffsetForIndex(raw_data(data), ttc_index)
    if offset < 0 {
        delete(data)
        return false
    }
    face := &the_font.faces[the_font.face_count]
    if !tt.InitFont(&face.info, raw_data(data), offset) {
        delete(data)
        return false
    }
    face.ttf = data
    face.scale = tt.ScaleForPixelHeight(&face.info, pixel_height)
    the_font.face_count += 1
    return true
}

font_pack :: proc(w, h: int) -> (x, y: int, ok: bool) {
    w := w + PAD * 2
    h := h + PAD * 2
    if w > ATLAS_SIZE || h > ATLAS_SIZE {
        return 0, 0, false
    }
    if the_font.pack_x + w > ATLAS_SIZE {
        the_font.pack_y += the_font.pack_row_h
        the_font.pack_x = 0
        the_font.pack_row_h = 0
    }
    if the_font.pack_y + h > ATLAS_SIZE {
        return 0, 0, false
    }
    x = the_font.pack_x + PAD
    y = the_font.pack_y + PAD
    the_font.pack_x += w
    the_font.pack_row_h = max(the_font.pack_row_h, h)
    return x, y, true
}

font_glyph :: proc(r: rune) -> Glyph {
    if g, found := the_font.glyphs[r]; found {
        return g
    }

    g: Glyph
    for i in 0 ..< the_font.face_count {
        face := &the_font.faces[i]
        if tt.FindGlyphIndex(&face.info, r) == 0 && r != ' ' {
            continue
        }

        adv, lsb: i32
        tt.GetCodepointHMetrics(&face.info, r, &adv, &lsb)
        g.xadvance = f32(adv) * face.scale
        g.ok = true

        ix0, iy0, ix1, iy1: i32
        tt.GetCodepointBitmapBox(&face.info, r, face.scale, face.scale, &ix0, &iy0, &ix1, &iy1)
        gw, gh := int(ix1 - ix0), int(iy1 - iy0)
        if gw <= 0 || gh <= 0 {
            the_font.glyphs[r] = g
            return g
        }

        bw, bh, xoff, yoff: i32
        bitmap := tt.GetCodepointBitmap(
            &face.info, face.scale, face.scale, r,
            &bw, &bh, &xoff, &yoff,
        )
        if bitmap == nil {
            break
        }

        px, py, fit := font_pack(int(bw), int(bh))
        if !fit {
            tt.FreeBitmap(bitmap, nil)
            g.ok = false
            break
        }

        gl_texture_update(gls.atlas, {i32(px), i32(py), bw, bh}, bitmap[:bw * bh])
        tt.FreeBitmap(bitmap, nil)

        s := 1.0 / f32(ATLAS_SIZE)
        g.size = {f32(bw), f32(bh)}
		g.xoff = f32(xoff)
		g.yoff = f32(yoff)
		g.uv_min = {f32(px) * s, f32(py) * s}
		g.uv_max = {f32(px + int(bw)) * s, f32(py + int(bh)) * s}
		the_font.glyphs[r] = g
		return g
    }

    the_font.glyphs[r] = g
    return g
}

font_index_at :: proc(s: string, x: f32) -> int {
    if x <= 0 {
        return 0
    }
    pen: f32
    i := 0
    for i < len(s) {
        r, n := utf8.decode_rune(s[i:])
        if n <= 0 || r == '\n' || r == '\r' {
            break
        }
        adv := font_glyph(r).xadvance
        if r == '\t' {
            adv = font_glyph(' ').xadvance * tab_spaces
        }
        if x < pen + adv * 0.5 {
            return i
        }
        pen += adv
        i += n
    }
    return len(s)
}

font_clear_atlas :: proc() {
    pixels := make([]u8, ATLAS_SIZE * ATLAS_SIZE)
    defer delete(pixels)
    pixels[0] = 255
    gl_texture_update(gls.atlas, {0, 0, ATLAS_SIZE, ATLAS_SIZE}, pixels)
}