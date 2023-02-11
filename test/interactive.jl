using Gtk4
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
