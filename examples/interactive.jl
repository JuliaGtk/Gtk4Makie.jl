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

screen = Gtk4Makie.GTKScreen(size=(800, 800),title="10 random numbers")
display(screen, lines(rand(10)))
ax=current_axis()

g=grid(screen)

g[1,2]=GtkButton("Generate new random plot")

function gen_cb(b)
    empty!(ax)
    lines!(ax,rand(10))
end

signal_connect(gen_cb,g[1,2],"clicked")
mb=Gtk4Makie.menubutton(screen)
