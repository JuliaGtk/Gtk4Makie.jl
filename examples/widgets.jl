using Gtk4Makie, Gtk4

# Simple example using GtkMakieWidget

win = GtkWindow("2 Makie widgets in one window", 600, 600, true, false)
p=GtkPaned(:v;position=200)
p[1]=GtkMakieWidget()
p[2]=GtkMakieWidget()
win[]=p

show(win)

push!(p[1],lines(rand(10)))
push!(p[2],scatter(rand(10)))

empty!(p[1])
push!(p[1],lines(rand(10)))
