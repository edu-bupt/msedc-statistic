# msedc_statistic.tcl --
#
#	Commands for the generation of JSON data for Google chart usage.
#
# Copyright (c) 2013-2014 william yang <william.w.yang@ericsson.com>
#
# ### ### ### ######### ######### #########

namespace eval statistic {
	namespace export duration \
					 formatDays \
					 passratio_overall \
					 passratio_stp \
					 stp_structure \
					 ue_connection \
					 uefault_passratio_correlation
	namespace ensemble create
	
	proc formatDays {start count} {
		if {$start eq ""} {
			return [formatDaysEx $count]
		}
		lappend date_list
		set date [clock scan $start -format "%Y%m%d"]
		for {set i 0} {$i < $count} {incr i} {
			set value [clock add $date $i days]
			lappend date_list [clock format $value -format "%Y%m%d"]
		}
		return $date_list
	}
	
	proc formatDaysEx {count} {
		lappend date_list
		set date [clock seconds]
		for {set i 0} {$i < $count} {incr i} {
			set value [clock add $date -$i days]
			lappend date_list [clock format $value -format "%Y%m%d"]
		}
		return [lreverse $date_list]	
	}
	
	proc buildFilter {args} {
		lappend conditions
		foreach {key value} $args {
			if {$value ne ""} {
				if {$key eq "start"} {
					lappend conditions "SuiteId >= '$value'" 
				} elseif {$key eq "end"} {
					lappend conditions "SuiteId <= '$value'"
				} else {
					lappend conditions "$key = '$value'"
				}
			}
		}
		set filter ""
		if {[llength $conditions] > 0} {
			append filter "WHERE " [join $conditions " AND "]
		}
		return $filter
	}
	
	proc getStps {} {
		return [lsort [::db eval "SELECT DISTINCT Stp FROM SuiteResult"]]
	}
	
	proc getSuites {args} {
		set filter [buildFilter {*}$args]
		return [lsort [::db eval "SELECT DISTINCT Name FROM SuiteResult $filter"]]
	}
	
	proc getTests {args} {
		set filter [buildFilter {*}$args]
		return [lsort [::db eval "SELECT DISTINCT Name FROM TestResult $filter"]]
	}
	
	proc getRuSwVers {args} {
		set filter [buildFilter {*}$args]
		return [lsort [::db eval "SELECT DISTINCT RuSwVersion FROM SuiteResult $filter"]]
	}
	
	
	proc getTimePeriod {} {
		foreach {start end} [::db eval "SELECT min(SuiteId), max(SuiteId) FROM SuiteResult"] {
			set start [clock format [clock scan $start -format {%Y%m%d%H%M%S}] -format {%Y-%m-%d}]
			set end [clock format [clock scan $end -format {%Y%m%d%H%M%S}] -format {%Y-%m-%d}]
			return "$start ~ $end"
		}
	}	
	
	proc ru_connection {stp args} {
	puts [info level 0]
		set filter [buildFilter Stp $stp {*}$args]
		
		set map [dict create]
		set sql "SELECT DISTINCT SerialNumber,LTE_path,WCDMA_path FROM RuInfo $filter"
		puts $sql
		foreach {id ltePath wcdmaPath} [::db eval $sql] {
			if {$wcdmaPath ne ""} {
				dict set map {*}[split $wcdmaPath :] $id
			}
			if {$ltePath ne ""} {
				dict set map {*}[split $ltePath :] $id
			}
		}
		lappend table_list
		foreach rbs [dict keys $map] {
			set row_list [json::write array 'Name' 'Parent' 'ToolTip']
			lappend row_list [json::write array '$rbs' null null]
			foreach sector [lsort [dict keys [dict get $map $rbs]]] {
				set content [json::write object v '$rbs-$sector' f [list 'Sector $sector']]
				lappend row_list [json::write array $content '$rbs' null]
				set sql "SELECT DISTINCT SerialNumber,BoardType FROM RuInfo WHERE LTE_path = '$rbs:$sector' OR WCDMA_path = '$rbs:$sector'"
				puts $sql
				foreach {id board} [::db eval $sql] {
					set content [json::write object v '$rbs-$sector-$id' f [json::write string "$board<br/><font color='red'>$id</font>"]]
					lappend row_list [json::write array $content '$rbs-$sector' null]
				}
			}
			lappend table_list $rbs [json::write array {*}$row_list]
		}
		return $table_list
	}
	
