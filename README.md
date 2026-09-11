# Group-Linkdin-FASM
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
08-09-2026
Hello Awesome — a simple Win32 GUI example written in FASM.
This small program creates a Windows GUI application that displays “Hello Awesome” in blue text on a red background.
The source code is commented line by line to make it easier to understand the basic structure of a FASM Win32 application, including window creation, the Windows message loop, STATIC control, GDI colors, and Win32 API calls.
A simple first example for anyone starting with Flat Assembler and Windows programming.
Create a solid red brush for the background
Win32 COLORREF format is 0x00BBGGRR -> Red = 0x000000FF
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

09-09-2026
Hello Awesome2 - FASM Win32 GUI — Show, Hide & Controlled Exit
A small Windows GUI application written entirely in **Flat Assembler (FASM)** using the **Win32 API**.
This project is a step beyond a basic "Hello World" example.  
It demonstrates how to create a simple event-driven Windows application with buttons, application state, and controlled window closing.
## Features
The application contains three buttons:
- **Afficher (Show)** — displays the `Hello Awesome` message.
- **Cacher (Hide)** — hides the message.
- **Quitter (Exit)** — closes the application only when the message is hidden.
If the user tries to exit while the message is still visible, the program displays a warning `MessageBox` and prevents the application from closing.
The same protection also applies when the user clicks the standard **X** button.
## What This Example Demonstrates
- Creating a Win32 GUI with FASM
- Registering and creating a Windows window
- Creating BUTTON and STATIC controls
- Windows message loop
- `WM_COMMAND` handling
- `WM_CLOSE` and `WM_DESTROY`
- `ShowWindow` with `SW_SHOW` and `SW_HIDE`
- Simple state management with a flag
- Warning dialogs using `MessageBox`
- Basic GDI text and background colors
- Direct Win32 API calls without a framework
## Program Logic
The variable `msgVisible` keeps track of the current state:
```text
msgVisible = 0  ->  Message hidden
msgVisible = 1  ->  Message visible
When Show is pressed:
ShowWindow -> SW_SHOW -> msgVisible = 1
When Hide is pressed:
ShowWindow -> SW_HIDE -> msgVisible = 0
When the user tries to close the application:

WM_CLOSE
   |
   +-- msgVisible = 1 --> Show warning --> Keep application open
   |
   +-- msgVisible = 0 --> DestroyWindow --> Exit
Requirements
Flat Assembler (FASM)
Windows
Win32 API
No external framework is required.
Build
Open the .asm source file in FASM and compile it to generate the Windows executable.

Purpose
This project is intended as a simple educational example for anyone learning:
FASM, x86 Assembly, Win32 API, GUI programming, and event-driven programming.
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
11-09-2026
ASM Service Terminal — Login-Controlled Win32 Application

This small Windows application was written entirely in Flat Assembler (FASM) using the native Win32 API.

The current version demonstrates several practical concepts that can later be reused in a more advanced engineering or microcontroller service terminal.

Main features:

Password is read dynamically: password.txt is opened and read only when the user presses OK in the Login dialog. Each new Login attempt reads the file again, so the password can be changed while the application is still running.
Controlled application exit: while the user is logged in, both the Exit button and the standard window close action are blocked. The user must perform Logout first.
Persistent message history during the session: messages are appended to a multiline Win32 EDIT control using EM_SETSEL and EM_REPLACESEL, so previous messages remain visible and can be reviewed with the scrollbar.
Memory-only message storage: the application does not write the message history to disk. Messages remain only in memory and inside the Win32 control until the application is closed.
Login / Logout state management: the input field and Send button are disabled by default and become available only after successful authentication.

The project is intentionally simple, but the same architecture can later be extended into a service or engineering terminal with serial communication, MCU diagnostics, GPIO tests, I²C commands, ADC measurements, configuration functions, and different access levels.

Built with:
FASM + Win32 API

#FASM #Assembly #AssemblyLanguage #Win32API #LowLevelProgramming #EmbeddedSystems #Firmware #STM32 #PIC32 #EngineeringTools
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
