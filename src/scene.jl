function mouse_event_to_string(val)
    button = string(val.button)
    action = string(val.action)
    "$button $action"
end

function keyboard_event_to_string(val)
    key = string(val.key)
    action = string(val.action)
    "$key $action"
end

# for debugging events
function scene_info(scene::Scene)
    w = GtkWindow("Scene events")
    b = GtkBox(:v)
    events_box = GtkGrid()
    push!(b,events_box)

    r = 1

    # fill events_box
    events_box[1,r] = GtkLabel("Mouse position: ")
    mouse_position_label = GtkLabel("")
    events_box[2,r] = mouse_position_label
    on(scene.events.mouseposition) do val
        Gtk4.label(mouse_position_label, string(val))
    end

    r += 1

    events_box[1,r] = GtkLabel("Mouse buttons: ")
    buttons_box = GtkBox(:h)

    mousebutton_label = GtkLabel("")
    mousebuttonstate_label = GtkLabel("")
    on(scene.events.mousebutton) do val
        Gtk4.label(mousebutton_label, mouse_event_to_string(val))
        Gtk4.label(mousebuttonstate_label, string(scene.events.mousebuttonstate))
    end
    push!(buttons_box, mousebutton_label)

    events_box[2,r] = buttons_box

    r += 1

    events_box[2,r] = mousebuttonstate_label

    r += 1

    events_box[1,r] = GtkLabel("Keyboard: ")
    kb_box = GtkBox(:h)

    keyboard_label = GtkLabel("")
    keyboardstate_label = GtkLabel("")
    on(scene.events.keyboardbutton) do val
        Gtk4.label(keyboard_label, keyboard_event_to_string(val))
        Gtk4.label(keyboardstate_label, string(scene.events.keyboardstate))
    end
    push!(kb_box, keyboard_label)

    events_box[2,r] = kb_box

    r += 1

    events_box[1,r] = GtkLabel("Unicode: ")
    unicode_label = GtkLabel("")

    on(scene.events.unicode_input) do val
        Gtk4.label(unicode_label, string(val))
    end

    events_box[2,r] = unicode_label

    r += 1

    events_box[2,r] = keyboardstate_label

    r += 1

    events_box[1,r] = GtkLabel("Window area: ")
    
    window_area_label = GtkLabel(string(scene.events.window_area[]))
    on(scene.events.window_area) do val
        Gtk4.label(window_area_label, string(val))
    end
    events_box[2,r] = window_area_label

    window_box = GtkBox(:h; spacing = 3)
    
    window_dpi_label = GtkLabel(string(scene.events.window_dpi[]))
    on(scene.events.window_dpi) do val
        Gtk4.label(window_dpi_label, "dpi is $val")
    end
    push!(window_box, window_dpi_label)
    
    window_open_label = GtkLabel(scene.events.window_open[] ? "window_open" : "")
    on(scene.events.window_open) do val
        Gtk4.label(window_open_label, val ? "window_open" : "")
    end
    push!(window_box, window_open_label)

    r += 1

    events_box[2,r] = window_box

    r += 1

    events_box[1,r] = GtkLabel("Tick:")

    tick_label = GtkLabel("")
    on(scene.events.tick) do tick
        Gtk4.label(tick_label, string(tick.time))
    end

    events_box[2,r] = tick_label

    r += 1
    
    events_box[1,r] = GtkLabel("Miscellaneous: ")
    misc_box = GtkBox(:h; spacing = 3)

    has_focus_label = GtkLabel("")
    on(scene.events.hasfocus) do val
        Gtk4.label(has_focus_label, val ? "hasfocus" : "")
    end
    push!(misc_box, has_focus_label)

    entered_window_label = GtkLabel("")
    on(scene.events.entered_window) do val
        Gtk4.label(entered_window_label, val ? "entered_window" : "")
    end
    push!(misc_box, entered_window_label)

    events_box[2,r] = misc_box

    w[] = b
end

function position_label(screen,ax::Axis)
    l=GtkLabel("")
    on(screen.root_scene.events.mouseposition) do val
        if screen.root_scene.events.hasfocus[] && screen.root_scene.events.entered_window[]
            pos = Makie.mouseposition(ax)
            Gtk4.label(l, "$pos")
        end
    end
    on(screen.root_scene.events.entered_window) do val
        if !val
            Gtk4.label(l,"")
        end
    end
    l
end

