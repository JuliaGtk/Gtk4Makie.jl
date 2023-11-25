using Gtk4
using Gtk4Makie

if isinteractive()
    stop_main_loop()  # g_application_run will run the loop
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
