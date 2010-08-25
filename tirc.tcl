set server "BROOKVILLE.PA.US.StarLink-IRC.Org"
set chn #prosapologian
set ::gotPing 0

proc send {msg} {
	puts $::net $msg
	flush $::net
}

proc post {} {
	set msg [.t.cmd get]

	send "PRIVMSG $::chn :$msg"
	.t.txt insert end $msg

	.t.cmd delete 0 end
}

proc recv {} {
	if [eof $::net] {
		fileevent $::net readable ""
		close $::net

		.t.txt insert end "Socket closed\n"
		.t.txt yview end
		return
	}

	gets $::net line
	if [regexp {^PING (:[0-9A-Za-z.\-]+)} $line -> code] {
		send "PONG $code"

		if {!$::gotPing} {
			send "JOIN $::chn"
			set ::gotPing 1
		}

		.t.txt insert end "$line\n"
		.t.txt insert end "PONG $code\n";
		return
	}

	if {[regexp {[^ ]+ +PRIVMSG } $line]} {
		set cols [split $line]

		set sender [lindex $cols 0]
		set bangIdx [string first "!" $sender]
		set sendName [string range $sender 1 $bangIdx]

		set first [lindex $cols 3]
		.t.txt insert end "$sendName [string range $first 1 end] "
		.t.txt insert end "[lrange $cols 4 end]\n"
	} else {
		.t.txt insert end "$line\n"
		.t.txt yview end
	}
}

wm withdraw .
toplevel .t

pack [frame .t.fTop] -side top -fill both -expand 1

pack [scrollbar .t.fTop.scrollV -orient vert -command ".t.txt yview"
] -side right -expand 1 -fill y

pack [text  .t.txt -yscrollcommand ".t.fTop.scrollV set"
] -expand 1 -fill both -in .t.fTop -side left
pack [entry .t.cmd] -expand 1 -fill x
bind .t.cmd <Return> post
 
set ::gotPing 0
set net [socket $server 6667]

fileevent $net readable recv

send "NICK NedTclTest"
send "USER ned ned ned :NedBrek"

