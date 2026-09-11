format PE GUI 4.0                           ; Build a 32-bit Windows GUI Portable Executable
entry start                                 ; Program entry point

include 'win32a.inc'                        ; FASM Win32 API macros, constants, and structures

section '.data' data readable writeable     ; Read/write data section

    ; -------------------------------------------------------------------------
    ; Core Windows structures
    ; -------------------------------------------------------------------------
    wc              WNDCLASS                ; Window-class structure used to register the main window
    msg             MSG                     ; Windows message structure used by the message loop

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
    btnExitText     db 'Exit',0              ; Text displayed on the Exit button

    ; -------------------------------------------------------------------------
    ; File name and message strings
    ; -------------------------------------------------------------------------
    fileName        db 'password.txt',0       ; Password file read only when Login is attempted
    msgWrongPass    db 'Invalid password! Please enter the correct password.',0 ; Wrong-password message
    msgMustLogout   db 'Please logout before exiting the application!',0        ; Exit-block warning
    msgErrTitle     db 'Error',0              ; MessageBox title used for errors
    msgWarnTitle    db 'Warning',0            ; MessageBox title used for warnings
    msgFileError    db 'Failed to open password.txt!',0 ; Message shown if password.txt cannot be opened

    ; -------------------------------------------------------------------------
    ; Standard Windows control-class names
    ; -------------------------------------------------------------------------
    editClass       db 'EDIT',0               ; Standard Win32 EDIT control class
    buttonClass     db 'BUTTON',0             ; Standard Win32 BUTTON control class

    ; -------------------------------------------------------------------------
    ; Session state
    ; -------------------------------------------------------------------------
    isLoggedIn      dd 0                      ; 0 = logged out, 1 = logged in

    ; -------------------------------------------------------------------------
    ; Handles of the main window and child controls
    ; -------------------------------------------------------------------------
    hwndMain        dd ?                      ; Handle of the main application window
    hwndInput       dd ?                      ; Handle of the message-input EDIT control
    hwndHistory     dd ?                      ; Handle of the message-history EDIT control
    hwndBtnLogin    dd ?                      ; Handle of the Login/Logout button
    hwndBtnSend     dd ?                      ; Handle of the Send button
    hwndBtnExit     dd ?                      ; Handle of the Exit button

    ; -------------------------------------------------------------------------
    ; Data buffers
    ; -------------------------------------------------------------------------
    passFileBuffer  db 16 dup(0)              ; Buffer receiving the password read from password.txt
    passInputBuffer db 16 dup(0)              ; Buffer receiving the password typed by the user
    msgBuffer       db 1024 dup(0)            ; Buffer receiving the text typed in the input field
    formatBuffer    db 1100 dup(0)            ; Buffer used to append CR/LF to the outgoing message

    msgTemplate     db '%s',13,10,0           ; Message format: text followed by CR/LF

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

    invoke  CreateWindowEx, 0, className, windowTitle,\ ; Create the main application window
            WS_OVERLAPPED or WS_CAPTION or WS_SYSMENU or WS_MINIMIZEBOX,\ ; Use a simple non-resizable window style
            CW_USEDEFAULT, CW_USEDEFAULT, 620, 420, 0, 0, [wc.hInstance], 0 ; Position, size, parent, menu, instance
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
            WS_CHILD or WS_VISIBLE or ES_MULTILINE or ES_AUTOVSCROLL or WS_VSCROLL or ES_READONLY,\ ; Multiline scrolling history
            10, 10, 430, 250, [hwnd], 101, [wc.hInstance], 0 ; Position, size, parent, control ID, instance
    mov     [hwndHistory], eax                  ; Save the history EDIT-control handle

    invoke  CreateWindowEx, WS_EX_CLIENTEDGE, editClass, 0,\ ; Create the message-input area
            WS_CHILD or WS_VISIBLE or ES_MULTILINE or ES_AUTOVSCROLL or WS_VSCROLL or WS_DISABLED,\ ; Disabled until Login succeeds
            10, 270, 430, 100, [hwnd], 102, [wc.hInstance], 0 ; Position, size, parent, control ID, instance
    mov     [hwndInput], eax                    ; Save the input EDIT-control handle

    invoke  CreateWindowEx, 0, buttonClass, btnLoginText,\ ; Create the Login/Logout button
            WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,\      ; Standard visible push button
            460, 10, 130, 35, [hwnd], 201, [wc.hInstance], 0 ; Position, size, parent, control ID, instance
    mov     [hwndBtnLogin], eax                 ; Save the Login/Logout button handle

    invoke  CreateWindowEx, 0, buttonClass, btnSendText,\ ; Create the Send button
            WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON or WS_DISABLED,\ ; Disabled until Login succeeds
            460, 270, 130, 35, [hwnd], 202, [wc.hInstance], 0 ; Position, size, parent, control ID, instance
    mov     [hwndBtnSend], eax                  ; Save the Send button handle

    invoke  CreateWindowEx, 0, buttonClass, btnExitText,\ ; Create the Exit button
            WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON,\      ; Standard visible push button
            460, 335, 130, 35, [hwnd], 203, [wc.hInstance], 0 ; Position, size, parent, control ID, instance
    mov     [hwndBtnExit], eax                  ; Save the Exit button handle

    xor     eax, eax                            ; Return 0 from WM_CREATE processing
    jmp     .finish                             ; Finish processing this message

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
    cmp     eax, 203                            ; Was the Exit button pressed?
    je      .on_exit                            ; If yes, request WM_CLOSE
    jmp     .finish_zero                        ; Ignore other command IDs

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
    jmp     .finish_zero                        ; Finish command processing

