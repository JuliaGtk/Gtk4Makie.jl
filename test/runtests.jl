using GtkMakie, GLMakie, Gtk4

screen = GtkMakie.GTKScreen(resolution=(800, 800))

display(screen, scatter(1:4))

g=grid(screen)

insert!(g,1,:top)
g[1,1]=GtkLabel("a title widget")

g[1,3]=GtkLabel("another widget on the bottom")
