# GLMakie event handling

Makie.disconnect!(window::WindowType, func) = Makie.disconnect!(win2glarea[window], func)
function Makie.disconnect!(window::GtkGLMakie, func)
    s=Symbol(func)
    !haskey(window.handlers,s) && return
    w,id=window.handlers[s]
    if signal_handler_is_connected(w, id)
        signal_handler_disconnect(w, id)
    end
    delete!(window.handlers,s)
end

function Makie.disconnect!(screen::Screen{T}, ::typeof(window_area)) where T<:GtkWindow
    
end

function _disconnect_handler(glarea::GtkGLMakie, s::Symbol)
    w,id=glarea.handlers[s]
    signal_handler_disconnect(w, id)
    delete!(glarea.handlers,s)
end

function _close_request_cb(ptr, event)
    event[] = false
    Cint(0)
end

function Makie.window_open(scene::Scene, window::GtkGLMakie)
    event = scene.events.window_open
    
    id = Gtk4.on_close_request(_close_request_cb, toplevel(window), event)
    window.handlers[:window_open] = (toplevel(window), id)
    event[] = true
end

function calc_dpi(m::GdkMonitor)
    g=Gtk4.geometry(m)
    wdpi=g.width/(Gtk4.width_mm(m)/25.4)
    hdpi=g.height/(Gtk4.height_mm(m)/25.4)
    min(wdpi,hdpi)
end

function _glarea_resize_cb(aptr, w, h, user_data)
    dpi, area, winscale = user_data
    a = convert(GtkGLArea, aptr)
    m=Gtk4.monitor(a)
    if m!==nothing
        dpi[] = calc_dpi(m)
    end
    winw, winh = round.(Int, (w, h)./winscale )
    area[] = Recti(minimum(area[]), winw, winh)
    nothing
end

function _window_area(scene, glarea, winscale)
    area = scene.events.window_area
    dpi = scene.events.window_dpi
    Gtk4.on_resize(_glarea_resize_cb, glarea, (dpi, area, winscale))
    Gtk4.queue_render(glarea)
end

function Makie.window_area(scene::Scene, screen::GLMakie.Screen{T}) where T <: GtkWindow
    glarea=win2glarea[Makie.to_native(screen)]
    winscale = screen.scalefactor[] / Gtk4.scale_factor(glarea)
    _window_area(scene, glarea, winscale)
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

function _mouse_event_cb(ptr, n_press, x, y, user_data)
    event, event_type = user_data
    controller = convert(GtkEventController, ptr)
    glarea = Gtk4.widget(controller)
    b = Gtk4.current_button(controller)
    b > 3 && return nothing
    event[] = MouseButtonEvent(_translate_mousebutton(b), event_type)
    Gtk4.queue_render(glarea)
    nothing
end

function Makie.mouse_buttons(scene::Scene, glarea::GtkGLMakie)
    event = scene.events.mousebutton

    g=GtkGestureClick(glarea,0) # 0 means respond to all buttons

    id = Gtk4.on_pressed(_mouse_event_cb, g, (event, Mouse.press))
    glarea.handlers[:mouse_button_pressed] = (g, id)
    id = Gtk4.on_released(_mouse_event_cb, g, (event, Mouse.release))
    glarea.handlers[:mouse_button_released] = (g, id)
end

function Makie.disconnect!(glarea::GtkGLMakie, ::typeof(mouse_buttons))
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

function _key_pressed_cb(ptr, keyval, keycode, state, event)
    event[] = KeyEvent(Keyboard.Button(_translate_keyval(keyval)), Keyboard.Action(Int(1)))
    Cint(0)
end

function _key_released_cb(ptr, keyval, keycode, state, event)
    event[] = KeyEvent(Keyboard.Button(_translate_keyval(keyval)), Keyboard.Action(Int(0)))
    nothing
end

function Makie.keyboard_buttons(scene::Scene, glarea::GtkGLMakie)
    event = scene.events.keyboardbutton
    e=GtkEventControllerKey(toplevel(glarea))
    id = Gtk4.on_key_pressed(_key_pressed_cb, e, event)
    glarea.handlers[:key_pressed] = (e, id)
    id = Gtk4.on_key_released(_key_released_cb, e, event)
    glarea.handlers[:key_released] = (e, id)