	proc ue_connection {stp args} {
	puts [info level 0]
		set filter [buildFilter Stp $stp {*}$args]
		
		lappend table_list
		set map [dict create]
		set sql "SELECT DISTINCT Rbs,Sector,Cell,UeId FROM TrafficResult $filter"
		puts $sql
		foreach {rbs sector cell ue} [::db eval $sql] {
			dict update map $rbs rbs_dict {
				dict set rbs_dict $sector $cell $ue
			}
		}
		foreach rbs [dict keys $map] {
			puts ${rbs}:
			set row_list [json::write array 'Name' 'Parent' 'ToolTip']
			lappend row_list [json::write array '$rbs' null null]
			set sectorMap [dict get $map $rbs]
			foreach sector [lsort [dict keys $sectorMap]] {
				puts -nonewline ${sector}->
				set content [json::write object v '$rbs-$sector' f [list 'Sector $sector']]
				lappend row_list [json::write array $content '$rbs' null]
				set cellMap [dict get $sectorMap $sector]
				foreach cell [lsort [dict keys $cellMap]] {
					puts -nonewline ${cell}->
					set content [json::write object v '$rbs-$sector-$cell' f [list 'Cell $cell']]
					lappend row_list [json::write array $content '$rbs-$sector' null]
					set ue [dict get $cellMap $cell]
					puts ${ue}
					set content [json::write object v '$rbs-$sector-$cell-$ue' f [list 'Ue $ue']]
					lappend row_list [json::write array $content '$rbs-$sector-$cell' null]
				}
			}
			lappend table_list $rbs [json::write array {*}$row_list]
		}
		return $table_list
	}
	
	proc correlation_uefault {start end args} {
	puts [info level 0]
		set filter [buildFilter start $start end $end {*}$args]		
		
		set sql "SELECT DISTINCT SuiteId,Stp,RuSwVersion FROM TrafficResult $filter ORDER by SuiteId ASC"
		puts $sql
		set cols_json [json::write array 'ID' 'Date' 'PassRatio' 'Stp',[list 'Ue Fault Count']]
		lappend row_list
		foreach {date stp ruSw} [::db eval $sql] {
			foreach {passRatio attachNok trafficNok} [::db eval "SELECT avg(PassRatio), sum(AttachNok),sum(TrafficNok) FROM TrafficResult WHERE SuiteId = '$date'"] {
				set seconds [clock scan $date -format "%Y%m%d%H%M%S"]
				set time [json::write object v $seconds f "'[clock format $seconds -format {%Y-%m-%d-%H:%M:%S}]'"]
				set count [expr {$attachNok + $trafficNok}]
				set fault [json::write object v $count f [list '$attachNok Attach Failures, $trafficNok Traffic Failures']]
				set pass [json::write object v $passRatio f '$passRatio%']
				set logurl [::db onecolumn "SELECT Logurl FROM SuiteResult WHERE SuiteId = '$date'"]
				lappend row_list [json::write array [json::write object v '$logurl' f '$ruSw'] $time $pass '$stp' $fault]
			}
		}
		return [json::write array $cols_json {*}$row_list]
	}
	
	proc passratio_overall {} {
	puts [info level 0]
		set pass_sum [::db onecolumn "select sum(Pass) from SuiteResult"]
		set fail_sum [::db onecolumn "select sum(Fail) from SuiteResult"]
		set skip_sum [::db onecolumn "select sum(Skip) from SuiteResult"]
		set cols_json [json::write array 'PASS' 'FAIL' 'SKIP']
		set rows_json [json::write array $pass_sum $fail_sum $skip_sum]
		return [json::write array [json::write array 'catalog' 'count'] \
								  [json::write array 'PASS' $pass_sum] \
								  [json::write array 'FAIL' $fail_sum] \
								  [json::write array 'SKIP' $skip_sum]]
	}
	
