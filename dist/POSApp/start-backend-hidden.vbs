' Starts the POS backend without showing a console window.
' Args:
'   0 = app directory
'   1 = backend executable name
'   2 = log file path
Option Explicit

Dim shell, fso, appDir, backendExe, logPath, command

If WScript.Arguments.Count < 3 Then
  WScript.Quit 1
End If

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

appDir = WScript.Arguments.Item(0)
backendExe = WScript.Arguments.Item(1)
logPath = WScript.Arguments.Item(2)

If Not fso.FolderExists(appDir) Then
  WScript.Quit 2
End If

shell.CurrentDirectory = appDir

' cmd.exe owns stdout/stderr redirection for the backend process, but the cmd
' window itself is hidden (windowStyle=0) and the launcher returns immediately.
command = "%ComSpec% /d /s /c " & _
  """" & """" & appDir & "\" & backendExe & """" & _
  " 1>>" & """" & logPath & """" & _
  " 2>&1" & """"

shell.Run command, 0, False
