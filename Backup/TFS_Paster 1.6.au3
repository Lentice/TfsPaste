#AutoIt3Wrapper_icon=minion.ico
#AutoIt3Wrapper_Res_Description=TFS Paster
#AutoIt3Wrapper_Res_Fileversion=1.6.0.22
#AutoIt3Wrapper_Res_Fileversion_AutoIncrement=y
#AutoIt3Wrapper_UseX64=y
#AutoIt3Wrapper_Au3Check_Parameters= -d -w 1 -w 2 -w 3 -w 4 -w 5 -w 6
#AutoIt3Wrapper_Run_Au3Stripper=y
#Au3Stripper_Parameters=/rsln /SO

#include <Clipboard.au3>

Opt("SendKeyDelay", 1) ;milliseconds
Opt("SendKeyDownDelay", 1) ;millisecond
Opt("TrayAutoPause", 0) ;0=no pause, 1=Pause

Global Const $TEMP_PATH = @TempDir & "\TFS Paster"
Global Const $LOG_PATH = $TEMP_PATH & "\TFS Paster Log"
Global Const $INI_FILE = @ScriptDir & "\Config.ini"


Global $sourceUrl = ""
Global $g_debug = Int(IniRead($INI_FILE, "General", "Debug", 0))
Global $opLatencyMs = Int(IniRead($INI_FILE, "General", "OpLatencyMs", 20))
Global $preShrinkHtml = Int(IniRead($INI_FILE, "General", "PreShrinkHtml", 0))
Global $postShrinkHtml = Int(IniRead($INI_FILE, "General", "PostShrinkHtml", 0))
Global $g_hMemory = False
Global $g_BrowserActive = False
Global $hGui = 0
Global $hWebBrowser = 0
Global $hotkey = ""
Global $labelHotkey = ""
Global $labelStatus
Global $tempFileNumber = 0
Global $__bMemFree = False
Global $avClip[1][2]

Global $__g_hGDIPBrush = 0
Global $__g_hGDIPDll = 0
Global $__g_hGDIPPen = 0
Global $__g_iGDIPRef = 0
Global $__g_iGDIPToken = 0
Global $__g_bGDIP_V1_0 = True
Global Const $GUI_EVENT_CLOSE = -3

Global $CLIP_HTML_FORMAT = _ClipBoard_RegisterFormat("HTML Format")
If @error Then
	MsgBox(16, "Error", "_ClipBoard_RegisterFormat() retruns error.")
	Exit
EndIf

OnAutoItExitRegister("__APP_EXIT")
__APP_INIT()

While 1
	Global $nMsg = GUIGetMsg()
	Switch $nMsg
		Case $GUI_EVENT_CLOSE
			Exit

	EndSwitch
WEnd
Exit
;#######################################################

Func __APP_INIT()
	If $CmdLine[0] > 0 And StringCompare($CmdLine[1], "Quiet") = 0 Then
		DoJob()
		Exit
	EndIf

	GetHotKey()
	HotKeySet($hotkey, "DoJob") ;Used to terminate the script
	_Log("Hotkey: " & $hotkey)

	CreateWindow()

	_Log("LogPath: " & $LOG_PATH)
EndFunc

Func __APP_EXIT()
	If $g_hMemory Then
		_MemGlobalFree($g_hMemory)
	EndIf
	__MemFree()
EndFunc


Func GetHotKey()
	Local $hkCtrl = Int(IniRead($INI_FILE, "Hotkey", "CTRL", "0"))
	Local $hkAlt = Int(IniRead($INI_FILE, "Hotkey", "ALT", "1"))
	Local $hkShift = Int(IniRead($INI_FILE, "Hotkey", "SHIFT", "1"))
	Local $hkKey = StringLower(IniRead($INI_FILE, "Hotkey", "KEY", "d"))

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
	Const $WS_EX_TOPMOST = 0x00000008
	$hGui = GUICreate("TFS Paster " & FileGetVersion(@ScriptFullPath), 400, 85, 192, 124, -1, $WS_EX_TOPMOST)
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


