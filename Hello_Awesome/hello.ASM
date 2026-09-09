; Format de l'exécutable : Portable Executable pour GUI (Interface Graphique) 32-bit
format PE GUI 4.0
entry start

; Inclusion des définitions Win32 standard pour FASM
include 'win32a.inc'

; ============================================================================
; Section des données (variables, chaînes de caractères et structures)
; ============================================================================
section '.data' data readable writeable
    staticClass db 'STATIC', 0
    className   db 'AwesomeClass', 0    ; Nom de la classe de fenêtre
    titleName   db 'Attention', 0       ; Titre de la barre de fenêtre
    labelText   db 'Hello Awesome', 0   ; Texte à afficher dans l'étiquette
    
    wc          WNDCLASS                ; Structure de configuration de la classe
    msg         MSG                     ; Structure pour recevoir les messages Windows
    hWnd        dd 0                    ; Handle de la fenêtre principale
    hStatic     dd 0                    ; Handle du composant texte (STATIC)
    hRedBrush   dd 0                    ; Handle du pinceau rouge pour le fond

; ============================================================================
; Section du code exécutable
; ============================================================================
section '.code' code readable executable
start:
    ; 1. Création d'un pinceau solide de couleur rouge pour le fond
    ; Le format de couleur Win32 COLORREF est 0x00BBGGRR -> Rouge = 0x000000FF
    invoke  CreateSolidBrush, $000000FF
    mov     [hRedBrush], eax            ; Sauvegarde du handle du pinceau

    ; 2. Initialisation de la structure WNDCLASS pour enregistrer la fenêtre
    mov     [wc.style], 0               ; Styles de la classe (aucun style particulier)
    mov     [wc.lpfnWndProc], WindowProc ; Adresse de la fonction de traitement des messages
    mov     [wc.cbClsExtra], 0          ; Octets supplémentaires pour la classe (aucun)
    mov     [wc.cbWndExtra], 0          ; Octets supplémentaires pour la fenêtre (aucun)
    invoke  GetModuleHandle, 0          ; Obtention du handle du module actuel (.exe)
    mov     [wc.hInstance], eax         ; Sauvegarde de l'instance du module
    invoke  LoadIcon, 0, IDI_APPLICATION ; Chargement de l'icône par défaut de l'application
    mov     [wc.hIcon], eax             ; Assignation de l'icône
    invoke  LoadCursor, 0, IDC_ARROW    ; Chargement du curseur standard (flèche)
    mov     [wc.hCursor], eax           ; Assignation du curseur
    invoke  GetSysColorBrush, COLOR_BTNFACE ; Pinceau par défaut pour le fond de la fenêtre
    mov     [wc.hbrBackground], eax     ; Assignation de la couleur de fond de la fenêtre
    mov     [wc.lpszMenuName], 0        ; Nom du menu (aucun menu)
    mov     [wc.lpszClassName], className ; Assignation du nom de la classe

    ; Enregistrement de la classe auprès du système d'exploitation Windows
    invoke  RegisterClass, wc

    ; 3. Création de la fenêtre principale (largeur: 300, hauteur: 150)
    invoke  CreateWindowEx, 0, className, titleName, \
            WS_OVERLAPPED or WS_CAPTION or WS_SYSMENU or WS_VISIBLE, \
            200, 200, 300, 150, 0, 0, [wc.hInstance], 0
    mov     [hWnd], eax                 ; Sauvegarde du handle de la fenêtre créée

    ; 4. Boucle principale de traitement des messages Windows
msg_loop:
    invoke  GetMessage, msg, 0, 0, 0     ; Extrait un message de la file d'attente
    test    eax, eax                    ; Vérifie si GetMessage retourne 0 (WM_QUIT)
    jz      end_loop                    ; Si oui, quitte la boucle
    invoke  TranslateMessage, msg       ; Traduit les messages de touches virtuelles
    invoke  DispatchMessage, msg        ; Envoie le message à la procédure WindowProc
    jmp     msg_loop                    ; Continue la boucle

end_loop:
    ; Nettoyage des ressources avant de quitter
    invoke  DeleteObject, [hRedBrush]   ; Supprime le pinceau rouge créé
    invoke  ExitProcess, [msg.wParam]   ; Termine le processus avec le code de sortie

; ============================================================================
; Procédure de fenêtre (Gestionnaire de messages)
; ============================================================================
proc WindowProc hwnd, umsg, wparam, lparam
    cmp     [umsg], WM_CREATE           ; Message reçu lors de la création de la fenêtre
    je      .wmcreate
    cmp     [umsg], WM_CTLCOLORSTATIC   ; Message reçu avant le dessin du texte STATIC
    je      .wmctlcolorstatic
    cmp     [umsg], WM_DESTROY          ; Message reçu lors de la fermeture de la fenêtre
    je      .wmdestroy

    ; Traitement par défaut pour tous les autres messages non gérés
    invoke  DefWindowProc, [hwnd], [umsg], [wparam], [lparam]
    ret

.wmcreate:
    invoke  CreateWindowEx, 0, staticClass, labelText, \
            WS_CHILD or WS_VISIBLE or SS_CENTER, \
            30, 35, 220, 30, [hwnd], 100, [wc.hInstance], 0
    mov     [hStatic], eax
    xor     eax, eax
    ret

.wmctlcolorstatic:
    ; Ce message est appelé juste avant d'afficher le texte
    ; wparam contient le contexte de périphérique (HDC)
    
    ; Définit la couleur du texte en bleu (0x00BBGGRR -> Bleu = 0x00FF0000)
    invoke  SetTextColor, [wparam], $00FF0000
    
    ; Définit la couleur de fond directement sous les lettres en rouge (0x000000FF)
    invoke  SetBkColor, [wparam], $000000FF
    
    ; Retourne le handle du pinceau rouge pour remplir tout le rectangle de l'étiquette
    mov     eax, [hRedBrush]
    ret

.wmdestroy:
    ; Demande la fermeture de la boucle de messages (envoie WM_QUIT)
    invoke  PostQuitMessage, 0
    xor     eax, eax                    ; Retourne 0
    ret
endp

; ============================================================================
; Section d'importation des DLLs système (Win32 API)
; ============================================================================
section '.idata' import data readable
    library kernel32, 'kernel32.dll', \
            user32,   'user32.dll', \
            gdi32,    'gdi32.dll'

    ; Fonctions du noyau Windows
    import kernel32, \
           GetModuleHandle, 'GetModuleHandleA', \
           ExitProcess,     'ExitProcess'

    ; Fonctions de gestion de l'interface utilisateur
    import user32, \
           RegisterClass,   'RegisterClassA', \
           CreateWindowEx,  'CreateWindowExA', \
           DefWindowProc,   'DefWindowProcA', \
           GetMessage,      'GetMessageA', \
           TranslateMessage,'TranslateMessage', \
           DispatchMessage, 'DispatchMessageA', \
           PostQuitMessage, 'PostQuitMessage', \
           LoadIcon,        'LoadIconA', \
           LoadCursor,      'LoadCursorA', \
           GetSysColorBrush,'GetSysColorBrush'

    ; Fonctions graphiques (GDI - Graphics Device Interface)
    import gdi32, \
           CreateSolidBrush,'CreateSolidBrush', \
           SetTextColor,    'SetTextColor', \
           SetBkColor,      'SetBkColor', \
           DeleteObject,    'DeleteObject'