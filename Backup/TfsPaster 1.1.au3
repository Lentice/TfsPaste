#AutoIt3Wrapper_icon=minion.ico
#AutoIt3Wrapper_Res_Description=TFS Paster
#AutoIt3Wrapper_Res_Fileversion=1.1
#AutoIt3Wrapper_UseX64=n

#include <Clipboard.au3>
#include <GDIPlus.au3>
#include <Array.au3>
#include <Misc.au3>
#include <Math.au3>
#include <Timers.au3>
#include <Debug.au3>
#include <StringConstants.au3>
#include <FileConstants.au3>
#include <AutoItConstants.au3>
#include <GUIConstantsEx.au3>
#include <StaticConstants.au3>
#include <WindowsConstants.au3>

;~ #include <Include\HotKey.au3>
;~ #include <Include\vkConstants.au3>

Opt("SendKeyDelay", 1) ;milliseconds
Opt("SendKeyDownDelay", 1) ;millisecond

Global Const $LOG_PATH = @ScriptDir & "\Log"
Global Const $INI_FILE = @ScriptDir & "Config.ini"

_DebugSetup("TFS Paster Debug Report", False, 2, $LOG_PATH & "Debug.log")
; 1 - Report Log Window ; 2 - ConsoleWrite. ; 4 - FileWrite into $sLogFile defines the filename.

Global $SaveBinary = Int(IniRead($INI_FILE, "Debug", "SaveBinary", "1"))

Global $CLIP_HTML_FORMAT
Global $hotkey = ""

Global $labelHotkey = ""
Global $labelStatus

Global $hGui = 0
Global $hWebBrowser = 0

Global $orignalHtml
Global $patchedHtmlData

Global $localImageCount = 0
Global $localImageFiles[1]

Global $remoteImageCount = 0
Global $remoteImageUrls[1]

;~ $orignalHtml = BinaryToString(_ClipBoard_GetData($CLIP_HTML_FORMAT), $SB_UTF8)
;~ SaveBinToFile("test.html", $orignalHtml)
;~ 	Exit

; Win + F9
;~ _HotKey_Assign($CK_CONTROL + $CK_ALT + $VK_P, 'DoPaste', BitOR($HK_FLAG_NOOVERLAPCALL, $HK_FLAG_NOREPEAT))

$CLIP_HTML_FORMAT = _ClipBoard_RegisterFormat("HTML Format")
If @error Then
	MsgBox(16, "Error", "_ClipBoard_RegisterFormat() retruns error.")
	Exit
EndIf

DirCreate($LOG_PATH)

GetHotKey()
HotKeySet($hotkey, "DoJob") ;Used to terminate the script

OnAutoItExitRegister("Terminate")

CreateWindow()

While 1
	$nMsg = GUIGetMsg()
	Switch $nMsg
		Case $GUI_EVENT_CLOSE
			Exit

	EndSwitch
WEnd

;#######################################################

Func GetHotKey()
	$hkCtrl = Int(IniRead($INI_FILE, "Hotkey", "CTRL", "0"))
	$hkAlt = Int(IniRead($INI_FILE, "Hotkey", "ALT", "1"))
	$hkShift = Int(IniRead($INI_FILE, "Hotkey", "SHIFT", "1"))
	$hkKey = StringLower(IniRead($INI_FILE, "Hotkey", "Key", "d"))

	If $hkCtrl Then
		$labelHotkey = $labelHotkey & "Ctrl + "
		$hotkey = $hotkey & "^"
	EndIf

	If $hkAlt Then
		$labelHotkey = $labelHotkey & "Alt + "
		$hotkey = $hotkey & "!"
	EndIf

	If $hkShift Then
		$labelHotkey = $labelHotkey & "Shift + "
		$hotkey = $hotkey & "+"
	EndIf

	$labelHotkey = $labelHotkey & $hkKey
	$hotkey = $hotkey & $hkKey
EndFunc