Func DoJob()
	$hWebBrowser = WinGetHandle("[active]")
	$g_BrowserActive = True

	Local $title = WinGetTitle($hWebBrowser)
	If Not StringInStr($title, '- Google Chrome') And Not StringInStr($title, '— Mozilla Firefox') Then
		ToolTip("TFS_Paster: Active window is not a browser" & @CRLF & "Title: " & $title)
		Sleep(1000)
		Return
	EndIf

	NormalStatus("Wating keys release...")
	; Waiting Ctrl, Alt, Shift and winkey are all released
	While _IsPressed("10") Or _IsPressed("11") Or _IsPressed("12") Or _IsPressed("5B") Or _IsPressed("5C")
		Sleep(10)
	WEnd

	NormalStatus("Wating clipboard idle...")
	If Not WaitClipboardIdle() Then
		MsgBox(16, "Error", "WaitClipboardIdle() timeout")
		Return SetError(-1, 0, 1)
	EndIf

	_ClipBoard_GetAll()
	Local $htmlBin = _ClipBoard_GetData($CLIP_HTML_FORMAT)
	If @error Then
		_Log("Cannot get html format from clipboard")
		Return SetError(-2, 0, 2)
	EndIf

	If $g_debug Then
		SaveBinToFile("Source.html", $htmlBin)
	EndIf

	Local $orignalHtml = BinaryToString($htmlBin, $SB_UTF8)
	GetSourceUrl($orignalHtml)

	NormalStatus("Patch Html Content")
	Local $patchedHtmlStr = PreShrinkHtml($orignalHtml)
	$patchedHtmlStr= PatchImages($patchedHtmlStr)
	If Not $g_BrowserActive Then
		_ClipBoard_PutAll()
		Return SetError(-3)
	EndIf
	; $patchedHtmlStr = PostShrinkHtml($patchedHtmlStr)
	$patchedHtmlStr = UpdateHeaderDescription($patchedHtmlStr)

	NormalStatus("Update Clipboard")
	Local $patchedBin = StringToBinary($patchedHtmlStr, $SB_UTF8)
	_ClipBoard_SetData($patchedBin, $CLIP_HTML_FORMAT)
;~ 	UpdateClipBoard($patchedBin, $CLIP_HTML_FORMAT)

	WaitClipboardIdle()
	If $g_debug Then
		$patchedBin = _ClipBoard_GetData($CLIP_HTML_FORMAT)
		SaveBinToFile("Patched.html", $patchedBin)
	EndIf

	If Not WebBrowserActive() Then
		_ClipBoard_PutAll()
		Return SetError(-2, 0, 0)
	EndIf

	Send("^a")
	Sleep($opLatencyMs)
	Send("{DEL}")
	Sleep($opLatencyMs)
	Send("^v")
	WaitClipboardIdle()


	_ClipBoard_PutAll()
	SuccessStatus("DONE")
EndFunc   ;==>DoPaste

Func ParseCmdParams()
	If $CmdLine[0] > 0 And StringCompare($CmdLine[1], "dbgOff") = 0 Then
		$g_debug = False
	EndIf
EndFunc

Func GetSourceUrl($html)
	Local $arr = StringRegExp($html, '(?sm)^\s*SourceURL\s*:(.*?)$', 1)
	If @error Then
		$sourceUrl = ""
	Else
		$sourceUrl = $arr[0]
	EndIf
	_Log("SourceURL: " & $sourceUrl)
EndFunc

Func PreShrinkHtml($htmlData)
	If Not $preShrinkHtml Then
		Return $htmlData
	EndIf

	; Know issue: can't handle nest tags case.

	$htmlData = StringRegExpReplace($htmlData, '(?s)(<!--\s*(?!StartFragment|EndFragment).*?-->)', "")
;~ 	$htmlData = StringRegExpReplace($htmlData, '(?s)(<link(?>\s|\r?\n).*?href=.*?>\s*\r?\n?)', "")

;~ 	$htmlData = StringRegExpReplace($htmlData, '(?s)(\n|\s)lang=([^\x22\x27].*?)(\s|>|\r?\n)', '$1lang="$2"$3')
;~ 	$htmlData = StringRegExpReplace($htmlData, '(?s)(\n|\s)class=([^\x22\x27].*?)(\s|>|\r?\n)', '$1class="$2"$3')

	$htmlData = StringRegExpReplace($htmlData, '(?s)<!\[if !supportLists\]>(.*?)<!\[endif\]>', "$1")
	$htmlData = StringReplace($htmlData, "'mso-list:Ignore'", "''")

	Return $htmlData
EndFunc

Func PostShrinkHtml($htmlData)
	If Not $postShrinkHtml Then
		Return $htmlData
	EndIf

	; Know issue: can't handle nest tags case.

