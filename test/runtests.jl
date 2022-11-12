using GtkMakie, GLMakie

screen = GtkMakie.GTKScreen(resolution=(800, 800))

display(screen, scatter(1:4))

Gtk4.queue_render(screen.glscreen[])
