module Gtk4Makie

using Gtk4, GtkObservables
using ModernGL, GLMakie, Colors, GeometryBasics, ShaderAbstractions
using GLMakie.GLAbstraction
using GLMakie.Makie
using GLMakie: empty_postprocessor, fxaa_postprocessor, OIT_postprocessor,
               to_screen_postprocessor
using GLMakie.Makie: MouseButtonEvent, KeyEvent
using Gtk4.GLib: GObject, signal_handler_is_connected, GVariant, GSimpleAction,
                 signal_handler_disconnect, add_action, add_stateful_action,
                 set_state

export GTKScreen, grid, glarea, window

include("screen.jl")
include("events.jl")
include("attributes.jl")
include("precompiles.jl")

end