;~ 	$htmlData = StringRegExpReplace($htmlData, '(?s)<v:shapetype(?>>|(?>\s|\r?\n).*?>)(.*?)<\/v:shapetype>', "")
	$htmlData = StringRegExpReplace($htmlData, '(?s)<v:\w*(?>>|(?>\s|\r?\n).*?>)(.*?)<\/v:\w*>', "")

	; TODO: remove office bookmarks (mso-bookmark:OLE_LINK\d)

	Return $htmlData
EndFunc

Func UpdateHeaderDescription($htmlData)
	$htmlData = StringRegExpReplace($htmlData, '(StartHTML):\d*', StringFormat("$1:%010d", GetBinPosRegx($htmlData, "<html", False)), 1)
	$htmlData = StringRegExpReplace($htmlData, '(EndHTML):\d*', StringFormat("$1:%010d", BinaryLen(StringToBinary($htmlData, $SB_UTF8))), 1)
	$htmlData = StringRegExpReplace($htmlData, '(StartFragment):\d*', StringFormat("$1:%010d", GetBinPosRegx($htmlData, "<!--\s*StartFragment\s*-->", True)), 1)
	$htmlData = StringRegExpReplace($htmlData, '(EndFragment):\d*', StringFormat("$1:%010d", GetBinPosRegx($htmlData, "<!--\s*EndFragment\s*-->", False)), 1)
	Return $htmlData
EndFunc

Func WaitClipboardIdle()
	Local Const $TIMEOUT = 15000

	Local $hTimer = TimerInit()
	Do
		If _ClipBoard_Open($hGui) Then
			_ClipBoard_Close()
			Return True
		EndIf

		Sleep(10)
	Until TimerDiff($hTimer) > $TIMEOUT

	Return SetError(1, 0, False)
EndFunc

Func PatchImages($html)
	If $g_BrowserActive Then $html = PathExistImg($html)
	If $g_BrowserActive Then $html = PatchVShape($html)

	Return $html
EndFunc

Func PathExistImg($html)
	Local $imgList, $img, $newImg, $filePath, $url

	; patch <img>
	$imgList = StringRegExp($html, '(?s)(<img[^>]+src="[^">]+".*?>)', 3)
	For $i = 0 To UBound($imgList) - 1
		$img = $imgList[$i]

		Local $fileInfo = GetSrcFromHtml($img, 'img')
		If @error <> 0 Then ContinueLoop

		$filePath = GetFilePath($fileInfo[0])
		If @error Then ContinueLoop

		$url = UploadToWeb($filePath)
		If Not $g_BrowserActive Then Return SetError(-1, 0, $html)

		$newImg = StringRegExpReplace($img, '(\s|\n)src="[^"]+"', '$1src="' & $url & '"')
		$html = StringReplace($html, $img, $newImg, 1)
	Next

	Return $html
EndFunc

Func PatchVShape($html)
	Local $vShapeList, $vs, $img

	$vShapeList = StringRegExp($html, '(?s)(<v:shape(?>\s|\r?\n).*?<\/v:shape>)', 3)
	If @error Then
		_Log("No v:shape found")
		Return SetExtended(1, $html)
	EndIf

	For $i = 0 To UBound($vShapeList) - 1
		$vs = $vShapeList[$i]
		$img = GetImgTag($vs)
		If Not @error Then
			$html = StringReplace($html, $vs, $img, 1)
		EndIf

		If Not $g_BrowserActive Then Return SetError(-1, 0, $html)
	Next

	Return $html
EndFunc

Func GetSrcFromHtml($html, $tagName)
	Local $pattern = '(?is)<\Q' & $tagName & '\E[^>]+src="' & _
		'([^"]*\.(gif|jpg|bmp|png|jpeg|apng|svg|tif|tiff|ico|cur|webp)\??[^"]*)' & _
		'"'
	If @error Then Return SetError(-1)

	Local $ret =  StringRegExp($html, $pattern, 1)
	If @error Then Return SetError(-1)

	; $ret[0]: path, $ret[1]: file type
	Return $ret
EndFunc

