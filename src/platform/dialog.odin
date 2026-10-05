package platform

import win "core:sys/windows"
import "core:fmt"

WM_MOUSEFIRST :: 0x0200
WM_MOUSELAST  :: 0x020E

Unsaved_Choice :: enum {
    Save,
    Discard,
    Cancel
}

dialog_unsaved :: proc(w: ^Window, name: string) -> Unsaved_Choice {
    if w == nil || w.hwnd == nil {
        return .Cancel
    }
    msg := fmt.tprintf("Save changes to %s?", name)
    caption := "NOE"
    r := win.MessageBoxW(
        w.hwnd,
        win.utf8_to_wstring(msg),
        win.utf8_to_wstring(caption),
        win.MB_YESNOCANCEL | win.MB_ICONWARNING
    )
    dialog_eat_mouse(w)
    switch r {
        case win.IDYES:
        {
            return .Save
        }
        case win.IDNO:
        {
            return .Discard
        }
    }
    return .Cancel
}

dialog_eat_mouse :: proc(w: ^Window) {
    if w == nil || w.hwnd == nil {
        return
    }
    if win.GetCapture() == w.hwnd {
        win.ReleaseCapture()
    }
    msg: win.MSG
    for win.PeekMessageW(&msg, w.hwnd, WM_MOUSEFIRST, WM_MOUSELAST, win.PM_REMOVE) {

    }
    events_clear(w)
}

dialog_open_path :: proc(w: ^Window) -> (path: string, ok: bool) {
    if w == nil || w.hwnd == nil {
        return "", false
    }
    buf: [1024]u16
    filter := "All Files\x00*.*\x00"
    ofn := win.OPENFILENAMEW {
        lStructSize = size_of(win.OPENFILENAMEW),
        hwndOwner   = w.hwnd,
        lpstrFilter = win.utf8_to_wstring(filter),
        lpstrFile   = win.wstring(&buf[0]),
        nMaxFile    = u32(len(buf)),
        Flags       = win.OFN_EXPLORER | win.OFN_FILEMUSTEXIST | win.OFN_PATHMUSTEXIST | win.OFN_NOCHANGEDIR
    }
    if win.GetOpenFileNameW(&ofn) != true {
        return "", false
    }
    dialog_eat_mouse(w)
    path, _ = win.utf16_to_utf8(buf[:], context.allocator)
    return path, true
}

dialog_save_path :: proc(w: ^Window) -> (path: string, ok: bool) {
    if w == nil || w.hwnd == nil {
        return "", false
    }
    buf: [1024]u16
    filter := "All Files\x00*.*\x00"
    ofn := win.OPENFILENAMEW {
        lStructSize = size_of(win.OPENFILENAMEW),
        hwndOwner   = w.hwnd,
        lpstrFilter = win.utf8_to_wstring(filter),
        lpstrFile   = win.wstring(&buf[0]),
        nMaxFile    = u32(len(buf)),
        lpstrDefExt = win.L("txt"),
        Flags       = win.OFN_EXPLORER | win.OFN_OVERWRITEPROMPT | win.OFN_NOCHANGEDIR
    }
    if win.GetSaveFileNameW(&ofn) != true {
        return "", false
    }
    dialog_eat_mouse(w)
    path, _ = win.utf16_to_utf8(buf[:], context.allocator)
    return path, true
}