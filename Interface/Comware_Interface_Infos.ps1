#[string]$switchliste = "C:\Sysjobs\Switch\Interface\Switche.csv"
[string]$switchliste = "C:\Sysjobs\Switch\Switch-Backup.csv"
$switche = Import-Csv $switchliste -delimiter ";"

#####Spezielle Variaben (ja / nein)
$leere_ports_anzeigen = "nein"

#####Benutzerdefinierte Variablen
$log_pfad			= "C:\Sysjobs\Switch\Interface\Logs"
$export_pfad		= "C:\Sysjobs\Switch\Interface\Exporte"
$keyfile_pfad		= "C:\Sysjobs\Switch\Keyfiles"
$temp_pfad			= "C:\Sysjobs\Switch\Temp"
$plink_aufruf_name	= "plink.cmd"
$plink_cmd_datei	= "ssh-cmd.txt"
$tage				= 28

#####Ausgelesene Variablen
$datum = get-date -Format "yyyy-MM-dd_HHmm"
$datum_check = get-date
$alter = (get-date).AddDays(-$tage)

#Der im $app_pfad hinterlegte Ordner muss die pLink Applikation ("plink.exe") enthalten
$app_pfad = "C:\Sysjobs\Switch\SSH" 

$CRCFehler    = 0
$EMailAusgabe = ""