Func GetImgTag($html)
	Local $fileInfo = GetSrcFromHtml($html, 'v:imagedata')
	If @error Then
		_log("No v:imagedata found")
		Return SetError(-1, 0, "")
	EndIf

	Local $attrWidth = "", $attrHeight = ""
	Local $width = GetStyleValueFromHtml($html, 'width', True)
	If Not @error Then
		$attrWidth = ' width="' & $width & '"'
	EndIf

	Local $height = GetStyleValueFromHtml($html, 'height', True)
	If Not @error Then
		$attrHeight = ' height="' & $height & '"'
	EndIf

	Local $filePath = GetFilePath($fileInfo[0])
	If @error Then
		Return SetError(-2, 0, "")
	EndIf

	Local $url = UploadToWeb($filePath)
	If Not $g_BrowserActive Then Return SetError(-3, 0, $html)

	Local $img = '<img ' & $attrWidth & $attrHeight & ' src="' & $url & '">'
	return $img
EndFunc

Func GetStyleValueFromHtml($html, $name, $convToPixel)
	;\x22: is "  and  \x27 is '
	Local $pattern = '(?si)[\s\n]style=[^>]*?[\x22\x27;\s]\Q' & $name & '\E:(.*?)[;\x22\x27]'
	Local $aArray = StringRegExp($html, $pattern, 1)
	If @error Then Return SetError(-1, 0, '')

	If $convToPixel Then
		Local $ret = ToPixel($aArray[0])
		If @error Then Return SetError(-2, 0, '')

		Return $ret
	EndIf

	Return $aArray[0]
EndFunc

Func ToPixel($strSize)
	Local $aArray = StringRegExp($strSize, '(?i)\s*(\d+(?>\.\d+)?)\s*(pt|px|cm|in|mm)', 1)
	If @error Then Return SetError(-1, 0, '')

	Local $value
	Switch $aArray[1]
		Case 'pt'
			; pixels = points * 96 / 72
			$value = Number($aArray[0]) * 96 / 72
		Case 'px'
			$value = Number($aArray[0])
		Case 'cm'
			; 1 cm = 37.795276 px; 1 px = 0.026458 cm
			$value = Number($aArray[0]) * 37.795276
		Case 'in'
			; 1 px = 0.010417 in; 1 in = 96 px
			$value = Number($aArray[0]) * 96
		Case 'mm'
			; 1 mm = 3.779528 px; 1 px = 0.264583 mm
			$value = Number($aArray[0]) * 3.779528
		Case Else
			_Log("Unknown unit: " & $aArray[1])
			Return SetError(-2)
	EndSwitch

	return $value
EndFunc

Func GetBinPosRegx($str, $pattern, $isCountPattern)

	Local $headPattern
	If $isCountPattern Then
		$headPattern = "(?s)(.*?" & $pattern & ")"
	Else
		$headPattern = "(?s)(.*?)" & $pattern & ""
	EndIf

	Local $headStr = StringRegExp($str, $headPattern, 1)
	If @error Then Return 0

	Return BinaryLen(StringToBinary($headStr[0], $SB_UTF8))
EndFunc

