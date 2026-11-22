package platform

import "core:os"
import "base:runtime"

import win "core:sys/windows"
import gl "vendor:OpenGL"

CLASS_NAME :: "NoeWindowClass"

ATTACH_PARENT_PROCESS :: win.DWORD(0xFFFFFFFF)

Cursor :: enum {
    Arrow,
    Size_WE
}


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
	needs_redraw:		bool,
	mouse_x, mouse_y:	f32,
	cursor:				Cursor
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
				case win.VK_ESCAPE:
				{
					key = .Escape
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
				case win.VK_OEM_5:
				{
					key = .Backslash
				}
				case win.VK_SPACE:
				{
					key = .Space
				}
				case win.VK_INSERT:
				{
					key = .Insert
				}
				case '0' ..= '9':
				{
					key = Key(int(Key.Digit_0) + int(wparam - '0'))
				}
				case win.VK_F1 ..= win.VK_F12:
				{
					key = Key(int(Key.F1) + int(wparam - win.VK_F1))
				}
				case win.VK_OEM_MINUS:
				{
					key = .Minus
				}
				case win.VK_OEM_PLUS:
				{
					key = .Equal
				}
				case win.VK_OEM_COMMA:
				{
					key = .Comma
				}
				case win.VK_OEM_PERIOD:
				{
					key = .Period
				}
				case win.VK_OEM_2:
				{
					key = .Slash
				}
				case win.VK_OEM_1:
				{
					key = .Semicolon
				}
				case win.VK_OEM_7:
				{
					key = .Apostrophe
				}
				case win.VK_OEM_4:
				{
					key = .LBracket
				}
				case win.VK_OEM_6:
				{
					key = .RBracket
				}
				case win.VK_OEM_3:
				{
					key = .Grave
				}
				case 'A':
				{
					key = .A
				}
				case 'B':
				{
					key = .B
				}
				case 'C':
				{
					key = .C
				}
				case 'D':
				{
					key = .D
				}
				case 'E':
				{
					key = .E
				}
				case 'F':
				{
					key = .F
				}
				case 'G':
				{
					key = .G
				}
				case 'H':
				{
					key = .H
				}
				case 'I':
				{
					key = .I
				}
				case 'J':
				{
					key = .J
				}
				case 'K':
				{
					key = .K
				}
				case 'L':
				{
					key = .L
				}
				case 'M':
				{
					key = .M
				}
				case 'N':
				{
					key = .N
				}
				case 'O':
				{
					key = .O
				}
				case 'P':
				{
					key = .P
				}
				case 'Q':
				{
					key = .Q
				}
				case 'R':
				{
					key = .R
				}
				case 'S':
				{
					key = .S
				}
				case 'T':
				{
					key = .T
				}
				case 'U':
				{
					key = .U
				}
				case 'V':
				{
					key = .V
				}
				case 'W':
				{
					key = .W
				}
				case 'X':
				{
					key = .X
				}
				case 'Y':
				{
					key = .Y
				}
				case 'Z':
				{
					key = .Z
				}
				case:
				{
					return win.DefWindowProcW(hwnd, msg, wparam, lparam)
				}
			}
			event_push(window, Key_Event{key, mods})
			return 0
		}
		case win.WM_SYSKEYDOWN:
		{
			if window == nil {
				return win.DefWindowProcW(hwnd, msg, wparam, lparam)
			}
			mods := key_mods()
			if .Alt in mods && (wparam == win.VK_UP || wparam == win.VK_DOWN) {
				key := Key.Down
				if wparam == win.VK_UP {
					key = .Up
				}
				event_push(window, Key_Event{key, mods})
				return 0
			}
			return win.DefWindowProcW(hwnd, msg, wparam, lparam)
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
					window.needs_redraw = true
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
			window.mouse_x = f32(win.GET_X_LPARAM(lparam))
			window.mouse_y = f32(win.GET_Y_LPARAM(lparam))
			event_push(window, Mouse_Event{window.mouse_x, window.mouse_y, .Left, .Down, key_mods()})
			return 0
		}
		case win.WM_LBUTTONDBLCLK:
		{
			if window == nil || window.ime_composing {
				return 0
			}
			win.SetCapture(hwnd)
			window.mouse_x = f32(win.GET_X_LPARAM(lparam))
			window.mouse_y = f32(win.GET_Y_LPARAM(lparam))
			event_push(window, Mouse_Event{window.mouse_x, window.mouse_y, .Left, .Double, key_mods()})
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

			window.mouse_x = f32(win.GET_X_LPARAM(lparam))
			window.mouse_y = f32(win.GET_Y_LPARAM(lparam))
			event_push(window, Mouse_Event{window.mouse_x, window.mouse_y, .Left, .Up, key_mods()})
			return 0
		}
		case win.WM_MOUSEMOVE:
		{
			if window == nil || window.ime_composing {
				return 0
			}
			window.mouse_x = f32(win.GET_X_LPARAM(lparam))
			window.mouse_y = f32(win.GET_Y_LPARAM(lparam))
			if wparam & win.MK_LBUTTON == 0 {
				return 0
			}
			event_push(window, Mouse_Event{window.mouse_x, window.mouse_y, .Left, .Move, key_mods()})
			return 0
		}
		case win.WM_MOUSEWHEEL:
		{
			if window == nil || window.ime_composing {
				return 0
			}
			d := f32(win.GET_WHEEL_DELTA_WPARAM(wparam)) / f32(win.WHEEL_DELTA)
			event_push(window, Scroll_Event{d, key_mods()})
			return 0
		}
		case win.WM_SIZE:
		{
			if window != nil {
				window.width = i32(win.LOWORD(lparam))
				window.height = i32(win.LOWORD(lparam))
				window.needs_redraw = true
			}
			return 0
		}
		case win.WM_SETCURSOR:
		{
			if window != nil && win.LOWORD(lparam) == win.HTCLIENT {
				id := win.IDC_ARROW
				if window.cursor == .Size_WE {
					id = win.IDC_SIZEWE
				}
				win.SetCursor(win.LoadCursorA(nil, id))
				return 1
			}
			return win.DefWindowProcW(hwnd, msg, wparam, lparam)
		}
	}

	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