foreach ($switch in $switche){

	#####Importierte Variablen
	$switch_ip       = $switch.ip
	$switch_name     = $switch.name
	$switch_benutzer = $switch.switch_benutzer
	$switch_password = $switch.switch_passwort
	#####Diese Variablen müssen als Zahl Importiert werden
	[int]$switch_10gigports = $switch.anzahl_10gigabit
	[int]$switch_40gigports = $switch.anzahl_40gigabit
	[int]$switch_anzahl = $switch.anzahl_switche_im_stack

	#####E-Mail-Adresse für Benachrichtigungen
	$mailzu     = $switch.mail_zu
	$mailvon    = $switch.mail_von
	$mailserver = $switch.mailserver
		
	#####Generierte Variablen
	$alter = $datum_check.AddDays(-$tage)
	$export_datei_name = "$datum" + "_" + "$switch_name.csv"
	$export_datei = "$export_pfad" + "\" + "$export_datei_name"
	$plink_aufruf_pfad = "$temp_pfad" + "\" + "$switch_name"
	$plink_aufruf_datei = "$plink_aufruf_pfad" + "-" + "$plink_aufruf_name"
	$switch_befehle_zum_ausfuehren = "$temp_pfad" + "\" + "$plink_cmd_datei"
	$plink_aufruf_befehl = "echo y | $app_pfad" + "\" + "plink.exe -l $switch_benutzer -pw $switch_password -ssh $switch_ip -m $switch_befehle_zum_ausfuehren" 
	$plink_log_name = "$datum"+"_"+"$switch_name.log"
	$plink_log = "$log_pfad" + "\" + "$plink_log_name"

	#####Pfad der temporären Dateien erstellen
	new-item -path $temp_pfad -type directory -force
	#####LOG Pfad erstellen
	new-item -path $log_pfad -type directory -force

	#####plink Aufruf erstellen
	new-item -path $plink_aufruf_datei -type file -force
	add-content $plink_aufruf_datei '@echo off'
	add-content $plink_aufruf_datei "cd $app_pfad"
	add-content $plink_aufruf_datei "$plink_aufruf_befehl"

	#####switch Befehle zum Ausführen erstellen
	new-item -path $switch_befehle_zum_ausfuehren -type file -force

	#####Erzeugt die Port Befehle für die Switche im Stack

	foreach ($switche in 1..$switch_anzahl){

		#####Erzeugt die 10 Gigabit Port Befehle für den Switch
		if ( $switch_10gigports -gt 0){
			foreach ($tengigports in 1..$switch_10gigports){
				add-content $switch_befehle_zum_ausfuehren "display interface Ten-Gigabit $switche/0/$tengigports"
				#add-content $switch_befehle_zum_ausfuehren "show packet-drop interface Ten-Gigabit $switche/0/$tengigports"
				}
			}
		#####Erzeugt die 40 Gigabit Port Befehle für den Switch
		if ( $switch_40gigports -gt 0){
			for ($i=$switch_10gigports + 1; $i -le ($switch_10gigports + $switch_40gigports); $i++)
				{
				add-content $switch_befehle_zum_ausfuehren "display interface FortyGig $switche/0/$i"
				#add-content $switch_befehle_zum_ausfuehren "show packet-drop interface FortyGig $switche/0/$i"
				}
			}
		}

	##### Debug nicht aktivieren! #####
	##### Abbruch des Skriptes um nur die Dateien zu erzeugen
	#exit

	##### Skript ausfuehren und Logdatei erstellen
	#Write-Host "$plink_aufruf_datei >$plink_log"
	invoke-expression "$plink_aufruf_datei >$plink_log"

	#####Löschen der temporären Dateien
	remove-item $plink_aufruf_datei -recurse
	remove-item $switch_befehle_zum_ausfuehren -recurse

	#####CSV Datei mit Kopf erzeugen
	new-item -path $export_datei -type file -force
	add-content $export_datei "Switch Name;Interface Name;Interface Status;Interface Beschreibung;Interface last Flapping;Interface Input Peak im MBit;Interface Output Peak in MBit;Input Pause Frames; Output Pause Frames;CRC Fehler"


	##### Debug nicht aktivieren! #####
	##### Test mit einer vorgefertigten Ausgabe
	#$plink_log = "AUSGABE.TXT"

	##### Auslesen der Ausgabe der einzelnen Switche

	foreach ($switche in 1..$switch_anzahl){

		if ( $switch_10gigports -gt 0){
			foreach ($tenGig in 1..$switch_10gigports){
				$InterfaceIndex = $tenGig - 1

				##### Auslesen des Interface Status
				##### [$InterfaceIndex + (($switche-1)*$switch_10gigports) + (($switche-1)*$switch_40gigports)] -> Da ab em zweiten Switch die 10 Gigabit bzw. 40 Gigabit Ports beachtet werden müssen, erhöht sich der Index um die Anzahl der Ports, z.B. Ten1/0/1 = Index 0, wenn wir 48 10 Gigabit Ports pro Switch haben, wäre im zweiten Switch bei Ten2/0/1 der Index 0 + 48 vom vorhergehenden Switch.
				[STRING]$Status = (Get-Content -Path $plink_log | Select-String "Current state")[$InterfaceIndex + (($switche-1)*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$Status = $Status.Replace("Current state: ","")

				##### Wenn das Interface nicht UP ist wird dieses Interface Übergangen
				if ($leere_ports_anzeigen -notlike "ja") {if ($Status -notlike "UP"){continue}}

				##### Auslesen des Interface Namen
				##### [$InterfaceIndex + (($switche-1)*$switch_10gigports)] -> Da ab em zweiten Switch die 10 Gigabit Ports beachtet werden müssen (40 Gigabit fällt hier auf Grund der Abfrage raus (Ten-GigabitEthernet)), erhöht sich der Index um die Anzahl der Ports, z.B. Ten1/0/1 = Index 0, wenn wir 48 10 Gigabit Ports pro Switch haben, wäre im zweiten Switch bei Ten2/0/1 der Index 0 + 48 vom vorhergehenden Switch.
				$InterfaceName = (Get-Content -Path $plink_log | Select-String "Ten-GigabitEthernet" | Where-Object {$_ -notmatch "Description"})[$InterfaceIndex + (($switche-1)*$switch_10gigports)]

				##### Auslesen der Interface Beschreibung
				[STRING]$InterfaceDescription = (Get-Content -Path $plink_log| Select-String "Description:")[$InterfaceIndex + (($switche-1)*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$InterfaceDescription = $InterfaceDescription.Replace("Description: ","")

				##### Auslesen des letzen Interface Flappens
				[STRING]$InterfaceLastFlap = (Get-Content -Path $plink_log | Select-String "Last link flapping:")[$InterfaceIndex + (($switche-1)*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$InterfaceLastFlap = $InterfaceLastFlap.Replace("Last link flapping: ","")

				##### Ersetzen der englischen Datumsangaben durch deutsche Datumsangaben
				$InterfaceLastFlap = $InterfaceLastFlap.Replace("weeks","Wochen")
				$InterfaceLastFlap = $InterfaceLastFlap.Replace("days","Tage")
				$InterfaceLastFlap = $InterfaceLastFlap.Replace("hours","Stunden")
				$InterfaceLastFlap = $InterfaceLastFlap.Replace("minutes","Minuten")

				##### Auslesen der Eingangsspitze des Interfaces
				[STRING]$InterfaceInputPeak = (Get-Content -Path $plink_log | Select-String "Peak input rate:")[$InterfaceIndex + (($switche-1)*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$InterfaceInputPeak = $InterfaceInputPeak.Replace(" Peak input rate: ","")

				##### Löscht alles nach dem ersten Leerzeichen um die Byte Anzahl zu erhalten.
				$InterfaceInputPeak = $InterfaceInputPeak.Substring(0,$InterfaceInputPeak.IndexOf(" "))

				##### Wandelt den String wieder in eine Zahl um und Rechnet es in MBit/s um
				[int]$InterfaceInputPeak = [convert]::ToInt32($InterfaceInputPeak, 10)
				$InterfaceInputPeak = ((($InterfaceInputPeak*8)/1024)/1024)

				##### Auslesen der Ausgangsspitze des Interfaces
				[STRING]$InterfaceOutputPeak = (Get-Content -Path $plink_log | Select-String "Peak output rate:")[$InterfaceIndex + (($switche-1)*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$InterfaceOutputPeak = $InterfaceOutputPeak.Replace(" Peak output rate: ","")

				##### Löscht alles nach dem ersten Leerzeichen um die Byte Anzahl zu erhalten.
				$InterfaceOutputPeak = $InterfaceOutputPeak.Substring(0,$InterfaceOutputPeak.IndexOf(" "))

				##### Wandelt den String wieder in eine Zahl um und Rechnet es in MBit/s um
				[int]$InterfaceOutputPeak = [convert]::ToInt32($InterfaceOutputPeak, 10)
				$InterfaceOutputPeak = ((($InterfaceOutputPeak*8)/1024)/1024)

				##### Auslesen der Pause Frames der eingehenenden Pakete des Interfaces
				#####([0+$InterfaceIndex*4] = Da in jedem Abschnitt 4x Pause vorkommt wird nach dem ersten Durchlauf immer eine 4 dazugerechnet, Port 24 = 0 + 24*4)
				#####([0+$InterfaceIndex*4 + (($switche-1)*4*$switch_10gigports) + (($switche-1)*4*$switch_40gigports)] = Ab dem zweiten Switch werden 4 x die Anzahl der 10 Gigabit Port und jeweils 4 x die Anzahl der 40 Gigabit Ports dazu addiert usw. usw.)
				[STRING]$InterfaceInputPause = (Get-Content -Path $plink_log | Select-String "pauses")[0+$InterfaceIndex*4 + (($switche-1)*4*$switch_10gigports) + (($switche-1)*4*$switch_40gigports)]

				##### Liest nur die Anzahl der Pause Frames aus dem String (+12 ist das wort multicasts und ein Leerzeichen und -7 ist pauses und ein Leerzeichen)
				$InputPauseStart = $InterfaceInputPause.IndexOf("multicasts") + 12
				$InputPauseLaenge = $InterfaceInputPause.Length - $InputPauseStart -7
				$InterfaceInputPause = $InterfaceInputPause.Substring($InputPauseStart,$InputPauseLaenge)

				##### Auslesen der Pause Frames der ausgehenden Pakete des Interfaces ([$InterfaceIndex+$InterfaceIndex*4] = Da in jedem Abschnitt 4x Pause vorkommt wird nach dem ersten Durchlauf immer eine 4 dazugerechnet und da hier nicht das erste sondern dritte Pause gesucht wird addieren wir 2 hinzu) 
				[STRING]$InterfaceOutputPause = (Get-Content -Path $plink_log | Select-String "pauses")[2+$InterfaceIndex*4 + (($switche-1)*4*$switch_10gigports) + (($switche-1)*4*$switch_40gigports)]

				##### Liest nur die Anzahl der Pause Frames aus dem String (+12 ist das wort multicasts und ein Leerzeichen und -7 ist pauses und ein Leerzeichen)
				$OutputPauseStart = $InterfaceOutputPause.IndexOf("multicasts") + 12
				$OutputPauseLaenge = $InterfaceOutputPause.Length - $OutputPauseStart -7
				$InterfaceOutputPause = $InterfaceOutputPause.Substring($OutputPauseStart,$OutputPauseLaenge)

				##### Auslesen der CRC Fehler der eingehenden Pakete des Interfaces
				[STRING]$InterfaceInputCRC = (Get-Content -Path $plink_log | Select-String "CRC")[$InterfaceIndex + (($switche-1)*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 

				##### Liest nur die Anzahl der CRC Fehler aus dem String
				$InterfaceInputCRC = $InterfaceInputCRC.Substring(0,$InterfaceInputCRC.IndexOf("CRC"))
				$InterfaceInputCRC = $InterfaceInputCRC.replace(' ','')
				$InterfaceInputCRC = $InterfaceInputCRC.replace("`t","")

				##### Hängt die Daten an die CSV Datei an
				add-content $export_datei "$switch_name;$InterfaceName;$Status;$InterfaceDescription;$InterfaceLastFlap;$InterfaceInputPeak;$InterfaceOutputPeak;$InterfaceInputPause;$InterfaceOutputPause;$InterfaceInputCRC"

				### Wenn es CRC Fheler gibt soll eine Email versendet werden
				if ($InterfaceInputCRC -gt 0){
					$EMailAusgabe = $EMailAusgabe + "Switchname:`t`t$switch_name`nInterface Name:`t$InterfaceName`nAnzahl CRC Fehler:`t$InterfaceInputCRC`n`n"
					$CRCFehler = 1
				}
			}
		}

		if ( $switch_40gigports -gt 0){
			foreach ($fortyGig in 1..$switch_40gigports){
				$InterfaceIndex = $fortyGig - 1

				##### Auslesen des Interface Status
				[STRING]$Status = (Get-Content -Path $plink_log | Select-String "Current state")[$InterfaceIndex + ($switche*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$Status = $Status.Replace("Current state: ","")

				##### Wenn das Interface nicht UP ist wird dieses Interface Übergangen
				if ($leere_ports_anzeigen -notlike "ja") {if ($Status -notlike "UP"){continue}}

				##### Auslesen des Interface Namen
				$InterfaceName = (Get-Content -Path $plink_log | Select-String "FortyGigE" | Where-Object {$_ -notmatch "Description"})[$InterfaceIndex + (($switche-1)*$switch_40gigports)]

				##### Auslesen der Interface Beschreibung
				[STRING]$InterfaceDescription = (Get-Content -Path $plink_log| Select-String "Description:")[$InterfaceIndex + ($switche*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$InterfaceDescription = $InterfaceDescription.Replace("Description: ","")

				##### Auslesen des letzen Interface Flappens
				[STRING]$InterfaceLastFlap = (Get-Content -Path $plink_log | Select-String "Last link flapping:")[$InterfaceIndex + ($switche*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$InterfaceLastFlap = $InterfaceLastFlap.Replace("Last link flapping: ","")

				##### Ersetzen der englischen Datumsangaben durch deutsche Datumsangaben
				$InterfaceLastFlap = $InterfaceLastFlap.Replace("weeks","Wochen")
				$InterfaceLastFlap = $InterfaceLastFlap.Replace("days","Tage")
				$InterfaceLastFlap = $InterfaceLastFlap.Replace("hours","Stunden")
				$InterfaceLastFlap = $InterfaceLastFlap.Replace("minutes","Minuten")

				##### Auslesen der Eingangsspitze des Interfaces
				[STRING]$InterfaceInputPeak = (Get-Content -Path $plink_log | Select-String "Peak input rate:")[$InterfaceIndex + ($switche*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$InterfaceInputPeak = $InterfaceInputPeak.Replace(" Peak input rate: ","")

				##### Löscht alles nach dem ersten Leerzeichen um die Byte Anzahl zu erhalten.
				$InterfaceInputPeak = $InterfaceInputPeak.Substring(0,$InterfaceInputPeak.IndexOf(" "))

				##### Wandelt den String wieder in eine Zahl um und Rechnet es in MB um
				[int]$InterfaceInputPeak = [convert]::ToInt32($InterfaceInputPeak, 10)
				$InterfaceInputPeak = $InterfaceInputPeak/1MB

				##### Auslesen der Ausgangsspitze des Interfaces
				[STRING]$InterfaceOutputPeak = (Get-Content -Path $plink_log | Select-String "Peak output rate:")[$InterfaceIndex + ($switche*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$InterfaceOutputPeak = $InterfaceOutputPeak.Replace(" Peak output rate: ","")

				##### Löscht alles nach dem ersten Leerzeichen um die Byte Anzahl zu erhalten.
				$InterfaceOutputPeak = $InterfaceOutputPeak.Substring(0,$InterfaceOutputPeak.IndexOf(" "))

				##### Wandelt den String wieder in eine Zahl um und Rechnet es in MB um
				[int]$InterfaceOutputPeak = [convert]::ToInt32($InterfaceOutputPeak, 10)
				$InterfaceOutputPeak = $InterfaceOutputPeak/1MB

				##### Auslesen der Pause Frames der eingehenenden Pakete des Interfaces	([$InterfaceIndex+$InterfaceIndex*4] = Da in jedem Abschnitt 4x Pause vorkommt wird nach dem ersten Durchlauf immer eine 4 dazugerechnet) 
				[STRING]$InterfaceInputPause = (Get-Content -Path $plink_log | Select-String "pauses")[0+$InterfaceIndex*4 + ($switche*4*$switch_10gigports) + (($switche-1)*4*$switch_40gigports)]

				##### Liest nur die Anzahl der Pause Frames aus dem String (+12 ist das wort multicasts und ein Leerzeichen und -7 ist pauses und ein Leerzeichen)
				$InputPauseStart = $InterfaceInputPause.IndexOf("multicasts") + 12
				$InputPauseLaenge = $InterfaceInputPause.Length - $InputPauseStart -7
				$InterfaceInputPause = $InterfaceInputPause.Substring($InputPauseStart,$InputPauseLaenge)

				##### Auslesen der Pause Frames der ausgehenden Pakete des Interfaces ([$InterfaceIndex+$InterfaceIndex*4] = Da in jedem Abschnitt 4x Pause vorkommt wird nach dem ersten Durchlauf immer eine 4 dazugerechnet und da hier nicht das erste sondern dritte Pause gesucht wird addieren wir 2 hinzu) 
				[STRING]$InterfaceOutputPause = (Get-Content -Path $plink_log | Select-String "pauses")[2+$InterfaceIndex*4 + ($switche*4*$switch_10gigports) + (($switche-1)*4*$switch_40gigports)]

				##### Liest nur die Anzahl der Pause Frames aus dem String (+12 ist das wort multicasts und ein Leerzeichen und -7 ist pauses und ein Leerzeichen)
				$OutputPauseStart = $InterfaceOutputPause.IndexOf("multicasts") + 12
				$OutputPauseLaenge = $InterfaceOutputPause.Length - $OutputPauseStart -7
				$InterfaceOutputPause = $InterfaceOutputPause.Substring($OutputPauseStart,$OutputPauseLaenge)

				##### Auslesen der CRC Fehler der eingehenden Pakete des Interfaces
				[STRING]$InterfaceInputCRC = (Get-Content -Path $plink_log | Select-String "CRC")[$InterfaceIndex + ($switche*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 

				##### Liest nur die Anzahl der CRC Fehler aus dem String
				$InterfaceInputCRC = $InterfaceInputCRC.Substring(0,$InterfaceInputCRC.IndexOf("CRC"))
				$InterfaceInputCRC = $InterfaceInputCRC.replace(' ','')
				$InterfaceInputCRC = $InterfaceInputCRC.replace("`t","")

				##### Hängt die Daten an die CSV Datei an
				add-content $export_datei "$switch_name;$InterfaceName;$Status;$InterfaceDescription;$InterfaceLastFlap;$InterfaceInputPeak;$InterfaceOutputPeak;$InterfaceInputPause;$InterfaceOutputPause;$InterfaceInputCRC"

				### Wenn es CRC Fheler gibt soll eine Email versendet werden
				if ($InterfaceInputCRC -gt 0){
					$EMailAusgabe = $EMailAusgabe + "Switchname:`t`t$switch_name`nInterface Name:`t$InterfaceName`nAnzahl CRC Fehler:`t$InterfaceInputCRC`n`n"
					$CRCFehler = 1
				}

			}
		}

		#exit

	}
}

#####E-Mail versenden mit dem CSV
if ( $CRCFehler -gt 0){
	$mailnachricht = new-object Net.Mail.MailMessage
	$mailanhang = new-object Net.Mail.Attachment($export_datei)
	$mail = new-object Net.Mail.SmtpClient($mailserver)
	$mailnachricht.From = "$mailvon"
	$mailnachricht.To.Add("$mailzu")
	$mailnachricht.Subject = "Es wurden CRC Fehler gefunden"
	$mailnachricht.Body = $EMailAusgabe
	#$mailnachricht.Attachments.Add($mailanhang)
	$mail.send($mailnachricht)
	$mailnachricht.Dispose(); 
	$mailanhang.Dispose();
}



#####Alte Logs loeschen
$dateien = get-childitem $log_pfad -include *.* -recurse | Where {$_.LastWriteTime -le "$alter"}

foreach ($datei in $dateien)
{write-host "Loesche Datei $datei" -foregroundcolor "Red"; Remove-Item $datei.FullName | out-null} 

#####Alte Exports loeschen
$dateien = get-childitem $export_pfad -include *.* -recurse | Where {$_.LastWriteTime -le "$alter"}

foreach ($datei in $dateien)
{write-host "Loesche Datei $datei" -foregroundcolor "Red"; Remove-Item $datei.FullName | out-null} 
