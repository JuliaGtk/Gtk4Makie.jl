# GtkMakieWidget

## Makie overloads

GLMakie.was_destroyed(nw::GtkGLMakie) = Gtk4.G_.in_destruction(nw)
Base.isopen(nw::GtkGLMakie) = !GLMakie.was_destroyed(nw)

function GLMakie.apply_config!(screen::GLMakie.Screen{T},config::GLMakie.ScreenConfig; start_renderloop=true) where T <: GtkGLArea
    return _apply_config!(screen, config, start_renderloop)
end

function GLMakie.destroy!(screen::GLMakie.Screen{T}) where T <: GtkGLArea
    close(screen; reuse=false)
    return
end

GLMakie.framebuffer_size(w::GtkGLMakie) = size(w) .* Gtk4.scale_factor(w)

function ShaderAbstractions.native_switch_context!(a::GtkGLMakie)
    Gtk4.G_.get_realized(a) || return
    Gtk4.make_current(a)
end

## Gtk4Makie overloads

glarea(screen::GLMakie.Screen{T}) where T <: GtkGLArea = screen.glscreen
window(screen::GLMakie.Screen{T}) where T <: GtkGLArea = toplevel(screen.glscreen)

##

function push!(w::GtkGLMakie,s::Makie.FigureLike)
    if Gtk4.G_.get_realized(w)
        display(screens[Ptr{GtkGLArea}(w.handle)], s)
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
