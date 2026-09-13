format PE GUI 4.0                           ; Build a 32-bit Windows GUI Portable Executable
entry start                                 ; Program entry point

include 'win32a.inc'                        ; FASM Win32 API macros, constants, and structures

section '.data' data readable writeable     ; Read/write data section

    ; -------------------------------------------------------------------------
    ; Core Windows structures
    ; -------------------------------------------------------------------------
    wc              WNDCLASS                ; Window-class structure used to register the main window
    msg             MSG                     ; Windows message structure used by the message loop
    stTime          SYSTEMTIME              ; System time structure for time-stamping
    rcClient        RECT                    ; Rectangle structure to retrieve accurate client area

    ; -------------------------------------------------------------------------
    ; Window class name and main application title
    ; -------------------------------------------------------------------------
    className       db 'FasmAppClass',0      ; Internal Win32 window-class name
    windowTitle     db 'FASM Service Terminal',0 ; Title shown in the main window caption

    ; -------------------------------------------------------------------------
    ; Button labels and user-interface strings
    ; -------------------------------------------------------------------------
    btnLoginText    db 'Login',0             ; Text displayed on the Login button
    btnLogoutText   db 'Logout',0            ; Text displayed on the same button after authentication
    btnSendText     db 'Send',0              ; Text displayed on the Send button
    btnClearText    db 'Clear',0             ; Text displayed on the Clear button
    btnSaveText     db 'Save',0              ; Text displayed on the Save button
    btnZoomInText   db 'Zoom +',0            ; Text displayed on the Zoom + button
    btnZoomOutText  db 'Zoom -',0            ; Text displayed on the Zoom - button
    btnExitText     db 'Exit',0              ; Text displayed on the Exit button
    fontName        db 'Courier New',0       ; Monospaced font name for history window

    ; -------------------------------------------------------------------------
    ; File name, save templates, and message strings
    ; -------------------------------------------------------------------------
    fileName        db 'password.txt',0       ; Password file read only when Login is attempted
    saveFileTemplate db 'window_%02d-%02d-%02d_%02d-%02d-%02d.txt',0 ; Template for save filename
    msgWrongPass    db 'Invalid password! Please enter the correct password.',0 ; Wrong-password message
    msgMustLogout   db 'Please logout before exiting the application!',0        ; Exit-block warning
    msgSaveOk       db 'History successfully saved to file!',0                  ; Success save notification
    msgSaveErr      db 'Failed to save history file!',0                        ; Save error notification
    msgErrTitle     db 'Error',0              ; MessageBox title used for errors
    msgWarnTitle    db 'Warning',0            ; MessageBox title used for warnings
    msgInfoTitle    db 'Information',0        ; MessageBox title used for info
    msgFileError    db 'Failed to open password.txt!',0 ; Message shown if password.txt cannot be opened
    crlfStr         db 13,10,0                ; CR/LF string to ensure forced newline

    ; -------------------------------------------------------------------------
    ; Standard Windows control-class names
    ; -------------------------------------------------------------------------
    editClass       db 'EDIT',0               ; Standard Win32 EDIT control class
    buttonClass     db 'BUTTON',0             ; Standard Win32 BUTTON control class

    ; -------------------------------------------------------------------------
    ; Session state and Font scaling
    ; -------------------------------------------------------------------------
    isLoggedIn      dd 0                      ; 0 = logged out, 1 = logged in
    currentFontSize dd 16                     ; Initial font height in pixels
    hHistoryFont    dd 0                      ; Handle to current custom font

    ; -------------------------------------------------------------------------
    ; Layout calculation variables
    ; -------------------------------------------------------------------------
    cliWidth        dd ?                      ; Client area width
    cliHeight       dd ?                      ; Client area height
    editWidth       dd ?                      ; Width allocated for EDIT controls
    btnX            dd ?                      ; X position for right-side buttons
    historyH        dd ?                      ; Height of the history EDIT control
    inputY          dd ?                      ; Y position of the input EDIT control

    ; -------------------------------------------------------------------------
    ; Handles of the main window and child controls
    ; -------------------------------------------------------------------------
    hwndMain        dd ?                      ; Handle of the main application window
    hwndInput       dd ?                      ; Handle of the message-input EDIT control
    hwndHistory     dd ?                      ; Handle of the message-history EDIT control
    hwndBtnLogin    dd ?                      ; Handle of the Login/Logout button
    hwndBtnSend     dd ?                      ; Handle of the Send button
    hwndBtnClear    dd ?                      ; Handle of the Clear button
    hwndBtnSave     dd ?                      ; Handle of the Save button
    hwndBtnZoomIn   dd ?                      ; Handle of the Zoom In button
    hwndBtnZoomOut  dd ?                      ; Handle of the Zoom Out button
    hwndBtnExit     dd ?                      ; Handle of the Exit button

    ; -------------------------------------------------------------------------
    ; Data buffers
    ; -------------------------------------------------------------------------
    passFileBuffer  db 16 dup(0)              ; Buffer receiving the password read from password.txt
    passInputBuffer db 16 dup(0)              ; Buffer receiving the password typed by the user
    msgBuffer       db 1024 dup(0)            ; Buffer receiving the text typed in the input field
    formatBuffer    db 1200 dup(0)            ; Buffer used to format timestamp and outgoing message
    saveFileNameBuf db 128 dup(0)             ; Buffer for dynamically created file name

    ; Format: <YY-MM-DD> <HH-MM-SS> - message
    msgTemplate     db '<%02d-%02d-%02d> <%02d-%02d-%02d> - %s',0

