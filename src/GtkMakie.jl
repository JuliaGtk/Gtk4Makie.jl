module GtkMakie

using Gtk4
using ModernGL, GLMakie, Colors, GeometryBasics, ShaderAbstractions
using GLMakie.GLAbstraction
using GLMakie.Makie
using GLMakie: empty_postprocessor, fxaa_postprocessor, OIT_postprocessor, to_screen_postprocessor
using GLMakie.Makie: MouseButtonEvent, KeyEvent
using Gtk4.GLib: GObject, signal_handler_is_connected, signal_handler_disconnect

export GTKScreen, grid, glarea, window

include("screen.jl")
include("events.jl")
include("precompiles.jl")

end