.do_logout:
    mov     [isLoggedIn], 0                     ; Mark the session as logged out
    invoke  SetWindowText, [hwndBtnLogin], btnLoginText ; Restore the Login button caption
    invoke  EnableWindow, [hwndInput], FALSE    ; Disable message input after Logout
    invoke  EnableWindow, [hwndBtnSend], FALSE  ; Disable Send after Logout
    jmp     .finish_zero                        ; Keep the existing history visible in memory

; -----------------------------------------------------------------------------
; Send button handler
; -----------------------------------------------------------------------------
.on_send:
    invoke  GetWindowText, [hwndInput], msgBuffer, 1024 ; Copy the current input text into msgBuffer
    cmp     eax, 0                              ; Was the input field empty?
    je      .finish_zero                        ; If yes, do not append an empty message

    cinvoke wsprintf, formatBuffer, msgTemplate, msgBuffer ; Add CR/LF after the typed message

    invoke  GetWindowTextLength, [hwndHistory]  ; Get the number of characters already stored in history
    invoke  SendMessage, [hwndHistory], EM_SETSEL, eax, eax ; Move the insertion point to the very end
    invoke  SendMessage, [hwndHistory], EM_REPLACESEL, FALSE, formatBuffer ; Append the new message without replacing old text

    invoke  SetWindowText, [hwndInput], 0       ; Clear the input field after a successful Send
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
; IMPORTANT: password.txt is opened here, not at application startup.
; Therefore each Login attempt reads the current file contents again.
; -----------------------------------------------------------------------------
.check_password:
    invoke  CreateFile, fileName, GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0 ; Open password.txt for reading only
    cmp     eax, INVALID_HANDLE_VALUE           ; Did CreateFile fail?
    je      .file_error                         ; If yes, report the file error and cancel Login

    mov     ebx, eax                            ; Keep the password-file handle in EBX

    invoke  RtlZeroMemory, passFileBuffer, 16   ; Clear the password-file buffer before reading new data

    lea     ecx, [msgBuffer]                    ; Use the first DWORD of msgBuffer as temporary bytes-read storage
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
            user32,   'USER32.DLL'               ; Import GUI and window-management functions from USER32.DLL

    import kernel32,\                            ; Begin KERNEL32 function imports
           GetModuleHandle, 'GetModuleHandleA',\ ; Get the current executable module handle
           CreateFile,      'CreateFileA',\      ; Open password.txt for reading
           ReadFile,        'ReadFile',\         ; Read the current password bytes from disk
           CloseHandle,     'CloseHandle',\      ; Close the file handle after reading
           RtlZeroMemory,   'RtlZeroMemory',\    ; Clear the password-file buffer before each Login attempt
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
           SetWindowText,      'SetWindowTextA',\ ; Change button captions and clear the input field
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
           DestroyWindow,      'DestroyWindow',\  ; Destroy the main window after Logout permits exit
           wsprintf,           'wsprintfA'        ; Format a sent message before appending it to history
