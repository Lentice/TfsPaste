#AutoIt3Wrapper_icon=minion.ico
#AutoIt3Wrapper_Res_Description=TFS Paster
#AutoIt3Wrapper_Res_Fileversion=2.0.0.1
#AutoIt3Wrapper_Res_Fileversion_AutoIncrement=y
#AutoIt3Wrapper_UseX64=n
#AutoIt3Wrapper_Au3Check_Parameters= -d -w 1 -w 2 -w 3 -w 4 -w 5 -w 6
#AutoIt3Wrapper_Run_Au3Stripper=y
#Au3Stripper_Parameters=/mo /rsln

#include <Clipboard.au3>
#include <Array.au3>
#include <Inet.au3>
#include <FileConstants.au3>

Opt("TrayAutoPause", 0) ;0=no pause, 1=Pause

Global Const $LOG_PATH = @TempDir & "\TFS Paster\Log"
Global Const $INI_FILE = @ScriptDir & "\Config.ini"

Global $sourceUrl = ""
Global $g_saveBinary = True
Global $g_hMemory = False

Global $CLIP_HTML_FORMAT = _ClipBoard_RegisterFormat("HTML Format")
If @error Then
	MsgBox(16, "Error", "_ClipBoard_RegisterFormat() retruns error.")
	Exit
EndIf

OnAutoItExitRegister("__APP_EXIT")
_Log("LogPath: " & $LOG_PATH)
Main()
Exit
;#######################################################

Func __APP_EXIT()
	If $g_hMemory Then
		_MemGlobalFree($g_hMemory)
	EndIf
EndFunc

Func Main()
	ToolTip("TFS Paster: Processing...")
	ParseCmdParams()
	_Log("SaveBinary: " & $g_saveBinary)

	_Log("Wating clipboard idle...")
	If Not WaitClipboardIdle() Then
		MsgBox(16, "Error", "WaitClipboardIdle() timeout")
		Return SetError(-1, 0, 1)
	EndIf

	Local $htmlBin = _ClipBoard_GetData($CLIP_HTML_FORMAT)
	If @error Then
		_Log("Cannot get html format from clipboard")
		Return SetError(-2, 0, 2)
	EndIf

	If $g_saveBinary Then
		SaveBinToFile("Source.html", $htmlBin)
	EndIf

	Local $orignalHtml = BinaryToString($htmlBin, $SB_UTF8)
	GetSourceUrl($orignalHtml)

	Local $patchedHtmlStr = PreShrinkHtml($orignalHtml)
	$patchedHtmlStr= patchImages($patchedHtmlStr)
	$patchedHtmlStr = PostShrinkHtml($patchedHtmlStr)
	$patchedHtmlStr = UpdateHeaderDescription($patchedHtmlStr)

	_Log("Update Clipboard")
	Local $patchedBin = StringToBinary($patchedHtmlStr, $SB_UTF8)
	UpdateClipBoard($patchedBin, $CLIP_HTML_FORMAT)

	Sleep(20)
	If $g_saveBinary Then
		SaveBinToFile("Patched.html", $patchedBin)
	EndIf

	_Log("DONE")
	ToolTip("TFS Paster: Clipboard Updated")
	Sleep(1000)
EndFunc   ;==>DoPaste

Func ParseCmdParams()
	If $CmdLine[0] > 0 And StringCompare($CmdLine[1], "QuietOnce") = 0 Then
		$g_saveBinary = False
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

	$htmlData = StringRegExpReplace($htmlData, '(?s)(<!--\s*(?!StartFragment|EndFragment).*?-->)', "")
	$htmlData = StringRegExpReplace($htmlData, '(?s)(<link(?>\s|\r?\n).*?href=.*?>\s*\r?\n?)', "")

;~ 	$htmlData = StringRegExpReplace($htmlData, '(?s)(\n|\s)lang=([^\x22\x27].*?)(\s|>|\r?\n)', '$1lang="$2"$3')
;~ 	$htmlData = StringRegExpReplace($htmlData, '(?s)(\n|\s)class=([^\x22\x27].*?)(\s|>|\r?\n)', '$1class="$2"$3')

	$htmlData = StringRegExpReplace($htmlData, '(?s)<!\[if !supportLists\]>(.*?)<!\[endif\]>', "$1")

	Return $htmlData
EndFunc

