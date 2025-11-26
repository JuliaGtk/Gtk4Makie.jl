# GtkMakieWidget

## Makie overloads

GLMakie.was_destroyed(nw::GtkGLMakie) = Gtk4.G_.in_destruction(nw)
Base.isopen(nw::GtkGLMakie) = Gtk4.visible(nw)

function GLMakie.apply_config!(screen::GLMakie.Screen{T},config::GLMakie.ScreenConfig; start_renderloop=true) where T <: GtkGLArea
    return _apply_config!(screen, config, start_renderloop)
end

GLMakie.destroy!(nw::GtkGLArea) = nothing
GLMakie.framebuffer_size(w::GtkGLMakie) = size(w) .* Gtk4.scale_factor(w)

function ShaderAbstractions.native_switch_context!(a::GtkGLMakie)
    Gtk4.isrealized(a) || return
    Gtk4.make_current(a)
end

function ShaderAbstractions.is_current_context(a::GtkGLMakie)
    Gtk4.isrealized(a) || return false
    a == ShaderAbstractions.ACTIVE_OPENGL_CONTEXT[] || return false
    curr = Gtk4.G_.get_current()
    return curr !== nothing && curr == Gtk4.G_.get_context(a)
end

## Gtk4Makie overloads

glarea(screen::GLMakie.Screen{T}) where T <: GtkGLArea = screen.glscreen
window(screen::GLMakie.Screen{T}) where T <: GtkGLArea = toplevel(screen.glscreen)

##

function push!(w::GtkGLMakie,s::Makie.FigureLike)
    if Gtk4.isrealized(w)
        display(screens[Ptr{GtkGLArea}(w.handle)], s)
        # prevents https://github.com/JuliaGtk/Gtk4Makie.jl/issues/24
        Gtk4.G_.queue_resize(w)
    else
        signal_connect(w,"realize") do a
            display(screens[Ptr{GtkGLArea}(w.handle)], s)
        end
    end
    w
end

function empty!(w::GtkGLMakie)
    empty!(screens[Ptr{GtkGLArea}(w.handle)])
    w
end

Gtk4.@guarded function realizewidgetcb(glareaptr, user_data)
    a, config = user_data
    check_gl_error(a)
    
    screen = _create_screen(a, a, config, (200,200))
    GLMakie.apply_config!(screen, config)

    a.render_id = Gtk4.on_render(refreshwidgetcb, a)
    _add_timeout(screen, a, a)
    
    nothing
end

function unrealizewidgetcb(glareaptr, glarea)
    Gtk4.GLib.signal_handler_disconnect(glarea, glarea.render_id)
    nothing
end

"""
    GtkMakieWidget(;
                   screen_config...)

Create a Gtk4Makie widget. Returns the widget. The screen will not be created until the widget is realized.
"""
function GtkMakieWidget(;
                   screen_config...
    )
    config = Makie.merge_screen_config(GLMakie.ScreenConfig, Dict{Symbol, Any}(screen_config))
    glarea = try
        GtkGLMakie()
    catch e
        @warn("""
            Gtk4 couldn't create an OpenGL window.
        """)
        rethrow(e)
    end

    Gtk4.on_realize(realizewidgetcb, glarea, (glarea, config))
    Gtk4.on_unrealize(unrealizewidgetcb, glarea)
    
    return glarea
end
