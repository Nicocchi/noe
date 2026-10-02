package platform

import "base:runtime"
import win "core:sys/windows"
import gl "vendor:OpenGL"

CLASS_NAME :: "NoeWindowClass"

Window :: struct {
	hwnd:				win.HWND,
	hdc:				win.HDC,
	hglrc:				win.HGLRC,
	width:				i32,
	height: 			i32,
	should_close:		bool,
	events:				[EVENT_CAP]Event,
	event_count:		int,
	ime_composing: 		bool,
	ime_preview: 		[256]u8,
	ime_preview_len: 	int,
	needs_redraw:		bool
}

g_ctx: runtime.Context
wgl_create_context_attribs: win.CreateContextAttribsARBType

GL_MAJOR :: 4
GL_MINOR :: 6
QS_ALLINPUT :: 0x04FF

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

		case win.WM_CHAR:
		{
			if window == nil {
				return 0
			}

			if window.ime_composing {
				return 0
			}

			ch := rune(wparam)
			if ch >= 32 && ch != 127 {
				event_push(window, Text_Event{ch})
			}
			return 0
		}

		case win.WM_KEYDOWN:
		{
			if window == nil {
				return 0
			}

			mods := key_mods()

			if window.ime_composing {
				switch wparam {
					case win.VK_BACK, win.VK_LEFT, win.VK_RIGHT, win.VK_RETURN, win.VK_UP, win.VK_DOWN,
     					 win.VK_HOME, win.VK_END, win.VK_DELETE, win.VK_PRIOR, win.VK_NEXT:
					{
						return win.DefWindowProcW(hwnd, msg, wparam, lparam)
					}
				}
			}

			key: Key
			switch wparam {
				case win.VK_BACK:
				{
					key = .Backspace
				}
				case win.VK_LEFT:
				{
					key = .Left
				}
				case win.VK_RIGHT:
				{
					key = .Right
				}
				case win.VK_UP:
				{
					key = .Up
				}
				case win.VK_DOWN:
				{
					key = .Down
				}
				case win.VK_RETURN:
				{
					key = .Enter
				}
				case win.VK_HOME:
				{
					key = .Home
				}
				case win.VK_END:
				{
					key = .End
				}
				case win.VK_DELETE:
				{
					key = .Delete
				}
				case win.VK_PRIOR:
				{
					key = .Page_Up
				}
				case win.VK_NEXT:
				{
					key = .Page_Down
				}
				case win.VK_TAB:
				{
					key = .Tab
				}
				case 'Z':
				{
					key = .Z
				}
				case 'Y':
				{
					key = .Y
				}
				case 'O':
				{
					key = .O
				}
				case 'S':
				{
					key = .S
				}
				case 'C':
				{
					key = .C
				}
				case 'X':
				{
					key = .X
				}
				case 'V':
				{
					key = .V
				}
				case:
				{
					return win.DefWindowProcW(hwnd, msg, wparam, lparam)
				}
			}
			event_push(window, Key_Event{key, mods})
			return 0
		}
		case win.WM_IME_STARTCOMPOSITION:
		{
			if window != nil {
				window.ime_composing = true
				ime_clear_preview(window)
			}
			window.needs_redraw = true
			return 0
		}
		case win.WM_IME_ENDCOMPOSITION:
		{
			if window != nil {
				window.ime_composing = false
				ime_clear_preview(window)
			}
			window.needs_redraw = true
			return 0
		}
		case win.WM_IME_COMPOSITION:
		{
			if window == nil {
				return 0
			}
			himc := ImmGetContext(hwnd)
			if himc != nil {
				if lparam & GCS_RESULTSTR != 0 {
					ev: IME_Commit_Event
					ev.len = ime_read_utf8(himc, GCS_RESULTSTR, ev.text[:])
					if ev.len > 0 {
						event_push(window, ev)
					}
					ime_clear_preview(window)
				}
				if lparam & GCS_COMPSTR != 0 {
					window.ime_preview_len = ime_read_utf8(himc, GCS_COMPSTR, window.ime_preview[:])
				}
				ImmReleaseContext(hwnd, himc)
			}
			window.needs_redraw = true
			return 0
		}
		case win.WM_IME_SETCONTEXT:
		{
			lp := lparam
			lp &= ~win.LPARAM(ISC_SHOWUICOMPOSITIONWINDOW)
			return win.DefWindowProcW(hwnd, msg, wparam, lp)
		}
		case win.WM_LBUTTONDOWN:
		{
			if window == nil || window.ime_composing {
				return 0
			}

			win.SetCapture(hwnd)
			x := f32(win.GET_X_LPARAM(lparam))
			y := f32(win.GET_Y_LPARAM(lparam))
			event_push(window, Mouse_Event{x, y, .Left, .Down, key_mods()})
			return 0
		}
		case win.WM_LBUTTONUP:
		{
			if window == nil {
				return 0
			}

			if win.GetCapture() == hwnd {
				win.ReleaseCapture()
			}

			x := f32(win.GET_X_LPARAM(lparam))
			y := f32(win.GET_Y_LPARAM(lparam))
			event_push(window, Mouse_Event{x, y, .Left, .Up, key_mods()})
			return 0
		}
		case win.WM_MOUSEMOVE:
		{
			if window == nil || window.ime_composing || (wparam & win.MK_LBUTTON == 0) {
				return 0
			}

			x := f32(win.GET_X_LPARAM(lparam))
			y := f32(win.GET_Y_LPARAM(lparam))
			event_push(window, Mouse_Event{x, y, .Left, .Move, key_mods()})
			return 0
		}
		case win.WM_MOUSEWHEEL:
		{
			if window == nil || window.ime_composing {
				return 0
			}
			d := f32(win.GET_WHEEL_DELTA_WPARAM(wparam)) / f32(win.WHEEL_DELTA)
			event_push(window, Scroll_Event{d})
			return 0
		}
		case win.WM_SIZE:
		{
			if window != nil {
				window.needs_redraw = true
			}
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

	w.hdc = win.GetDC(w.hwnd)
	if w.hdc == nil {
		win.DestroyWindow(w.hwnd)
		w.hwnd = nil
		return false
	}

	rect: win.RECT
	win.GetClientRect(w.hwnd, &rect)
	w.width = rect.right - rect.left
	w.height = rect.bottom - rect.top

	return true
}

