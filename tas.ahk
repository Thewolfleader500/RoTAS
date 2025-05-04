; Roblox TAS with Raw Mouse + Key Input (AHK v1.1+)
#NoEnv
SendMode Input
#SingleInstance Force
SetWorkingDir %A_ScriptDir%
#Persistent
CoordMode, Mouse, Screen

; -------------------------
; MouseDelta class for raw input deltas
; -------------------------
Class MouseDelta {
    __New(callback){
        this.Callback := callback
        this.MouseMovedFn := this.MouseMoved.Bind(this)
    }
    Start(){
        static DevSize := 8 + A_PtrSize, RIDEV_INPUTSINK := 0x00000100
        VarSetCapacity(RID, DevSize)
        NumPut(1, RID, 0, "UShort")
        NumPut(2, RID, 2, "UShort")
        NumPut(RIDEV_INPUTSINK, RID, 4, "UInt")
        Gui +Hwndhwnd
        NumPut(hwnd, RID, 8, A_PtrSize==8?"Ptr":"UInt")
        DllCall("RegisterRawInputDevices", "Ptr", &RID, "UInt", 1, "UInt", DevSize)
        OnMessage(0x00FF, this.MouseMovedFn)
        return this
    }
    Stop(){
        static DevSize := 8 + A_PtrSize, RIDEV_REMOVE := 0x00000001
        OnMessage(0x00FF, this.MouseMovedFn, 0)
        NumPut(RIDEV_REMOVE, RID, 4, "UInt")
        DllCall("RegisterRawInputDevices", "Ptr", &RID, "UInt", 1, "UInt", DevSize)
        return this
    }
    MouseMoved(wParam, lParam){
        static pcb := 8 + 2*A_PtrSize, size := 0
        static off := { x:(20+2*A_PtrSize), y:(24+2*A_PtrSize) }
        if (!size)
            DllCall("GetRawInputData", "UPtr", lParam, "UInt", 0x10000003, "Ptr", 0, "UInt*", size, "UInt", pcb)
        VarSetCapacity(buf, size)
        DllCall("GetRawInputData", "UPtr", lParam, "UInt", 0x10000003, "Ptr", &buf, "UInt*", size, "UInt", pcb)
        dx := NumGet(&buf, off.x, "Int")
        dy := NumGet(&buf, off.y, "Int")
        this.Callback.Call(0, dx, dy)
    }
}

; -------------------------
; Globals & Setup
; -------------------------
recording       := false
startTime       := 0
events          := []                 
playbackBuffer  := []                 
customCode      := ""                 
keys            := ["w","a","s","d","e","space","LButton","RButton"]
md              := new MouseDelta(Func("OnRawMouse"))
prevState       := {}
isPlaying := false

; -------------------------
; Hotkeys
; -------------------------

F1::
    if (recording) {
        ; stop
        md.Stop()
        SetTimer, PollKeys, Off
        recording := false
        ToolTip
        MsgBox % "Recorded " events.Length() " total events."
        return
    }
    ; start
    events := []          ; Clear previous events
    playbackBuffer := []  ; Clear any old playback buffer
    prevState := {}
    startTime := A_TickCount
    md.Start()
    SetTimer, PollKeys, 10
    recording := true
    ToolTip, Recording TAS -- F1 to stop
return


