package platform

import "base:runtime"
import win "core:sys/windows"

CLASS_NAME :: "NoeWindowClass"

Window :: struct {
	hwnd: win.HWND,
	width: i32,
	height: i32,
	should_close: bool
}

g_ctx: runtime.Context

window_proc :: proc "stdcall" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM,
								lparam: win.LPARAM) -> win.LRESULT {
	context = g_ctx

	window := (^Window)(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA)))

	switch msg {
		case win.WM_NCCREATE:
		{
			cs := (^win.CREATESTRUCTW)(uintptr(lparam))
			win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, win.LONG_PTR(uintptr(cs.lpCreateParams)))
			return win.DefWindowProcW(hwnd, msg, wparam, lparam)
		}

		case win.WM_CLOSE:
		{
			if window != nil {
				window.should_close = true
			}
			return 0
		}

		case win.WM_DESTROY:
		{
			win.PostQuitMessage(0)
			return 0
		}
	}

	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

window_create :: proc(w: ^Window, width, height: i32, title: string) -> bool {
	g_ctx = context

	instance := win.HINSTANCE(win.GetModuleHandleW(nil))

	wc := win.WNDCLASSW {
		style = win.CS_HREDRAW | win.CS_VREDRAW | win.CS_OWNDC,
		lpfnWndProc = window_proc,
		hInstance = instance,
		hCursor = win.LoadCursorA(nil, win.IDC_ARROW),
		lpszClassName = win.L(CLASS_NAME)
	}

	if win.RegisterClassW(&wc) == 0 {
		return false
	}

	w.width, w.height = width, height

	w.hwnd = win.CreateWindowExW(
		0,
		win.L(CLASS_NAME),
		win.utf8_to_wstring(title),
		win.WS_OVERLAPPEDWINDOW,
		win.CW_USEDEFAULT, win.CW_USEDEFAULT,
		width, height,
		nil, nil, instance, w
	)
	if w.hwnd == nil {
		return false
	}

	win.ShowWindow(w.hwnd, win.SW_SHOW)
	return true
}

window_poll :: proc(w: ^Window) {
	msg: win.MSG
	for win.PeekMessageW(&msg, nil, 0, 0, win.PM_REMOVE) {
		win.TranslateMessage(&msg)
		win.DispatchMessageW(&msg)
	}
}

window_destroy :: proc(w: ^Window) {
	if w.hwnd != nil {
		win.DestroyWindow(w.hwnd)
		w.hwnd = nil
	}
}
