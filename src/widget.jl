# GtkMakieWidget

function Base.resize!(screen::Screen{T}, w::Int, h::Int) where T <: GtkGLArea
    widget = screen.glscreen
    (w > 0 && h > 0 && isopen(widget)) || return nothing
    
    winscale = screen.scalefactor[] / Gtk4.scale_factor(widget)
    winw, winh = round.(Int, winscale .* (w, h))
    if size(widget) != (winw, winh)
        # following sets minimum size, which isn't what we want
        # should we just ignore what Makie requests?
        #Gtk4.G_.set_size_request(widget, winw, winh)
    end

    # Then resize the underlying rendering framebuffers as well, which can be scaled
    # independently of the window scale factor.
    fbscale = screen.px_per_unit[]
    fbw, fbh = round.(Int, fbscale .* (w, h))
    resize!(screen.framebuffer, fbw, fbh)
    return nothing
end

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
    check_gl_error(a)
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
    GLMakie.apply_config!(screen, config)

    a.render_id = Gtk4.signal_connect(refreshwidgetcb, a, "render", Cint, (Ptr{Gtk4.Gtk4.GdkGLContext},))
    
    # start polling for changes to the scene every 50 ms - fast enough?
    update_timeout = Gtk4.GLib.g_timeout_add(50) do
        GLMakie.requires_update(screen) && Gtk4.queue_render(a)
        if GLMakie.was_destroyed(a)
            return Cint(0)
        end
        Cint(1)
    end
    
    nothing
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
    winscale = screen.scalefactor[] / Gtk4.scale_factor(glarea)
    _window_area(scene, glarea, winscale)
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

function GLMakie.set_screen_visibility!(nw::GtkGLMakie, b::Bool)
    if b
        Gtk4.show(nw)
    else
        Gtk4.hide(nw)
    end
end


function GLMakie.apply_config!(screen::GLMakie.Screen{T},config::GLMakie.ScreenConfig; start_renderloop=true) where T <: GtkGLArea
    return _apply_config!(screen, config, start_renderloop)
end

function Base.close(screen::GLMakie.Screen{T}; reuse=true) where T <: GtkGLArea
    _close(screen, reuse)
    return
end

GLMakie.framebuffer_size(w::GtkGLMakie) = size(w) .* Gtk4.scale_factor(w)
GLMakie.window_size(w::GtkGLMakie) = size(w)

GLMakie.to_native(gl::GtkGLMakie) = gl

function ShaderAbstractions.native_switch_context!(a::GtkGLMakie)
    Gtk4.G_.get_realized(a) || return
    Gtk4.make_current(a)
end
ShaderAbstractions.native_context_alive(x::GtkGLMakie) = !GLMakie.was_destroyed(toplevel(x))

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
