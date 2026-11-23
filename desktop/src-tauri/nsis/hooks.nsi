; NSIS Installer Hooks for ClipSync
; Automatically manages Windows Firewall rules for seamless local network connectivity

!macro customInstall
  DetailPrint "Configuring Windows Firewall rule for ClipSync..."
  ExecWait 'netsh advfirewall firewall add rule name="ClipSync" dir=in action=allow protocol=TCP localport=47821 program="$INSTDIR\clipsync-desktop.exe"'
!macroend

!macro customUnInstall
  DetailPrint "Removing Windows Firewall rule for ClipSync..."
  ExecWait 'netsh advfirewall firewall delete rule name="ClipSync"'
!macroend
