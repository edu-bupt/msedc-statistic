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

set output_dir /proj/terass_func/JcatResult/statistic

#
#	PACKAGES
#

if {[lsearch $auto_path $pkgdir] < 0} {
	set auto_path [linsert $auto_path 0 $pkgdir]
}

package require json::write 
package require sqlite3

sqlite3 db $dbfile

package require statistic

proc exportHtmlEx {output_dir json_map html_name {mode 1}} {	
	set fd [open statistic_template.htm]
	set html [read $fd]
	close $fd
	
	lappend json_list
	set table "<table><tbody><tr>"
	foreach {id map} $json_map {
		set json [dict get $map table]
		lappend json_list $json
		set title [expr {[dict exists $map title] ? [dict get $map title] : ""}]
		set description [expr {[dict exists $map description] ? [dict get $map description] : ""}]
		set note ""
		if {$description ne "" || $title ne ""} {
			set note "<blockquote class='button'>$title<br><br><span style='font-weight:normal'>$description</span></blockquote>"
		}
		append table [expr {$id ne "" ? "<td><div id='$id'></div>$note</td>" : "<td/>"}]
		if {[incr count] % $mode == 0} {
			append table "</tr><tr>"
		}
	}
	append table "</tr></tbody></table>"
	set html [regsub "\{JSONDATA\}" $html "var DATA = [json::write array {*}$json_list]"]
	set html [regsub "\{CONTAINER\}" $html $table]
	
	if {![file exists $output_dir]} {
		file mkdir $output_dir
		file attributes $output_dir -permissions 00755
	}
	set html_file [file join $output_dir ${html_name}.htm]
	if {[file exists $html_file]} {
		file delete -force $html_file
	}
	set fd [open $html_file w+]
	puts $fd $html
	close $fd
	file attributes [file join $output_dir ${html_name}.htm] -permissions 00755
}

proc executionTime {output_dir stp start end} {
	set prefix [clock milliseconds]
	set count 0
	
	array set maxMap [list suite 150 test 60]
	foreach catalog [list suite test] {
		set json_dict [dict create]
		set table_json [statistic::duration_$catalog Stp $stp start $start end $end]
		set vAxis_json [json::write object title {'Duration (minutes)'} viewWindow [json::write object max $maxMap($catalog)]]
		set hAxis_json [json::write object title [list 'Suite Name']]
		set legend_json [json::write object position 'bottom']
		set options_json [json::write object title [list '$catalog Execution Time'] \
								width 1000 height 500 \
								vAxis $vAxis_json hAxis $hAxis_json \
								legend $legend_json]
		set id ${prefix}[incr count]
		dict set json_dict $id table [json::write object chartType 'ColumnChart' \
								dataTable $table_json \
								options $options_json \
								containerId '$id']
		set output [file join $output_dir $stp]
		if {![file exists $output]} {
			file mkdir $output
			file attributes $output -permissions 00755	
		}
		exportHtmlEx [file join $output_dir $stp] $json_dict ExecutionTime_$catalog
	}
}

proc overallStatistic {output_dir} {
	set prefix [clock milliseconds]
	set count 0
	
	#overall pass ratio
	set table_json [statistic::passratio_overall]
	set title "Overall Pass Ratio"
	set options_json [json::write object title '$title' width 900 height 500 pieHole 0.4]
	set id ${prefix}[incr count]
	append description "Time Period (xAxis): [statistic::getTimePeriod]" <br>
	append description "Stps : <br>[join [statistic::getStps] <br>]" <br>
	append description "Tests : <br>[join [statistic::getTests] <br>]" <br>
	dict set json_dict $id title $title
	dict set json_dict $id description $description
	dict set json_dict $id table [json::write object chartType 'PieChart' dataTable $table_json \
											   options $options_json containerId '$id']
	exportHtmlEx $output_dir $json_dict PassRatio_Overall
}