section '.code' code readable executable      ; Executable code section

; =============================================================================
; Application entry point
; =============================================================================
start:
    invoke  GetModuleHandle, 0                 ; Get the current process module handle
    mov     [wc.hInstance], eax                ; Store the module handle in the WNDCLASS structure

    mov     [wc.style], CS_HREDRAW or CS_VREDRAW ; Redraw window after horizontal/vertical size changes
    mov     [wc.lpfnWndProc], WndProc          ; Set the main window procedure callback
    mov     [wc.cbClsExtra], 0                 ; No extra bytes allocated for the window class
    mov     [wc.cbWndExtra], 0                 ; No extra bytes allocated for each window instance
    mov     [wc.hIcon], 0                      ; Use no custom application icon
    invoke  LoadCursor, 0, IDC_ARROW           ; Load the standard Windows arrow cursor
    mov     [wc.hCursor], eax                  ; Save the cursor handle in the WNDCLASS structure
    invoke  GetSysColorBrush, COLOR_BTNFACE    ; Obtain the standard button-face background brush
    mov     [wc.hbrBackground], eax            ; Use that brush as the main window background
    mov     [wc.lpszMenuName], 0               ; No menu resource is attached to the window class
    mov     [wc.lpszClassName], className      ; Point to the internal window-class name
    invoke  RegisterClass, wc                  ; Register the main window class with Windows

    ; WS_OVERLAPPEDWINDOW allows resizing and maximizing
    invoke  CreateWindowEx, 0, className, windowTitle,\
            WS_OVERLAPPEDWINDOW,\
            CW_USEDEFAULT, CW_USEDEFAULT, 640, 520, 0, 0, [wc.hInstance], 0
    mov     [hwndMain], eax                    ; Save the handle of the newly created main window

    invoke  ShowWindow, [hwndMain], SW_SHOW    ; Make the main window visible
    invoke  UpdateWindow, [hwndMain]           ; Force the first repaint immediately

; -----------------------------------------------------------------------------
; Standard Win32 message loop
; -----------------------------------------------------------------------------
msg_loop:
    invoke  GetMessage, msg, 0, 0, 0           ; Wait for the next message from the thread message queue
    cmp     eax, 0                             ; GetMessage returns 0 after WM_QUIT
    je      end_loop                           ; Leave the loop when the application is terminating
    invoke  TranslateMessage, msg              ; Translate keyboard messages when appropriate
    invoke  DispatchMessage, msg               ; Dispatch the message to the target window procedure
    jmp     msg_loop                           ; Continue processing messages

end_loop:
    invoke  ExitProcess, [msg.wParam]           ; Terminate the process using the WM_QUIT return code

; =============================================================================
; Main window procedure
; =============================================================================
proc WndProc hwnd, uMsg, wParam, lParam
    push    ebx esi edi                         ; Preserve non-volatile registers used by this procedure

    cmp     [uMsg], WM_CREATE                   ; Is this the initial window-creation message?
    je      .wm_create                          ; If yes, create the child controls
    cmp     [uMsg], WM_SIZE                     ; Window resized or maximized?
    je      .wm_size                            ; Recalculate layout dynamically
    cmp     [uMsg], WM_COMMAND                  ; Is this a command from a button/control?
    je      .wm_command                         ; If yes, process the command
    cmp     [uMsg], WM_CLOSE                    ; Is the user trying to close the window?
    je      .wm_close                           ; If yes, enforce the Logout rule
    cmp     [uMsg], WM_DESTROY                  ; Has the window already been destroyed?
    je      .wm_destroy                         ; If yes, finish the application

    invoke  DefWindowProc, [hwnd], [uMsg], [wParam], [lParam] ; Let Windows process all unhandled messages
    jmp     .finish                             ; Return the value produced by DefWindowProc