window_create :: proc(w: ^Window, width, height: i32, title: string) -> bool {
	g_ctx = context

	instance := win.HINSTANCE(win.GetModuleHandleW(nil))

	icon := transmute(win.LPCWSTR)uintptr(1)
	wc := win.WNDCLASSEXW {
		cbSize = size_of(win.WNDCLASSEXW),
		style = win.CS_HREDRAW | win.CS_VREDRAW | win.CS_OWNDC | win.CS_DBLCLKS,
		lpfnWndProc = window_proc,
		hInstance = instance,
		hIcon = win.HICON(win.LoadImageW(instance, icon, win.IMAGE_ICON, 0, 0, win.LR_DEFAULTSIZE)),
		hCursor = win.LoadCursorA(nil, win.IDC_ARROW),
		lpszClassName = win.L(CLASS_NAME),
		hIconSm = win.HICON(win.LoadImageW(instance, icon, win.IMAGE_ICON, 256, 256, 0)),
	}

	if win.RegisterClassExW(&wc) == 0 {
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
	win.ShowWindow(w.hwnd, win.SW_SHOWMAXIMIZED)
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

window_set_cursor :: proc(w: ^Window, c: Cursor) {
	if w.cursor == c {
		return
	}
	w.cursor = c
	id := win.IDC_ARROW
	if c == .Size_WE {
		id = win.IDC_SIZEWE
	}
	win.SetCursor(win.LoadCursorA(nil, id))
}

console_attach :: proc() {
    if !win.AttachConsole(ATTACH_PARENT_PROCESS) {
        return
    }

	sa := win.SECURITY_ATTRIBUTES{
		nLength = size_of(win.SECURITY_ATTRIBUTES),
		bInheritHandle = true
	}
    
    h := win.CreateFileW(
        win.L("CONOUT$"),
        win.GENERIC_READ | win.GENERIC_WRITE,
        win.FILE_SHARE_READ | win.FILE_SHARE_WRITE,
        &sa,
        win.OPEN_EXISTING,
        0,
        nil
    )
    
    if h == win.INVALID_HANDLE_VALUE { return }

	mode: win.DWORD
	if win.GetConsoleMode(h, &mode) {
		mode |= win.ENABLE_PROCESSED_OUTPUT | win.ENABLE_WRAP_AT_EOL_OUTPUT | win.ENABLE_VIRTUAL_TERMINAL_PROCESSING
		mode &= ~win.DISABLE_NEWLINE_AUTO_RETURN
		win.SetConsoleMode(h, mode)
	}
    
    SetStdHandle(win.STD_OUTPUT_HANDLE, h)
	SetStdHandle(win.STD_ERROR_HANDLE, h)
    
    Std :: struct {
        file: os.File,
        fd: rawptr
    }
    if os.stdout != nil && os.stdout.impl != nil {
        (^Std)(os.stdout.impl).fd = rawptr(h)
    }
    if os.stderr != nil && os.stderr.impl != nil {
        (^Std)(os.stderr.impl).fd = rawptr(h)
    }
}

process_run_attached :: proc(command_line, working_dir: string) -> (exit_code: u32, ok: bool) {
	cl := win.utf8_to_utf16(command_line, context.allocator)
	if len(cl) == 0 { return }
	defer delete(cl)
	dir16: []u16
	defer if len(dir16) > 0 {
		delete(dir16)
	}
	dirw: win.wstring
	if len(working_dir) > 0 {
		dir16 = win.utf8_to_utf16(working_dir, context.allocator)
		if len(dir16) == 0 {
			return
		}
		dirw = win.wstring(raw_data(dir16))
	}
	si: win.STARTUPINFOW
	si.cb = size_of(si)
	pi: win.PROCESS_INFORMATION
	if !win.CreateProcessW(nil, win.wstring(raw_data(cl)), nil, nil, true, 0, nil, dirw, &si, &pi) {
		return
	}
	win.CloseHandle(pi.hThread)
	win.WaitForSingleObject(pi.hProcess, win.INFINITE)
	code: win.DWORD
	win.GetExitCodeProcess(pi.hProcess, &code)
	win.CloseHandle(pi.hProcess)
	return u32(code), true
}