Func CreateWindow()
	$hGui = GUICreate("TFS Paster 1.1", 400, 85, 192, 124, -1, $WS_EX_TOPMOST)
	GUICtrlCreateLabel("Hotkey:", 8, 8, 80)
	GUICtrlSetFont(-1, 12, 700)
	GUICtrlCreateLabel($labelHotkey, 80, 8, 300)
	GUICtrlSetFont(-1, 12, 700)
	GUICtrlSetColor(-1, 0x388E3C)
	GUICtrlCreateLabel("   Using hotkey to paste content to TFS instead of using Ctrl + V", 8, 30, 300)
	GUICtrlCreateLabel("Status:", 8, 55, 80)
	GUICtrlSetFont(-1, 12, 700)
	$labelStatus = GUICtrlCreateLabel("Idle", 80, 55, 300) ; max 44 characters
	GUICtrlSetFont(-1, 12)
	GUISetState(@SW_SHOW)
EndFunc

Func Terminate()
;~ 	_HotKey_Release()
EndFunc

Func DoJob()
	$hWebBrowser = WinGetHandle("[active]")

	; Waiting Ctrl, Alt, Shift and winkey are all released
	While _IsPressed("10") Or _IsPressed("11") Or _IsPressed("12") Or _IsPressed("5B") Or _IsPressed("5C")
		Sleep(10)
	WEnd

	_Log("Start Job")
	WaitingClipboardUpdated()
	If @error Then

		Return SetError(1, 0, 0)
	EndIf

	$orignalHtml = GetHtmlFromClipboard()
	If @error Or StringLen($orignalHtml) = 0 Then
		ErrorStatus("Cannot get html format from clipboard")
		Return SetError(2, 0, 0)
	EndIf

	$patchedHtmlData = $orignalHtml
	HtmlShrink()

	If GetLocalImageFiles($orignalHtml) Then
		If Not ReplaceFilePathToUrl() Then
			Return SetError(3, 0, 0)
		EndIf
	Else
		_Log("No image found")
	EndIf

	NormalStatus("Paste patched html")

	_ClipBoard_SetData(StringToBinary($patchedHtmlData, $SB_UTF8), $CLIP_HTML_FORMAT)

	If Not WebBrowserActive() Then Return SetError(100, 0, 0)
	Send("^a")
	Send("^v")

	SaveBinToFile("patched.html", $patchedHtmlData)

	SuccessStatus("DONE")
	_Log("Job is done")
EndFunc   ;==>DoPaste

Func HtmlShrink()
	$patchedHtmlData = StringRegExpReplace($patchedHtmlData, '(?ims)(<!--\[if gte mso .*?<!\[endif\]-->)', "")
EndFunc

Func WaitingClipboardUpdated()
	Local Const $UPDATE_TIMEOUT = 15000

	Local $useHTML = True

	NormalStatus("Clipboard updating")

	Local $hStarttime = _Timer_Init()
	Do
		If _ClipBoard_Open($hGui) Then
			_ClipBoard_Close()
			Return True
		EndIf

		Sleep(10)
	Until _Timer_Diff($hStarttime) > $UPDATE_TIMEOUT

	ErrorStatus("WaitingClipboardUpdated() timeout")
	Return SetError(1, 0, 0)
EndFunc

Func GetHtmlFromClipboard()
;~ 	If Not _ClipBoard_Open($hGui) Then
;~ 		_log("ERROR: clipboard is locked when call GetHtmlFromClipboard()")
;~ 		SetError(1, 0, 0)
;~ 	EndIf

;~ 	Local $htmlBin = _ClipBoard_GetData($CLIP_HTML_FORMAT)
;~ 	Local $isFail = @error
;~ 	_ClipBoard_Close()

;~ 	If $isFail Then
;~ 		_log("ERROR: _ClipBoard_GetData() failed in GetHtmlFromClipboard()")
;~ 		Return SetError(2, 0, 0)
;~ 	EndIf

	Local $htmlBin = _ClipBoard_GetData($CLIP_HTML_FORMAT)
	If @error Then Return SetError(1, 0, 0)

	SaveBinToFile("Source.html", $htmlBin)

	Return BinaryToString($htmlBin, $SB_UTF8)
EndFunc

Func GetLocalImageFiles($html)
	$localImageCount = 0

	Local $tempImageList = StringRegExp($html, '(?i)src="file:///(.*?)"', 3)
	If @error Then Return SetError(1, 0, 0)

	For $i = 0 To UBound($tempImageList) - 1
		; Filter out duplicate files
		If $localImageCount = 0 Or StringCompare($localImageFiles[$localImageCount - 1], $tempImageList[$i]) Then
			ReDim $localImageFiles[$localImageCount + 1]

			$localImageFiles[$localImageCount] = $tempImageList[$i]
			$localImageCount += 1
		EndIf
	Next

	_log("Got " & $localImageCount & " image(s) from original html")
	Return $localImageCount