; -----------------------------------------------------------------------------
; WM_CREATE: create all child controls
; -----------------------------------------------------------------------------
.wm_create:
    invoke  CreateWindowEx, WS_EX_CLIENTEDGE, editClass, 0,\ ; Create the read-only message-history area
            WS_CHILD or WS_VISIBLE or ES_MULTILINE or ES_AUTOVSCROLL or WS_VSCROLL or ES_READONLY,\
            10, 10, 430, 250, [hwnd], 101, [wc.hInstance], 0
    mov     [hwndHistory], eax                  ; Save the history EDIT-control handle

    invoke  CreateWindowEx, WS_EX_CLIENTEDGE, editClass, 0,\ ; Create the message-input area
            WS_CHILD or WS_VISIBLE or ES_MULTILINE or ES_AUTOVSCROLL or WS_VSCROLL or WS_DISABLED,\
            10, 270, 430, 100, [hwnd], 102, [wc.hInstance], 0
    mov     [hwndInput], eax                    ; Save the input EDIT-control handle

    invoke  CreateWindowEx, 0, buttonClass, btnLoginText,\ ; Create the Login/Logout button
            WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,\
            460, 10, 130, 32, [hwnd], 201, [wc.hInstance], 0
    mov     [hwndBtnLogin], eax                 ; Save the Login/Logout button handle

    invoke  CreateWindowEx, 0, buttonClass, btnSendText,\ ; Create the Send button
            WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON or WS_DISABLED,\
            460, 50, 130, 32, [hwnd], 202, [wc.hInstance], 0
    mov     [hwndBtnSend], eax                  ; Save the Send button handle

    invoke  CreateWindowEx, 0, buttonClass, btnClearText,\ ; Create the Clear button
            WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON or WS_DISABLED,\
            460, 90, 130, 32, [hwnd], 204, [wc.hInstance], 0
    mov     [hwndBtnClear], eax                 ; Save the Clear button handle

    invoke  CreateWindowEx, 0, buttonClass, btnSaveText,\ ; Create the Save button
            WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON or WS_DISABLED,\
            460, 130, 130, 32, [hwnd], 207, [wc.hInstance], 0
    mov     [hwndBtnSave], eax                  ; Save the Save button handle

    invoke  CreateWindowEx, 0, buttonClass, btnZoomInText,\ ; Create the Zoom In button
            WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,\
            460, 170, 130, 32, [hwnd], 205, [wc.hInstance], 0
    mov     [hwndBtnZoomIn], eax                ; Save the Zoom In button handle

    invoke  CreateWindowEx, 0, buttonClass, btnZoomOutText,\ ; Create the Zoom Out button
            WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,\
            460, 210, 130, 32, [hwnd], 206, [wc.hInstance], 0
    mov     [hwndBtnZoomOut], eax               ; Save the Zoom Out button handle

    invoke  CreateWindowEx, 0, buttonClass, btnExitText,\ ; Create the Exit button
            WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,\
            460, 250, 130, 32, [hwnd], 203, [wc.hInstance], 0
    mov     [hwndBtnExit], eax                  ; Save the Exit button handle

    call    UpdateHistoryFont                   ; Apply default font size to history window

    xor     eax, eax                            ; Return 0 from WM_CREATE processing
    jmp     .finish                             ; Finish processing this message

