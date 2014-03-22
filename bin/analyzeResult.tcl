#/usr/bin/tclsh

#
#	VARIABLES
#

set tmp [file dirname [info script]]
if {[file pathtype $tmp] eq "relative"} {
	set script_dir [file normalize [file join [pwd] $tmp]]
} else {
	set script_dir [file normalize $tmp]
}
set basedir	[file dirname $script_dir]
set dbfile	[file join $script_dir ntc_ms_edc.sqlite]
set pkgdir	[file join $basedir tcllib]

set jcatlogdir "/proj/terass_func/JcatResult"
set urlPrefix "http://sekilc8116.prbs.rnd.ki.sw.ericsson.se:8015"
set STP ""


#
#	PACKAGES
#

if {[lsearch $auto_path $pkgdir] < 0} {
	set auto_path [linsert $auto_path 0 $pkgdir]
}

package require sqlite3
package require inifile

#
#	PROGRAM
#

sqlite3 db $dbfile


array set opts "-logdir $jcatlogdir -user $env(USER) -sdate [clock format [clock seconds] -format {%Y%m%d}]"

array set opts $argv

set logfile [open [file join $basedir log.txt] w+]

set logdir $opts(-logdir)
set users $opts(-user)
set startDay $opts(-sdate)

set filter "\[a-z]*"
if {$users ne ""} {
    set filter "*{[join $users ","]}*"
}

puts "User Filter: $filter"
puts "Log dir: $logdir"
puts "Day filter: $startDay or later"

#delete old items
db eval {
	DELETE FROM SuiteResult WHERE SuiteId > $startDay;
	DELETE FROM TestResult WHERE SuiteId > $startDay;
	DELETE FROM RuResult WHERE SuiteId > $startDay;
	DELETE FROM TrafficResult WHERE SuiteId > $startDay;
}

proc logMsg {level msg} {
	global logfile
	set date [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]
	puts $msg
	puts $logfile "\[$date\]\t$level\t$msg"
}

proc getTcLogUrl {tc_result_file} {
	global jcatlogdir urlPrefix
	lassign [split [file tail $tc_result_file] _] tcIndex
	set logdir [file dirname [file dirname $tc_result_file]]
	set logfile ""
	set logurl ""
	foreach logfile [glob -nocomplain -type f -directory $logdir "${tcIndex}_*.log.html"] {
	
	}
	if {$logfile ne ""} {
		set logurl [string map [list $jcatlogdir $urlPrefix] $logfile]
	}
	return $logurl
}

proc logRuResult {suiteId ru_result_file} {
logMsg INFO [info level 0]
	set serialNum [file tail [file rootname $ru_result_file]]
	set ini [::ini::open $ru_result_file r]
	array set rumap [list SuiteId $suiteId SerialNumber $serialNum PassRatio "" BoardType "" UnitType "" ProductNumber "" ProductionDate "" FaultIndicator "" RunningSw "" LTE_path "" WCDMA_path "" GSM_path "" Stp $::STP]
	array set rumap [::ini::get $ini result]
	# insert RU info
	set cols [list SerialNumber BoardType UnitType ProductNumber ProductionDate LTE_path WCDMA_path GSM_path Stp] 
	lappend values1
	foreach col $cols {
		lappend values1 [expr {[info exists rumap($col)] ? $rumap($col) : ""}]
	}
	if {[::db onecolumn "SELECT count(*) FROM RuInfo WHERE SerialNumber = '$serialNum'"] <= 0} {
		set sql "INSERT INTO RuInfo VALUES ('[join $values1 ',']');"
		logMsg INFO $sql
		::db eval $sql
	}
	# insert RU result
	lassign [split $rumap(RunningSw) "_"] swProduct swVersion
	array set rumap [list SwProduct $swProduct SwVersion $swVersion]
	set cols [list SuiteId SerialNumber FaultIndicator SwProduct SwVersion PassRatio] 
	lappend values2
	foreach col $cols {
		lappend values2 [expr {[info exists rumap($col)] ? $rumap($col) : ""}]
	}
	set sql "INSERT INTO RuResult VALUES ('[join $values2 ',']');"
	logMsg INFO $sql
	::db eval $sql
	::ini::close $ini
}

proc logTrafficResult {suiteId ue_result_file} {
logMsg INFO [info level 0]
	set ueId [file tail [file rootname $ue_result_file]]
	set ini [::ini::open $ue_result_file r]
	array set ueMap [list SuiteId $suiteId UeId $ueId Stp $::STP Rbs "" Sector "" Cell "" AttachOk "" AttachNok "" TrafficOk "" TrafficNok ""  DlThroughput "" UlThroughput "" PassRatio "" RuSwVersion ""]
	array set ueMap [::ini::get $ini result]
	set cols [list SuiteId UeId Stp Rbs Sector Cell AttachOk AttachNok TrafficOk TrafficNok DlThroughput UlThroughput PassRatio RuSwVersion]
	lappend values
	foreach col $cols {
		lappend values [expr {[info exists ueMap($col)] ? $ueMap($col) : ""}]
	}
	set sql "INSERT INTO TrafficResult VALUES ('[join $values ',']');"
	logMsg INFO $sql
	::db eval $sql
	::ini::close $ini
}

