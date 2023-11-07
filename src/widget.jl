function GLMakie.resize_native!(widget::GtkGLMakie, resolution...)
    isopen(widget) || return
    oldsize = size(widget)
    retina_scale = GLMakie.retina_scaling_factor(widget)
    w, h = resolution .÷ retina_scale
    if oldsize == (w, h)
        return
    end
    Gtk4.default_size(toplevel(widget), w, h)
end

function render_to_glarea(screen, glarea)
    screen.render_tick[] = nothing
    glarea.framebuffer_id[] = glGetIntegerv(GL_FRAMEBUFFER_BINDING)
    GLMakie.render_frame(screen)
end

function push!(w::GtkGLMakie,s::Makie.FigureLike)
    signal_connect(w,"realize") do a
        display(Gtk4Makie.screens[Ptr{GtkGLArea}(w.handle)], s)
    end
    w
end

Gtk4.@guarded Cint(false) function refreshwidgetcb(a, c, user_data)
    if haskey(screens, Ptr{GtkGLArea}(a))
        screen = screens[Ptr{GtkGLArea}(a)]
        isopen(screen) || return Cint(false)
        render_to_glarea(screen, screen.glscreen)
    end
    return Cint(true)
end

function realizewidgetcb(glareaptr, user_data)
    a, config = user_data
    # tell GLAbstraction that we created a new context.
    # This is important for resource tracking, and only needed for the first context
    shader_cache = GLAbstraction.ShaderCache(a)
    ShaderAbstractions.switch_context!(a)
    fb = GLMakie.GLFramebuffer((200,200))

    postprocessors = [
        config.ssao ? ssao_postprocessor(fb, shader_cache) : empty_postprocessor(),
        OIT_postprocessor(fb, shader_cache),
        config.fxaa ? fxaa_postprocessor(fb, shader_cache) : empty_postprocessor(),
        to_screen_postprocessor(fb, shader_cache, a.framebuffer_id)
    ]

    screen = GLMakie.Screen(
        a, shader_cache, fb,
        config, false,
        nothing,
        Dict{WeakRef, GLMakie.ScreenID}(),
        GLMakie.ScreenArea[],
        Tuple{GLMakie.ZIndex, GLMakie.ScreenID, GLMakie.RenderObject}[],
        postprocessors,
        Dict{UInt64, GLMakie.RenderObject}(),
        Dict{UInt32, Makie.AbstractPlot}(),
        false,
    )
    screens[Ptr{Gtk4.GtkGLArea}(a.handle)] = screen

    a.render_id = Gtk4.signal_connect(refreshwidgetcb, a, "render", Cint, (Ptr{Gtk4.Gtk4.GdkGLContext},))
    
    Gtk4.make_current(a)
    c=Gtk4.context(a)
    ma,mi = Gtk4.version(c)
    v=ma+0.1*mi
    @debug("using OPENGL version $(ma).$(mi)")
    use_es = Gtk4.use_es(c)
    @debug("use_es: $(use_es)")
    e = Gtk4.get_error(a)
    if e != C_NULL
        msg = Gtk4.GLib.bytestring(Gtk4.GLib.GError(e).message)
        @async println("Error during realize callback: $msg")
        return
    end
    if v<3.3
        @warn("Makie requires OpenGL 3.3")
    end
end

function unrealizewidgetcb(glareaptr, glarea)
    Gtk4.GLib.signal_handler_disconnect(glarea, glarea.render_id)
    nothing
end

function Makie.mouse_position(scene::Scene, screen::GLMakie.Screen{T}) where T <: GtkGLMakie
    glarea = screen.glscreen
    _mouse_position(scene, glarea)
end

function Makie.window_area(scene::Scene, screen::GLMakie.Screen{T}) where T <: GtkGLMakie
    glarea=screen.glscreen
    _window_area(scene, glarea)
end

glarea(screen::GLMakie.Screen{T}) where T <: GtkGLArea = screen.glscreen
window(screen::GLMakie.Screen{T}) where T <: GtkGLArea = toplevel(screen.glscreen)

GLMakie.pollevents(::GLMakie.Screen{T}) where T <: GtkGLArea = nothing

function GLMakie.was_destroyed(nw::GtkGLMakie)
    nw = toplevel(nw)
    !(nw.handle in Gtk4.G_.list_toplevels()) || Gtk4.G_.in_destruction(nw)
end
function Base.isopen(win::GtkGLMakie)
    GLMakie.was_destroyed(toplevel(win)) && return false
    return true
end

function GLMakie.apply_config!(screen::GLMakie.Screen{T},config::GLMakie.ScreenConfig; start_renderloop=true) where T <: GtkGLArea
    return _apply_config!(screen, config, start_renderloop)
end

function Base.close(screen::GLMakie.Screen{T}; reuse=true) where T <: GtkGLArea
    _close(screen, reuse)
    return
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
    config = Makie.merge_screen_config(GLMakie.ScreenConfig, screen_config)
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
