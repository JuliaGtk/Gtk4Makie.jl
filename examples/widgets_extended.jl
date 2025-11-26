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

# Extended example using GtkMakieWidget

win = GtkWindow("2 Makie widgets", 800, 800, true, false)
vbox = GtkBox(:v)
hbox = push!(GtkBox(:h), vbox)
g=GtkGrid()
g[1,1]=GtkMakieWidget()
g[2,1]=GtkMakieWidget()
push!(hbox, g)
win[]=hbox

# Add axes to the widgets
function add_axis!(widget)
    f = Figure()
    ax = Axis(f[1, 1])
    push!(widget, f)
    ax
end

axes = [add_axis!(g[i,1]) for i in 1:2]

g[1,2]=Gtk4Makie.interactive_legend(axes[1])
g[2,2]=Gtk4Makie.interactive_legend(axes[2])

new_scatter_button = GtkButton("Add a scatter")
clear_figure = GtkButton("Clear figure")
dropdown = GtkDropDown(string.(1:2))
entry = GtkEntry()
push!(vbox, GtkLabel("Select figure:"), dropdown, new_scatter_button, GtkLabel("Label:"), entry, clear_figure)

signal_connect(new_scatter_button, "clicked") do b
    plotnum = Gtk4.selected(dropdown)
    scatter!(axes[plotnum], rand(100); label = Gtk4.text(entry))
    @idle_add Gtk4.model(g[plotnum,2], Gtk4Makie.plots_model(axes[plotnum]))  # update the legend
end

signal_connect(clear_figure, "clicked") do b
    plotnum = Gtk4.selected(dropdown)
    empty!(axes[plotnum])
    @idle_add Gtk4.model(g[plotnum,2], Gtk4Makie.plots_model(axes[plotnum]))  # update the legend
end

show(win)

