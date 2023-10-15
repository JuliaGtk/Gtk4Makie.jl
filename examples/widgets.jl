using Gtk4Makie, Gtk4, GLMakie, Makie

win = GtkWindow(;visible=false,title="2 Makie widgets in one window")
p=GtkPaned(:v;position=200)
p[1]=Gtk4Makie.GtkMakieWidget()
p[2]=Gtk4Makie.GtkMakieWidget()
win[]=p

push!(p[1],lines(rand(10)))
push!(p[2],scatter(rand(10)))
show(win)