; -----------------------------------------------------------------------------
; WM_SIZE: Layout calculation fixing buttons and scaling edit windows
; -----------------------------------------------------------------------------
.wm_size:
    invoke  GetClientRect, [hwnd], rcClient    ; Obtain current accurate client area coordinates
    
    mov     eax, [rcClient.right]
    sub     eax, [rcClient.left]
    mov     [cliWidth], eax                     ; Store client width
    
    mov     eax, [rcClient.bottom]
    sub     eax, [rcClient.top]
    mov     [cliHeight], eax                    ; Store client height

    cmp     [cliWidth], 300
    jb      .finish_zero                        ; Ignore if window size is too small
    cmp     [cliHeight], 300
    jb      .finish_zero

    ; Calculate Edit controls width
    mov     eax, [cliWidth]
    sub     eax, 160                            ; 10px left margin + 140px buttons + 10px gap
    mov     [editWidth], eax
    
    ; Right buttons X position (pinned to right margin)
    mov     eax, [cliWidth]
    sub     eax, 140
    mov     [btnX], eax

    ; History Edit height = Total Height - 130px
    mov     eax, [cliHeight]
    sub     eax, 130
    mov     [historyH], eax

    ; Input Edit Y position
    mov     eax, [historyH]
    add     eax, 20
    mov     [inputY], eax

    ; Apply new position and size to text windows
    invoke  MoveWindow, [hwndHistory], 10, 10, [editWidth], [historyH], TRUE
    invoke  MoveWindow, [hwndInput], 10, [inputY], [editWidth], 100, TRUE

    ; Position buttons strictly from top to bottom on the right panel
    invoke  MoveWindow, [hwndBtnLogin],   [btnX], 10,  130, 32, TRUE
    invoke  MoveWindow, [hwndBtnSend],    [btnX], 50,  130, 32, TRUE
    invoke  MoveWindow, [hwndBtnClear],   [btnX], 90,  130, 32, TRUE
    invoke  MoveWindow, [hwndBtnSave],    [btnX], 130, 130, 32, TRUE
    invoke  MoveWindow, [hwndBtnZoomIn],  [btnX], 170, 130, 32, TRUE
    invoke  MoveWindow, [hwndBtnZoomOut], [btnX], 210, 130, 32, TRUE
    invoke  MoveWindow, [hwndBtnExit],    [btnX], 250, 130, 32, TRUE

    jmp     .finish_zero

; -----------------------------------------------------------------------------
; WM_COMMAND: route button commands by their control ID
; -----------------------------------------------------------------------------
.wm_command:
    mov     eax, [wParam]                       ; Copy wParam locally
    and     eax, 0FFFFh                         ; Keep only the low word containing the control ID

    cmp     eax, 201                            ; Was the Login/Logout button pressed?
    je      .on_login_logout                    ; If yes, process Login or Logout
    cmp     eax, 202                            ; Was the Send button pressed?
    je      .on_send                            ; If yes, append the typed text to the history
    cmp     eax, 204                            ; Was the Clear button pressed?
    je      .on_clear                           ; If yes, clear the history EDIT control
    cmp     eax, 207                            ; Was the Save button pressed?
    je      .on_save
    cmp     eax, 205                            ; Was the Zoom + button pressed?
    je      .on_zoom_in
    cmp     eax, 206                            ; Was the Zoom - button pressed?
    je      .on_zoom_out
    cmp     eax, 203                            ; Was the Exit button pressed?
    je      .on_exit                            ; If yes, request WM_CLOSE
    jmp     .finish_zero                        ; Ignore other command IDs

; -----------------------------------------------------------------------------
; Save button handler (saves history to window_YY-MM-DD_HH-MM-SS.txt)
; -----------------------------------------------------------------------------
.on_save:
    invoke  GetWindowTextLength, [hwndHistory]  ; Check length of history text
    cmp     eax, 0
    je      .finish_zero                        ; Do nothing if history is empty

    mov     esi, eax                            ; ESI = length of text in history
    add     eax, 1
    invoke  GlobalAlloc, GPTR, eax              ; Allocate memory buffer for text export
    cmp     eax, 0
    je      .finish_zero
    mov     edi, eax                            ; EDI = allocated memory pointer

    invoke  GetWindowText, [hwndHistory], edi, esi ; Copy history text into buffer

    invoke  GetLocalTime, stTime                ; Get system time for filename

    ; Format file name: window_YY-MM-DD_HH-MM-SS.txt
    movzx   eax, [stTime.wYear]
    mov     ecx, 100
    xor     edx, edx
    div     ecx                                 ; EDX = Year mod 100

    movzx   eax, [stTime.wSecond]
    push    eax                                 ; SS
    movzx   eax, [stTime.wMinute]
    push    eax                                 ; MM
    movzx   eax, [stTime.wHour]
    push    eax                                 ; HH
    movzx   eax, [stTime.wDay]
    push    eax                                 ; DD
    movzx   eax, [stTime.wMonth]
    push    eax                                 ; MM
    push    edx                                 ; YY
    push    saveFileTemplate
    push    saveFileNameBuf
    call    [wsprintf]
    add     esp, 32

    ; Create new file in current program directory
    invoke  CreateFile, saveFileNameBuf, GENERIC_WRITE, 0, 0, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0
    cmp     eax, INVALID_HANDLE_VALUE
    je      .save_failed

    mov     ebx, eax                            ; EBX = file handle
    lea     ecx, [formatBuffer]                 ; Temp bytes written pointer
    invoke  WriteFile, ebx, edi, esi, ecx, 0    ; Write history text to disk
    invoke  CloseHandle, ebx

    invoke  MessageBox, [hwnd], msgSaveOk, msgInfoTitle, MB_OK or MB_ICONINFORMATION
    jmp     .free_mem

