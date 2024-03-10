using Test
using Gtk4Makie, GLMakie, Gtk4

Gtk4.GLib.start_main_loop()

@testset "backend" begin
    Gtk4Makie.enable_backend(false)
end

@testset "window screen" begin
    screen = Gtk4Makie.GTKScreen(size=(800, 800))
    @test isopen(screen)
    @test GLMakie.ALL_SCREENS == Set([screen])
    @test isempty(GLMakie.SCREEN_REUSE_POOL)
    @test isempty(GLMakie.SINGLETON_SCREEN)
    
    screen2 = Gtk4Makie.GTKScreen(size=(800, 800))
    @test GLMakie.ALL_SCREENS == Set([screen, screen2])
    @test isempty(GLMakie.SCREEN_REUSE_POOL)

    @test window(screen) != window(screen2)

    display(screen, scatter(1:4))
    ax=current_axis()
    @test Makie.getscreen(ax.scene) == screen
    
    g=grid(screen)
    
    insert!(g,1,:top)
    g[1,1]=GtkLabel("a title widget")
    
    g[1,3]=GtkLabel("another widget on the bottom")
    
    sleep(10)

    GLMakie.framebuffer_size(screen.glscreen)

    GLMakie.save("test.png", Makie.colorbuffer(screen))
    @test isfile("test.png")
    
    awin = attributes_window()
    close(awin)
    
    Gtk4.G_.activate_action(window(screen), "win.figure", nothing)
    sleep(0.5)
    Gtk4.G_.activate_action(window(screen), "win.inspector", nothing)
    sleep(0.5)
    Gtk4.G_.activate_action(window(screen), "win.fullscreen", nothing)
    sleep(0.5)
    
    close(screen)
    
    @test !isopen(screen) && isopen(screen2)
    
    # assure we correctly close screen and remove it from plot
    @test Makie.getscreen(ax.scene) === nothing
    @test !events(ax.scene).window_open[]
    @test isempty(events(ax.scene).window_open.listeners)
    
    Gtk4.G_.activate_action(window(screen2), "win.close", nothing)

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
    
    screen = Gtk4Makie.screens[Ptr{Gtk4.GtkGLArea}(p[1].handle)]
    @test isopen(screen)
    @test window(screen) == win
    
    ax = current_axis()
    @test Makie.getscreen(ax.scene) == screen
    
    screen2 = Gtk4Makie.screens[Ptr{Gtk4.GtkGLArea}(p[2].handle)]
    @test isopen(screen2)
    @test window(screen) == window(screen2)
    
    push!(p[2],scatter(rand(10)))
    sleep(1)
    
    empty!(p[1])
    sleep(1)

    destroy(win)
end

function test_event_handling(screen)
    g = glarea(screen)
    s = screen.root_scene
    if get(ENV, "CI", nothing) != "true"
        @test s.events.hasfocus[]
    end
    ecm = Gtk4.find_controller(g, GtkEventControllerMotion)
    signal_emit(ecm, "motion", Nothing, 200.0, 200.0)
    sleep(1)
    if get(ENV, "CI", nothing) != "true"
        @test s.events.mouseposition[] == GLMakie.correct_mouse(g,200.0,200.0)
    end
    
    signal_emit(ecm, "leave", Nothing)
    @test !s.events.entered_window[]
    
    signal_emit(ecm, "enter", Nothing, 200.0, 200.0)
    @test s.events.entered_window[]
    
    egc = Gtk4.find_controller(g, GtkGestureClick)
    signal_emit(egc, "pressed", Nothing, 1, 200.0, 200.0)
    @test s.events.mousebutton[].action == Mouse.press
    signal_emit(egc, "released", Nothing, 1, 200.0, 200.0)
    @test s.events.mousebutton[].action == Mouse.release
    
    eck = Gtk4.find_controller(toplevel(g), GtkEventControllerKey)
    signal_emit(eck, "key-pressed", Bool, Cuint(65507), Cuint(0), Cuint(0))
    @test s.events.keyboardbutton[].key == Makie.Keyboard.left_control
    @test s.events.keyboardbutton[].action == Keyboard.Action(Int(1))
    signal_emit(eck, "key-released", Nothing, Cuint(65508), Cuint(0), Cuint(0))
    @test s.events.keyboardbutton[].key == Makie.Keyboard.right_control
    @test s.events.keyboardbutton[].action == Keyboard.Action(Int(0))
    
    ecs = Gtk4.find_controller(g, GtkEventControllerScroll)
    signal_emit(ecs, "scroll", Bool, 0.0, 1.0)
    @test s.events.scroll[] == (0.0,1.0)
end

@testset "event handling for window" begin
    screen = Gtk4Makie.GTKScreen(size=(800, 800))
    display(screen, scatter(1:4))
    
    w = window(screen)
    s = screen.root_scene
    sleep(1) # allow window to be drawn
    start_area = s.events.window_area[]
    
    w.default_height = 800
    sleep(1)
    finish_area = s.events.window_area[]
    @test start_area.widths[1] == finish_area.widths[1]
    @test start_area.widths[2] != finish_area.widths[2]
    
    test_event_handling(screen)
    
    close(w)
    @test !isopen(screen)
end

@testset "event handling for widget" begin
    win = GtkWindow("2 Makie widgets in one window", 600, 600, true, false)
    wid = GtkMakieWidget()
    win[] = wid
    push!(wid,lines(rand(10)))
    show(win)
    
    screen = Gtk4Makie.screens[Ptr{Gtk4.GtkGLArea}(wid.handle)]
    
    sleep(2)
    test_event_handling(screen)
    
    sleep(1)
    destroy(win)
end