proc logTcResult {suiteId user tc_result_file} {
logMsg INFO [info level 0]
	lassign [split [file tail [file rootname $tc_result_file]] "_"] tcIndex testName
	set ini [::ini::open $tc_result_file r]
	array set tcMap [list SuiteId $suiteId User $user Stp $::STP Logurl [getTcLogUrl $tc_result_file] TcIndex $tcIndex Name $testName Start "" End "" Duration "" Status "" UeFaultRatio "" RuSwVersion "" LteUp "" WcdmaUp "" GsmUp ""]
	array set tcMap [::ini::get $ini result]
	set tcMap(Duration) [expr {$tcMap(Start) ne "" && $tcMap(End) ne "" ? ($tcMap(End) -$tcMap(Start)) / 1000 : ""}]
	if {$tcMap(Duration) ne ""} {
		set cols [list SuiteId User Stp Name Logurl Start End Duration TcIndex Status UeFaultRatio RuSwVersion LteUp WcdmaUp GsmUp]
		lappend values
		foreach col $cols {
			lappend values [expr {[info exists tcMap($col)] ? $tcMap($col) : ""}]
		}
		set sql "INSERT INTO TestResult VALUES ('[join $values ',']');"
		logMsg INFO $sql
		::db eval $sql
	} else {
		logMsg ERROR "Can't parse result data, skipping $tc_result_file"
	}
	::ini::close $ini
}

proc logTsResult {suiteId user ts_result_file} {
logMsg INFO [info level 0]
	global jcatlogdir urlPrefix
	set suite [file tail [file rootname $ts_result_file]]
	set ini [::ini::open $ts_result_file r]
	set logdir [file dirname [file dirname $ts_result_file]]
	array set tsMap [list SuiteId $suiteId User $user Stp "" Name $suite Logurl [string map [list $jcatlogdir $urlPrefix] $logdir] Start "" End "" Duration "" Pass "" Fail "" Skip "" PassRatio "" RuSwVersion ""]
	array set tsMap [::ini::get $ini result]
	set ::STP $tsMap(Stp)
	set tsMap(Duration) [expr {$tsMap(Start) ne "" && $tsMap(End) ne "" ? ($tsMap(End) -$tsMap(Start)) / 1000 : ""}]
	set cols [list SuiteId User Stp Name Logurl Start End Duration Pass Fail Skip PassRatio RuSwVersion]
	lappend values
	foreach col $cols {
		lappend values [expr {[info exists tsMap($col)] ? $tsMap($col) : ""}]
	}
	set sql "INSERT INTO SuiteResult VALUES ('[join $values ',']');"
	logMsg INFO $sql
	::db eval $sql
	::ini::close $ini

}



proc logResult {user date statistic_folder} {
logMsg INFO [info level 0]
	foreach suite_result_file [glob -nocomplain -type f -directory $statistic_folder *.TS] {
		if {[file readable $suite_result_file]} {
			logTsResult $date $user $suite_result_file
		}
	}

	foreach tc_result_file [glob -nocomplain -type f -directory $statistic_folder *.TC] {
		if {[file readable $tc_result_file]} {
			logTcResult $date $user $tc_result_file
		}
	}
	
	foreach ru_result_file [glob -nocomplain -type f -directory $statistic_folder *.RU] {
		if {[file readable $ru_result_file]} {
			logRuResult $date $ru_result_file
		}
	}
	
	foreach ue_result_file [glob -nocomplain -type f -directory $statistic_folder *.UE] {
		if {[file readable $ue_result_file]} {
			logTrafficResult $date $ue_result_file
		}
	}
		
}

foreach user_dir [glob -nocomplain -type d -directory $logdir $filter] {
	#logMsg INFO $user_dir
	set user [lindex [file split $user_dir] end]
	if {[file readable $user_dir]} {
		foreach month [glob -nocomplain -type d -directory $user_dir "\[0-9]*"] {
			#logMsg INFO $month
			if {[file readable $month]} {
				foreach day [glob -nocomplain -type d -directory $month "\[0-9]*"] {
					#logMsg INFO $day
					if {[file readable $day]} {
						set date [lindex [file split $day] end]
						if {[string compare $date $startDay] > 0} {
							logMsg INFO $day
							foreach ntcmsedc [glob -nocomplain -type d -directory $day "ntcmsedc"] {
								logResult $user $date $ntcmsedc
							}
						}
					}
				}
			}
		}
	}
}

close $logfile
