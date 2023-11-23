# Maybe these should eventually go into GtkObservables?

function toggled_cb(p::Ptr, obs)
    button = convert(GtkCheckButton,p)
    obs[] = Gtk4.G_.get_active(button)
    nothing
end

mutable struct CheckButton{T} <: GtkCheckButton
    handle::Ptr{GObject}
    obs::Observable{T}
    
    function CheckButton(observable::Observable{T}, label=nothing) where T
        cb = if label === nothing
            GtkCheckButton()
        else
            GtkCheckButton(label)
        end
        widget = new{T}(getfield(cb,:handle), observable)
        
        on(observable; update=true) do val
            Gtk4.G_.set_active(widget, Bool(val))
        end
        
        Gtk4.on_toggled(toggled_cb, widget, observable)
        
        widget = Gtk4.GLib.gobject_move_ref(widget, cb)
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
    obs[] = parse(T, Gtk4.G_.get_text(entry))
    nothing
end

mutable struct TextBox{T} <: GtkEntry
    handle::Ptr{GObject}
    obs::Observable
    T
    
    function TextBox(observable::Observable, T=String)
        entry = GtkEntry()
        
        widget = new{T}(getfield(entry,:handle), observable)
        
        on(observable; update=true) do val
            Gtk4.G_.set_text(widget, string(val))
        end
        
        if T <: AbstractString
            Gtk4.on_activate(activated_cb_string, widget, observable)
        else
            Gtk4.on_activate(activated_cb_num, widget, (observable,T))
        end
        
        widget = Gtk4.GLib.gobject_move_ref(widget, entry)
    end
end
