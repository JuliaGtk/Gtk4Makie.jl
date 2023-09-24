using Gtk4, Gtk4.GLib
using Gtk4Makie, GLMakie

if isinteractive()
    Gtk4.GLib.stop_main_loop()  # g_application_run will run the loop
end

function activate(app)
    screen = Gtk4Makie.GTKScreen(resolution=(800, 800),title="10 random numbers",app=app)
    display(screen, lines(rand(10)))
    ax=current_axis()
    f=current_figure()

    g=grid(screen)
    
    g[1,2]=GtkButton("Generate new random plot")
    
    function gen_cb(b)
        empty!(ax)
        lines!(ax,rand(10))
        Gtk4.queue_render(Gtk4Makie.win2glarea[screen.glscreen])
    end
    
    signal_connect(gen_cb,g[1,2],"clicked")
end

global app = GtkApplication("julia.gtkmakie.example")

Gtk4.signal_connect(activate, app, :activate)

if isinteractive()
    loop()=Gtk4.run(app)
    t = schedule(Task(loop))
else
    Gtk4.run(app)
end