F2::
    if (!events.Length()) {
        MsgBox, No recording to play!
        return
    }

    MsgBox, Playback in 2 Seconds -- Focus Roblox.
    Sleep, 2000
    ToolTip

    ; Optionally run custom code *in parallel*
    if (customCode != "") {
        ExecScript(customCode) ; runs it in a temporary script, not blocking
    }

    playbackBuffer := []
    lastT := 0
    SendMode Play
    Loop % events.Length() {
        ev := events[A_Index]
        t    := ev["time"]
        dT   := t - lastT
        Sleep, % dT
        lastT := t

        if (ev["type"] = "move") {
            dx := ev["dx"]
            dy := ev["dy"]
            DllCall("mouse_event", "UInt", 0x0001|0x2000, "Int", dx, "Int", dy, "UInt", 0, "UPtr", 0)
        } else {
            key := ev["key"]
            down := ev["down"]
            if (key = "LButton" or key = "RButton") {
                if (key = "LButton") {
                    flag := down ? 0x0002 : 0x0004
                } else {
                    flag := down ? 0x0008 : 0x0010
                }
                DllCall("mouse_event", "UInt", flag, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
            } else {
                action := down ? "Down" : "Up"
                SendInput, {%key% %action%}
            }
        }

        ; store into buffer for chaining
        playbackBuffer.Push({ time:t, type:ev["type"], key:ev.HasKey("key") ? ev["key"] : "", down:ev.HasKey("down") ? ev["down"] : "", dx:ev.HasKey("dx") ? ev["dx"] : 0, dy:ev.HasKey("dy") ? ev["dy"] : 0 })
    }
    SendMode Input
    MsgBox, Done.
return



F3::
{
    outputFile := A_ScriptDir "\tas_output.ahk"

    ; Try to delete first, just in case
    if FileExist(outputFile)
        FileDelete, %outputFile%

    if (!events.Length()) {
        MsgBox, Nothing to export!
        return
    }

    ; Create new file with a clean header
    FileAppend,
    (
; Auto-generated TAS playback
#NoEnv
SendMode Input
SetWorkingDir %A_ScriptDir%
Sleep, 1000

    ), %outputFile%

    lastT := 0
    Loop % events.Length() {
        ev := events[A_Index]
        t    := ev["time"]
        dT   := t - lastT
        lastT := t

        if (ev["type"] = "move") {
            dx := ev["dx"]
            dy := ev["dy"]
            s  := "Sleep " dT "`n"
              . "DllCall(""mouse_event"",""UInt"",0x0001|0x2000,""Int""," dx ",""Int""," dy ",""UInt"",0,""UPtr"",0)`n"
        } else {
            key := ev["key"]
            down := ev["down"]
            if (key = "LButton") {
                flag := down ? "0x0002" : "0x0004"
                s := "Sleep " dT "`n"
                  . "DllCall(""mouse_event"",""UInt""," flag ",""UInt"",0,""UInt"",0,""UInt"",0,""UPtr"",0)`n"
            } else if (key = "RButton") {
                flag := down ? "0x0008" : "0x0010"
                s := "Sleep " dT "`n"
                  . "DllCall(""mouse_event"",""UInt""," flag ",""UInt"",0,""UInt"",0,""UInt"",0,""UPtr"",0)`n"
            } else {
                action := down ? "Down" : "Up"
                s := "Sleep " dT "`n"
                  . "SendInput {" key " " action "}`n"
            }
        }
        FileAppend, % s, %outputFile%
    }

    MsgBox, Exported to tas_output.ahk (previous contents wiped).
}
return


; -------------------------
; F4: Show multiline GUI for custom AHK code
; -------------------------
F4::
    Gui, New, +Resize +MinSize600x300, Inject Custom AHK Script
    Gui, Font, s10
    Gui, Add, Text, x10 y10, Paste your AHK code below:
    ; Editable, multi-line, with vertical scroll and support for ENTER
    Gui, Add, Edit, vCustomCodeEdit w580 h200 +WantReturn +VScroll, % customCode
    Gui, Add, Button, gSaveCode Default x350 y220 w100 h30, Save
    Gui, Add, Button, gCancelCode   x460 y220 w100 h30, Cancel
    Gui, Show, AutoSize Center
return

SaveCode:
    Gui, Submit, NoHide
    GuiControlGet, customCode,, CustomCodeEdit
    Gui, Destroy
    MsgBox, 64, Injected!, Custom AHK script stored.`n[F2] will now run it.
return

CancelCode:
    Gui, Destroy
return


; F5: Save / Load `events[]` to/from disk
F5::
    ; Show Yes/No dialog with proper title parameter
    MsgBox, 4, TAS Save/Load, Yes = Save current TAS to disk`nNo = Load TAS from disk
    ; Note: no comma after IfMsgBox
    IfMsgBox Yes
    {
        FileDelete, %A_ScriptDir%\tas_saved.txt
        ; first line = count
        FileAppend, % events.Length() "`n", %A_ScriptDir%\tas_saved.txt
        for i, ev in events {
            FileAppend, % ev["time"] "|" ev["type"] "|" ev.HasKey("key") ? ev["key"] : "" "|" ev.HasKey("down") ? ev["down"] : "" "|" ev.HasKey("dx") ? ev["dx"] : "" "|" ev.HasKey("dy") ? ev["dy"] : "" "`n", %A_ScriptDir%\tas_saved.txt
        }
        MsgBox, TAS saved to tas_saved.txt.
    }
    Else
    {
        ; Load
        FileReadLine, cnt, %A_ScriptDir%\tas_saved.txt, 1
        events := []
        Loop, % cnt {
            FileReadLine, line, %A_ScriptDir%\tas_saved.txt, % A_Index+1
            parts := StrSplit(line, "|")
            if (parts[2] = "move")
                events.Push({time:parts[1], type:"move", dx:parts[5], dy:parts[6]})
            else
                events.Push({time:parts[1], type:"key", key:parts[3], down:parts[4]})
        }
        MsgBox, Loaded %cnt% events from disk.
    }
return


; F8: Reset everything
F8::
    events := []
    playbackBuffer := []
    customCode := ""
    MsgBox, All TAS data reset.
return

; -------------------------
; Raw Mouse Callback
; -------------------------
OnRawMouse(device, dx, dy) {
    global recording, events, startTime
    if (!recording || (dx = 0 && dy = 0))
        return
    t := A_TickCount - startTime
    events.Push({ time:t, type:"move", dx:dx, dy:dy })
}


; -------------------------
; Key Polling Timer
; -------------------------
PollKeys:
    global events, keys, prevState, startTime
    t := A_TickCount - startTime
    for _, k in keys {
        s := GetKeyState(k, "P")
        prev := prevState.HasKey(k) ? prevState[k] : 0
        if (s != prev) {
            events.Push({ time:t, type:"key", key:k, down:s })
            prevState[k] := s
        }
    }
return

; -------------------------
; ExecScript: run raw AHK code
; -------------------------
isCustomRunning := false

ExecScript(code) {
    global isCustomRunning
    if (isCustomRunning)
        return
    isCustomRunning := true
    tmp := A_ScriptDir "\_temp_exec.ahk"
    FileDelete, %tmp%
    FileAppend, %code%, %tmp%
    Run, %A_AhkPath% "%tmp%", , Hide
    SetTimer, ResetCustomRunning, -5000 ; assume it'll finish in 5s or less
}

ResetCustomRunning:
    isCustomRunning := false
return
