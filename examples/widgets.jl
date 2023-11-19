using Gtk4Makie, Gtk4, GLMakie

# Simple example using GtkMakieWidget

win = GtkWindow("2 Makie widgets in one window", 600, 600, true, false)
p=GtkPaned(:v;position=200)
p[1]=Gtk4Makie.GtkMakieWidget()
p[2]=Gtk4Makie.GtkMakieWidget()
win[]=p

push!(p[1],lines(rand(10)))
push!(p[2],scatter(rand(10)))
show(win)

