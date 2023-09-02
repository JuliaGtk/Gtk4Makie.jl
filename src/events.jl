Makie.disconnect!(window::WindowType, func) = Makie.disconnect!(win2glarea[window], func)
function Makie.disconnect!(window::GTKGLWindow, func)
    s=Symbol(func)
    !haskey(window.handlers,s) && return
    w,id=window.handlers[s]
    if signal_handler_is_connected(w, id)
        signal_handler_disconnect(w, id)
    end
    delete!(window.handlers,s)
end

function _disconnect_handler(glarea::GTKGLWindow, s::Symbol)
    w,id=glarea.handlers[s]
    signal_handler_disconnect(w, id)
    delete!(glarea.handlers,s)
end

function Makie.window_open(scene::Scene, window::GTKGLWindow)
    event = scene.events.window_open
    
    id = signal_connect(toplevel(window), :close_request) do w
        event[] = false
        nothing
     end
    window.handlers[:window_open] = (toplevel(window), id)
    event[] = true
end

function calc_dpi(m::GdkMonitor)
    g=Gtk4.geometry(m)
    wdpi=g.width/(Gtk4.width_mm(m)/25.4)
    hdpi=g.height/(Gtk4.height_mm(m)/25.4)
    min(wdpi,hdpi)
end

function Makie.window_area(scene::Scene, screen::GLMakie.Screen{T}) where T <: GtkWindow
    area = scene.events.window_area
    dpi = scene.events.window_dpi
    function on_resize(a,w,h)
        m=Gtk4.monitor(a)
        if m!==nothing
            dpi[] = calc_dpi(m)
        end
        area[] = Recti(0, 0, w, h)
    end
    glarea=win2glarea[Makie.to_native(screen)]
    signal_connect(on_resize, glarea, :resize)
    Gtk4.queue_render(glarea)
end

function _translate_mousebutton(b)
    if b==1
        return Mouse.left
    elseif b==3
        return Mouse.right
    elseif b==2
        return Mouse.middle
    else
        return Mouse.none
    end
end

function Makie.mouse_buttons(scene::Scene, glarea::GTKGLWindow)
    event = scene.events.mousebutton

    g=GtkGestureClick(glarea,0) # 0 means respond to all buttons
    function on_pressed(controller, n_press, x, y)
        b = Gtk4.current_button(controller)
        b > 3 && return nothing
        event[] = MouseButtonEvent(_translate_mousebutton(b), Mouse.press)
        Gtk4.queue_render(glarea)
        nothing
    end
    function on_released(controller, n_press, x, y)
        b = Gtk4.current_button(controller)
        b > 3 && return nothing
        event[] = MouseButtonEvent(_translate_mousebutton(b), Mouse.release)
        Gtk4.queue_render(glarea)
        nothing
    end

    id = signal_connect(on_pressed, g, "pressed")
    glarea.handlers[:mouse_button_pressed] = (g, id)
    id = signal_connect(on_released, g, "released")
    glarea.handlers[:mouse_button_released] = (g, id)
end

function Makie.disconnect!(glarea::GTKGLWindow, ::typeof(mouse_buttons))
    _disconnect_handler(glarea, :mouse_button_pressed)
    _disconnect_handler(glarea, :mouse_button_released)
end

# currently only handles a few common keys!
function _translate_keyval(c)
    if c>0 && c<=96 # letters - corresponding Gdk codes are uppercase, which implies shift is also being pressed I think
        return Int(c)
    elseif c>=97 && c<=122
        return Int(c-32) # this is the lowercase version
    elseif c==65507 # left control
        return Int(341)
    elseif c==65508 # right control
        return Int(345)
    elseif c==65505 # left shift
        return Int(340)
    elseif c==65506 # right shift
        return Int(344)
    elseif c==65513 # left alt
        return Int(342)
    elseif c==65514 # right alt
        return Int(346)
    elseif c==65361 # left arrow
        return Int(263)
    elseif c==65364 # down arrow
        return Int(264)
    elseif c==65362 # up arrow
        return Int(265)
    elseif c==65363 # right arrow
        return Int(262)
    elseif c==65360 # home
        return Int(268)
    elseif c==65365 # page up
        return Int(266)
    elseif c==65366 # page down
        return Int(267)
    elseif c==65367 # end
        return Int(269)
    elseif c==65307 # escape
        return Int(256)
    elseif c==65293 # enter
        return Int(257)
    elseif c==65289 # tab
        return Int(258)
    elseif c==65535 # delete
        return Int(261)
    elseif c==65388 # backspace
        return Int(259)
    elseif c==65379 # insert
        return Int(260)
    elseif c>=65470 && c<= 65481 # function keys
        return Int(c-65470+290)
    end
    return Int(-1) # unknown