	proc passratio_daily {args} {
	puts [info level 0]
		set filter [buildFilter {*}$args]
		
		set sql "SELECT min(SuiteId), max(SuiteId) FROM SuiteResult $filter"
		puts $sql
		lassign [::db eval $sql] start end
		set seconds [clock scan $start -format {%Y%m%d%H%M%S}]
		set day [clock format $seconds -format {%Y%m%d}]
		set cols_json [json::write array 'Date' {'Pass Ratio'}]
		while {[string compare $day $end] <= 0} {
			set condition [expr {$filter eq "" ? "WHERE SuiteId LIKE '$day%'" : "$filter AND SuiteId LIKE '$day%'"}]
			set sql "SELECT avg(passRatio) FROM SuiteResult $condition"
			puts $sql
			set passratio [::db onecolumn $sql]
			if {$passratio ne ""} {
				set passratio [::tcl::mathfunc::round $passratio]
				set value [json::write object v $passratio f '$passratio%']				
				lappend row_list [json::write array [clock format [clock add $seconds -1 months] -format {new Date(%Y,%m,%d)}] $value]
			}
			set seconds [clock add $seconds 1 days]
			set day [clock format $seconds -format {%Y%m%d}]
		}
		return [json::write array $cols_json {*}$row_list]
	}
	
	proc throughput_daily {stp args} {
	puts [info level 0]
		set filter [buildFilter Stp $stp {*}$args]
		
		set sql "SELECT min(SuiteId), max(SuiteId) FROM SuiteResult $filter"
		puts $sql
		lassign [::db eval $sql] start end
		set cols_json [json::write array 'Date' {'Throughput kbps'}]
		set result_list {}
		foreach {rbs sector ue} [::db eval "SELECT DISTINCT Rbs,Sector,UeId FROM TrafficResult $filter ORDER BY Rbs,Sector ASC"] {
			foreach direction [list DlThroughput UlThroughput] {
				set row_list {}
				set seconds [clock scan $start -format {%Y%m%d%H%M%S}]
				set day [clock format $seconds -format {%Y%m%d}]
				set key "$rbs,$sector,$ue,$direction"
				while {[string compare $day $end] <= 0} {
					set sql "SELECT avg($direction) FROM TrafficResult [buildFilter Stp $stp Rbs $rbs Sector $sector UeId $ue {*}$args] AND SuiteId LIKE '$day%'"
					set value [::db onecolumn $sql]
					if {$value ne ""} {
						set value [::tcl::mathfunc::round $value]
						set value [json::write object v $value f {'$value kbps'}]
						lappend row_list [json::write array [clock format [clock add $seconds -1 months] -format {new Date(%Y,%m,%d)}] $value]
					}
					set seconds [clock add $seconds 1 days]
					set day [clock format $seconds -format {%Y%m%d}]
				}
				lappend result_list $key [json::write array $cols_json {*}$row_list]
			}
		}
		return $result_list
	}
	
	proc utilization_daily {args} {
	puts [info level 0]
		set filter [buildFilter {*}$args]
		
		set sql "SELECT min(SuiteId), max(SuiteId) FROM SuiteResult $filter"
		puts $sql
		lassign [::db eval $sql] start end
		set seconds [clock scan $start -format {%Y%m%d%H%M%S}]
		set day [clock format $seconds -format {%Y%m%d}]
		set cols_json [json::write array 'Date' {'Utilization Ratio'}]
		while {[string compare $day $end] <= 0} {
			set condition [expr {$filter eq "" ? "WHERE SuiteId LIKE '$day%'" : "$filter AND SuiteId LIKE '$day%'"}]
			set sql "SELECT sum(duration) FROM SuiteResult $condition"
			puts $sql
			set execution_time [::db onecolumn $sql]
			if {$execution_time ne ""} {
				set utilization_ratio [expr {100 * $execution_time / ( 24 * 3600)}]
				set value [json::write object v $utilization_ratio f '$utilization_ratio%']				
				lappend row_list [json::write array [clock format [clock add $seconds -1 months] -format {new Date(%Y,%m,%d)}] $value]
			}
			set seconds [clock add $seconds 1 days]
			set day [clock format $seconds -format {%Y%m%d}]
		}
		return [json::write array $cols_json {*}$row_list]
	}
	
