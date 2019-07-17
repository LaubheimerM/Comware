[string]$switchliste = "C:\Sysjobs\Switch\Switch-Backup.csv"
$switche = Import-Csv $switchliste -delimiter ";"
foreach ($switch in $switche){

#####Benutzerdefinierte Variablen
$log_pfad = "C:\Sysjobs\Switch\Logs"
$cfg_pfad = "C:\Sysjobs\Switch\Config"
$logbuffer_pfad = "C:\Sysjobs\Switch\Logbuffer"
$keyfile_pfad = "C:\Sysjobs\Switch\Keyfile"
$temp_pfad = "C:\Temp"
$scp_aufruf_name = "scp.cmd"
$tage = 28

#Der im $app_pfad hinterlegte Ordner muss die pSCP Applikation ("pscp.exe") und pLink Applikation ("plink.exe") enthalten
$app_pfad = "C:\Sysjobs\Switch\SSH" 

#####Importierte Variablen
$switch_ip = $switch.ip
$switch_name = $switch.name
$switch_benutzer = $switch.switch_benutzer
$switch_passwort = $switch.switch_passwort

#####E-Mail-Adresse f�r Benachrichtigungen
$mailzu = $switch.mail_zu
$mailvon = $switch.mail_von
$mailserver = $switch.mailserver
	
#####Ausgelesene Variablen
$datum = get-date -Format "yyyy-MM-dd_HHmm"
$datum_check = get-date
$alter = (get-date).AddDays(-$tage)
		
#####Generierte Variablen
$alter = $datum_check.AddDays(-$tage)
$cfg_name = "$datum" + "-" + "$switch_name.cfg"
$logbuffer_name = "$datum" + "-" + "$switch_name.log"
$scp_aufruf_pfad = "$temp_pfad" + "\" + "$switch_name"
$scp_aufruf_datei = "$scp_aufruf_pfad" + "-" + "$scp_aufruf_name"
$scp_aufruf_befehl_config = "echo n | $app_pfad" + "\" + "pscp.exe -l $switch_benutzer -pw $switch_passwort -2 $switch_ip" + ":/startup.cfg " + "$cfg_pfad" + "\" + "$cfg_name"
$scp_aufruf_befehl_logbuffer = "echo n | $app_pfad" + "\" + "pscp.exe -l $switch_benutzer -pw $switch_passwort -2 $switch_ip" + ":/logfile/logfile.log " + "$logbuffer_pfad" + "\" + "$logbuffer_name"
$plink_aufruf_befehl_stp = "echo n | $app_pfad" + "\" + "plink.exe -l $switch_benutzer -pw $switch_passwort $switch_ip" + ":/logfile/logfile.log " + "$logbuffer_pfad" + "\" + "$logbuffer_name" 
$scp_log_name = "$datum"+"-"+"$switch_name.log"
$scp_log = "$log_pfad" + "\" + "$scp_log_name"

#####Pfad der tempor�ren Dateien erstellen
new-item -path $temp_pfad -type directory -force
#####LOG Pfad erstellen
new-item -path $log_pfad -type directory -force
#####scp Aufruf erstellen
new-item -path $scp_aufruf_datei -type file -force
add-content $scp_aufruf_datei '@echo off'
add-content $scp_aufruf_datei "cd $app_pfad"
add-content $scp_aufruf_datei "$scp_aufruf_befehl_config"
add-content $scp_aufruf_datei "$scp_aufruf_befehl_logbuffer"
#####Log erstellen
invoke-expression "$scp_aufruf_datei >$scp_log"
#####L�schen der tempor�ren Dateien
#remove-item $scp_aufruf_datei -recurse	

#####Alte Versionen l�schen#####

#Alle Logs
$dateien = get-childitem $log_pfad -include *.* -recurse | Where {$_.LastWriteTime -le "$alter"}

foreach ($datei in $dateien)
{write-host "L�sche Datei $datei" -foregroundcolor "Red"; Remove-Item $datei.FullName | out-null} 

#Alle Configs
$dateien = get-childitem $cfg_pfad -include *.* -recurse | Where {$_.LastWriteTime -le "$alter"}

foreach ($datei in $dateien)
{write-host "L�sche Datei $datei" -foregroundcolor "Red"; Remove-Item $datei.FullName | out-null} 

$log = Get-content $scp_log
if ($log -like "*100%*")	{
		#####E-Mail versenden : Vorgang erfolgreich
#		$mailzu
#		$mailserver
#		$mailnachricht = new-object Net.Mail.MailMessage
#		$mailanhang = new-object Net.Mail.Attachment($scp_log)
#		$mail = new-object Net.Mail.SmtpClient($mailserver)
#		$mailnachricht.From = "$mailvon"
#		$mailnachricht.To.Add("$mailzu")
#		$mailnachricht.Subject = "Backup erfolgreich $switch_name"
#		$mailnachricht.Body = "Das Log vom $datum befindet sich im Anhang."
#		$mailnachricht.Attachments.Add($mailanhang)
#		$mail.send($mailnachricht)
#		$mailnachricht.Dispose(); 
#		$mailanhang.Dispose();
		}
		ELSE {
		#####E-Mail versenden: Vorgang fehlgeschlagen
		$mailzu
		$mailserver
		$mailnachricht = new-object Net.Mail.MailMessage
		$mailanhang = new-object Net.Mail.Attachment($scp_log)
		$mail = new-object Net.Mail.SmtpClient($mailserver)
		$mailnachricht.From = "$mailvon"
		$mailnachricht.To.Add("$mailzu")
		$mailnachricht.Subject = "Backup fehlgeschlagen $switch_name"
		$mailnachricht.Body = "Das Log vom $datum befindet sich im Anhang."
		$mailnachricht.Attachments.Add($mailanhang)
		write-output $scp_log
		$mail.send($mailnachricht)
		$mailnachricht.Dispose(); 
		$mailanhang.Dispose();
		}
	}