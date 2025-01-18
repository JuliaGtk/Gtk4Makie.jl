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
vbox = GtkBox(:v)
hbox = push!(GtkBox(:h), vbox)
p=GtkPaned(:v;position=300)
p[1]=GtkMakieWidget()
p[2]=GtkMakieWidget()
push!(hbox, p)
win[]=hbox

# Add axes to the widgets
function add_axis!(widget)
    f = Figure()
    ax = Axis(f[1, 1])
    push!(widget, f)
    ax
end

axes = [add_axis!(p[i]) for i in 1:2]

new_scatter_button = GtkButton("Add a scatter")
clear_figure = GtkButton("Clear figure")
label = GtkLabel("Select figure:")
dropdown = GtkDropDown(string.(1:2))
push!(vbox, label, dropdown, new_scatter_button, clear_figure)

signal_connect(new_scatter_button, "clicked") do b
    plotnum = Gtk4.G_.get_selected(dropdown) + 1
    scatter!(axes[plotnum], rand(100))
end

signal_connect(clear_figure, "clicked") do b
    plotnum = Gtk4.G_.get_selected(dropdown) + 1
    empty!(axes[plotnum])
end

show(win)

