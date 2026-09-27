package platform

import win "core:sys/windows"

HIMC :: distinct win.HANDLE

GCS_COMPSTR                 :: 0x0008
GCS_RESULTSTR               :: 0x0800
ISC_SHOWUICOMPOSITIONWINDOW :: 0x8000_0000

CFS_POINT                   :: 0x0002

COMPOSITIONFORM :: struct {
    dwStyle:        win.DWORD,
    ptCurrentPos:   win.POINT,
    rcArea:         win.RECT
}

foreign import imm32 "system:Imm32.lib"

@(default_calling_convention="system")
foreign imm32 {
    ImmGetContext :: proc(hWnd: win.HWND) -> HIMC ---
	ImmReleaseContext :: proc(hWnd: win.HWND, hIMC: HIMC) -> win.BOOL ---
	ImmGetCompositionStringW :: proc(hIMC: HIMC, index: win.DWORD, buf: rawptr, buflen: win.DWORD) -> win.LONG ---
	ImmSetCompositionWindow :: proc(hIMC: HIMC, form: ^COMPOSITIONFORM) -> win.BOOL ---
}

ime_read_utf8 :: proc(himc: HIMC, what: win.DWORD, dst: []u8) -> int {
    nbytes := ImmGetCompositionStringW(himc, what, nil, 0)
    if nbytes <= 0 {
        return 0
    }
    wlen := int(nbytes) / 2
    wbuf: [256]u16
    n := min(wlen, len(wbuf))
    ImmGetCompositionStringW(himc, what, raw_data(wbuf[:]), win.DWORD(n * 2))
    s, _ := win.utf16_to_utf8(wbuf[:n])
    n_out := min(len(s), len(dst))
    copy(dst, s[:n_out])
    return n_out
}

ime_clear_preview :: proc(w: ^Window) {
    w.ime_preview_len = 0
}

ime_set_pos :: proc(w: ^Window, x, y: i32) {
    himc := ImmGetContext(w.hwnd)
    if himc == nil {
        return
    }
    form := COMPOSITIONFORM {
        dwStyle = CFS_POINT,
        ptCurrentPos = {x, y}
    }
    ImmSetCompositionWindow(himc, &form)
    ImmReleaseContext(w.hwnd, himc)
}