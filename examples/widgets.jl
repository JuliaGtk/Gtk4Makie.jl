using Gtk4
# Gt4kMakie seems to need the GLib main loop to be running, which takes a little
# while on a Mac in an interactive session, due to the libuv stuff
# FIXME
if Sys.isapple()
    while !istaskstarted(Gtk4.GLib.glib_main_task)
        sleep(0.001)
    end
end
using Gtk4Makie

# Simple example using GtkMakieWidget

win = GtkWindow("2 Makie widgets in one window", 600, 600, true, false)
p=GtkPaned(:v;position=200)
p[1]=GtkMakieWidget()
p[2]=GtkMakieWidget()
win[]=p

show(win)

push!(p[1],lines(rand(10)))
push!(p[2],scatter(rand(10)))

# not needed, just demonstrates that this works
empty!(p[1])
push!(p[1],lines(rand(10)))