end

function Makie.disconnect!(glarea::GtkGLMakie, ::typeof(keyboard_buttons))
    _disconnect_handler(glarea, :key_pressed)
    _disconnect_handler(glarea, :key_released)
end

function Makie.dropped_files(scene::Scene, window::GtkGLMakie)
end

function Makie.unicode_input(scene::Scene, window::GtkGLMakie)
end

function GLMakie.correct_mouse(window::GtkGLMakie, w, h)
    fb = GLMakie.framebuffer_size(window)
    s = Gtk4.scale_factor(window)
    (w * s, fb[2] - (h * s))
end

function _mouse_motion_cb(ptr, x, y, user_data)
    ec = convert(GtkEventControllerMotion, ptr)
    glarea = Gtk4.widget(ec)
    hasfocus, event = user_data
    if hasfocus[]
        event[] = GLMakie.correct_mouse(glarea, x,y) # TODO: retina factor
        Gtk4.queue_render(glarea)
    end
    nothing
end

function _mouse_enter_cb(ptr, x, y, entered)
    entered[] = true
    nothing
end

function _mouse_leave_cb(ptr, entered)
    entered[] = false
    nothing
end

function _mouse_position(scene, glarea)
    g = Gtk4.GtkEventControllerMotion(glarea)
    event = scene.events.mouseposition
    hasfocus = scene.events.hasfocus
    # for now, put enter and leave in here, since they share the same event controller
    entered = scene.events.entered_window
    id = Gtk4.on_motion(_mouse_motion_cb, g, (hasfocus, event))
    glarea.handlers[:motion] = (g, id)
    id = Gtk4.on_enter(_mouse_enter_cb, g, entered)
    glarea.handlers[:enter] = (g, id)
    id = Gtk4.on_leave(_mouse_leave_cb, g, entered)
    glarea.handlers[:leave] = (g, id)
end

"""
Registers a callback for the mouse cursor position.
returns an `Observable{Vec{2, Float64}}`,
which is not in scene coordinates, with the upper left window corner being 0
[GLFW Docs](http://www.glfw.org/docs/latest/group__input.html#ga1e008c7a8751cea648c8f42cc91104cf)
"""
function Makie.mouse_position(scene::Scene, screen::GLMakie.Screen{T}) where T <: GtkWindow
    glarea = win2glarea[Makie.to_native(screen)]
    _mouse_position(scene, glarea)
end

function _scroll_cb(ptr, dx, dy, user_data)
    event, window = user_data
    event[] = (dx,dy)
    Gtk4.queue_render(window)
    Cint(0)
end

function Makie.scroll(scene::Scene, window::GtkGLMakie)
    event = scene.events.scroll
    e = GtkEventControllerScroll(Gtk4.EventControllerScrollFlags_HORIZONTAL | Gtk4.EventControllerScrollFlags_VERTICAL, window)
    id = Gtk4.on_scroll(_scroll_cb, e, (event, window))
    window.handlers[:scroll] = (e, id)
end

function _is_active_callback(ptr, param, event)
    w = convert(GtkWindow, ptr)
    event[] = Gtk4.G_.is_active(w)
    nothing
end

function Makie.hasfocus(scene::Scene, window::GtkGLMakie)
    event = scene.events.hasfocus
    id = Gtk4.GLib.on_notify(_is_active_callback, toplevel(window), "is-active", event)
    window.handlers[:hasfocus] = (toplevel(window), id)
    event[] = Gtk4.G_.is_active(toplevel(window))
end

function Makie.entered_window(scene::Scene, window::GtkGLMakie)
    # event for this is currently in mouse_position
end

function Makie.disconnect!(glarea::GtkGLMakie, ::typeof(entered_window))
    _disconnect_handler(glarea, :motion)
    _disconnect_handler(glarea, :enter)
    _disconnect_handler(glarea, :leave)
end
