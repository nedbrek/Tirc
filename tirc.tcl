set server "BROOKVILLE.PA.US.StarLink-IRC.Org"
set chn #prosapologian
set ::gotPing 0
set ::inNames 0
set ::nick    Ned

# high contrast colors for different people
set colors {
	darkblue
	darkgreen
	darkcyan
	darkred
	darkmagenta
	darkorange
	darkslategrey
}

proc adjustWin {} {
	set cursor [.t.fTop.scrollV get]
	if {[lindex $cursor 1] == 1.0} {
		.t.txt yview end
	}
}

# assign a random (but deterministic) color to a nick
proc nickcolor {nick} {
	binary scan $nick c* v
	set hash 4817
	set op +

	foreach x $v {
		set hash [expr "$hash $op $x"]
		set op [if {$op eq {+}} {concat *} {concat +}]
	}

	set hash [expr {$hash % [llength $::colors]}]
	return [lindex $::colors $hash]
}

proc send {msg} {
	puts $::net $msg
	flush $::net
}

proc post {} {
	set msg [.t.cmd get]
	if {$msg eq ""} {return}

	if {[regexp {^ */([^ ]+) *(.*)} $msg -> cmd line]} {
		switch $cmd {
			me {
				set sendout "\001ACTION $line\001"
				send "PRIVMSG $::chn :$sendout"
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

	.t.txt insert end "$msg\n"
	adjustWin

	.t.cmd delete 0 end
}

proc handlePing {code} {
	send "PONG $code"

	if {!$::gotPing} {
		send "JOIN $::chn"
		set ::gotPing 1
	}

	.t.txt insert end "PONG $code\n" ping
	adjustWin
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
		.t.txt insert end "* $sendName " $nc

		# strip the trailing 1
		set cols [lreplace $cols end end \
        [string range [lindex $cols end] 0 end-1]]
	} else {
		.t.txt insert end "$sendName $first " $nc
	}

	.t.txt insert end "[join [lrange $cols 4 end]]\n" $nc

	adjustWin
}

proc recv {} {
	if [eof $::net] {
		fileevent $::net readable ""
		close $::net

		.t.txt insert end "Socket closed\n"
		adjustWin
		return
	}

	gets $::net line

	if [regexp {^PING (:[0-9A-Za-z.\-]+)} $line -> code] {
		.t.txt insert end "$line\n" ping
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
			.t.txt insert end "$line\n"
			adjustWin
		}
	}
}

proc completeName {} {
	set s [.t.cmd get]
	set i [.t.cmd index insert]
	if {[string index $s $i] == " "} {
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

	.t.cmd delete $i $e
	.t.cmd insert $i $name
}

####################################################################
wm withdraw .
toplevel .t

pack [frame .t.fTop] -side top -fill both -expand 1

pack [scrollbar .t.fTop.scrollV -orient vert -command ".t.txt yview"
] -side right -expand 1 -fill y

# create the main text widget
pack [text  .t.txt -yscrollcommand ".t.fTop.scrollV set"
] -expand 1 -fill both -in .t.fTop -side left

foreach color $colors {
	.t.txt tag config $color -foreground $color
}
.t.txt tag config ping -foreground lightgrey

pack [entry .t.cmd] -expand 1 -fill x
bind .t.cmd <Return> post
bind .t.cmd <Tab> {completeName; break}
 
####################################################################
toplevel .tNames

pack [listbox .tNames.lb -listvariable names -height 25 \
-yscrollcommand ".tNames.scrollV set"] -side left

pack [scrollbar .tNames.scrollV -orient vert -command ".tNames.lb yview"
] -side right -expand 1 -fill y

####################################################################
proc connect {} {
	.t.txt insert end "Connecting to $::server\n"

	set ::gotPing 0
	set ::net [socket $::server 6667]
	fconfigure $::net -encoding utf-8

	fileevent $::net readable recv

	send "NICK $::nick"
	send "USER ned ned ned :NedBrek"
}
connect

