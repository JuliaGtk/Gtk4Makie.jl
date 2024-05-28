# Maybe these should eventually go into GtkObservables?

function toggled_cb(p::Ptr, obs::Observable{T}) where T
    button = convert(GtkCheckButton,p)::CheckButton{T}
    act = Gtk4.G_.get_active(button)
    if obs[] != act
        obs[] = act
    end
    nothing
end

mutable struct CheckButton{T} <: GtkCheckButton
    handle::Ptr{GObject}
    obs::Observable{T}
    
    function CheckButton(observable::Observable{T}, label=nothing; kwargs...) where T
        cb = if label === nothing
            GtkCheckButton(; kwargs...)
        else
            GtkCheckButton(label; kwargs...)
        end
        widget = new{T}(getfield(cb,:handle), observable)
        
        on(observable; update=true) do val
            if Gtk4.active(widget) != Bool(val)
                @idle_add Gtk4.G_.set_active(widget, Bool(val))
            end
        end
        
        Gtk4.on_toggled(toggled_cb, widget, observable)
        
        Gtk4.GLib.gobject_move_ref(widget, cb)
    end    
end

function activated_cb_string(p::Ptr, obs)
    entry = convert(GtkEntry,p)
    obs[] = Gtk4.G_.get_text(entry)
    nothing
end

function activated_cb_num(p::Ptr, user_data)
    obs, T = user_data
    entry = convert(GtkEntry,p)
    try
        obs[] = parse(T, Gtk4.G_.get_text(entry))
    catch e
    end
    nothing
end

mutable struct TextBox{T} <: GtkEntry
    handle::Ptr{GObject}
    obs::Observable
    T
    
    function TextBox(observable::Observable, T=String; kwargs...)
        entry = GtkEntry(; kwargs...)
        
        widget = new{T}(getfield(entry,:handle), observable)
        
        on(observable; update=true) do val
            @idle_add Gtk4.G_.set_text(widget, string(val))
        end
        
        if T <: AbstractString
            Gtk4.on_activate(activated_cb_string, widget, observable)
        else
            Gtk4.on_activate(activated_cb_num, widget, (observable,T))
        end
        
        Gtk4.GLib.gobject_move_ref(widget, entry)
    end
end

# GI method in Gtk4.jl is broken
function get_rgba(instance::GtkColorDialogButton)
    ret = ccall(("gtk_color_dialog_button_get_rgba", Gtk4.libgtk4), Ptr{Gtk4._GdkRGBA}, (Ptr{Gtk4.GLib.GObject},), instance)
    unsafe_load(ret)
end

function activated_cb_color(p::Ptr, propspec, obs::Observable{T}) where T
    b = convert(GtkColorDialogButton,p)
    new_rgba = convert(RGBA, get_rgba(b))
    if obs[] != new_rgba
        obs[] = new_rgba
    end
    nothing
end

mutable struct ColorButton{T} <: GtkColorDialogButton
    handle::Ptr{GObject}
    obs::Observable{T}

    function ColorButton(observable::Observable, T=RGBA{Float32}; kwargs...)
        cb = GtkColorDialogButton(GtkColorDialog(); kwargs...)
        widget = new{T}(getfield(cb, :handle), observable)

        on(observable; update=true) do val
            new_rgba = convert(GdkRGBA,val)
            if new_rgba != get_rgba(widget)
                @idle_add begin
                    Gtk4.G_.set_rgba(widget, new_rgba)
                    Gtk4.GLib.on_notify(activated_cb_color, widget, "rgba", observable)
                end
            end
        end

        Gtk4.GLib.gobject_move_ref(widget, cb)
    end
end