.save_failed:
    invoke  MessageBox, [hwnd], msgSaveErr, msgErrTitle, MB_OK or MB_ICONERROR

.free_mem:
    invoke  GlobalFree, edi                     ; Free allocated buffer
    jmp     .finish_zero

; -----------------------------------------------------------------------------
; Zoom + button handler (Increases font size up to 36px)
; -----------------------------------------------------------------------------
.on_zoom_in:
    cmp     [currentFontSize], 36
    jge     .finish_zero                        ; Maximum size limit reached
    add     [currentFontSize], 4                ; Increase font height by 4px
    call    UpdateHistoryFont
    jmp     .finish_zero

; -----------------------------------------------------------------------------
; Zoom - button handler (Decreases font size down to 12px)
; -----------------------------------------------------------------------------
.on_zoom_out:
    cmp     [currentFontSize], 12
    jle     .finish_zero                        ; Minimum size limit reached
    sub     [currentFontSize], 4                ; Decrease font height by 4px
    call    UpdateHistoryFont
    jmp     .finish_zero

; -----------------------------------------------------------------------------
; Login / Logout button handler
; -----------------------------------------------------------------------------
.on_login_logout:
    cmp     [isLoggedIn], 1                     ; Is a session already active?
    je      .do_logout                          ; If yes, the same button now performs Logout

.do_login:
    invoke  DialogBoxParam, [wc.hInstance], 1, [hwnd], LoginDlgProc, 0 ; Open the modal password dialog
    cmp     eax, 1                              ; Did the dialog report successful authentication?
    jne     .finish_zero                        ; If not, leave the application in logged-out state

    mov     [isLoggedIn], 1                     ; Mark the session as authenticated
    invoke  SetWindowText, [hwndBtnLogin], btnLogoutText ; Change button caption from Login to Logout
    invoke  EnableWindow, [hwndInput], TRUE     ; Enable message input after successful Login
    invoke  EnableWindow, [hwndBtnSend], TRUE   ; Enable the Send button after successful Login
    invoke  EnableWindow, [hwndBtnClear], TRUE  ; Enable the Clear button after successful Login
    invoke  EnableWindow, [hwndBtnSave], TRUE   ; Enable the Save button after successful Login
    jmp     .finish_zero                        ; Finish command processing

.do_logout:
    mov     [isLoggedIn], 0                     ; Mark the session as logged out
    invoke  SetWindowText, [hwndBtnLogin], btnLoginText ; Restore the Login button caption
    invoke  EnableWindow, [hwndInput], FALSE    ; Disable message input after Logout
    invoke  EnableWindow, [hwndBtnSend], FALSE  ; Disable Send after Logout
    invoke  EnableWindow, [hwndBtnClear], FALSE ; Disable Clear after Logout
    invoke  EnableWindow, [hwndBtnSave], FALSE  ; Disable Save after Logout
    jmp     .finish_zero                        ; Keep the existing history visible in memory

; -----------------------------------------------------------------------------
; Send button handler (formats date and time as <YY-MM-DD> <HH-MM-SS>)
; -----------------------------------------------------------------------------
.on_send:
    invoke  GetWindowText, [hwndInput], msgBuffer, 1024 ; Copy the current input text into msgBuffer
    cmp     eax, 0                              ; Was the input field empty?
    je      .finish_zero                        ; If yes, do not append an empty message

    invoke  GetLocalTime, stTime                ; Get current system local date and time

    ; Extract date/time fields from SYSTEMTIME
    movzx   eax, [stTime.wYear]
    mov     ecx, 100
    xor     edx, edx
    div     ecx                                 ; EDX = Year mod 100

    push    msgBuffer                           ; Pointer to message text (%s)
    movzx   eax, [stTime.wSecond]
    push    eax                                 ; SS
    movzx   eax, [stTime.wMinute]
    push    eax                                 ; MM
    movzx   eax, [stTime.wHour]
    push    eax                                 ; HH
    movzx   eax, [stTime.wDay]
    push    eax                                 ; DD
    movzx   eax, [stTime.wMonth]
    push    eax                                 ; MM
    push    edx                                 ; YY
    push    msgTemplate                         ; Format: <%02d-%02d-%02d> <%02d-%02d-%02d> - %s
    push    formatBuffer                        ; Destination buffer
    call    [wsprintf]
    add     esp, 36                             ; Clean up 9 arguments pushed on stack

    invoke  GetWindowTextLength, [hwndHistory]  ; Get length of text in history
    cmp     eax, 0                              ; Is history window currently empty?
    je      .append_text                        ; If empty, append message directly

    ; If history is not empty, force a newline first
    invoke  SendMessage, [hwndHistory], EM_SETSEL, eax, eax
    invoke  SendMessage, [hwndHistory], EM_REPLACESEL, FALSE, crlfStr