	proc passratio_rusw_tc {args} {
	puts [info level 0]
		set filter [buildFilter {*}$args]
		
		array set statusMap [list 1 "pass" 2 "fail" 3 "skip"]
		set sql "SELECT RuSwVersion, Status FROM TestResult $filter"
		puts $sql
		set result_dict [dict create]
		foreach {ver status} [::db eval $sql] {
			set cat $statusMap($status)	
			dict update result_dict $ver ver_dict {
				dict incr ver_dict $cat
			}
		}
		set count_rows [json::write array 'RUS SW' 'PASS' 'FAIL' 'SKIP']
		set ratio_rows [json::write array 'RUS SW' 'PASS' 'FAIL' 'SKIP']
		foreach ver [lsort [dict keys $result_dict]] {
			set map [dict get $result_dict $ver]
			set pass [expr {[dict exists $map pass] ? [dict get $map pass] : 0}]
			set fail [expr {[dict exists $map fail] ? [dict get $map fail] : 0}]
			set skip [expr {[dict exists $map skip] ? [dict get $map skip] : 0}]
			lappend count_rows [json::write array '$ver' "{v:$pass,f:'$pass times'}" "{v:$fail,f:'$fail times'}" "{v:$skip,f:'$skip times'}" ]
			set sum [expr {$pass + $fail + $skip}]
			set pass_ratio [expr {$sum == 0 ? 0 : 100 * $pass / $sum}]
			set fail_ratio [expr {$sum == 0 ? 0 : 100 * $fail / $sum}]
			set skip_ratio [expr {$sum == 0 ? 0 : 100 * $skip / $sum}]
			lappend ratio_rows [json::write array '$ver' \
								     [json::write object v $pass_ratio f '$pass_ratio%'] \
								     [json::write object v $fail_ratio f '$fail_ratio%'] \
								     [json::write object v $skip_ratio f '$skip_ratio%'] ]
		}
		return [list [json::write array {*}$count_rows] [json::write array {*}$ratio_rows]]
	}
	
	proc passratio_tc_rusw {args} {
	puts [info level 0]
		set filter [buildFilter {*}$args]

		array set statusMap [list 1 "pass" 2 "fail" 3 "skip"]
		set sql "SELECT Name,Status FROM TestResult $filter"
		puts $sql
		set result_dict [dict create]
		foreach {tc status} [::db eval $sql] {
			set cat $statusMap($status)	
			dict update result_dict $tc tc_dict {
				dict incr tc_dict $cat
			}
		}
		set count_rows [json::write array 'Test' 'PASS' 'FAIL' 'SKIP']
		set ratio_rows [json::write array 'Test' 'PASS' 'FAIL' 'SKIP']
		foreach test [lsort [dict keys $result_dict]] {
			set map [dict get $result_dict $test]
			set pass [expr {[dict exists $map pass] ? [dict get $map pass] : 0}]
			set fail [expr {[dict exists $map fail] ? [dict get $map fail] : 0}]
			set skip [expr {[dict exists $map skip] ? [dict get $map skip] : 0}]
			lappend count_rows [json::write array '$test' $pass $fail $skip]
			set sum [expr {$pass + $fail + $skip}]
			set pass_ratio [expr {$sum == 0 ? 0 : 100 * $pass / $sum}]
			set fail_ratio [expr {$sum == 0 ? 0 : 100 * $fail / $sum}]
			set skip_ratio [expr {$sum == 0 ? 0 : 100 * $skip / $sum}]
			lappend ratio_rows [json::write array '$test' \
								     [json::write object v $pass_ratio f '$pass_ratio%'] \
								     [json::write object v $fail_ratio f '$fail_ratio%'] \
								     [json::write object v $skip_ratio f '$skip_ratio%']]
		}
		return [list [json::write array {*}$count_rows] [json::write array {*}$ratio_rows]]
	}
	
	proc duration_suite {args} {
	puts [info level 0]
		lappend json_row_list [json::write array 'Suite' \
					[list 'Average Execution Time in Minutes'] \
					[list 'Min Execution Time in Minutes'] \
					[list 'Max Execution Time in Minutes']]
		set sql "SELECT avg(duration), min(duration), max(duration) FROM SuiteResult"
		
		foreach suite [getSuites] {
			set filter [buildFilter Name $suite {*}$args]
			if {[::db onecolumn "SELECT count(*) FROM SuiteResult $filter"] > 0} {
				puts "$sql $filter"
				foreach {avg min max} [::db eval "$sql $filter"] {
					set avg [::tcl::mathfunc::round [expr {$avg / 60}]]
					set min [::tcl::mathfunc::round [expr {$min / 60}]]
					set max [::tcl::mathfunc::round [expr {$max / 60}]]
					lappend json_row_list [json::write array '$suite' $avg $min $max] 
				}
			}
		}
		return [json::write array {*}$json_row_list]
	}
	