EndFunc   ;==>GetLocalImageFiles

Func ReplaceFilePathToUrl()

	For $retry = 1 To 3
		GetRemoteImageUrl()
		If Not @error Then
			ExitLoop
		ElseIf @error = 100 Then
			Return SetError(@error, 0, 0)
		ElseIf @error == 200 And $retry = 3 Then
			ErrorStatus("Upload images to TFS failed")
			Return SetError(@error, 0, 0)
		EndIf
	Next

	NormalStatus("Patch file path to URL")
	PatchVShape()

	For $i = 0 To $localImageCount - 1
		$patchedHtmlData = StringReplace($patchedHtmlData, "file:///" & $localImageFiles[$i], $remoteImageUrls[$i])
	Next

	Return True
EndFunc

Func GetRemoteImageUrl()
	Local Const $IMAGE_UPLOAD_TIMEOUT = 5000

	If $localImageCount = 0 Then
		Return True
	EndIf

	NormalStatus("Upload Images To TFS")

	ReDim $remoteImageUrls[$localImageCount]

	If Not WebBrowserActive() Then Return SetError(100, 0, 0)
	Send("^a")
	Send("{DEL}")

	For $i = 0 To $localImageCount - 1
		_ImageToClip($localImageFiles[$i])

		If Not WebBrowserActive() Then Return SetError(100, 0, 0)
		Send("^v")

		; Copy image on web to get the URL
		Local $hStarttime = _Timer_Init()
		While 1
			Send("^a")
			Send("^x")
			Sleep(10)

			Local $imageUrl = ParseRemoteImageUrlFromClip()
			If Not @error Then
				$remoteImageUrls[$i] = $imageUrl[0]
				$remoteImageCount += 1
				ExitLoop
			EndIf

			If _Timer_Diff($hStarttime) > $IMAGE_UPLOAD_TIMEOUT Then
				_log("ERROR: Uploading image timeout")
				Return SetError(200, 0, 0)
			EndIf

			If Not WebBrowserActive() Then Return SetError(100, 0, 0)
		WEnd
	Next

	If Not WebBrowserActive() Then Return SetError(100, 0, 0)
	Send("^a")
	Sleep(10)
	Send("{DEL}")

	Return True
EndFunc   ;==>GetRemoteImageUrl

Func ParseRemoteImageUrlFromClip()
;~ 	If Not _ClipBoard_Open($hGui) Then SetError(1, 0, 0)

;~ 	Local $htmlBin = _ClipBoard_GetData($CLIP_HTML_FORMAT)
;~ 	Local $isFail = @error
;~ 	_ClipBoard_Close()

;~ 	If $isFail Then Return SetError(2, 0, 0)

	Local $htmlBin = _ClipBoard_GetData($CLIP_HTML_FORMAT)
	If @error Then Return SetError(1, 0, 0)

	Local $html = BinaryToString($htmlBin, $SB_UTF8)
	Local $tempUrlList = StringRegExp($html, '(?i)src="(.*?)"', 3)
	If @error Then Return SetError(3, 0, 0)
	If Not IsArray($tempUrlList) Or UBound($tempUrlList) = 0 Then Return SetError(2, 0, 0)

	Return $tempUrlList
EndFunc   ;==>ParseRemoteImageUrlFromClip

Func PatchVShape()
	Local $iOffset = 1
	Local $vShapeList[1]
	Local $vShapeCount = 0

	While 1
		Local $aArray = StringRegExp($patchedHtmlData, '(?ims)<v:shape[\s\R](.*?)</v:shape>', 2,  $iOffset)
		If @error Then ExitLoop
		$iOffset = @extended

		ReDim $vShapeList[$vShapeCount + 1]
		$vShapeList[$vShapeCount] = $aArray[0]
		$vShapeCount += 1
	WEnd

	For $k = 0 To $vShapeCount - 1
		Local $imgSize = VShapeGetImageSize($vShapeList[$k])
		For $i = 0 To $localImageCount - 1
			If ReplaceVShape($vShapeList[$k], $localImageFiles[$i], $remoteImageUrls[$i], $imgSize[0], $imgSize[1]) Then
				ExitLoop
			EndIf
		Next
	Next

	_log("Got " & $localImageCount & " vshape from html")
	Return $localImageCount
