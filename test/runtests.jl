using Test
using Gtk4Makie, GLMakie, Gtk4

@testset "window screen" begin
    screen = Gtk4Makie.GTKScreen(resolution=(800, 800))
    screen2 = Gtk4Makie.GTKScreen(resolution=(800, 800))

    @test window(screen) != window(screen2)

    display(screen, scatter(1:4))
    
    g=grid(screen)
    
    insert!(g,1,:top)
    g[1,1]=GtkLabel("a title widget")
    
    g[1,3]=GtkLabel("another widget on the bottom")
    
    sleep(10)

    GLMakie.framebuffer_size(screen.glscreen)

    GLMakie.save("test.png", Makie.colorbuffer(screen))
    @test isfile("test.png")
    
    attributes_window()

    close(screen)

    GLMakie.closeall()
end

@testset "widget screen" begin
    win = GtkWindow("2 Makie widgets in one window", 600, 600, true, false)
    p=GtkPaned(:v;position=200)
    p[1]=GtkMakieWidget()
    p[2]=GtkMakieWidget()
    win[]=p

    show(win)

    push!(p[1],lines(rand(10)))
    push!(p[2],scatter(rand(10)))

    destroy(win)
end
