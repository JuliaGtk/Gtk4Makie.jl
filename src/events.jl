function Makie.disconnect!(window::Gtk4.GtkWindowLeaf, func)
    # TODO
end
function Makie.disconnect!(window::GTKGLWindow, func)
    # TODO
end

function Makie.window_open(scene::Scene, window::GTKGLWindow)
    event = scene.events.window_open
    signal_connect(parent(window), :close_request) do w
        event[] = false
        nothing
    end
    event[] = true
end

function Makie.window_area(scene::Scene, screen::GLMakie.Screen{Gtk4.GtkWindowLeaf})
end

function Makie.mouse_buttons(scene::Scene, window::GTKGLWindow)
    event = scene.events.mousebutton
    # create callback and connect to event controller
    g=GtkGestureClick(window)
    function on_pressed(controller, n_press, x, y)
        event[] = MouseButtonEvent(Mouse.Button(Int(0)), Mouse.Action(Int(1)))
        nothing
    end
    function on_released(controller, n_press, x, y)
        event[] = MouseButtonEvent(Mouse.Button(Int(0)), Mouse.Action(Int(0)))
        nothing
    end

    signal_connect(on_pressed, g, "pressed")
    signal_connect(on_released, g, "released")
end

function Makie.keyboard_buttons(scene::Scene, window::GTKGLWindow)
end

function Makie.dropped_files(scene::Scene, window::GTKGLWindow)
end

function Makie.unicode_input(scene::Scene, window::GTKGLWindow)
end

# TODO both of these methods are slow!
# ~90µs, ~80µs
# This is too slow for events that may happen 100x per frame
function GLMakie.framebuffer_size(window::GTKGLWindow)
end

function GLMakie.window_size(window::GTKGLWindow)
end

function GLMakie.retina_scaling_factor(window::GTKGLWindow)
end

function GLMakie.correct_mouse(window::GTKGLWindow, w, h)
    # ws, fb = window_size(window), framebuffer_size(window)
    # s = retina_scaling_factor(ws, fb)
    # (w * s[1], fb[2] - (h * s[2]))
end

"""
Registers a callback for the mouse cursor position.
returns an `Observable{Vec{2, Float64}}`,
which is not in scene coordinates, with the upper left window corner being 0
[GLFW Docs](http://www.glfw.org/docs/latest/group__input.html#ga1e008c7a8751cea648c8f42cc91104cf)
"""
function Makie.mouse_position(scene::Scene, screen::GLMakie.Screen{Gtk4.GtkWindowLeaf})
    window = Makie.to_native(screen)
    g = Gtk4.GtkEventControllerMotion(window)
    event = scene.events.mouseposition
    hasfocus = scene.events.hasfocus
    function on_motion(controller, x, y)
        if hasfocus[]
            event[] = (x,y) # TODO: retina factor
        end
        nothing
    end
    # for now, put enter and leave in here, since they share the same event controller
    entered = scene.events.entered_window
    function on_enter(controller, x, y)
        entered[] = true
        nothing
    end
    function on_leave(controller)
        entered[] = false
        nothing
    end
    signal_connect(on_motion, g, "motion")
    signal_connect(on_enter, g, "enter")
    signal_connect(on_leave, g, "leave")
end

function Makie.scroll(scene::Scene, window::GTKGLWindow)
end

function Makie.hasfocus(scene::Scene, window::GTKGLWindow)
    # TODO: figure out to GLFW's "hasfocus" onto GTK's behavior
end

function Makie.entered_window(scene::Scene, window::GTKGLWindow)
    # event for this is currently in mouse_position
end