end

function Makie.keyboard_buttons(scene::Scene, glarea::GTKGLWindow)
    event = scene.events.keyboardbutton
    e=GtkEventControllerKey(toplevel(glarea))
    function on_key_pressed(controller, keyval, keycode, state)
        if _iscloseshortcut(state,keyval)
            @idle_add Gtk4.destroy(toplevel(glarea))
        end
        if _isfullscreenshortcut(state,keyval)
            @idle_add _toggle_fullscreen(toplevel(glarea))
        end
        event[] = KeyEvent(Keyboard.Button(_translate_keyval(keyval)), Keyboard.Action(Int(1)))
        return true # returning from callbacks currently broken
    end
    function on_key_released(controller, keyval, keycode, state)
        event[] = KeyEvent(Keyboard.Button(_translate_keyval(keyval)), Keyboard.Action(Int(0)))
        return true
    end
    id = signal_connect(on_key_pressed, e, "key-pressed")
    glarea.handlers[:key_pressed] = (e, id)
    id = signal_connect(on_key_released, e, "key-released")
    glarea.handlers[:key_released] = (e, id)
end

function Makie.disconnect!(glarea::GTKGLWindow, ::typeof(keyboard_buttons))
    _disconnect_handler(glarea, :key_pressed)
    _disconnect_handler(glarea, :key_released)
end

function Makie.dropped_files(scene::Scene, window::GTKGLWindow)
end

function Makie.unicode_input(scene::Scene, window::GTKGLWindow)
end

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
function Makie.mouse_position(scene::Scene, screen::GLMakie.Screen{T}) where T <: GtkWindow
    glarea = win2glarea[Makie.to_native(screen)]
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
    id = signal_connect(on_motion, g, "motion")
    glarea.handlers[:motion] = (g, id)
    id = signal_connect(on_enter, g, "enter")
    glarea.handlers[:enter] = (g, id)
    id = signal_connect(on_leave, g, "leave")
    glarea.handlers[:leave] = (g, id)
end

function Makie.scroll(scene::Scene, window::GTKGLWindow)
    event = scene.events.scroll
    e = GtkEventControllerScroll(Gtk4.EventControllerScrollFlags_HORIZONTAL | Gtk4.EventControllerScrollFlags_VERTICAL, window)
    function on_scroll(controller, dx, dy)
        event[] = (dx,dy)
        Gtk4.queue_render(window)
        nothing
    end
    id = signal_connect(on_scroll, e, "scroll")
    window.handlers[:scroll] = (e, id)
end

function Makie.hasfocus(scene::Scene, window::GTKGLWindow)
    event = scene.events.hasfocus
    function on_is_active_changed(w,ps)
        event[] = Gtk4.G_.is_active(w)
        nothing
    end
    id = signal_connect(on_is_active_changed, toplevel(window), "notify::is-active")
    window.handlers[:hasfocus] = (toplevel(window), id)
    event[] = Gtk4.G_.is_active(toplevel(window))
end

function Makie.entered_window(scene::Scene, window::GTKGLWindow)
    # event for this is currently in mouse_position
end

function Makie.disconnect!(glarea::GTKGLWindow, ::typeof(entered_window))
    _disconnect_handler(glarea, :motion)
    _disconnect_handler(glarea, :enter)
    _disconnect_handler(glarea, :leave)
end