window_show :: proc(w: ^Window) {
	win.ShowWindow(w.hwnd, win.SW_SHOW)
}

window_wait :: proc(timeout_ms: u32) {
	win.MsgWaitForMultipleObjects(0, nil, false, timeout_ms, QS_ALLINPUT)
}

window_poll :: proc(w: ^Window) {
	msg: win.MSG
	for win.PeekMessageW(&msg, nil, 0, 0, win.PM_REMOVE) {
		win.TranslateMessage(&msg)
		win.DispatchMessageW(&msg)
	}
}

window_destroy :: proc(w: ^Window) {
	if w.hdc != nil {
		win.ReleaseDC(w.hwnd, w.hdc)
		w.hdc = nil
	}

	if w.hwnd != nil {
		win.DestroyWindow(w.hwnd)
		w.hwnd = nil
	}
}

pixel_format_set :: proc(hdc: win.HDC) -> bool {
	pfd := win.PIXELFORMATDESCRIPTOR {
		nSize =			win.WORD(size_of(win.PIXELFORMATDESCRIPTOR)),
		nVersion = 		1,
		dwFlags = 		win.PFD_DRAW_TO_WINDOW | win.PFD_SUPPORT_OPENGL | win.PFD_DOUBLEBUFFER,
		iPixelType = 	win.PFD_TYPE_RGBA,
		cColorBits = 	32,
		cDepthBits = 	24,
		cStencilBits = 	8,
	}

	format := win.ChoosePixelFormat(hdc, &pfd)
	if format == 0 {
		return false
	}

	return win.SetPixelFormat(hdc, format, &pfd) == true
}

load_wgl_extensions :: proc() -> bool {
	instance := win.HINSTANCE(win.GetModuleHandleW(nil))

	dummy := win.CreateWindowExW(
		0,
		win.L(CLASS_NAME),
		win.L("NOE Dummy"),
		win.WS_OVERLAPPED,
		0, 0, 1, 1,
		nil, nil, instance, nil
	)
	if dummy == nil {
		return false
	}
	defer win.DestroyWindow(dummy)

	hdc := win.GetDC(dummy)
	if hdc == nil {
		return false
	}
	defer win.ReleaseDC(dummy, hdc)

	if !pixel_format_set(hdc) {
		return false
	}

	dummy_gl := win.wglCreateContext(hdc)
	if dummy_gl == nil {
		return false
	}
	defer win.wglDeleteContext(dummy_gl)
	if win.wglMakeCurrent(hdc, dummy_gl) != true {
		return false
	}
	defer win.wglMakeCurrent(nil, nil)

	proc_ptr := win.wglGetProcAddress("wglCreateContextAttribsARB")
	switch uintptr(proc_ptr) {
		case 0, 1, 2, 3, ~uintptr(0):
			return false
	}

	wgl_create_context_attribs = win.CreateContextAttribsARBType(proc_ptr)
	return wgl_create_context_attribs != nil
}

gl_context_create :: proc(w: ^Window) -> bool {
	if !load_wgl_extensions() || !pixel_format_set(w.hdc) {
		return false
	}

	attribs := [?]win.c_int {
		win.CONTEXT_MAJOR_VERSION_ARB, GL_MAJOR,
		win.CONTEXT_MINOR_VERSION_ARB, GL_MINOR,
		win.CONTEXT_PROFILE_MASK_ARB, win.CONTEXT_CORE_PROFILE_BIT_ARB,
		0
	}

	w.hglrc = wgl_create_context_attribs(w.hdc, nil, raw_data(attribs[:]))
	if w.hglrc == nil {
		return false
	}

	if win.wglMakeCurrent(w.hdc, w.hglrc) != true {
		win.wglDeleteContext(w.hglrc)
		w.hglrc = nil
		return false
	}

	gl.load_up_to(GL_MAJOR, GL_MINOR, win.gl_set_proc_address)

	return true
}

gl_context_destroy :: proc(w: ^Window) {
	if w.hglrc != nil {
		win.wglMakeCurrent(nil, nil)
		win.wglDeleteContext(w.hglrc)
		w.hglrc = nil
	}
}

key_mods :: proc() -> Mods {
	mods: Mods
	if u16(win.GetKeyState(win.VK_CONTROL)) & 0x8000 != 0 {
		mods += {.Ctrl}
	}
	if u16(win.GetKeyState(win.VK_SHIFT)) & 0x8000 != 0 {
		mods += {.Shift}
	}
	if u16(win.GetKeyState(win.VK_MENU)) & 0x8000 != 0 {
		mods += {.Alt}
	}
	return mods
}

window_set_title :: proc(w: ^Window, title: string) {
	if w == nil || w.hwnd == nil {
		return
	}
	win.SetWindowTextW(w.hwnd, win.utf8_to_wstring(title))
}