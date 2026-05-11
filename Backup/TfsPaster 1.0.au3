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

;~ #include <Include\HotKey.au3>
;~ #include <Include\vkConstants.au3>

Opt("SendKeyDelay", 1) ;milliseconds
Opt("SendKeyDownDelay", 1) ;millisecond

Global Const $LOG_PATH = @ScriptDir & "\Log"
Global Const $SAVE_BIN = True

Global $hWebBrowser = 0

Global $orignalHtml
Global $patchedHtmlData

Global $localImageCount = 0
Global $localImageFiles[1]

Global $remoteImageCount = 0
Global $remoteImageUrls[1]

Global $vShapeCount = 0
Global $vShapeList[1]
Global $vShapeImageWidth[1]
Global $vShapeImageHigh[1]

; 1 - Report Log Window (Default).
; 2 - ConsoleWrite.
; 3 - MsgBox.
; 4 - FileWrite into $sLogFile defines the filename.
; 5 - Report Notepad Window.
_DebugSetup("TFS Paster Debug Report", False, 2, $LOG_PATH & "Debug.log")


;~ $orignalHtml = BinaryToString(_ClipBoard_GetData($CLIP_HTML_FORMAT), $SB_UTF8)
;~ SaveBinToFile("test.html", $orignalHtml)
;~ 	Exit

; Win + F9
;~ _HotKey_Assign($CK_CONTROL + $CK_ALT + $VK_P, 'DoPaste', BitOR($HK_FLAG_NOOVERLAPCALL, $HK_FLAG_NOREPEAT))

Global $CLIP_HTML_FORMAT = _ClipBoard_RegisterFormat("HTML Format")
If @error Then
	MsgBox(16, "Error", "_ClipBoard_RegisterFormat() retruns error.")
	Exit
EndIf

DirCreate($LOG_PATH)

HotKeySet("+!d", "DoJob") ;Used to terminate the script
OnAutoItExitRegister("Terminate")

While 1
	Sleep(0x0fffffff)
WEnd

;#######################################################

Func Terminate()
;~ 	_HotKey_Release()
EndFunc

Func DoJob()
	$hWebBrowser = WinGetHandle("[active]")
	While _IsPressed("10") Or _IsPressed("11") Or _IsPressed("12") Or _IsPressed("5B") Or _IsPressed("5C")
		Sleep(10)
	WEnd

	_Log("Start Job")

	WaitingClipboardUpdated()
	If @error Then
		_Log("ERROR: WaitingClipboardUpdated() timeout")
		Return SetError(1, 0, 0)
	EndIf

	$orignalHtml = GetHtmlFromClipboard()
	If @error Or StringLen($orignalHtml) = 0 Then
		_Log("ERROR: Cannot get html from clipboard")
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

	_ClipBoard_SetData(StringToBinary($patchedHtmlData, $SB_UTF8), $CLIP_HTML_FORMAT)

	If Not WebBrowserActive() Then Return SetError(100, 0, 0)
	Send("^a")
	Send("^v")

	_ClipBoard_SetData(StringToBinary($orignalHtml, $SB_UTF8), $CLIP_HTML_FORMAT)
	SaveBinToFile("patched.html", $patchedHtmlData)

	_Log("Job is done")
EndFunc   ;==>DoPaste

Func HtmlShrink()
	$patchedHtmlData = StringRegExpReplace($patchedHtmlData, '(?ims)(<!--\[if gte mso .*?<!\[endif\]-->)', "")
EndFunc

Func WaitingClipboardUpdated()
	Local $clipLen = 0
	Local $useHTML = True
	Local $clipStr

	$useHTML = _ClipBoard_IsFormatAvailable($CLIP_HTML_FORMAT)
	If Not $useHTML And Not _ClipBoard_IsFormatAvailable($CF_TEXT) Then
		_Log("WARN: Cannot find TEXT or HTML format in clipboard")
		Return SetError(1, 0, 0)
	EndIf

	Local $hStarttime = _Timer_Init()
	Do
		$clipStr = $useHTML? _ClipBoard_GetData($CLIP_HTML_FORMAT) : _ClipBoard_GetData($CF_TEXT)
		If @error = 0 Then
			If $clipLen = @extended Then
				Return True
			EndIf
			$clipLen = @extended
		ElseIf @error = 1 Or @error = 2 Then
			Return SetError(2, 0, 0)
		EndIf

		Sleep(10)
	Until _Timer_Diff($hStarttime) > 5000

	_Log("ERROR: Waiting clipboard updated....Timeout")
	Return SetError(3, 0, 0)