.append_text:
    invoke  GetWindowTextLength, [hwndHistory]  ; Get new caret position at the very end
    invoke  SendMessage, [hwndHistory], EM_SETSEL, eax, eax ; Move cursor to end
    invoke  SendMessage, [hwndHistory], EM_REPLACESEL, FALSE, formatBuffer ; Append formatted message
    invoke  SendMessage, [hwndHistory], EM_SCROLLCARET, 0, 0 ; Scroll down automatically

    invoke  SetWindowText, [hwndInput], 0       ; Clear the input field after a successful Send
    jmp     .finish_zero                        ; Finish command processing

; -----------------------------------------------------------------------------
; Clear button handler
; -----------------------------------------------------------------------------
.on_clear:
    invoke  SetWindowText, [hwndHistory], 0     ; Clear the message-history EDIT control
    jmp     .finish_zero                        ; Finish command processing

; -----------------------------------------------------------------------------
; Exit button handler
; -----------------------------------------------------------------------------
.on_exit:
    invoke  SendMessage, [hwnd], WM_CLOSE, 0, 0 ; Route Exit through WM_CLOSE so the Logout rule is enforced
    jmp     .finish_zero                        ; Finish command processing

; -----------------------------------------------------------------------------
; WM_CLOSE: block application exit while the user is logged in
; -----------------------------------------------------------------------------
.wm_close:
    cmp     [isLoggedIn], 1                     ; Is a session still active?
    jne     .allow_close                        ; If not logged in, closing is allowed

    invoke  MessageBox, [hwnd], msgMustLogout, msgWarnTitle, MB_OK or MB_ICONWARNING ; Warn the user to Logout first
    xor     eax, eax                            ; Return 0 without destroying the window
    jmp     .finish                             ; Application remains open

.allow_close:
    cmp     [hHistoryFont], 0
    je      @f
    invoke  DeleteObject, [hHistoryFont]        ; Clean up font handle on exit
  @@:
    invoke  DestroyWindow, [hwnd]               ; Destroy the main window when Logout has already been completed
    xor     eax, eax                            ; Return 0 after handling WM_CLOSE
    jmp     .finish                             ; Finish message processing

; -----------------------------------------------------------------------------
; WM_DESTROY: terminate the message loop
; -----------------------------------------------------------------------------
.wm_destroy:
    invoke  PostQuitMessage, 0                  ; Post WM_QUIT to end the application's message loop
    xor     eax, eax                            ; Return 0 from WM_DESTROY handling
    jmp     .finish                             ; Finish message processing

.finish_zero:
    xor     eax, eax                            ; Standard handled-message return value = 0
.finish:
    pop     edi esi ebx                         ; Restore the preserved registers
    ret                                         ; Return to Windows
endp                                            ; End of WndProc

; =============================================================================
; Helper procedure: Creates and sets font for history EDIT control
; =============================================================================
proc UpdateHistoryFont
    push    ebx esi edi
    invoke  CreateFont, [currentFontSize], 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,\
            ANSI_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,\
            FIXED_PITCH or FF_MODERN, fontName
    cmp     eax, 0
    je      .exit_font

    mov     ebx, eax
    invoke  SendMessage, [hwndHistory], WM_SETFONT, ebx, TRUE

    cmp     [hHistoryFont], 0
    je      @f
    invoke  DeleteObject, [hHistoryFont]        ; Delete previous GDI font object
  @@:
    mov     [hHistoryFont], ebx

.exit_font:
    pop     edi esi ebx
    ret
endp

; =============================================================================
; Login dialog procedure
; =============================================================================
proc LoginDlgProc hwndDlg, uMsg, wParam, lParam
    push    ebx esi edi                         ; Preserve non-volatile registers used by this procedure

    cmp     [uMsg], WM_INITDIALOG               ; Is the password dialog being initialized?
    je      .init                               ; If yes, configure the password input field
    cmp     [uMsg], WM_COMMAND                  ; Did the user press a dialog button?
    je      .command                            ; If yes, process OK or Cancel
    jmp     .default                            ; Ignore all other dialog messages

