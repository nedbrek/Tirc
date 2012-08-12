package require Tk

##############################################################################
# global state
set ::gotPing 0
set ::inNames 0
set resourceFileName .tircrc

# current connection
set ::server ""
set ::chn    ""
set ::nick   ""

##############################################################################
# nick colorization

# high contrast colors for different people
set ::colors {
	darkblue
	darkgreen
	darkcyan
	darkred
	darkmagenta
	darkorange
	darkslategrey
}

# assign a random (but deterministic) color to a nick
proc nickcolor {nick} {
	binary scan $nick c* v
	set hash 4817
	set op *

	foreach x $v {
		set hash [expr "$hash $op $x"]
		set op [if {$op eq {+}} {concat *} {concat +}]
	}

	set hash [expr {$hash % [llength $::colors]}]
	return [lindex $::colors $hash]
}

##############################################################################
# server management

# make the current settings match 'idx'
proc setServer {idx} {
	set cfg $::servers($idx)

	set ::server [lindex $cfg 0]
	set ::chn    [lindex $cfg 1]
	set ::nick   [lindex $cfg 2]
}

# show a dialog with all configured servers, along with "Set" buttons for each
proc showServers {} {
	toplevel .tServers
	wm title .tServers "Servers"

	foreach i [lsort -integer [array names ::servers]] {
		set cfg $::servers($i)

		grid [label .tServers.lS$i -text "[lindex $cfg 0]"] -row $i -column 0
		grid [label .tServers.lC$i -text "[lindex $cfg 1]"] -row $i -column 1
		grid [label .tServers.lN$i -text "[lindex $cfg 2]"] -row $i -column 2

		grid [button .tServers.bS$i -text "Set" -command [list setServer $i]] \
-row $i -column 3
	}
}

# write current server info to resource file
proc saveAllServers {} {
	set f [open [file join ~ $::resourceFileName] w]

	puts $f "set server $::server"
	puts $f "set chn    $::chn"
	puts $f "set nick   $::nick"

	set ct 0

	foreach cfg [lsort -integer [array names ::servers]] {
		puts $f "set ::servers($ct) [list $::servers($cfg)]"

		incr ct
	}

	close $f
}

# helper for createServInfoWin
# save the dialog settings into the server array
proc saveServInfo {} {
	set sv [.tsi.eServ get]
	set cn [.tsi.eChn  get]
	set nk [.tsi.eNick get]

	if {$sv eq "" || $cn eq "" || $nk eq ""} {
		tk_messageBox -message "Invalid configuration: All fields required"
		return
	}

	set ct [llength [array names ::servers]]
	set ::servers($ct) [list $sv $cn $nk]
	setServer $ct
	saveAllServers
}

# create a dialog to get server settings
# new server is saved to the ::servers array
proc createServInfoWin {} {
	toplevel .tsi

	grid [label .tsi.lServ -text "Server:"] -row 0 -column 0
	grid [entry .tsi.eServ] -row 0 -column 1
	if {[info exists ::server]} {
		.tsi.eServ insert end $::server
	}

	grid [label .tsi.lChn -text "Channel:"] -row 1 -column 0
	grid [entry .tsi.eChn] -row 1 -column 1
	if {[info exists ::chn]} {
		.tsi.eChn insert end $::chn
	}

	grid [label .tsi.lNick -text "Nickname:"] -row 2 -column 0
	grid [entry .tsi.eNick] -row 2 -column 1
	if {[info exists ::nick]} {
		.tsi.eNick insert end $::nick
	}

	grid [button .tsi.bOk -text "Ok" -command {
		saveServInfo
		destroy .tsi
	}] -row 3 -column 0

	grid [button .tsi.bCan -text "Cancel" -command {destroy .tsi}
	] -row 3 -column 1

	tkwait window .tsi
}

##############################################################################
### handle resource file
# read existing
if {[file exists [file join ~ $resourceFileName]]} {

	set f [open [file join ~ $resourceFileName]]
	eval [read $f]
	close $f
	unset f

} else {
	# prompt user
	createServInfoWin
}

# check results
while {![info exists ::servers] || [array names ::servers] eq ""} {

	set r [tk_messageBox -message "No channel information set, Quit?" \
	       -title "Quit" -type yesno]

	if {$r eq "yes"} {exit}

	createServInfoWin
}

##############################################################################
# text widget management

# make the bottom visible (if not scrolling back)
proc adjustWin {w} {
	set cursor [$w.fTop.scrollV get]
	if {[lindex $cursor 1] == 1.0} {
		$w.fTop.txt yview end
	}
}

# append 'msg' to 'w' with 'tag'
proc log {w msg {tag ""}} {
	$w.fTop.txt configure -state normal
	$w.fTop.txt insert end $msg $tag
	$w.fTop.txt configure -state disabled
	adjustWin $w
}

##############################################################################
# send 'msg' to the current net connection
proc send {msg} {
	puts $::net $msg
	flush $::net
}

# process current command line
proc post {} {
	set msg [string trimright [.t.cmd get 1.0 end]]
	if {$msg eq ""} {return} ;# nothing to do

	# check for slash command
	if {[regexp {^ */([^ ]+) *(.*)} $msg -> cmd line]} {
		switch $cmd {
			me {
				set sendout "\001ACTION $line\001"
				send "PRIVMSG $::chn :$sendout"
			}

			msg {
				set tgt [lindex $line 0]
				send "PRIVMSG $tgt :[lrange $line 1 end]"
			}

			nick {
				send "NICK $line"
				set ::nick $line
			}

			quit {
				send "QUIT $line"
			}
		}
	} else {
		send "PRIVMSG $::chn :$msg"
	}

	log .t "$msg\n"

	.t.cmd delete 1.0 end
}

