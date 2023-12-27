# GtkMakieWidget

## overloads

size_change(g::GtkGLArea, w, h) = nothing  # we get what Gtk4 gives us

function render_to_glarea(screen, glarea)
    screen.render_tick[] = nothing
    glarea.framebuffer_id[] = glGetIntegerv(GL_FRAMEBUFFER_BINDING)
    GLMakie.render_frame(screen)
end

function push!(w::GtkGLMakie,s::Makie.FigureLike)
    if Gtk4.G_.get_realized(w)
        display(Gtk4Makie.screens[Ptr{GtkGLArea}(w.handle)], s)
    else
        signal_connect(w,"realize") do a
            display(Gtk4Makie.screens[Ptr{GtkGLArea}(w.handle)], s)
        end
    end
    w
end

function empty!(w::GtkGLMakie)
    empty!(Gtk4Makie.screens[Ptr{GtkGLArea}(w.handle)])
    w
end

Gtk4.@guarded function realizewidgetcb(glareaptr, user_data)
    a, config = user_data
    check_gl_error(a)
    
    screen = _create_screen(a, a, config, (200,200))
    GLMakie.apply_config!(screen, config)

    a.render_id = Gtk4.on_render(refreshwidgetcb, a)
    
    # start polling for changes to the scene every 50 ms - fast enough?
    update_timeout = Gtk4.GLib.g_timeout_add(50) do
        GLMakie.requires_update(screen) && Gtk4.queue_render(a)
        return !GLMakie.was_destroyed(a)
    end
    
    nothing
end

function unrealizewidgetcb(glareaptr, glarea)
    Gtk4.GLib.signal_handler_disconnect(glarea, glarea.render_id)
    nothing
end

glarea(screen::GLMakie.Screen{T}) where T <: GtkGLArea = screen.glscreen
window(screen::GLMakie.Screen{T}) where T <: GtkGLArea = toplevel(screen.glscreen)

GLMakie.pollevents(::GLMakie.Screen{T}) where T <: GtkGLArea = nothing

GLMakie.was_destroyed(nw::GtkGLMakie) = GLMakie.was_destroyed(toplevel(nw))
Base.isopen(win::GtkGLMakie) = !GLMakie.was_destroyed(toplevel(win))

function GLMakie.apply_config!(screen::GLMakie.Screen{T},config::GLMakie.ScreenConfig; start_renderloop=true) where T <: GtkGLArea
    return _apply_config!(screen, config, start_renderloop)
end

GLMakie.framebuffer_size(w::GtkGLMakie) = size(w) .* Gtk4.scale_factor(w)

function ShaderAbstractions.native_switch_context!(a::GtkGLMakie)
    Gtk4.G_.get_realized(a) || return
    Gtk4.make_current(a)
end

"""
    GtkMakieWidget(;
                   resolution = (200, 200),
                   screen_config...)

Create a Gtk4Makie widget. Returns the widget. The screen will not be created until the widget is realized.
"""
function GtkMakieWidget(;
                   resolution = (200, 200),
                   screen_config...
    )
    config = Makie.merge_screen_config(GLMakie.ScreenConfig, Dict{Symbol, Any}(screen_config))
    glarea = try
        glarea = GtkGLMakie()
        glarea.hexpand = glarea.vexpand = true
        glarea
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
