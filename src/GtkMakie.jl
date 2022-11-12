module GtkMakie

using ModernGL, GLMakie, Colors, GeometryBasics, Gtk4, ShaderAbstractions
using GLMakie.GLAbstraction
using GLMakie.Makie
using GLMakie: empty_postprocessor, fxaa_postprocessor, OIT_postprocessor, to_screen_postprocessor
using GLMakie.Makie: MouseButtonEvent, KeyEvent

include("screen.jl")
include("events.jl")

end
