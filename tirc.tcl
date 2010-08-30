set server "BROOKVILLE.PA.US.StarLink-IRC.Org"
set chn #prosapologian
set ::gotPing 0

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

	send "PRIVMSG $::chn :$msg"
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
		set cols [lreplace $cols end end [string range [lindex $cols end] 0 end-1]]
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
		.t.txt insert end "$line\n"
		adjustWin
	}
}

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
 
proc connect {} {
	set ::gotPing 0
	set ::net [socket $::server 6667]
	fconfigure $::net -encoding utf-8

	fileevent $::net readable recv

	send "NICK Ned"
	send "USER ned ned ned :NedBrek"
}
connect

