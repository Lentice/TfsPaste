#include-once
#include <Clipboard.au3>

OnAutoItExitRegister("__AutoItExit_ClipAll")

Global $__bMemFree = False
Global $avClip

; #FUNCTION# ====================================================================================================================
; Name ..........: _ClipBoard_GetAll
; Description ...: Backup clipboard content
; Syntax ........: _ClipBoard_GetAll(Byref $avClip)
; Parameters ....: $avClip              - [in/out] An array of variants.
; Return values .: Returns 1 if no error, else 0 and sets @error:
;                  1 = failed to open clipboard
;                  2 = _ClipBoard_GetDataEx failed
;                  3 = _MemGlobalAlloc failed
;                  4 = DllCall failed
;                  5 = _ClipBoard_Close failed
;                  @extended = total number of errors
; Author ........: wraithdu (modified by iCode)
; Modified ......: 29-Apr-2014
; Remarks .......:
; Related .......:
; Link ..........: http://www.autoitscript.com/forum/topic/81267-clipboard-getall-clipboard-putall-clipboard-wait/
; Example .......: No
; ===============================================================================================================================
Func _ClipBoard_GetAll(ByRef $avClip)

    Local $i = 0, $iFormat = 0, $hMem, $hMemNew, $pSource, $pDest, $iSize, $iErr = 0, $iErrEx = 0

    If $__bMemFree = True Then
        __MemFree($avClip)
    Else
        Dim $avClip[1][2]
    EndIf

    If Not _ClipBoard_Open(0) Then Return SetError(1, 1, 0)

    Do
        $iFormat = _ClipBoard_EnumFormats($iFormat)
        If $iFormat = 0 Then ExitLoop
        $hMem = _ClipBoard_GetDataEx($iFormat) ; this can/will fail for some formats - don't know why yet, so let's continue without retutning an error
        If $hMem = 0 Then ContinueLoop

        ; copy the memory
        $pSource = _MemGlobalLock($hMem)
        If $pSource = 0 Then
            $iErr = 3
            $iErrEx += 1
            ExitLoop
        EndIf
        $iSize = _MemGlobalSize($hMem)
        $hMemNew = _MemGlobalAlloc($iSize, $GHND)
        If $hMemNew = 0 Then
            _MemGlobalUnlock($hMemNew)
            $iErr = 4
            $iErrEx += 1
            ExitLoop
        EndIf
        $pDest = _MemGlobalLock($hMemNew)
        If $pDest = 0 Then
            _MemGlobalFree($hMemNew)
            $iErr = 5
            $iErrEx += 1
            ExitLoop
        EndIf
        DllCall("msvcrt.dll", "int:cdecl", "memcpy_s", "ptr", $pDest, "ulong_ptr", $iSize, "ptr", $pSource, "ulong_ptr", $iSize)
        If @error Then
            $iErr = 6
            $iErrEx += 1
        EndIf
        _MemGlobalUnlock($hMem)
        _MemGlobalUnlock($hMemNew)
        $__bMemFree = True
        If $iErr = 6 Then
            __MemFree($avClip)
            ExitLoop
        EndIf

        ; add handle and format to array
        $i += 1
        ReDim $avClip[$i + 1][2]
        $avClip[0][0] = $i
        $avClip[$i][0] = $hMemNew
        $avClip[$i][1] = $iFormat
    Until $iFormat = 0

    If Not _ClipBoard_Close() Then $iErr = 5

    If $iErr Then Return SetError($iErr, $iErrEx, 0)
    Return 1

EndFunc