	proc duration_test {args} {
	puts [info level 0]
		lappend json_row_list [json::write array 'Test' \
					[list 'Average Execution Time in Minutes'] \
					[list 'Min Execution Time in Minutes'] \
					[list 'Max Execution Time in Minutes']]
		set sql "SELECT avg(duration), min(duration), max(duration) FROM TestResult"

		foreach test [getTests] {
			set filter [buildFilter Name $test {*}$args]
			if {[::db onecolumn "SELECT count(*) FROM TestResult $filter"] > 0} {
				puts "$sql $filter"
				foreach {avg min max} [::db eval "$sql $filter"] {
					set avg [::tcl::mathfunc::round [expr {$avg / 60}]]
					set min [::tcl::mathfunc::round [expr {$min / 60}]]
					set max [::tcl::mathfunc::round [expr {$max / 60}]]
					lappend json_row_list [json::write array '$test' $avg $min $max] 
				}
			}
		}
		return [json::write array {*}$json_row_list]
	}
	
	proc throughput_rus {stp args} {
	puts [info level 0]
		
		lappend table_list
		set sql "SELECT DISTINCT Rbs FROM TrafficResult [buildFilter Stp $stp {*}$args]"
		puts $sql
		foreach rbs [::db eval $sql] {
			foreach key [list DlThroughput UlThroughput] {
				set sql "SELECT RuSwVersion, Sector, UeId, $key FROM TrafficResult [buildFilter Stp $stp Rbs $rbs {*}$args] AND $key > 0"
				puts $sql
				set result_dict [dict create]
				set count_dict [dict create]
				set ue_set {}
				foreach {rus sector ue value} [::db eval $sql] {
					set ue [list 'Sector $sector, Ue $ue']
					set ue_set [lsort -unique [lappend ue_set $ue]]
					dict incr count_dict $rus,$ue
					dict update result_dict $rus rus_dict {
						dict incr rus_dict $ue [::tcl::mathfunc::round $value]
					}	
				}
				set cols_json [json::write array {'RU SW'} {*}$ue_set]
				set row_list {}
				foreach rus [lsort [dict keys $result_dict]] {
					set rus_dict [dict get $result_dict $rus]
					set data ""
					foreach ue $ue_set {
						set value 0
						set sampleNum 0
						if {[dict exists $count_dict $rus,$ue]} {
							set sampleNum [dict get $count_dict $rus,$ue]
							set value [expr {[dict get $rus_dict $ue] / $sampleNum}]
						}
						set value [::tcl::mathfunc::round $value]
						lappend data [json::write object v $value f [list '$value kbps (samples: $sampleNum)']]
					}
					lappend row_list [json::write array '$rus' {*}$data]
				}
				lappend table_list $rbs,$key [json::write array $cols_json {*}$row_list]
			}
		}
		return $table_list
	}
	
	proc upgradePath_rus {stp args} {
	puts [info level 0]
	
		lappend row_list
		set ver_set [statistic::getRuSwVers {*}$args]
		set cols_json [json::write array 'Date' "'RUS SW'"]
		set sql "SELECT SuiteId, RuSwVersion From SuiteResult [buildFilter Stp $stp {*}$args] ORDER by SuiteId ASC"
		puts $sql
		set old ""
		foreach {date ver} [::db eval $sql] {
			if {$ver ne $old} {
				set date [clock format [clock scan $date -format "%Y%m%d%H%M%S"] -format {new Date(%Y,%m,%d,%H,%M,%S)}]
				if {$old ne ""} {
					set value [lsearch -exact $ver_set $old]
					lappend row_list [json::write array $date [json::write object v $value f '$old']]
				}
				set value [lsearch -exact $ver_set $ver]
				lappend row_list [json::write array $date [json::write object v $value f '$ver']]
				set old $ver
			}
		}
		return [list $ver_set [json::write array $cols_json {*}$row_list]]
	}
}


package provide statistic 1.0.0
