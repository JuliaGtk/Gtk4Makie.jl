using GtkMakie

screen = GTKScreen(resolution=(800, 800))

display(screen, scatter(1:4))

window[] = glarea
window[]