Func PostShrinkHtml($htmlData)
;~ 	$htmlData = StringRegExpReplace($htmlData, '(?s)<v:shapetype(?>>|(?>\s|\r?\n).*?>)(.*?)<\/v:shapetype>', "")

	$htmlData = StringRegExpReplace($htmlData, '(?s)<v:\w*(?>>|(?>\s|\r?\n).*?>)(.*?)<\/v:\w*>', "")
	$htmlData = StringRegExpReplace($htmlData, "(?s)[\s\n]style=[\x22\x27]mso-bookmark:(\r?\n)?OLE_LINK\d[\x22\x27]", "")

	; mask since can't patch nest tags isuue
;~ 	$htmlData = StringRegExpReplace($htmlData, '(?s)<o:p(?>>|(?>\s|\r?\n).*?>)(.*?)<\/o:p>', "$1")
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
		If _ClipBoard_Open(0) Then
			_ClipBoard_Close()
			Return True
		EndIf

		Sleep(10)
	Until TimerDiff($hTimer) > $TIMEOUT

	Return SetError(1, 0, False)
EndFunc

Func PatchImages($html)
	$html = PathExistImg($html)
	$html = PatchVShape($html)

	Return $html
EndFunc

Func PathExistImg($html)
	Local $imgList, $img, $newImg, $filePath, $dataType, $base64

	; patch <img>
	$imgList = StringRegExp($html, '(?s)(<img[^>]+src="[^">]+".*?>)', 3)
	For $i = 0 To UBound($imgList) - 1
		$img = $imgList[$i]
		Local $fileInfo = GetSrcFromHtml($img, 'img')
		If @error <> 0 Then ContinueLoop

		$filePath = $fileInfo[0]
		$dataType = GetDataTypeFromFileType($fileInfo[1])

		$base64 = GetBase64($filePath)
		If @error Then ContinueLoop

		$newImg = StringRegExpReplace($img, '(\s|\n)src="[^"]+"', '$1src="data:' & $dataType & ';base64,' & $base64 & '"')
		$html = StringReplace($html, $img, $newImg)
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
			$html = StringReplace($html, $vs, $img)
		EndIf
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

	Local $filePath = $fileInfo[0]
	Local $dataType = GetDataTypeFromFileType($fileInfo[1])
	Local $attrWidth = "", $attrHeight = ""

	Local $width = GetStyleValueFromHtml($html, 'width', True)
	If Not @error Then
		$attrWidth = ' width="' & $width & '"'
	EndIf

	Local $height = GetStyleValueFromHtml($html, 'height', True)
	If Not @error Then
		$attrHeight = ' height="' & $height & '"'
	EndIf

	Local $base64 = GetBase64($filePath)
	If @error Then
		_log("ERROR: bad Base64")
		Return SetError(-2, 0, "")
	EndIf

	Local $img = '<img ' & $attrWidth & $attrHeight & ' src="data:' & $dataType & ';base64,' & $base64 & '">'
	return $img
EndFunc

