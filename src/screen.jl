
function GLMakie.resize_native!(window::Gtk4.GtkWindowLeaf, resolution...)
    oldsize = size(window[])
    #retina_scale = retina_scaling_factor(window)
    w, h = resolution #./ retina_scale
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

GLMakie.framebuffer_size(w::Gtk4.GtkWindowLeaf) = size(w[])
GLMakie.isopen(::Gtk4.GtkWindowLeaf) = true
GLMakie.to_native(w::Gtk4.GtkWindowLeaf) = w[]
GLMakie.to_native(gl::GTKGLWindow) = gl

default_ID = Ref{Int}()

Gtk4.@guarded Cint(false) function refreshwindowcb(a, c, user_data)
    #@async println("refreshwindow")
    if haskey(screens, Ptr{Gtk4.GtkGLArea}(a))
        @async println("renderin'")
        screen = screens[Ptr{Gtk4.GtkGLArea}(a)]
        screen.render_tick[] = nothing
        default_ID[] = glGetIntegerv(GL_FRAMEBUFFER_BINDING)
        GLMakie.render_frame(screen)
    end
    #glClearColor(0.0, 0.0, 0.5, 1.0)
    #glClear(GL_COLOR_BUFFER_BIT)
    return Cint(true)
end

ShaderAbstractions.native_switch_context!(a::GTKGLWindow) = Gtk4.make_current(a)
ShaderAbstractions.native_switch_context!(a::Gtk4.GtkWindowLeaf) = ShaderAbstractions.native_switch_context!(a[])

ShaderAbstractions.native_context_alive(x::Gtk4.GtkWindowLeaf) = true  # TODO!!!
ShaderAbstractions.native_context_alive(x::GTKGLWindow) = true  # TODO!!!


function GTKScreen(;
        resolution = (10, 10), visible = false,
        screen_config...
    )
    config = Makie.merge_screen_config(GLMakie.ScreenConfig, screen_config)
    window, glarea = try
        w = Gtk4.GtkWindow(config.title, resolution[1], resolution[2])
        glarea = Gtk4.GtkGLArea()
        #glarea.has_stencil_buffer = true
        #glarea.has_depth_buffer = true
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
        # Instead of being hard-coded as 2, this "default_ID" should be found with
        # `default_ID = glGetIntegerv(GL_FRAMEBUFFER_BINDING)` near the beginning of
        # `render_frame`
        to_screen_postprocessor(fb, shader_cache, 2)
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
