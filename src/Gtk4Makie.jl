module Gtk4Makie

using Gtk4
import ModernGL, GLMakie, Makie, ShaderAbstractions, FileIO
using ModernGL: GL_FRAMEBUFFER_BINDING, glGetIntegerv
using Colors: Colors, Colorant, RGB, RGBA, @colorant_str
using GeometryBasics: GeometryBasics, area
using FixedPointNumbers: N0f8
using ComputePipeline
using Preferences: Preferences, @load_preference, @set_preferences!
using GLMakie.GLAbstraction: GLAbstraction, ShaderCache
using Makie: Attributes, Axis, Axis3, Colorbar, DataInspector,
               Figure, GridLayout, Heatmap, Inside, Keyboard, Lines, Mixed,
               Mouse, Observable, Outside, PolarAxis, Recti, Scatter, Scene,
               colorbuffer, contents, current_figure, entered_window, hasfocus,
               keyboard_buttons, lines, mouse_buttons, on, plots, update_theme!,
               window_area, MouseButtonEvent, KeyEvent
using GLMakie: empty_postprocessor, fxaa_postprocessor, OIT_postprocessor,
               to_screen_postprocessor, GLFramebuffer, RenderObject,
               SCREEN_REUSE_POOL, SINGLETON_SCREEN, ScreenArea,
               ZIndex, apply_config!, closeall, correct_mouse,
               destroy!, fast_color_data!, framebuffer_size, pollevents,
               render_frame, requires_update, set_screen_visibility!,
               stop_renderloop!, was_destroyed
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
include("axis_widgets.jl")
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

