package platform

import win "core:sys/windows"

CF_UNICODETEXT  :: 13
GMEM_MOVEABLE   :: 0x0002

foreign import kernel32 "system:Kernel32.lib"
foreign import user32 "system:User32.lib"

@(default_calling_convention="system")
foreign kernel32 {
    GlobalAlloc  :: proc(uFlags: win.UINT, dwBytes: win.SIZE_T) -> win.HGLOBAL ---
	GlobalLock   :: proc(hMem: win.HGLOBAL) -> rawptr ---
	GlobalUnlock :: proc(hMem: win.HGLOBAL) -> win.BOOL ---
	GlobalFree   :: proc(hMem: win.HGLOBAL) -> win.HGLOBAL ---
}

@(default_calling_convention="system")
foreign user32 {
	OpenClipboard    :: proc(hWndNewOwner: win.HWND) -> win.BOOL ---
	CloseClipboard   :: proc() -> win.BOOL ---
	EmptyClipboard   :: proc() -> win.BOOL ---
	SetClipboardData :: proc(uFormat: win.UINT, hMem: win.HANDLE) -> win.HANDLE ---
	GetClipboardData :: proc(uFormat: win.UINT) -> win.HANDLE ---
}

clipboard_set :: proc(w: ^Window, s: string) -> bool {
    if w == nil || w.hwnd == nil || len(s) == 0 {
        return false
    }
    wide := win.utf8_to_utf16(s, context.allocator)
    if wide == nil {
        return false
    }
    defer delete(wide)

    bytes := win.SIZE_T((len(wide) + 1) * size_of(u16))
    mem := GlobalAlloc(GMEM_MOVEABLE, bytes)
    if mem == nil {
        return false
    }
    ptr := GlobalLock(mem)
    if ptr == nil {
        GlobalFree(mem)
        return false
    }
    dst := ([^]u16)(ptr)
    for i in 0 ..< len(wide) {
        dst[i] = wide[i]
    }
    dst[len(wide)] = 0
    GlobalUnlock(mem)

    if OpenClipboard(w.hwnd) != true {
        GlobalFree(mem)
        return false
    }
    EmptyClipboard()
    if SetClipboardData(CF_UNICODETEXT, win.HANDLE(mem)) == nil {
        CloseClipboard()
        GlobalFree(mem)
        return false
    }
    CloseClipboard()
    return true
}

clipboard_get :: proc(w: ^Window) -> (s: string, ok: bool) {
    if w == nil || w.hwnd == nil {
        return "", false
    }
    if OpenClipboard(w.hwnd) != true {
        return "", false
    }
    defer CloseClipboard()

    mem := GetClipboardData(CF_UNICODETEXT)
    if mem == nil {
        return "", false
    }
    h := win.HGLOBAL(mem)
    ptr := GlobalLock(h)
    if ptr == nil {
        return "", false
    }
    defer GlobalUnlock(h)
    
    src := ([^]u16)(ptr)
    n := 0
    for src[n] != 0 {
        n += 1
    }
    s, _ = win.utf16_to_utf8(src[:n], context.allocator)
    return s, len(s) > 0
}