proc passRatio {output_dir stp start end } {
	set prefix [clock milliseconds]
	set count 0
	
	set json_dict [dict create]
	foreach tc [list "" {*}[statistic::getTests Stp $stp]] {
		foreach {column_table_json line_table_json} [statistic::passratio_rusw_tc stp $stp Name $tc start $start end $end] {
			#set series_json [json::write object 0 [json::write object type 'line']]
			set vAxis_json [json::write object title {'COUNT'}]
			set hAxis_json [json::write object title {'RUS SW VERSION'}]
			set legend_json [json::write object position 'bottom']
			set colors [json::write array '#99CC00' '#FF3300' '#FF9933']
			set options_json [json::write object title [list 'Test $tc Result on Different RUS SWs'] \
											 width 500 height 350 \
											 vAxis $vAxis_json hAxis $hAxis_json \
											 seriesType 'bars'\
											 legend $legend_json \
											 colors $colors \
											 isStacked true]
			set id ${prefix}[incr count]
			dict set json_dict $id table [json::write object chartType 'ColumnChart' \
													dataTable $column_table_json \
													options $options_json \
													containerId '$id']
			
			set vAxis_json [json::write object title {'Percentage'}]
			set hAxis_json [json::write object title {'RUS SW VERSION'}]										
			set options_json [json::write object title [list 'Test $tc Result on Different RUS SWs'] \
											 width 500 height 350 \
											 vAxis $vAxis_json hAxis $hAxis_json \
											 legend $legend_json \
											 colors $colors \
											 pointSize 5]										
			set id ${prefix}[incr count]
			dict set json_dict $id table [json::write object chartType 'LineChart' \
													dataTable $line_table_json \
													options $options_json \
													containerId '$id']
		}
	}	
	exportHtmlEx [file join $output_dir $stp] $json_dict PassRatio_Rus 2
	foreach rusw [list "" {*}[statistic::getRuSwVers Stp $stp]] {
		foreach {column_table_json line_table_json} [statistic::passratio_tc_rusw stp $stp RuSwVersion $rusw start $start end $end] {
			set json_dict [dict create]
			set vAxis_json [json::write object title {'COUNT'}]
			set hAxis_json [json::write object title {'Test'}]
			set legend_json [json::write object position 'bottom']
			set colors [json::write array '#99CC00' '#FF3300' '#FF9933']
			set options_json [json::write object title [list 'RUS SW $rusw Test Result'] \
											 width 900 height 600 \
											 vAxis $vAxis_json hAxis $hAxis_json \
											 seriesType 'bars'\
											 legend $legend_json \
											 colors $colors \
											 isStacked true]
			set id ${prefix}[incr count]
			dict set json_dict $id table [json::write object chartType 'ColumnChart' \
													dataTable $column_table_json \
													options $options_json \
													containerId '$id']
			exportHtmlEx [file join $output_dir $stp] $json_dict TestResult_$rusw	
		}
	}	
}

proc throughput {output_dir stp start end} {
	set prefix [clock milliseconds]
	set count 0
		
	set json_dict [dict create]
	foreach {name table_json} [statistic::throughput_rus $stp start $start end $end] {
		set hAxis [json::write object title 'Date']
		set vAxis [json::write object title {'Throughput kbps'}]
		set legend_json [json::write object position 'bottom']
		set options_json [json::write object title [list '$name kbps'] \
						pointSize 5 width 500 height 350 \
						hAxis $hAxis vAxis $vAxis \
						legend $legend_json]
		set id ${prefix}[incr count]
		dict set json_dict $id table [json::write object chartType 'LineChart' \
						dataTable $table_json \
						options $options_json \
						containerId '$id']
		exportHtmlEx [file join $output_dir $stp] $json_dict Throughput_Rus 2
	}	
}

proc buildStpMap {output_dir stp start end} {
	set prefix [clock milliseconds]
	set count 0
	
	set json_dict [dict create]
	foreach {rbs table_json} [statistic::ru_connection $stp start $start end $end] {
		set options_json [json::write object title [list '$rbs RU connection'] \
									 allowHtml true]
		set id ${prefix}[incr count]
		dict set json_dict $id title "$rbs RU connection"
		dict set json_dict $id table [json::write object chartType 'OrgChart' \
										   dataTable $table_json \
										   options $options_json \
										   containerId '$id']
	}

	foreach {rbs table_json} [statistic::ue_connection $stp] {
		set options_json [json::write object title [list '$rbs Ue Connection'] \
									 allowHtml true]
		set id ${prefix}[incr count]
		dict set json_dict $id title "$rbs Ue connection"
		dict set json_dict $id table [json::write object chartType 'OrgChart' \
										   dataTable $table_json \
										   options $options_json \
										   containerId '$id']
	}
	exportHtmlEx [file join $output_dir $stp] $json_dict StpMap 2
}