Func GetDataTypeFromFileType($fileType)
	Local $dataType
	Switch $fileType
		Case "jpg" Or "jpeg" Or "jfif" Or "pjpeg" Or "pjp"
			$dataType = "image/jpeg"
		Case "svg"
			$dataType = "image/svg+xml"
		Case "tif" Or "tiff"
			$dataType = "image/tiff"
		Case "ico" Or "cur"
			$dataType = "image/x-icon"
		Case Else
			$dataType = "image/" & $fileType
	EndSwitch

	Return $dataType
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

	Local $file = FileOpen($LOG_PATH & "\" & $filename, $FO_OVERWRITE + $FO_UTF8)
	FileWrite($file, $binary)
	FileClose($file)
EndFunc

Func GetBase64($path)
	Local $file, $dat, $objXML, $objNode, $aArray, $appendSourceUrl = False

	Do
		$aArray = StringRegExp($path, '^https?:\/\/.*', 1)
		If Not @error Then
			$path = StringReplace($path, "&amp;", "&")
			_Log("URL: " & $path)
			$dat = InetRead($path, 8)
			If @error Then
				_Log("Get URL fail")
				Return SetError(-1, 0, "")
			EndIf
			ExitLoop
		EndIf

		$aArray = StringRegExp($path, '^file:\/\/+(.*)', 1)
		If Not @error Then
			_Log("File: " & $aArray[0])
			$file = FileOpen($aArray[0], 16)
			If $file = -1 Then
				_Log("Open file fail")
				Return SetError(-2, 0, "")
			EndIf

			$dat = FileRead($file)
			ExitLoop
		EndIf

		If Not $appendSourceUrl Then
			$aArray = StringRegExp($sourceUrl, '(?sm)((?>file:\/+|https?:\/\/).*\/).*', 1)
			If @error Then Return SetError(-3, 0, "")

			$path = $aArray[0] & $path
			$appendSourceUrl = True
			_Log("Append source url: " & $path)
			ContinueLoop
		EndIf

		Return SetError(-4, 0, "")
	Until False

	$objXML = ObjCreate("MSXML2.DOMDocument")
	$objNode = $objXML.createElement("b64")
	$objNode.dataType= "bin.base64"
	$objNode.nodeTypedValue = $dat

	Return StringRegExpReplace($objNode.Text, '(?s)\r?\n', "")
EndFunc

Func _Log($Msg)
	ConsoleWrite(StringFormat("[%02d:%02d:%02d.%03d] ", @HOUR, @MIN, @SEC, @MSEC) & $Msg & @CRLF)
EndFunc   ;==>_Log


Func UpdateClipBoard($binary, $iFormat)
	Local $clipInfo[1][2]
	Local $enumFormat = 0, $i = 0, $iDataSize, $hMemory, $hLock, $tData

	If Not _ClipBoard_Open(0) Then Return SetError(-1, 0, 0)

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


;~ Func UpdateClipBoard($binary, $iFormat)
;~ 	Local $clipInfo[1][2]
;~ 	Local $enumFormat = 0, $i = 0, $iDataSize, $hMemory, $pMemoryBlock, $hLock, $tData

;~ 	If Not _ClipBoard_Open(0) Then Return SetError(-1, 0, 0)

;~ 	; Enumerate clipboard formats
;~ 	Do
;~ 		$enumFormat = _ClipBoard_EnumFormats($enumFormat)
;~ 		If $iFormat = 0 Then ExitLoop
;~ 		Local $saveBinary
;~ 		If $enumFormat = $iFormat Then
;~ 			$saveBinary = $binary
;~ 		Else
;~ 			$hMemory = _ClipBoard_GetDataEx($enumFormat)
;~ 			$pMemoryBlock = _MemGlobalLock($hMemory)
;~ 			$iDataSize = _MemGlobalSize($hMemory)
;~ 			If $iDataSize = 0 Then
;~ 				_MemGlobalUnlock($hMemory)
;~ 				ContinueLoop
;~ 			EndIf
;~ 			$tData = DllStructCreate("byte[" & $iDataSize & "]", $pMemoryBlock)
;~ 			$saveBinary = DllStructGetData($tData, 1)
;~ 		EndIf

;~ 		$i += 1
;~ 		$clipInfo[0][0] = $i
;~ 		ReDim $clipInfo[$i + 1][2]
;~ 		$clipInfo[$i][0] = $saveBinary
;~ 		$clipInfo[$i][1] = $enumFormat
;~ 	Until $enumFormat = 0

;~ 	If Not _ClipBoard_Empty() Then
;~ 		_ClipBoard_Close()
;~ 		Return SetError(-2, 0, 0)
;~ 	EndIf

;~ 	For $i = 1 To $clipInfo[0][0]
;~ 		$iDataSize = BinaryLen($clipInfo[$i][0]) + 1
;~ 		$hMemory = _MemGlobalAlloc($iDataSize, $GHND)
;~ 		If $hMemory = 0 Then Return SetError(-1, 0, 0)

;~ 		$hLock = _MemGlobalLock($hMemory)
;~ 		If $hLock = 0 Then Return SetError(-2, 0, 0)

;~ 		$tData = DllStructCreate("byte[" & $iDataSize & "]", $hLock)
;~ 		DllStructSetData($tData, 1, $clipInfo[$i][0])
;~ 		_MemGlobalUnlock($hMemory)

;~ 		If Not _ClipBoard_SetDataEx($hMemory, $clipInfo[$i][1]) Then
;~ 			_ClipBoard_Close()
;~ 			Return SetError(-7, 0, 0)
;~ 		EndIf
;~ 	Next

;~ 	_ClipBoard_Close()
;~ EndFunc
