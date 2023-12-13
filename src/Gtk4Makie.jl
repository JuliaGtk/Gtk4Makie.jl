module Gtk4Makie

using Gtk4
using ModernGL, GLMakie, Colors, GeometryBasics, ShaderAbstractions
using Preferences
import FileIO
using GLMakie.GLAbstraction
using GLMakie.Makie
using GLMakie: empty_postprocessor, fxaa_postprocessor, OIT_postprocessor,
               to_screen_postprocessor
using GLMakie.Makie: MouseButtonEvent, KeyEvent
using Gtk4.GLib: GObject, signal_handler_is_connected, GVariant, GSimpleAction,
                 signal_handler_disconnect, add_action, add_stateful_action,
                 set_state
import Base: push!, empty!

export GTKScreen, grid, glarea, window, attributes_window, GtkMakieWidget

# re-export Makie, including deprecated names
for name in names(Makie, all=true)
    if Base.isexported(Makie, name)
        @eval using Makie: $(name)
        @eval export $(name)
    end
end

include("screen.jl")
include("window.jl")
include("widget.jl")
include("events.jl")
include("settings_widgets.jl")
include("attributes.jl")
include("scene.jl")
include("precompiles.jl")

const gtk4makie_default_theme = Attributes(title = "Makie",
                                 fullscreen = false)

"""
    enable_backend(s::Bool)

Set `s` to `true` to make Gtk4Makie behave like a real Makie backend, allowing
you to create figures from the REPL without first creating a Gtk4Makie screen.
Set `s` to `false` to let GLMakie act as the backend.

This setting will take effect after you restart Julia.
"""
function enable_backend(s)
    b = s ? "Gtk4Makie" : "GLMakie"
    @set_preferences!("backend" => b)
    @info("Setting will take effect after restarting Julia.")
end

const backend = @load_preference("backend", "GLMakie")

function __init__()
    if backend == "Gtk4Makie"
        update_theme!(Gtk4Makie=gtk4makie_default_theme)
        activate!()
    end
end

end