Func SaveBinToFile($filename, $binary)
	DirCreate($LOG_PATH)

	Local $file = FileOpen($LOG_PATH & "\" & $filename, 2 + 128)
	FileWrite($file, $binary)
	FileClose($file)
EndFunc

Func GetFilePath($path)
	Local $aArray, $appendSourceUrl = False

	Do
		$aArray = StringRegExp($path, '^file:\/\/+(.*)', 1)
		If Not @error Then
			Local $filePath = $aArray[0]
			_Log("File: " & $filePath)
			If Not FileExists($filePath) Then Return SetError(-2, 0, 0)

			Return $filePath
		EndIf

		If Not $appendSourceUrl Then
			$aArray = StringRegExp($sourceUrl, '(?sm)((?>file:\/+).*\/).*', 1)
			If @error Then Return SetError(-3, 0, "")

			$path = $aArray[0] & $path
			$appendSourceUrl = True
			_Log("Append source url: " & $path)
			ContinueLoop
		EndIf

		Return SetError(-4, 0, 0)
	Until False

	Return SetError(-5, 0, 0)
EndFunc


Func UploadToWeb($filePath)
	Local Const $IMAGE_UPLOAD_TIMEOUT = 8000

	_Log("Upload Images To TFS: " & $filePath)

	If Not _ImageToClip($filePath) Then Return SetError(-1, 0, 0)
	If Not WebBrowserActive() Then Return SetError(-2, 0, 0)

	Send("^a")
	Sleep($opLatencyMs)
	Send("{DEL}")
	Sleep($opLatencyMs)
	Send("^v")
	Sleep($opLatencyMs)

	If Not WaitClipboardIdle() Then
		MsgBox(16, "Error", "WaitClipboardIdle() timeout")
		Return SetError(-3, 0, 1)
	EndIf

	; Copy image on web to get the URL
	Local $hStarttime = TimerInit()
	While 1
		Send("^a")
		Sleep($opLatencyMs)
		Send("^c")
		Sleep($opLatencyMs)

		If Not WaitClipboardIdle() Then
			MsgBox(16, "Error", "WaitClipboardIdle() timeout")
			Return SetError(-4, 0, 1)
		EndIf

		Local $imageUrl = ParseRemoteImageUrlFromClip()
		If Not @error Then
			_log("Get image URL: " & $imageUrl)
			Sleep(_Max($opLatencyMs, 50))
			Send("{DEL}")
			Return $imageUrl
		EndIf

		If TimerDiff($hStarttime) > $IMAGE_UPLOAD_TIMEOUT Then
			_log("ERROR: Uploading image timeout")
			Return SetError(-5, 0, 0)
		EndIf

		If Not WebBrowserActive() Then Return SetError(-6, 0, 0)
	WEnd

	Return SetError(-7, 0, 0)
EndFunc   ;==>GetRemoteImageUrl

Func ParseRemoteImageUrlFromClip()

	Local $htmlBin = _ClipBoard_GetData($CLIP_HTML_FORMAT)
	If @error Then Return SetError(1, 0, 0)

	Local $html = BinaryToString($htmlBin, $SB_UTF8)
	Local $tempUrlList = StringRegExp($html, '(?i)src="(https?.*?)"', 1)
	If @error Then Return SetError(2, 0, 0)

	Return $tempUrlList[0]
EndFunc   ;==>ParseRemoteImageUrlFromClip

Func WebBrowserActive()
	$g_BrowserActive = WinActive($hWebBrowser)
	If Not $g_BrowserActive Then
		ErrorStatus("Web browser is not active")
	EndIf

	Return $g_BrowserActive
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
	ConsoleWrite(StringFormat("[%02d:%02d:%02d.%03d] ", @HOUR, @MIN, @SEC, @MSEC) & $Msg & @CRLF)
EndFunc   ;==>_Log


Func UpdateClipBoard($binary, $iFormat)
	Local $clipInfo[1][2]
	Local $enumFormat = 0, $i = 0, $iDataSize, $hMemory, $hLock, $tData

	If Not _ClipBoard_Open($hGui) Then Return SetError(-1, 0, 0)

	; Enumerate clipboard formats
	Do
		$enumFormat = _ClipBoard_EnumFormats($enumFormat)
		If $iFormat = 0 Then ExitLoop
		$i += 1
		$clipInfo[0][0] = $i
		ReDim $clipInfo[$i + 1][2]

		If $enumFormat = $iFormat Then
			$iDataSize = BinaryLen($binary) + 1
			$hMemory = _MemGlobalAlloc($iDataSize, $GHND)
			If $hMemory = 0 Then Return SetError(-1, 0, 0)

			If $g_hMemory Then
				_MemGlobalFree($g_hMemory)
			EndIf
			$g_hMemory = $hMemory

			$hLock = _MemGlobalLock($hMemory)
			If $hLock = 0 Then Return SetError(-2, 0, 0)

			$tData = DllStructCreate("byte[" & $iDataSize & "]", $hLock)
			DllStructSetData($tData, 1, $binary)
			_MemGlobalUnlock($hMemory)

		Else
			$hMemory = _ClipBoard_GetDataEx($enumFormat)
		EndIf


		$clipInfo[$i][0] = $hMemory
		$clipInfo[$i][1] = $enumFormat
	Until $enumFormat = 0

	If Not _ClipBoard_Empty() Then
		_ClipBoard_Close()
		Return SetError(-2, 0, 0)
	EndIf

	For $i = 1 To $clipInfo[0][0]
		If Not _ClipBoard_SetDataEx($clipInfo[$i][0], $clipInfo[$i][1]) Then
			_ClipBoard_Close()
			Return SetError(-7, 0, 0)
		EndIf
	Next

	_ClipBoard_Close()
EndFunc

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
	Return $ret
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

	If Not _ClipBoard_IsFormatAvailable($CF_BITMAP) Then Return SetError(1, 0, False)
	Return True
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
	Const $LR_COPYRETURNORG = 0x0004
	Const $LR_COPYDELETEORG = 0x0008

	Local $hBitmap2 = _GDIPlus_BitmapCreateHBITMAPFromBitmap($hImg)
	Local $hBitmap = _WinAPI_CopyImage($hBitmap2, 0, 0, 0, $LR_COPYDELETEORG + $LR_COPYRETURNORG)
	_WinAPI_DeleteObject($hBitmap2)
	Return $hBitmap
EndFunc   ;==>_GDIPlus_ImageCreateGDICompatibleHBITMAP



; #FUNCTION# ====================================================================================================================
; Name ..........: _ClipBoard_GetAll
; Description ...: Backup clipboard content
; Syntax ........: _ClipBoard_GetAll()
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
Func _ClipBoard_GetAll()

    Local $i = 0, $iFormat = 0, $hMem, $hMemNew, $pSource, $pDest, $iSize, $iErr = 0, $iErrEx = 0

    If $__bMemFree = True Then
        __MemFree()
    Else
        ReDim $avClip[1][2]
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
            __MemFree()
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
; Syntax ........: _ClipBoard_PutAll()
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
Func _ClipBoard_PutAll()

    ; DO NOT free the memory handles after a call to this function - the system now owns the memory
    Local $iErr = 0, $iErrEx = 0 ; , $bOpen, $iTime

    $__bMemFree = False

    If Not IsArray($avClip) Or UBound($avClip, 0) <> 2 Or $avClip[0][0] < 1 Then
        ReDim $avClip[1][2]
        Return SetError(1, 1, 0)
    EndIf

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
; Syntax ........: __MemFree()
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
Func __MemFree()

    Local $iErr = 0, $iErrEx = 0

    If $__bMemFree = False Then
        Return
    ElseIf Not IsArray($avClip) Or UBound($avClip, 0) <> 2 Or $avClip[0][0] < 1 Then
        ReDim $avClip[1][2]
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
    ReDim $avClip[1][2]

    If $iErr Then Return SetError($iErr, $iErrEx, 0)
    Return 1

EndFunc

; #FUNCTION# ====================================================================================================================
; Author ........: Paul Campbell (PaulIA)
; Modified.......: Gary Frost
; ===============================================================================================================================
Func _GDIPlus_BitmapCreateHBITMAPFromBitmap($hBitmap, $iARGB = 0xFF000000)
	Local $aResult = DllCall($__g_hGDIPDll, "int", "GdipCreateHBITMAPFromBitmap", "handle", $hBitmap, "handle*", 0, "dword", $iARGB)
	If @error Then Return SetError(@error, @extended, 0)
	If $aResult[0] Then Return SetError(10, $aResult[0], 0)

	Return $aResult[2]
EndFunc   ;==>_GDIPlus_BitmapCreateHBITMAPFromBitmap

; #FUNCTION# ====================================================================================================================
; Author.........: Yashied
; Modified.......: Jpm
; ===============================================================================================================================
Func _WinAPI_CopyImage($hImage, $iType = 0, $iXDesiredPixels = 0, $iYDesiredPixels = 0, $iFlags = 0)
	Local $aRet = DllCall('user32.dll', 'handle', 'CopyImage', 'handle', $hImage, 'uint', $iType, _
			'int', $iXDesiredPixels, 'int', $iYDesiredPixels, 'uint', $iFlags)
	If @error Then Return SetError(@error, @extended, 0)
	; If Not $aRet[0] Then Return SetError(1000, 0, 0)

	Return $aRet[0]
EndFunc   ;==>_WinAPI_CopyImage

; #FUNCTION# ====================================================================================================================
; Author ........: Paul Campbell (PaulIA)
; Modified.......:
; ===============================================================================================================================
Func _WinAPI_DeleteObject($hObject)
	Local $aResult = DllCall("gdi32.dll", "bool", "DeleteObject", "handle", $hObject)
	If @error Then Return SetError(@error, @extended, False)

	Return $aResult[0]
EndFunc   ;==>_WinAPI_DeleteObject

; #FUNCTION# ====================================================================================================================
; Author ........: ezzetabi and Jon
; Modified.......:
; ===============================================================================================================================
Func _IsPressed($sHexKey, $vDLL = "user32.dll")
	Local $aReturn = DllCall($vDLL, "short", "GetAsyncKeyState", "int", "0x" & $sHexKey)
	If @error Then Return SetError(@error, @extended, False)
	Return BitAND($aReturn[0], 0x8000) <> 0
EndFunc   ;==>_IsPressed

; #FUNCTION# ====================================================================================================================
; Author ........: Jeremy Landes <jlandes at landeserve dot com>
; Modified ......: guinness - Added ternary operator.
; ===============================================================================================================================
Func _Max($iNum1, $iNum2)
	; Check to see if the parameters are numbers
	If Not IsNumber($iNum1) Then Return SetError(1, 0, 0)
	If Not IsNumber($iNum2) Then Return SetError(2, 0, 0)
	Return ($iNum1 > $iNum2) ? $iNum1 : $iNum2
EndFunc   ;==>_Max


; #FUNCTION# ====================================================================================================================
; Author ........: Paul Campbell (PaulIA)
; Modified.......: Gary Frost, jpm, UEZ
; ===============================================================================================================================
Func _GDIPlus_Startup($sGDIPDLL = Default, $bRetDllHandle = False)
	$__g_iGDIPRef += 1
	If $__g_iGDIPRef > 1 Then Return True

	If $sGDIPDLL = Default Then $sGDIPDLL = "gdiplus.dll"

	$__g_hGDIPDll = DllOpen($sGDIPDLL)
	If $__g_hGDIPDll = -1 Then
		$__g_iGDIPRef = 0
		Return SetError(1, 2, False)
	EndIf

	Local $sVer = FileGetVersion($sGDIPDLL)
	$sVer = StringSplit($sVer, ".")
	If $sVer[1] > 5 Then $__g_bGDIP_V1_0 = False

	Local $tInput = DllStructCreate($tagGDIPSTARTUPINPUT)
	Local $tToken = DllStructCreate("ulong_ptr Data")
	DllStructSetData($tInput, "Version", 1)
	Local $aResult = DllCall($__g_hGDIPDll, "int", "GdiplusStartup", "struct*", $tToken, "struct*", $tInput, "ptr", 0)
	If @error Then Return SetError(@error, @extended, False)
	If $aResult[0] Then Return SetError(10, $aResult[0], False)

	$__g_iGDIPToken = DllStructGetData($tToken, "Data")
	If $bRetDllHandle Then Return $__g_hGDIPDll
	Return SetExtended($sVer[1], True)
EndFunc   ;==>_GDIPlus_Startup

; #FUNCTION# ====================================================================================================================
; Author ........: Paul Campbell (PaulIA)
; Modified.......: Gary Frost/martin
; ===============================================================================================================================
Func _GDIPlus_ImageLoadFromFile($sFileName)
	Local $aResult = DllCall($__g_hGDIPDll, "int", "GdipLoadImageFromFile", "wstr", $sFileName, "handle*", 0)
	If @error Then Return SetError(@error, @extended, 0)
	If $aResult[0] Then Return SetError(10, $aResult[0], 0)

	Return $aResult[2]
EndFunc   ;==>_GDIPlus_ImageLoadFromFile

; #FUNCTION# ====================================================================================================================
; Author ........: Paul Campbell (PaulIA)
; Modified.......: Gary Frost
; ===============================================================================================================================
Func _GDIPlus_ImageDispose($hImage)
	Local $aResult = DllCall($__g_hGDIPDll, "int", "GdipDisposeImage", "handle", $hImage)
	If @error Then Return SetError(@error, @extended, False)
	If $aResult[0] Then Return SetError(10, $aResult[0], False)

	Return True
EndFunc   ;==>_GDIPlus_ImageDispose

; #FUNCTION# ====================================================================================================================
; Author ........: Paul Campbell (PaulIA)
; Modified.......:
; ===============================================================================================================================
Func _GDIPlus_Shutdown()
	If $__g_hGDIPDll = 0 Then Return SetError(-1, -1, False)

	$__g_iGDIPRef -= 1
	If $__g_iGDIPRef = 0 Then
		DllCall($__g_hGDIPDll, "none", "GdiplusShutdown", "ulong_ptr", $__g_iGDIPToken)
		DllClose($__g_hGDIPDll)
		$__g_hGDIPDll = 0
	EndIf
	Return True
EndFunc   ;==>_GDIPlus_Shutdown