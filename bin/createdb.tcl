#/usr/bin/tclsh

#
#	VARIABLES
#

# the script is in drive:/.../atp_bsc/scheduler and basedir is drive:/.../atp_bsc
set tmp [file dirname [info script]]
if {[file pathtype $tmp] eq "relative"} {
	set script_dir [file normalize [file join [pwd] $tmp]]
} else {
	set script_dir [file normalize $tmp]
}
set basedir	[file dirname $script_dir]
set dbfile	[file join $script_dir ntc_ms_edc.sqlite]
set pkgdir	[file join $basedir tcllib]


#
#	PACKAGES
#

if {[lsearch $auto_path $pkgdir] < 0} {
	set auto_path [linsert $auto_path 0 $pkgdir]
}

package require sqlite3


#
#	PROGRAM
#

sqlite3 db $dbfile

db eval {

	PRAGMA page_size=4096;

	CREATE TABLE SuiteResult (SuiteId TEXT PRIMARY KEY,
				User TEXT,
				Stp TEXT,
				Name TEXT,
				Logurl TEXT,
				Start TEXT,
				End TEXT,
				Duration INTEGER,
				Pass INTEGER,
				Fail INTEGER,
				Skip INTEGER,
				PassRatio INTEGER,
				RuSwVersion TEXT);
	
	CREATE TABLE TestResult (
				SuiteId TEXT,
				User TEXT,
				Stp TEXT,
				Name TEXT,
				Logurl TEXT,
				Start TEXT,
				End TEXT,
				Duration INTEGER,
				TcIndex TEXT,
				Status INTEGER,
				UeFaultRatio INTEGER,
				RuSwVersion TEXT,
				LteUp TEXT,
				WcdmaUp TEXT,
				GSMUp TEXT);

		
	CREATE TABLE RuInfo (
			SerialNumber TEXT PRIMARY KEY,
			BoardType TEXT,
			UnitType TEXT,
			ProductNumber TEXT,
			ProductionDate TEXT,
			LTE_path TEXT,
			WCDMA_path TEXT,
			GSM_path TEXT,
			Stp TEXT);
		
	CREATE TABLE RuResult (
			SuiteId TEXT,
			SerialNumber TEXT,
			FaultIndicator TEXT,
			SwProduct TEXT,
			SwVersion TEXT,
			PassRatio INTEGER);
		
	CREATE TABLE TrafficResult (
			SuiteId TEXT,
			UeId TEXT,
			Stp TEXT,
			Rbs TEXT,
			Sector TEXT,
			Cell TEXT,
			AttachOk INTEGER,
			AttachNok INTEGER,
			TrafficOk INTEGER,
			TrafficNok INTEGER,
			DlThroughput FLOAT,
			UlThroughput FLOAT,
			PassRatio INTEGER,
			RuSwVersion TEXT);
}

db close