EndFunc

Func VShapeGetImageSize($vShape)
	Local $aArray = 0
	Local $ret[] = [0, 0]
	Local $keyword[] = ['width', 'height']

	For $i = 0 To UBound($keyword) - 1
		Local $value = 0
		Do
			$aArray = StringRegExp($vShape, '(?i)' & $keyword[$i] & ':(\d+(\.\d+)?)pt', 3)
			If Not @error And Number($aArray[0]) <> 0 Then
;~ 				_Log("unit pt: " & $aArray[0])
				;  pixels = points * 96 / 72

				$value = Number($aArray[0]) * 96 / 72
				ExitLoop
			EndIf

			$aArray = StringRegExp($vShape, '(?i)' & $keyword[$i] & ':(\d+(\.\d+)?)px', 3)
			If Not @error And Number($aArray[0]) <> 0 Then
;~ 				_Log("unit px: " & $aArray[0])
				$value = Number($aArray[0])
				ExitLoop
			EndIf

			$aArray = StringRegExp($vShape, '(?i)' & $keyword[$i] & ':(\d+(\.\d+)?)cm', 3)
			If Not @error And Number($aArray[0]) <> 0 Then
;~ 				_Log("unit cm: " & $aArray[0])
				; 1 cm = 37.795276 px; 1 px = 0.026458 cm
				$value = Number($aArray[0]) * 37.795276
				ExitLoop
			EndIf

			$aArray = StringRegExp($vShape, '(?i)' & $keyword[$i] & ':(\d+(\.\d+)?)in', 3)
			If Not @error And Number($aArray[0]) <> 0 Then
;~ 				_Log("unit in: " & $aArray[0])
				; 1 px = 0.010417 in; 1 in = 96 px
				$value = Number($aArray[0]) * 96
				ExitLoop
			EndIf

			$aArray = StringRegExp($vShape, '(?i)' & $keyword[$i] & ':(\d+(\.\d+)?)mm', 3)
			If Not @error And Number($aArray[0]) <> 0 Then
;~ 				_Log("unit mm: " & $aArray[0])
				; 1 mm = 3.779528 px; 1 px = 0.264583 mm
				$value = Number($aArray[0]) * 3.779528
				ExitLoop
			EndIf

			$aArray = StringRegExp($vShape, '(?i)' & $keyword[$i] & ":(.*?)[;']", 3)
			If Not @error  Then
				_Log("Unknown unit: " & $aArray[0])
				Return $ret
			EndIf
		Until 0 = 0

		$ret[$i] =  $value
	Next

	_Log("Image Size: " & $ret[0] & ", " & $ret[1])
	Return $ret
EndFunc

Func ReplaceVShape($vShape, $localFile, $remoteUrl, $imgWidth, $imgHight)
	If Not StringInStr($vShape, $localFile) Then
		Return False
	EndIf

	Local $imgTag = '<img'
	If $imgWidth > 0 Then
		$imgTag = $imgTag & ' width=' & $imgWidth
	EndIf

	If $imgHight > 0 Then
		$imgTag = $imgTag & ' height=' & $imgHight
	EndIf

	$imgTag = $imgTag & ' src="' & $remoteUrl & '">'
	$patchedHtmlData = StringReplace($patchedHtmlData, $vShape, $imgTag)

	Return True
EndFunc