proc upgradePath {output_dir stp start end} {
	set prefix [clock milliseconds]
	set count 0
	
	set json_dict [dict create]
	lassign [statistic::upgradePath_rus $stp start $start end $end] vers table_json
	set values ""
	set level -1
	foreach ver $vers {
		lappend values "[incr level]=$ver"
	}
	set vAxis [json::write object title "'[join $values ,]'"]
	set legend_json [json::write object position 'bottom']
	set options_json [json::write object title [list '$stp RUS SW Upgrade History'] \
						 width 900 height 500 hAxis $vAxis\
						 pointSize 5]
	set id ${prefix}[incr count]
	dict set json_dict $id table [json::write object chartType 'LineChart' \
						dataTable $table_json \
						options $options_json \
						containerId '$id']

	exportHtmlEx [file join $output_dir $stp] $json_dict UpgradeHistory_Rus
}


proc dailyStatistic {output_dir stp year} {
	set json_dict [dict create]
	set prefix [clock milliseconds]
	set count 0 
	
	set table_json [statistic::passratio_daily stp $stp start $year]
	set title [list '$stp Test Pass Ratio']
	set hAxis [json::write object title 'Date']
	set vAxis [json::write object title {'Pass Ratio'} minValue 0 maxValue 100]
	set calendar_json [json::write object cellSize 16]
	set options_json [json::write object title $title hAxis $hAxis vAxis $vAxis \
							width 1200 height 260 \
							calendar $calendar_json]
	set id ${prefix}[incr count]
	dict set json_dict $id table [json::write object chartType 'Calendar' \
							dataTable $table_json \
							options $options_json \
							containerId '$id']
							
	set table_json [statistic::utilization_daily stp $stp start $year]
	set title [list '$stp Utilization Ratio']
	set hAxis [json::write object title 'Date']
	set vAxis [json::write object title {'Pass Ratio'} minValue 0 maxValue 100]
	set calendar_json [json::write object cellSize 16]
	set options_json [json::write object title $title hAxis $hAxis vAxis $vAxis \
							width 1200 height 260 \
							calendar $calendar_json]
	set id ${prefix}[incr count]
	dict set json_dict $id table [json::write object chartType 'Calendar' \
							dataTable $table_json \
							options $options_json \
							containerId '$id']
							
	exportHtmlEx [file join $output_dir $stp] $json_dict DailyStatistic_$year
	if {$stp ne ""} {
		set json_dict [dict create]
		foreach {key table_json} [statistic::throughput_daily $stp start $year] {
			set title [json::write string "$key (kbps)"]
			set hAxis [json::write object title 'Date']
			set vAxis [json::write object title {'Pass Ratio'} minValue 0 maxValue 100]
			set calendar_json [json::write object cellSize 16]
			set options_json [json::write object title $title hAxis $hAxis vAxis $vAxis \
							width 1200 height 260 \
							calendar $calendar_json]
			set id ${prefix}[incr count]
			dict set json_dict $id table [json::write object chartType 'Calendar' \
							dataTable $table_json \
							options $options_json \
							containerId '$id']
		}
		exportHtmlEx [file join $output_dir $stp] $json_dict DailyThroughput_$year
	}
}

