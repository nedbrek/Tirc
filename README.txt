This is the Tcl IRC client I wrote over the course of a few days.

I wanted to join a particular IRC channel, but the recommended client was
nag-ware.

Supports:
	colorized nicks
	partial implementation of the name list gui (some names may get lost)

	actions (/me does action)
	changing nick (/nick command)
	quit (/quit)

	tab completion of nicks
	auto-rejoin after kick (some people are playful with kicking)

Not bad for <300 lines of Tcl!

I usually source the client into a wish shell, that way I can inspect state
or make patches on the fly:

wish &
wish> source tirc.tcl

What is needed for general use is a way to easily set the server name, channel,
and starting nick (which I have hardcoded to me and my channel).

