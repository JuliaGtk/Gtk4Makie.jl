
function GLMakie.resize_native!(window::Gtk4.GtkWindowLeaf, resolution...)
    oldsize = size(window[])
    retina_scale = GLMakie.retina_scaling_factor(window[])
    w, h = resolution .÷ retina_scale
    if oldsize == (w, h)
        return
    end
    Gtk4.G_.set_default_size(window, w, h)
end

function realizecb(a)
    Gtk4.make_current(a)
    e = Gtk4.get_error(a)
    if e != C_NULL
        @async println("Error!")
        return
    end
end

const GTKGLWindow = Gtk4.GtkGLAreaLeaf

const screens = Dict{Ptr{Gtk4.GtkGLArea}, GLMakie.Screen}();

GLMakie.framebuffer_size(w::Gtk4.GtkWindowLeaf) = size(w[]) .* GLMakie.retina_scaling_factor(w[])
GLMakie.isopen(::Gtk4.GtkWindowLeaf) = true
GLMakie.to_native(w::Gtk4.GtkWindowLeaf) = w[]
GLMakie.to_native(gl::GTKGLWindow) = gl
GLMakie.pollevents(::GLMakie.Screen{Gtk4.GtkWindowLeaf}) = nothing

GLMakie.was_destroyed(nw::Gtk4.GtkWindowLeaf) = nw.handle == C_NULL || Gtk4.G_.in_destruction(nw)
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
    Gtk4.title(glw,config.title)

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

default_ID = Ref{Int}(2)

Gtk4.@guarded Cint(false) function refreshwindowcb(a, c, user_data)
    if haskey(screens, Ptr{Gtk4.GtkGLArea}(a))
        screen = screens[Ptr{Gtk4.GtkGLArea}(a)]
        screen.render_tick[] = nothing
        default_ID[] = glGetIntegerv(GL_FRAMEBUFFER_BINDING)
        GLMakie.render_frame(screen)
    end
    return Cint(true)
end

ShaderAbstractions.native_switch_context!(a::GTKGLWindow) = Gtk4.make_current(a)
ShaderAbstractions.native_switch_context!(a::Gtk4.GtkWindowLeaf) = ShaderAbstractions.native_switch_context!(a[])

ShaderAbstractions.native_context_alive(x::Gtk4.GtkWindowLeaf) = !GLMakie.was_destroyed(x)
ShaderAbstractions.native_context_alive(x::GTKGLWindow) = !GLMakie.was_destroyed(toplevel(x))


function GTKScreen(;
        resolution = (10, 10), visible = false,
        screen_config...
    )
    config = Makie.merge_screen_config(GLMakie.ScreenConfig, screen_config)
    window, glarea = try
        w = Gtk4.GtkWindow(config.title, -1, -1, true, false)
        f=Gtk4.scale_factor(w)
        Gtk4.default_size(w, resolution[1] ÷ f, resolution[2] ÷ f)
        show(w)
        glarea = Gtk4.GtkGLArea()
        w, glarea
    catch e
        @warn("""
            GLFW couldn't create an OpenGL window.
            This likely means, you don't have an OpenGL capable Graphic Card,
            or you don't have an OpenGL 3.3 capable video driver installed.
            Have a look at the troubleshooting section in the GLMakie readme:
            https://github.com/JuliaPlots/Makie.jl/tree/master/GLMakie#troubleshooting-opengl.
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
        to_screen_postprocessor(fb, shader_cache, default_ID)
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
