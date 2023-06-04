using Gtk4
# Gt4kMakie seems to need the GLib main loop to be running, which takes a little
# while on a Mac in an interactive session, due to the libuv stuff
# FIXME
if Sys.isapple()
    while !istaskstarted(Gtk4.GLib.glib_main_task)
        sleep(0.001)
    end
end
using Gtk4Makie, GLMakie

screen = Gtk4Makie.GTKScreen(resolution=(800, 800),title="10 random numbers")
display(screen, lines(rand(10)))
ax=current_axis()
f=current_figure()
inspector=DataInspector()
Makie.disable!(inspector)

g=grid(screen)

g[1,2]=GtkButton("Generate new random plot")

function gen_cb(b)
    empty!(ax)
    lines!(ax,rand(10))
    Gtk4.queue_render(Gtk4Makie.win2glarea[screen.glscreen])
end

signal_connect(gen_cb,g[1,2],"clicked")

g[1,3]=GtkButton("Save!")

function save_cb(b)
    save_dialog("Save plot",screen.glscreen) do filename
        GLMakie.save(filename, Makie.colorbuffer(screen))
    end
end

signal_connect(save_cb,g[1,3],"clicked")

g[1,4]=GtkToggleButton("Data inspector")

function inspector_cb(b)
    b.active ? Makie.enable!(inspector) : Makie.disable!(inspector)
    nothing
end

signal_connect(inspector_cb,g[1,4],"toggled")
