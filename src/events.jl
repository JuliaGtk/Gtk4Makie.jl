function Makie.disconnect!(window::Gtk4.GtkWindowLeaf, func)
    # TODO
end
function Makie.disconnect!(window::GTKGLWindow, func)
    # TODO
end

function Makie.window_open(scene::Scene, window::GTKGLWindow)
    event = scene.events.window_open
    signal_connect(toplevel(window), :close_request) do w
        event[] = false
        nothing
    end
    event[] = true
end

function calc_dpi(m::GdkMonitor)
    g=Gtk4.G_.get_geometry(m)
    wdpi=g.width/(Gtk4.G_.get_width_mm(m)/25.4)
    hdpi=g.height/(Gtk4.G_.get_height_mm(m)/25.4)
    min(wdpi,hdpi)
end

function Makie.window_area(scene::Scene, screen::GLMakie.Screen{Gtk4.GtkWindowLeaf})
    area = scene.events.window_area
    dpi = scene.events.window_dpi
    function on_resize(a,w,h)
        m=Gtk4.monitor(a)
        dpi[] = calc_dpi(m)
        area[] = Recti(0, 0, w, h)
    end
    glarea=Makie.to_native(screen)[]
    signal_connect(on_resize, glarea, :resize)
end

function translate_mousebutton(b)
    if b==1
        return Mouse.Button(Int(0))
    elseif b==3
        return Mouse.Button(Int(1))
    elseif b==2
        return Mouse.Button(Int(2))
    end
end

function Makie.mouse_buttons(scene::Scene, glarea::GTKGLWindow)
    event = scene.events.mousebutton

    g=GtkGestureClick(glarea,0) # 0 means respond to all buttons
    function on_pressed(controller, n_press, x, y)
        b = Gtk4.G_.get_current_button(controller)
        event[] = MouseButtonEvent(translate_mousebutton(b), Mouse.Action(Int(1)))
        Gtk4.queue_render(glarea)
        nothing
    end
    function on_released(controller, n_press, x, y)
        b = Gtk4.G_.get_current_button(controller)
        event[] = MouseButtonEvent(translate_mousebutton(b), Mouse.Action(Int(0)))
        Gtk4.queue_render(glarea)
        nothing
    end

    signal_connect(on_pressed, g, "pressed")
    signal_connect(on_released, g, "released")
end

# currently only handles a few common keys!
function translate_keyval(c)
    if (c>0 && c<93)
        return Int(c)
    elseif c>=97 && c<=120 # letters - corresponding Gdk codes are uppercase, which implies shift is also being pressed I think
        return Int(c-32) # this is the lowercase version
    elseif c==65507 # left control
        return Int(341)
    elseif c==65508 # right control
        return Int(345)
    elseif c==65505 # left shift
        return Int(340)
    elseif c==65506 # right shift
        return Int(344)
    end
    return Int(-1) # unknown
end

function Makie.keyboard_buttons(scene::Scene, glarea::GTKGLWindow)
    event = scene.events.keyboardbutton
    e=GtkEventControllerKey(toplevel(glarea))
    function on_key_pressed(controller, keyval, keycode, state)
        event[] = KeyEvent(Keyboard.Button(translate_keyval(keyval)), Keyboard.Action(Int(1)))
        return true # returning from callbacks currently broken
    end
    function on_key_released(controller, keyval, keycode, state)
        event[] = KeyEvent(Keyboard.Button(translate_keyval(keyval)), Keyboard.Action(Int(0)))
        return true
    end
    signal_connect(on_key_pressed, e, "key-pressed")
    signal_connect(on_key_released, e, "key-released")
end

function Makie.dropped_files(scene::Scene, window::GTKGLWindow)
end

function Makie.unicode_input(scene::Scene, window::GTKGLWindow)
end

GLMakie.framebuffer_size(window::GTKGLWindow) = size(window) .* GLMakie.retina_scaling_factor(window)
GLMakie.window_size(window::GTKGLWindow) = size(window)

function GLMakie.retina_scaling_factor(window::GTKGLWindow)
    f=Gtk4.scale_factor(window)
    (f,f)
end

function GLMakie.correct_mouse(window::GTKGLWindow, w, h)
    fb = GLMakie.framebuffer_size(window)
    s = Gtk4.scale_factor(window)
    (w * s, fb[2] - (h * s))
end

"""
Registers a callback for the mouse cursor position.
returns an `Observable{Vec{2, Float64}}`,
which is not in scene coordinates, with the upper left window corner being 0
[GLFW Docs](http://www.glfw.org/docs/latest/group__input.html#ga1e008c7a8751cea648c8f42cc91104cf)
"""
function Makie.mouse_position(scene::Scene, screen::GLMakie.Screen{Gtk4.GtkWindowLeaf})
    glarea = Makie.to_native(screen)[]
    g = Gtk4.GtkEventControllerMotion(glarea)
    event = scene.events.mouseposition
    hasfocus = scene.events.hasfocus
    function on_motion(controller, x, y)
        if hasfocus[]
            event[] = GLMakie.correct_mouse(glarea, x,y) # TODO: retina factor
            Gtk4.queue_render(glarea)
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
    event = scene.events.scroll
    e = GtkEventControllerScroll(Gtk4.EventControllerScrollFlags_HORIZONTAL | Gtk4.EventControllerScrollFlags_VERTICAL, window)
    function on_scroll(controller, dx, dy)
        event[] = (dx,dy)
        nothing
    end
    signal_connect(on_scroll, e, "scroll")
end

function Makie.hasfocus(scene::Scene, window::GTKGLWindow)
    event = scene.events.hasfocus
    function on_is_active_changed(w,ps)
        event[] = Gtk4.G_.is_active(w)
        nothing
    end
    signal_connect(on_is_active_changed, toplevel(window), "notify::is-active")
    event[] = Gtk4.G_.is_active(toplevel(window))
end

function Makie.entered_window(scene::Scene, window::GTKGLWindow)
    # event for this is currently in mouse_position
end
