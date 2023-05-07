using Gtk4
# GtkMakie seems to need the main loop to be running, which takes a little
# while on a Mac in an interactive session, due to the libuv stuff
# FIXME
if Sys.isapple()
    while !istaskstarted(Gtk4.GLib.glib_main_task)
        sleep(0.001)
    end
end
using GtkMakie, GLMakie

screen = GtkMakie.GTKScreen(resolution=(800, 800),title="10 random numbers")
display(screen, lines(rand(10)))
ax=current_axis()
f=current_figure()

g=grid(screen)

g[1,2]=GtkButton("Generate new random plot")

function gen_cb(b)
    empty!(ax)
    lines!(ax,rand(10))
    Gtk4.queue_render(GtkMakie.win2glarea[screen.glscreen])
end

signal_connect(gen_cb,g[1,2],"clicked")

g[1,3]=GtkButton("Save!")

function save_cb(b)
    save_dialog("Save plot",screen.glscreen) do filename
        GLMakie.save(filename, Makie.colorbuffer(screen))
    end
end

signal_connect(save_cb,g[1,3],"clicked")
