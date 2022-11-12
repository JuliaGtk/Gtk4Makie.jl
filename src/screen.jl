
function GLMakie.resize_native!(::Gtk4.GtkWindowLeaf, resolution...)
    # TODO implement
end

function realizecb(a)
    Gtk4.G_.make_current(a)
    e = Gtk4.G_.get_error(a)
    if e != C_NULL
        @async println("Error!")
        return
    end
end

const GTKGLWindow = Gtk4.GtkGLAreaLeaf

const screens = Dict{Ptr{Gtk4.GtkGLArea}, GLMakie.Screen}();

GLMakie.framebuffer_size(::Gtk4.GtkWindowLeaf) = (800, 800)
GLMakie.isopen(::Gtk4.GtkWindowLeaf) = true
GLMakie.to_native(w::Gtk4.GtkWindowLeaf) = w[]
GLMakie.to_native(gl::GTKGLWindow) = gl

Gtk4.@guarded Cint(false) function refreshwindowcb(a, c, user_data)
    #@async println("refreshwindow")
    if haskey(screens, Ptr{Gtk4.GtkGLArea}(a))
        screen = screens[Ptr{Gtk4.GtkGLArea}(a)]
        screen.render_tick[] = nothing
        GLMakie.render_frame(screen)
    end
    #glClearColor(0.0, 0.0, 0.5, 1.0)
    #glClear(GL_COLOR_BUFFER_BIT)
    return Cint(0)
end

ShaderAbstractions.native_switch_context!(a::GTKGLWindow) = Gtk4.G_.make_current(a)
ShaderAbstractions.native_switch_context!(a::Gtk4.GtkWindowLeaf) = ShaderAbstractions.native_switch_context!(a[])

ShaderAbstractions.native_context_alive(x) = true  # TODO!!!


function GTKScreen(;
        resolution = (10, 10), visible = false,
        screen_config...
    )
    config = Makie.merge_screen_config(GLMakie.ScreenConfig, screen_config)
    window, glarea = try
        w = Gtk4.GtkWindow(config.title)
        glarea = Gtk4.GtkGLArea()
        glarea.has_stencil_buffer = true
        glarea.has_depth_buffer = true
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
        to_screen_postprocessor(fb, shader_cache)
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