; -----------------------------------------------------------------------------
; WM_INITDIALOG: configure password-entry rules
; -----------------------------------------------------------------------------
.init:
    invoke  GetDlgItem, [hwndDlg], 1001         ; Get the handle of the password EDIT control
    invoke  SendMessage, eax, EM_SETLIMITTEXT, 4, 0 ; Limit password entry to exactly four typed characters maximum
    mov     eax, TRUE                           ; Report that initialization was handled
    jmp     .finish                             ; Return from the dialog procedure

; -----------------------------------------------------------------------------
; WM_COMMAND: process OK and Cancel buttons
; -----------------------------------------------------------------------------
.command:
    mov     eax, [wParam]                       ; Copy wParam locally
    and     eax, 0FFFFh                         ; Keep only the low word containing the dialog command ID

    cmp     eax, IDOK                           ; Did the user press OK?
    je      .check_password                     ; If yes, read and verify password.txt now
    cmp     eax, IDCANCEL                       ; Did the user press Cancel?
    je      .cancel                             ; If yes, close the dialog with a failed-login result
    jmp     .default                            ; Ignore unrelated dialog commands

; -----------------------------------------------------------------------------
; Password verification
; -----------------------------------------------------------------------------
.check_password:
    invoke  CreateFile, fileName, GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0 ; Open password.txt
    cmp     eax, INVALID_HANDLE_VALUE           ; Did CreateFile fail?
    je      .file_error                         ; If yes, report the file error and cancel Login

    mov     ebx, eax                            ; Keep the password-file handle in EBX

    invoke  RtlZeroMemory, passFileBuffer, 16   ; Clear the password-file buffer before reading new data

    lea     ecx, [msgBuffer]                    ; Use temporary bytes-read storage
    invoke  ReadFile, ebx, passFileBuffer, 4, ecx, 0 ; Read exactly four bytes from password.txt
    invoke  CloseHandle, ebx                    ; Close the password file immediately after reading

    invoke  GetDlgItemText, [hwndDlg], 1001, passInputBuffer, 16 ; Copy the typed password into memory

    mov     esi, passFileBuffer                 ; ESI points to the four bytes read from password.txt
    mov     edi, passInputBuffer                ; EDI points to the four characters entered by the user
    mov     ecx, 4                              ; Compare exactly four bytes
    repe    cmpsb                               ; Compare the two buffers byte by byte while they are equal
    jne     .wrong_pass                         ; Any mismatch means authentication failed

    invoke  EndDialog, [hwndDlg], 1             ; Close the dialog and return success to the main window
    jmp     .finish_zero                        ; Finish processing the successful Login

.wrong_pass:
    invoke  MessageBox, [hwndDlg], msgWrongPass, msgErrTitle, MB_OK or MB_ICONERROR ; Inform the user that the password is invalid
    invoke  SetDlgItemText, [hwndDlg], 1001, 0  ; Clear the password input field for another attempt
    jmp     .finish_zero                        ; Keep the dialog open

.file_error:
    invoke  MessageBox, [hwndDlg], msgFileError, msgErrTitle, MB_OK or MB_ICONERROR ; Report that password.txt could not be opened
    invoke  EndDialog, [hwndDlg], 0             ; Close the Login dialog with failure status
    jmp     .finish_zero                        ; Finish file-error handling

.cancel:
    invoke  EndDialog, [hwndDlg], 0             ; Close the Login dialog with failure/cancel status
    jmp     .finish_zero                        ; Return to the main application window

.default:
    xor     eax, eax                            ; Return FALSE for unhandled dialog messages
    jmp     .finish                             ; Finish dialog processing

.finish_zero:
    mov     eax, TRUE                           ; Return TRUE for handled dialog messages
.finish:
    pop     edi esi ebx                         ; Restore the preserved registers
    ret                                         ; Return to the dialog manager
endp                                            ; End of LoginDlgProc

; =============================================================================
; Embedded resources: password dialog definition
; =============================================================================
section '.rsrc' resource data readable          ; Resource section containing the Login dialog template

    directory RT_DIALOG, dialogs                ; Declare a dialog-resource directory

    resource dialogs,\                          ; Begin dialog resource definitions
             1, LANG_ENGLISH+SUBLANG_DEFAULT, login_dialog ; Resource ID 1 uses the English default language

    dialog login_dialog, 'Login', -1, -1, 150, 60, WS_CAPTION or WS_SYSMENU or DS_CENTER ; Define the modal Login dialog
        dialogitem 'STATIC', 'Enter 4 digits:', -1, 10, 10, 130, 10, WS_VISIBLE ; Instruction label
        dialogitem 'EDIT', '', 1001, 10, 22, 130, 12, WS_VISIBLE or WS_BORDER or ES_PASSWORD or ES_NUMBER ; Masked numeric password input
        dialogitem 'BUTTON', 'OK', IDOK, 20, 40, 50, 14, WS_VISIBLE or BS_DEFPUSHBUTTON ; Default OK button
        dialogitem 'BUTTON', 'Cancel', IDCANCEL, 80, 40, 50, 14, WS_VISIBLE ; Cancel button
    enddialog                                    ; End of Login dialog definition

