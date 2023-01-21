
function GLMakie.resize_native!(window::Gtk4.GtkWindowLeaf, resolution...)
    isopen(window) || return
    oldsize = size(window[])
    retina_scale = GLMakie.retina_scaling_factor(window[])
    w, h = resolution .÷ retina_scale
    if oldsize == (w, h)
        return
    end
    Gtk4.default_size(window, w, h)
end

Gtk4.@guarded Cint(false) function refreshwindowcb(a, c, user_data)
    if haskey(screens, Ptr{GtkGLArea}(a))
        screen = screens[Ptr{GtkGLArea}(a)]
        isopen(screen) || return Cint(false)
        screen.render_tick[] = nothing
        screen.glscreen[].framebuffer_id[] = glGetIntegerv(GL_FRAMEBUFFER_BINDING)
        GLMakie.render_frame(screen)
    end
    return Cint(true)
end

function realizecb(a)
    Gtk4.make_current(a)
    e = Gtk4.get_error(a)
    if e != C_NULL
        @async println("Error!")
        return
    end
end

mutable struct GtkGLMakie <: GtkGLArea
    handle::Ptr{GObject}
    framebuffer_id::Ref{Int}
    handlers::Dict{Symbol,Tuple{GObject,Culong}}

    function GtkGLMakie()
        glarea = GtkGLArea()
        Gtk4.auto_render(glarea,false)
        ids = Dict{Symbol,Culong}()
        widget = new(glarea.handle, Ref{Int}(0), ids)
        return Gtk4.GLib.gobject_move_ref(widget, glarea)
    end
end

const GTKGLWindow = GtkGLMakie

const screens = Dict{Ptr{Gtk4.GtkGLArea}, GLMakie.Screen}();

GLMakie.framebuffer_size(w::Gtk4.GtkWindowLeaf) = GLMakie.framebuffer_size(w[])
GLMakie.framebuffer_size(w::GTKGLWindow) = size(w) .* GLMakie.retina_scaling_factor(w)
GLMakie.window_size(w::GTKGLWindow) = size(w)

GLMakie.to_native(w::Gtk4.GtkWindowLeaf) = w[]
GLMakie.to_native(gl::GTKGLWindow) = gl
GLMakie.pollevents(::GLMakie.Screen{Gtk4.GtkWindowLeaf}) = nothing

GLMakie.was_destroyed(nw::Gtk4.GtkWindowLeaf) = nw.handle == C_NULL || Gtk4.G_.in_destruction(nw)
function Base.isopen(win::Gtk4.GtkWindowLeaf)
    GLMakie.was_destroyed(win) && return false
    return true
end
function GLMakie.set_screen_visibility!(nw::Gtk4.GtkWindowLeaf, b::Bool)
    if b
        Gtk4.show(nw)
    else
        Gtk4.hide(nw)
    end
end

function GLMakie.apply_config!(screen::GLMakie.Screen{Gtk4.GtkWindowLeaf},config::GLMakie.ScreenConfig; visible = true, start_renderloop=true)
    ShaderAbstractions.switch_context!(screen.glscreen)
    glw = screen.glscreen
    ShaderAbstractions.switch_context!(glw)

    # TODO: figure out what to do with "focus_on_show" and "float"
    Gtk4.decorated(glw, config.decorated)
    Gtk4.title(glw,"GtkMakie: "*config.title)

    if !isnothing(config.monitor)
        # TODO: set monitor where this window appears?
    end

    # following could probably be shared between GtkMakie and GLMakie
    function replace_processor!(postprocessor, idx)
        fb = screen.framebuffer
        shader_cache = screen.shader_cache
        post = screen.postprocessors[idx]
        if post.constructor !== postprocessor
            destroy!(screen.postprocessors[idx])
            screen.postprocessors[idx] = postprocessor(fb, shader_cache)
        end
        return
    end

    replace_processor!(config.ssao ? ssao_postprocessor : empty_postprocessor, 1)
    replace_processor!(config.oit ? OIT_postprocessor : empty_postprocessor, 2)
    replace_processor!(config.fxaa ? fxaa_postprocessor : empty_postprocessor, 3)
    # Set the config
    screen.config = config

    GLMakie.set_screen_visibility!(screen, visible)
    return screen
end

function Base.close(screen::GLMakie.Screen{Gtk4.GtkWindowLeaf}; reuse=true)
    GLMakie.set_screen_visibility!(screen, false)
    GLMakie.stop_renderloop!(screen; close_after_renderloop=false)
    if screen.window_open[]
        screen.window_open[] = false
    end
    empty!(screen)
    if reuse && screen.reuse
        push!(SCREEN_REUSE_POOL, screen)
    end
    close(toplevel(screen.glscreen))
    return
end

ShaderAbstractions.native_switch_context!(a::GTKGLWindow) = Gtk4.make_current(a)
ShaderAbstractions.native_switch_context!(a::Gtk4.GtkWindowLeaf) = ShaderAbstractions.native_switch_context!(a[])

ShaderAbstractions.native_context_alive(x::Gtk4.GtkWindowLeaf) = !GLMakie.was_destroyed(x)
ShaderAbstractions.native_context_alive(x::GTKGLWindow) = !GLMakie.was_destroyed(toplevel(x))

function GLMakie.destroy!(nw::Gtk4.GtkWindow)
    was_current = ShaderAbstractions.is_current_context(nw)
    if !GLMakie.was_destroyed(nw)
        close(nw)
    end
    was_current && ShaderAbstractions.switch_context!()
end

function GTKScreen(;
        resolution = (10, 10), visible = false,
        screen_config...
    )
    config = Makie.merge_screen_config(GLMakie.ScreenConfig, screen_config)
    window, glarea = try
        w = GtkWindow("GtkMakie: "*config.title, -1, -1, true, false)
        f=Gtk4.scale_factor(w)
        Gtk4.default_size(w, resolution[1] ÷ f, resolution[2] ÷ f)
        show(w)
        glarea = GtkGLMakie()
        w, glarea
    catch e
        @warn("""
            Gtk4 couldn't create an OpenGL window.
        """)
        rethrow(e)
    end

    Gtk4.signal_connect(realizecb, glarea, "realize")
    window[] = glarea

    # tell GLAbstraction that we created a new context.
    # This is important for resource tracking, and only needed for the first context
    shader_cache = GLAbstraction.ShaderCache(glarea)
    ShaderAbstractions.switch_context!(glarea)
    fb = GLMakie.GLFramebuffer(resolution)

    postprocessors = [
        config.ssao ? ssao_postprocessor(fb, shader_cache) : empty_postprocessor(),
        OIT_postprocessor(fb, shader_cache),
        config.fxaa ? fxaa_postprocessor(fb, shader_cache) : empty_postprocessor(),
        to_screen_postprocessor(fb, shader_cache, glarea.framebuffer_id)
    ]

    screen = GLMakie.Screen(
        window, shader_cache, fb,
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
    screens[Ptr{Gtk4.GtkGLArea}(glarea.handle)] = screen

    Gtk4.signal_connect(refreshwindowcb, glarea, "render", Cint, (Ptr{Gtk4.Gtk4.GdkGLContext},))

    return screen
end