proc joinTimeout {} {
	if {!$::gotPing} {
		send "JOIN $::chn"
		set ::gotPing 1
	}
}

proc handlePing {code} {
	send "PONG $code"

	if {!$::gotPing} {
		send "JOIN $::chn"
		set ::gotPing 1
	}

	log .t "PONG $code\n" ping
}

# a normal message
proc handleMsg {line} {
	# strip color commands
	regsub -all {\003([[:digit:]]+(,[[:digit:]])?)?} $line "~" line
	set cols [split $line]

	set sender [lindex $cols 0]
	set bangIdx [string first "!" $sender]
	set sendName [string range $sender 1 $bangIdx]

	set nc [nickcolor $sendName]

	# column 1 is PRIVMSG
	# column 2 is target (usually channel name)
	# column 3 starts message with ':'

	set first [string range [lindex $cols 3] 1 end]
	if {$first == "\001ACTION"} {
		log .t "* $sendName " $nc

		# strip the trailing 1
		set cols [lreplace $cols end end \
		  [string range [lindex $cols end] 0 end-1]]
	} else {
		log .t "$sendName $first " $nc
	}

	log .t "[join [lrange $cols 4 end]]\n" $nc
}

proc recv {} {
	if [eof $::net] {
		fileevent $::net readable ""
		close $::net

		log .t "Socket closed\n"
		return
	}

	gets $::net line
#puts $line;#debugging

	if [regexp {^PING (:[0-9A-Za-z.\-]+)} $line -> code] {
		log .t "$line\n" ping
		handlePing $code

		return
	}

	if {[regexp {[^ ]+ +PRIVMSG } $line]} {
		handleMsg $line
	} else {
		set cols [split $line]

		set print 1
		switch [lindex $cols 1] {
			353 {
				# names
				if {!$::inNames} {
					set ::names ""
					set ::inNames 1
				}

				lappend ::names [string range [lindex $cols 5] 1 end]
				lappend ::names {*}[lrange $cols 6 end]
			}

			366 {
				# end of names
				set ::inNames 0

				set print 0 ;# don't need to see
			}

			JOIN {
				set sender [lindex $cols 0]
				set bangIdx [string first "!" $sender]
				set sendName [string range $sender 1 $bangIdx-1]
				lappend ::names $sendName
			}

			KICK {
				if {[lindex $cols 3] eq $::nick} {
					send "JOIN $::chn"
				} else {
				}
			}

			NICK {
				set sender [lindex $cols 0]
				set bangIdx [string first "!" $sender]
				set sendName [string range $sender 1 $bangIdx-1]
				set li [lsearch -regexp $::names "@?$sendName"]
				if {$li != -1} {
					set newNick [string range [lindex $cols 2] 1 end]
					set ::names [lreplace $::names $li $li $newNick]
				}
			}

			QUIT {
				set sender [lindex $cols 0]
				set bangIdx [string first "!" $sender]
				set sendName [string range $sender 1 $bangIdx-1]
				set li [lsearch -regexp $::names "@?$sendName"]
				if {$li != -1} {
					set ::names [lreplace $::names $li $li]
				}
			}
		}

		if {$print} {
			log .t "$line\n"
		}
	}
}

proc completeName {} {
	set s [.t.cmd get 1.0 end]

	set i [lindex [split [.t.cmd index insert] .] 1]

	set si [string index $s $i]
	if {$si eq " " || $si eq "\n"} {
		incr i -1
	}

	set i [string wordstart $s $i]

	set e [string wordend   $s $i]

	set ss [string range $s $i $e-1]

	set li [lsearch -regexp $::names $ss]
	set name [lindex $::names $li]
	if {[string index $name 0] == "@"} {
		set name [string range $name 1 end]
	}

	.t.cmd delete 1.$i 1.$e
	.t.cmd insert 1.$i $name
}

####################################################################
# main gui
wm withdraw .
toplevel .t
wm title .t "Tirc"

pack [frame .t.fTop] -side top -fill both -expand 1

pack [scrollbar .t.fTop.scrollV -orient vert -command ".t.fTop.txt yview"
] -side right -expand 1 -fill y

# create the main text widget
pack [text .t.fTop.txt -yscrollcommand ".t.fTop.scrollV set" -state disabled
] -expand 1 -fill both -side left

foreach color $colors {
	.t.fTop.txt tag config $color -foreground $color
}
.t.fTop.txt tag config ping -foreground lightgrey

# command line
pack [text .t.cmd -height 1]
bind .t.cmd <Return> {post; break}
bind .t.cmd <Tab> {completeName; break}
 
# menu
menu .mTopMenu -tearoff 0
menu .mTopMenu.mSettings -tearoff 0

.mTopMenu add cascade -label "Settings" -menu .mTopMenu.mSettings -underline 0

.mTopMenu.mSettings add command -label "Host Info" -underline 0 \
  -command createServInfoWin
.mTopMenu.mSettings add command -label "Servers" -underline 0 \
  -command showServers

.t configure -menu .mTopMenu

####################################################################
# names window (current people in channel)
toplevel .tNames

pack [listbox .tNames.lb -listvariable names -height 25 \
-yscrollcommand ".tNames.scrollV set"] -side left

pack [scrollbar .tNames.scrollV -orient vert -command ".tNames.lb yview"
] -side right -expand 1 -fill y

####################################################################
proc connect {} {
	log .t "Connecting to $::server\n"
	wm title .t "Tirc $::server"

	set ::gotPing 0
	set ::net [socket $::server 6667]
	fconfigure $::net -encoding utf-8

	fileevent $::net readable recv

	send "NICK $::nick"
	send "USER $::nick $::nick $::nick :$::nick"
	after 5000 joinTimeout 
}