; #FUNCTION# ====================================================================================================================
; Name ..........: _ClipBoard_PutAll
; Description ...: Restore clipboard content
; Syntax ........: _ClipBoard_PutAll(Byref $avClip)
; Parameters ....: $avClip              - [in/out] An array of variants.
; Return values .: Returns 1 if no error, else 0 and sets @error:
;                  1 = invalid array
;                  2 = _ClipBoard_Open failed
;                  3 = _ClipBoard_Empty failed
;                  4 = _ClipBoard_Close failed
;                  5 = _ClipBoard_Open failed
;                  6 = _ClipBoard_SetDataEx failed
;                  7 = _ClipBoard_Close failed
;                  @extended = total number of errors
; Author ........: wraithdu (modified by iCode)
; Modified ......: iCode 29-Apr-2014
; Remarks .......:
; Related .......:
; Link ..........: http://www.autoitscript.com/forum/topic/81267-clipboard-getall-clipboard-putall-clipboard-wait/
; Example .......: No
; ===============================================================================================================================
Func _ClipBoard_PutAll(ByRef $avClip)

    ; DO NOT free the memory handles after a call to this function - the system now owns the memory
    Local $iErr = 0, $iErrEx = 0 ; , $bOpen, $iTime

    $__bMemFree = False

    If Not IsArray($avClip) Or UBound($avClip, 0) <> 2 Or $avClip[0][0] < 1 Then
        Dim $avClip[1][2]
        Return SetError(1, 1, 0)
    EndIf

    ; test if clipboard can be opened
    ; if _ClipBoard_Open failes, the clipboard is likely still being updated, so we keep trying until it succeeds
    ;Local $hTimer = TimerInit()
    ;Do
    ;    $bOpen = _ClipBoard_Open(0)
    ;    Sleep(50)
    ;    $iTime = TimerDiff($hTimer)
    ;Until $bOpen = 1 Or $iTime >= 2000
    ;If $bOpen = 0 Then
    ;    Return SetError(2, 1, 0)
    ;EndIf

    ; empty clipboard
    If Not _ClipBoard_Open(0) Then Return SetError(2, 1, 0) ; comment out if using the code above
    If Not _ClipBoard_Empty() Then
        _ClipBoard_Close()
        Return SetError(3, 1, 0)
    EndIf
    If Not _ClipBoard_Close() Then Return SetError(4, 1, 0)

    ; re-open clipboard and put data
    If Not _ClipBoard_Open(0) Then Return SetError(5, 1, 0)
    For $i = 1 To $avClip[0][0]
        If Not _ClipBoard_SetDataEx($avClip[$i][0], $avClip[$i][1]) Then
            $iErr = 6
            $iErrEx += 1
        EndIf
    Next
    If Not _ClipBoard_Close() Then
        $iErr = 7
        $iErrEx += 1
    EndIf

    If $iErr Then Return SetError($iErr, $iErrEx, 0)
    Return 1

EndFunc

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __MemFree
; Description ...: Free clipboard memory
; Syntax ........: __MemFree(Byref $avClip)
; Parameters ....: $avClip              - [in/out] An array of variants.
; Return values .: Returns 1 if no error, else 0 and sets @error:
;                  1 = array is invalid
;                  2 = _MemGlobalFree failed
;                  @extended = total number of errors
; Author ........: wraithdu (modified by iCode)
; Modified ......: 29-Apr-2014
; Remarks .......:
; Related .......:
; Link ..........: http://www.autoitscript.com/forum/topic/81267-clipboard-getall-clipboard-putall-clipboard-wait/
; Example .......: No
; ===============================================================================================================================
Func __MemFree(ByRef $avClip)

    Local $iErr = 0, $iErrEx = 0

    If $__bMemFree = False Then
        Return
    ElseIf Not IsArray($avClip) Or UBound($avClip, 0) <> 2 Or $avClip[0][0] < 1 Then
        Dim $avClip[1][2]
        $__bMemFree = False
        Return SetError(1, 1, 0)
    EndIf

    For $i = 1 To $avClip[0][0]
        If Not _MemGlobalFree($avClip[$i][1]) Then
            $iErr = 2
            $iErrEx += 1
        EndIf
    Next

    $__bMemFree = False
    Dim $avClip[1][2]

    If $iErr Then Return SetError($iErr, $iErrEx, 0)
    Return 1

EndFunc

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __AutoItExit_ClipAll
; Description ...: Free clipboard memory on AutoIt exit
; Syntax ........: __AutoItExit_ClipAll()
; Parameters ....:
; Return values .: None
; Author ........: iCode
; Modified ......: 29-Apr-2014
; Remarks .......:
; Related .......:
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __AutoItExit_ClipAll()
    #forcedef $avClip
    __MemFree($avClip)
EndFunc

