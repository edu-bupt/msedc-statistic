#
# Tcl package index file
#
# Note sqlite*3* init specifically
#
package ifneeded inifile 0.2.5 [list source [file join $dir ini.tcl]]
package ifneeded json::write 1.0.2 [list source [file join $dir json_write.tcl]]
package ifneeded statistic 1.0.0 [list source [file join $dir statistic.tcl]]
package ifneeded sqlite3 3.7.14 \
    [list load [file join $dir libsqlite3.7.14.so] Sqlite3]
