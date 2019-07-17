[string]$switchliste = "C:\Sysjobs\Switch\Switch-Backup.csv"
$switche = Import-Csv $switchliste -delimiter ";"

#####Spezielle Variaben (ja / nein)
$leere_ports_anzeigen = "nein"

#####Benutzerdefinierte Variablen
$log_pfad          = "C:\Sysjobs\Switch\Interface\Logs"
$export_pfad       = "C:\Sysjobs\Switch\Interface\Exporte"
$keyfile_pfad      = "C:\Sysjobs\Switch\Keyfiles"
$temp_pfad         = "C:\Sysjobs\Switch\Temp"
$plink_aufruf_name = "plink_drop.cmd"
$plink_cmd_datei   = "ssh-cmd_drop.txt"
$tage              = 28

#####Ausgelesene Variablen
$datum       = get-date -Format "yyyy-MM-dd_HHmm"
$datum_check = get-date
$alter       = (get-date).AddDays(-$tage)

#Der im $app_pfad hinterlegte Ordner muss die pLink Applikation ("plink.exe") enthalten
$app_pfad = "C:\Sysjobs\Switch\SSH" 

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
	$export_datei_name = "$datum" + "_" + "$switch_name" + "_Drop.csv"
	$export_datei = "$export_pfad" + "\" + "$export_datei_name"
	$plink_aufruf_pfad = "$temp_pfad" + "\" + "$switch_name"
	$plink_aufruf_datei = "$plink_aufruf_pfad" + "-" + "$plink_aufruf_name"
	$switch_befehle_zum_ausfuehren = "$temp_pfad" + "\" + "$plink_cmd_datei"
	$plink_aufruf_befehl = "echo y | $app_pfad" + "\" + "plink.exe -l $switch_benutzer -pw $switch_password -ssh $switch_ip -m $switch_befehle_zum_ausfuehren" 
	$plink_log_name = "$datum"+"_"+"$switch_name" + "_Drop.log"
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
				#add-content $switch_befehle_zum_ausfuehren "display interface Ten-Gigabit $switche/0/$tengigports"
				add-content $switch_befehle_zum_ausfuehren "show packet-drop interface Ten-Gigabit $switche/0/$tengigports"
				}
			}
		#####Erzeugt die 40 Gigabit Port Befehle für den Switch
		if ( $switch_40gigports -gt 0){
			for ($i=$switch_10gigports + 1; $i -le ($switch_10gigports + $switch_40gigports); $i++)
				{
				#add-content $switch_befehle_zum_ausfuehren "display interface FortyGig $switche/0/$i"
				add-content $switch_befehle_zum_ausfuehren "show packet-drop interface FortyGig $switche/0/$i"
				}
			}
		}

	##### Debug nicht aktivieren! #####
	##### Abbruch des Skriptes um nur die Dateien zu erzeugen
	#exit

	##### Skript ausfuehren und Logdatei erstellen
	invoke-expression "$plink_aufruf_datei >$plink_log"

	#####Löschen der temporären Dateien
	remove-item $plink_aufruf_datei -recurse
	remove-item $switch_befehle_zum_ausfuehren -recurse

	#####CSV Datei mit Kopf erzeugen
	new-item -path $export_datei -type file -force
	add-content $export_datei "Switch Name;Interface Name;Drop wegen GBP;Drop wegen FFP;Drop wegen STP;ungenuegent Eingangsspeicher;ungenuegend Ausgangsspeicher;Markiert als ECN"


	##### Debug nicht aktivieren! #####
	##### Test mit einer vorgefertigten Ausgabe
	#$plink_log = "AUSGABE.TXT"

	##### Auslesen der Ausgabe der einzelnen Switche

	foreach ($switche in 1..$switch_anzahl){

		if ( $switch_10gigports -gt 0){
			foreach ($tenGig in 1..$switch_10gigports){
				$InterfaceIndex = $tenGig - 1

				##### Interface Name auslesen
				[STRING]$InterfaceName = (Get-Content -Path $plink_log | Select-String "Ten-GigabitEthernet")[$InterfaceIndex + (($switche-1)*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$InterfaceName = $InterfaceName.Replace(":","")

				##### Auslesen Drop GBP
				##### [$InterfaceIndex + (($switche-1)*$switch_10gigports) + (($switche-1)*$switch_40gigports)] -> Da ab em zweiten Switch die 10 Gigabit bzw. 40 Gigabit Ports beachtet werden müssen, erhöht sich der Index um die Anzahl der Ports, z.B. Ten1/0/1 = Index 0, wenn wir 48 10 Gigabit Ports pro Switch haben, wäre im zweiten Switch bei Ten2/0/1 der Index 0 + 48 vom vorhergehenden Switch.
				[STRING]$Drop_GBP = (Get-Content -Path $plink_log | Select-String "insufficient bandwidth")[$InterfaceIndex + (($switche-1)*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$Drop_GBP = $Drop_GBP.Replace("  Packets dropped due to full GBP or insufficient bandwidth: ","")

				##### Auslesen Drop FFP
				##### [$InterfaceIndex + (($switche-1)*$switch_10gigports)] -> Da ab em zweiten Switch die 10 Gigabit Ports beachtet werden müssen (40 Gigabit fällt hier auf Grund der Abfrage raus (Ten-GigabitEthernet)), erhöht sich der Index um die Anzahl der Ports, z.B. Ten1/0/1 = Index 0, wenn wir 48 10 Gigabit Ports pro Switch haben, wäre im zweiten Switch bei Ten2/0/1 der Index 0 + 48 vom vorhergehenden Switch.
				[STRING]$Drop_FFP = (Get-Content -Path $plink_log | Select-String "(FFP)")[$InterfaceIndex + (($switche-1)*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$Drop_FFP = $Drop_FFP.Replace("  Packets dropped due to Fast Filter Processor (FFP): ","")

				##### Auslesen Drop STP
				##### [$InterfaceIndex + (($switche-1)*$switch_10gigports)] -> Da ab em zweiten Switch die 10 Gigabit Ports beachtet werden müssen (40 Gigabit fällt hier auf Grund der Abfrage raus (Ten-GigabitEthernet)), erhöht sich der Index um die Anzahl der Ports, z.B. Ten1/0/1 = Index 0, wenn wir 48 10 Gigabit Ports pro Switch haben, wäre im zweiten Switch bei Ten2/0/1 der Index 0 + 48 vom vorhergehenden Switch.
				[STRING]$Drop_STP = (Get-Content -Path $plink_log | Select-String "non-forwarding state")[$InterfaceIndex + (($switche-1)*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$Drop_STP = $Drop_STP.Replace("  Packets dropped due to STP non-forwarding state: ","")

				##### Auslesen Mark ECN
				##### [$InterfaceIndex + (($switche-1)*$switch_10gigports)] -> Da ab em zweiten Switch die 10 Gigabit Ports beachtet werden müssen (40 Gigabit fällt hier auf Grund der Abfrage raus (Ten-GigabitEthernet)), erhöht sich der Index um die Anzahl der Ports, z.B. Ten1/0/1 = Index 0, wenn wir 48 10 Gigabit Ports pro Switch haben, wäre im zweiten Switch bei Ten2/0/1 der Index 0 + 48 vom vorhergehenden Switch.
				[STRING]$Drop_ECN = (Get-Content -Path $plink_log | Select-String "to ECN")[$InterfaceIndex + (($switche-1)*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$Drop_ECN = $Drop_ECN.Replace("  Packets marked due to ECN: ","")

				##### Hängt die Daten an die CSV Datei an
				add-content $export_datei "$switch_name;$InterfaceName;$Drop_GBP;$Drop_FFP;$Drop_STP;;;$Drop_ECN"
			}
		}

		if ( $switch_40gigports -gt 0){
			foreach ($fortyGig in 1..$switch_40gigports){
				$InterfaceIndex = $fortyGig - 1

				##### Interface Namen auslesen
				[STRING]$InterfaceName = (Get-Content -Path $plink_log | Select-String "FortyGigE")[$InterfaceIndex + ($switche*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$InterfaceName = $InterfaceName.Replace(":","")

				##### Auslesen Drop GBP
				[STRING]$Drop_GBP = (Get-Content -Path $plink_log | Select-String "insufficient bandwidth")[$InterfaceIndex + ($switche*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$Drop_GBP = $Drop_GBP.Replace("  Packets dropped due to full GBP or insufficient bandwidth: ","")

				##### Auslesen Drop FFP
				[STRING]$Drop_FFP = (Get-Content -Path $plink_log | Select-String "(FFP)")[$InterfaceIndex + ($switche*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$Drop_FFP = $Drop_FFP.Replace("  Packets dropped due to Fast Filter Processor (FFP): ","")

				##### Auslesen Drop STP
				[STRING]$Drop_STP = (Get-Content -Path $plink_log | Select-String "non-forwarding state")[$InterfaceIndex + ($switche*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$Drop_STP = $Drop_STP.Replace("  Packets dropped due to STP non-forwarding state: ","")

				##### Auslesen Mark ECN
				[STRING]$Drop_ECN = (Get-Content -Path $plink_log | Select-String "to ECN")[$InterfaceIndex + ($switche*$switch_10gigports) + (($switche-1)*$switch_40gigports)] 
				$Drop_ECN = $Drop_ECN.Replace("  Packets marked due to ECN: ","")


				##### Hängt die Daten an die CSV Datei an
				add-content $export_datei "$switch_name;$InterfaceName;$Drop_GBP;$Drop_FFP;$Drop_STP;;;$Drop_ECN"
				
			}
		}

		#exit

		#####E-Mail versenden mit dem CSV
		#$mailnachricht = new-object Net.Mail.MailMessage
		#$mailanhang = new-object Net.Mail.Attachment($export_datei)
		#$mail = new-object Net.Mail.SmtpClient($mailserver)
		#$mailnachricht.From = "$mailvon"
		#$mailnachricht.To.Add("$mailzu")
		#$mailnachricht.Subject = "Die taegliche CSV vom Switch $switch_name."
		#$mailnachricht.Body = "Das Log vom $datum befindet sich im Anhang."
		#$mailnachricht.Attachments.Add($mailanhang)
		#$mail.send($mailnachricht)
		#$mailnachricht.Dispose(); 
		#$mailanhang.Dispose();
	}
}
#####Alte Logs loeschen
$dateien = get-childitem $log_pfad -include *.* -recurse | Where {$_.LastWriteTime -le "$alter"}

foreach ($datei in $dateien)
{write-host "Loesche Datei $datei" -foregroundcolor "Red"; Remove-Item $datei.FullName | out-null} 

#####Alte Exports loeschen
$dateien = get-childitem $export_pfad -include *.* -recurse | Where {$_.LastWriteTime -le "$alter"}

foreach ($datei in $dateien)
{write-host "Loesche Datei $datei" -foregroundcolor "Red"; Remove-Item $datei.FullName | out-null} 