Func SaveBinToFile($filename, $binary)
	If $SaveBinary Then
		Local $file = FileOpen($LOG_PATH & "\" & $filename, $FO_OVERWRITE + $FO_UTF8)
		FileWrite($file, $binary)
		FileClose($file)
	EndIf
EndFunc

Func WebBrowserActive()
	If WinActive($hWebBrowser) Then
		Return True
	EndIf

	ErrorStatus("Web browser is not active")
	Return False
EndFunc

Func NormalStatus($msg)
	_log($msg)
	GUICtrlSetData($labelStatus, $msg)
	GUICtrlSetColor($labelStatus, 0)
EndFunc

Func ErrorStatus($msg)
	_log("ERROR: " & $msg)
	GUICtrlSetData($labelStatus, $msg)
	GUICtrlSetColor($labelStatus, 0xd32f2f)
EndFunc

Func SuccessStatus($msg)
	_log($msg)
	GUICtrlSetData($labelStatus, $msg)
	GUICtrlSetColor($labelStatus, 0x388E3C)
EndFunc

Func _Log($Msg)
	_DebugOut(StringFormat("[%02d:%02d:%02d:%03d] ", @HOUR, @MIN, @SEC, @MSEC) & $Msg)
EndFunc   ;==>_Log

;===============================================================================
;
; Function Name:   _ImageToClip
; Description::    Copies all Image Files to ClipBoard
; Parameter(s):    $Path -> Path of image
; Requirement(s):  GDIPlus.au3
; Return Value(s): Success: 1
;                  Error: 0 and @error:
;                          1 -> Error in FileOpen
;                          2 -> Error when setting to Clipboard
; Author(s):
;
;===============================================================================
;
Func _ImageToClip($Path)
	_GDIPlus_Startup()
	Local $hImg = _GDIPlus_ImageLoadFromFile($Path)
	If $hImg = 0 Then Return SetError(1, 0, 0)
	Local $hBitmap = _GDIPlus_ImageCreateGDICompatibleHBITMAP($hImg)
	_GDIPlus_ImageDispose($hImg)
	_GDIPlus_Shutdown()
	Local $ret = _ClipBoard_SetHBITMAP($hBitmap)
	Return 1
EndFunc   ;==>_ImageToClip

;===============================================================================
;
; Function Name:   _ClipBoard_SetHBITMAP
; Description::    Sets a HBITAMP as ClipBoardData
; Parameter(s):    $hBitmap -> Handle to HBITAMP from GDI32, NOT GDIPlus
; Requirement(s):  ClipBoard.au3
; Return Value(s): Success: 1 ; Error: 0 And @error = 1
; Author(s):       Prog@ndy
; Notes:           To use Images from GDIplus, convert them with _GDIPlus_ImageCreateGDICompatibleHBITMAP
;
;===============================================================================
;
Func _ClipBoard_SetHBITMAP($hBitmap, $Empty = 1)
	_ClipBoard_Open($hGui)
	If $Empty Then _ClipBoard_Empty()
	_ClipBoard_SetDataEx($hBitmap, $CF_BITMAP)
	_ClipBoard_Close()
	If Not _ClipBoard_IsFormatAvailable($CF_BITMAP) Then
		Return SetError(1, 0, 0)
	EndIf
EndFunc   ;==>_ClipBoard_SetHBITMAP

;===============================================================================
;
; Function Name:   _GDIPlus_ImageCreateGDICompatibleHBITMAP
; Description::    Converts a GDIPlus-Image to GDI-combatible HBITMAP
; Parameter(s):    $hImg -> GDIplus Image object
; Requirement(s):  GDIPlus.au3
; Return Value(s): HBITMAP, compatible with ClipBoard
; Author(s):       Prog@ndy
;
;===============================================================================
;

Func _GDIPlus_ImageCreateGDICompatibleHBITMAP($hImg)
	Local $hBitmap2 = _GDIPlus_BitmapCreateHBITMAPFromBitmap($hImg)
	Local $hBitmap = _WinAPI_CopyImage($hBitmap2, 0, 0, 0, $LR_COPYDELETEORG + $LR_COPYRETURNORG)
	_WinAPI_DeleteObject($hBitmap2)
	Return $hBitmap
EndFunc   ;==>_GDIPlus_ImageCreateGDICompatibleHBITMAP


;===============================================================================
;
; Function Name:   _AutoItWinGetHandle
; Description::    Returns the Windowhandle of AutoIT-Window
; Parameter(s):    --
; Requirement(s):  --
; Return Value(s): Autoitwindow Handle
; Author(s):       Prog@ndy
;
;===============================================================================
;
Func _AutoItWinGetHandle()
	Local $oldTitle = AutoItWinGetTitle()
	Local $x = Random(1248578, 1249780)
	AutoItWinSetTitle("qwrzu" & $x)
	Local $y = WinGetHandle("qwrzu" & $x)
	AutoItWinSetTitle($oldTitle)
	Return $y
EndFunc   ;==>_AutoItWinGetHandle
