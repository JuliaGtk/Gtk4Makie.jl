using Test
using Gtk4Makie, GLMakie, Gtk4

@testset "screen" begin
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

    close(screen)

    GLMakie.closeall()
end