; =============================================================================
; Win32 API import table
; =============================================================================
section '.idata' import data readable writeable ; Import section containing DLL and function references

    library kernel32, 'KERNEL32.DLL',\           ; Import low-level process and file functions from KERNEL32.DLL
            user32,   'USER32.DLL',\             ; Import GUI and window-management functions from USER32.DLL
            gdi32,    'GDI32.DLL'                ; Import font management functions from GDI32.DLL

    import kernel32,\                            ; Begin KERNEL32 function imports
           GetModuleHandle, 'GetModuleHandleA',\ ; Get the current executable module handle
           CreateFile,      'CreateFileA',\      ; Open password.txt for reading / create export file
           ReadFile,        'ReadFile',\         ; Read the current password bytes from disk
           WriteFile,       'WriteFile',\        ; Write history text to disk file
           CloseHandle,     'CloseHandle',\      ; Close the file handle after reading/writing
           RtlZeroMemory,   'RtlZeroMemory',\    ; Clear the password-file buffer before each Login attempt
           GetLocalTime,    'GetLocalTime',\     ; Retrieve system time for timestamping messages
           GlobalAlloc,     'GlobalAlloc',\      ; Allocate dynamic memory buffer for history save
           GlobalFree,      'GlobalFree',\       ; Free dynamic memory buffer
           ExitProcess,     'ExitProcess'        ; Terminate the process after the message loop ends

    import user32,\                              ; Begin USER32 function imports
           RegisterClass,      'RegisterClassA',\ ; Register the application's window class
           CreateWindowEx,     'CreateWindowExA',\ ; Create the main window and all child controls
           ShowWindow,         'ShowWindow',\     ; Show the main application window
           UpdateWindow,       'UpdateWindow',\   ; Force immediate repainting
           GetMessage,         'GetMessageA',\    ; Retrieve messages from the thread message queue
           TranslateMessage,   'TranslateMessage',\ ; Translate keyboard messages
           DispatchMessage,    'DispatchMessageA',\ ; Dispatch messages to window procedures
           DefWindowProc,      'DefWindowProcA',\ ; Default handler for unprocessed window messages
           PostQuitMessage,    'PostQuitMessage',\ ; Post WM_QUIT to terminate the message loop
           SendMessage,        'SendMessageA',\   ; Send messages to EDIT controls and the main window
           GetWindowText,      'GetWindowTextA',\ ; Read text from the message-input control
           SetWindowText,      'SetWindowTextA',\ ; Change button captions and clear fields
           GetWindowTextLength,'GetWindowTextLengthA',\ ; Determine the current length of the message history
           EnableWindow,       'EnableWindow',\   ; Enable or disable controls according to Login state
           MessageBox,         'MessageBoxA',\    ; Display error and warning dialogs
           DialogBoxParam,     'DialogBoxParamA',\ ; Open the modal Login dialog
           EndDialog,          'EndDialog',\      ; Close the Login dialog and return a result
           GetDlgItem,         'GetDlgItem',\     ; Get a child control handle from the Login dialog
           GetDlgItemText,     'GetDlgItemTextA',\ ; Read the password typed into the dialog
           SetDlgItemText,     'SetDlgItemTextA',\ ; Clear the password field after a failed attempt
           LoadCursor,         'LoadCursorA',\    ; Load the standard Windows arrow cursor
           GetSysColorBrush,   'GetSysColorBrush',\ ; Use a standard system brush for the window background
           GetClientRect,      'GetClientRect',\  ; Retrieve precise client rect for WM_SIZE layout
           MoveWindow,         'MoveWindow',\     ; Dynamically move/resize controls on WM_SIZE
           DestroyWindow,      'DestroyWindow',\  ; Destroy the main window after Logout permits exit
           wsprintf,           'wsprintfA'        ; Format a sent message before appending it to history

    import gdi32,\                               ; Begin GDI32 function imports
           CreateFont,         'CreateFontA',\    ; Create custom sized font for scaling history text
           DeleteObject,       'DeleteObject'     ; Free GDI font resources