EndFunc

Func GetHtmlFromClipboard()
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
		If @error And (@error <> 200 Or $retry = 3) Then
			_log("ERROR: Cannot get all images URL on TFS")
			Return SetError(@error, 0, 0)
		EndIf
	Next

	GetVShapeList()
	For $i = 0 To $localImageCount - 1
		ReplaceVShape($localImageFiles[$i], $remoteImageUrls[$i])
		$patchedHtmlData = StringReplace($patchedHtmlData, "file:///" & $localImageFiles[$i], $remoteImageUrls[$i])
	Next
	Return True
EndFunc

Func GetRemoteImageUrl()
	Local Const $IMAGE_UPLOAD_TIMEOUT = 5000

	If $localImageCount = 0 Then
		Return True
	EndIf

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
	Local $htmlBin = _ClipBoard_GetData($CLIP_HTML_FORMAT)
	If @error Then Return SetError(1, 0, 0)

	Local $html = BinaryToString($htmlBin, $SB_UTF8)
	Local $tempUrlList = StringRegExp($html, '(?i)src="(.*?)"', 3)
	If @error Then Return SetError(2, 0, 0)
	If Not IsArray($tempUrlList) Or UBound($tempUrlList) = 0 Then Return SetError(2, 0, 0)

	Return $tempUrlList
EndFunc   ;==>ParseRemoteImageUrlFromClip

Func GetVShapeList()
	Local $aArray = 0,  $iOffset = 1

	$vShapeCount = 0
	While 1
		$aArray = StringRegExp($patchedHtmlData, '(?ims)<v:shape[\s\R](.*?)</v:shape>', 2,  $iOffset)
		If @error Then ExitLoop
		$iOffset = @extended

		ReDim $vShapeList[$vShapeCount + 1]
		ReDim $vShapeImageWidth[$vShapeCount + 1]
		ReDim $vShapeImageHigh[$vShapeCount + 1]

		$vShapeList[$vShapeCount] = $aArray[0]
		VShapeGetImageSize($aArray[0])
		$vShapeCount += 1
	WEnd

	_log("Got " & $localImageCount & " vshape from html")
	Return $vShapeCount
EndFunc

Func VShapeGetImageSize($vShape)
	Local $aArray = 0
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
			EndIf
		Until 0 = 0

		If $i = 0 Then
			$vShapeImageWidth[$vShapeCount] = $value
		ElseIf $i = 1 Then
			$vShapeImageHigh[$vShapeCount] = $value
		EndIf
	Next

	_Log("Image " & $vShapeCount & " Size: " & $vShapeImageWidth[$vShapeCount] & ", " & $vShapeImageHigh[$vShapeCount])
EndFunc

Func ReplaceVShape($localFile, $remoteUrl)
	If $vShapeCount = 0 Then
		Return True
	EndIf

	For $i = 0 To $vShapeCount - 1
		If StringInStr($vShapeList[$i], $localFile) Then
			Local $imgTag = '<img'
			If $vShapeImageWidth[$i] > 0 Then
				$imgTag = $imgTag & ' width=' & $vShapeImageWidth[$i]
			EndIf

			If $vShapeImageHigh[$i] > 0 Then
				$imgTag = $imgTag & ' height=' & $vShapeImageHigh[$i]
			EndIf

			$imgTag = $imgTag & ' src="' & $remoteUrl & '">'
			$patchedHtmlData = StringReplace($patchedHtmlData, $vShapeList[$i], $imgTag)

			$vShapeList[$i] = "" ; Clear replaced context
		EndIf
	Next
EndFunc

Func SaveBinToFile($filename, $binary)
	If $SAVE_BIN Then
		Local $file = FileOpen($LOG_PATH & "\" & $filename, $FO_OVERWRITE + $FO_UTF8)
		FileWrite($file, $binary)
		FileClose($file)
	EndIf
EndFunc

Func WebBrowserActive()
	If WinActive($hWebBrowser) Then
		Return True
	EndIf

	_log("WARN: Web browser is not active")
	Return False
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
	_ClipBoard_Open(_AutoItWinGetHandle())
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