proc createLogUrls {output_dir config ver args} {
puts [info level 0]
	set test_set [statistic::getTests Stp $config RuSwVersion $ver {*}$args]
	array set statusMap [list 1 PASS 2 FAIL 3 SKIP]
	append html "<ul>"
	foreach test $test_set {
		array set countMap [list 1 0 2 0 3 0]
		set content "<div class='list'><ol>"
		set filter [statistic::buildFilter Name $test Stp $config RuSwVersion $ver {*}$args]
		set sql "SELECT SuiteId, Name, Status, Logurl, User, Stp, duration, LteUp, WcdmaUp FROM TestResult $filter ORDER BY SuiteId"
		foreach {date test status logurl user stp duration lteUp wcdmaUp} [::db eval $sql] {
			incr countMap($status)
			set date [clock format [clock scan $date -format {%Y%m%d%H%M%S}] -format {%Y-%m-%d %H:%M:%S}]
			set duration "[expr {$duration / 60}] minutes [expr {$duration % 30}] seconds"
			set detail ""
			append detail <table><tbody><tr> \
				[join [list "<td>User</td><td>$user</td>" \
					  "<td>Stp</td><td>$stp</td>" \
					  "<td>RUS SW</td><td>$ver</td>" \
					  "<td>LTE UP</td><td>$lteUp</td>" \
					  "<td>WCDMA UP</td><td>$wcdmaUp</td>" \
					  "<td>Duration</td><td>$duration</td>" \
					  "<td>Result</td><td>$statusMap($status)</td>"] \
					  </tr><tr>] \
				</tr></tbody></table>
			set item "<a href='$logurl' class='$statusMap($status) tooltip'>$date<span><strong>$test</strong>$detail</span></a>"
			append content "<li><p><em>$item</em></p></li>"
		}
		set title "<a><h3>$test ($countMap(1) / [expr {$countMap(1) + $countMap(2) + $countMap(3)}])</h3></a>"
		append content "</ol></div>"
		append html <li> $title $content </li>
	}
	append html "</ul>"
	
	set fd [open LogNav_template.htm]
	set data [read $fd]
	close $fd
	
	set data [regsub "\{CONTAINER\}" $data $html]
	
	set output_dir [file join $output_dir $config]
	if {![file exists $output_dir]} {
		file mkdir $output_dir
		file attributes $output_dir -permissions 00755
	}
	set name [expr {$ver ne "" ? "TestLog_$ver.htm" : "TestLog.htm"}]
	set html_file [file join $output_dir $name]
	if {[file exists $html_file]} {
		file delete -force $html_file
	}
	set fd [open $html_file w+]
	puts $fd $data
	close $fd
	file attributes $html_file -permissions 00755
}

proc faultCorrelation {output_dir stp start end} {
puts [info level 0]
	set json_dict [dict create]
	set prefix [clock milliseconds]
	set count 0
	
	set table_json [statistic::correlation_uefault $start $end Stp $stp]
	set title "Correlation between Pass Ratio and Ue Faults"
	set hAxis [json::write object title 'Date']
	set vAxis [json::write object title {'Pass Ratio'} minValue 0 maxValue 100]
	set explorer \{\}
	set sizeAxis [json::write object maxSize 40 minSize 10]
	set legend_json [json::write object position 'bottom']
	set options_json [json::write object title '$title' hAxis $hAxis vAxis $vAxis \
							width 1000 height 600 \
							explorer $explorer sizeAxis $sizeAxis \
							legend $legend_json]
	set id ${prefix}[incr count]
	append description "Time Period (xAxis): $start ~ $end" <br>
	append description "Pass Ratio (yAxis) : 0% ~ 100%" <br>
	append description "Ue Fault Number (Size of Bubble):  Ue Faults found during execution, including attach failure, Ping and Ftp failure" <br>
	append description "Note: click bubble to open JCAT log URL"
	dict set json_dict $id title $title
	dict set json_dict $id description $description
	dict set json_dict $id table [json::write object chartType 'BubbleChart' \
							dataTable $table_json \
							options $options_json \
							containerId '$id']
	
	exportHtmlEx [file join $output_dir $stp] $json_dict Correlation_Uefault_${start}_${end}
}


#
array set opts {-stp "" -user "" -start "" -end "" -type "common" -ver ""}
array set opts $argv
#
set stp $opts(-stp)
set stp_set [statistic::getStps]
#

if {$stp in [list "" {*}$stp_set]} {
	switch -exact -- $opts(-type) {
		"common" {
			throughput $output_dir $stp $opts(-start) $opts(-end)	
			passRatio $output_dir $stp $opts(-start) $opts(-end)
		}
		"executiontime" {
			executionTime $output_dir $stp $opts(-start) $opts(-end)
		}
		"daily" {
			set year [clock format [clock seconds] -format {%Y}]
			dailyStatistic $output_dir $stp $year
		}
		"stpmap" {
			if {$stp ne ""} {
				buildStpMap $output_dir $stp $opts(-start) $opts(-end)
			} else {
				puts "Please specify a stp"
			}
		}
		"faultcorrelation" {
			faultCorrelation $output_dir $stp $opts(-start) $opts(-end)
		}
		"upgradepath" {
			upgradePath $output_dir $stp $opts(-start) $opts(-end)
		}
		"logurls" {
			createLogUrls $output_dir $stp $opts(-ver) start $opts(-start) end $opts(-end)
		}
		default {
			puts [info level]
			puts "No charts will be generated!"
		}
	}
} else {
	puts "$stp is not found in database"
}

