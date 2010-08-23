set server "BROOKVILLE.PA.US.StarLink-IRC.Org"
set chn #prosapologian

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
	if [regexp {^PING (:[0-9]+)} $line -> code] {
		send "PONG $code"

		.t.txt insert end "PING\n"; .t.txt yview end
		return
	}

	.t.txt insert end "$line\n"
	.t.txt yview end
}

wm withdraw .
toplevel .t

pack [text  .t.txt] -expand 1 -fill both
pack [entry .t.cmd] -expand 1 -fill x
bind .t.cmd <Return> post

set net [socket $server 6667]
fileevent $net readable recv

send "NICK NedTclTest"
send "USER ned ned ned :NedBrek"
send "JOIN $chn"

