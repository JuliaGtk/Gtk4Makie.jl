module Gtk4Makie

using Gtk4, GtkObservables
using ModernGL, GLMakie, Colors, GeometryBasics, ShaderAbstractions
import FileIO
using GLMakie.GLAbstraction
using GLMakie.Makie
using GLMakie: empty_postprocessor, fxaa_postprocessor, OIT_postprocessor,
               to_screen_postprocessor
using GLMakie.Makie: MouseButtonEvent, KeyEvent
using Gtk4.GLib: GObject, signal_handler_is_connected, GVariant, GSimpleAction,
                 signal_handler_disconnect, add_action, add_stateful_action,
                 set_state
import Base: push!

export GTKScreen, grid, glarea, window, attributes_window, GtkMakieWidget

include("screen.jl")
include("window.jl")
include("widget.jl")
include("events.jl")
include("settings_widgets.jl")
include("attributes.jl")
include("scene.jl")
include("precompiles.jl")

end

