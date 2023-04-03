const WindowType = Union{Gtk4.GtkWindowLeaf, Gtk4.GtkApplicationWindowLeaf}

function GLMakie.resize_native!(window::WindowType, resolution...)
    isopen(window) || return
    oldsize = size(win2glarea[window])
    retina_scale = GLMakie.retina_scaling_factor(win2glarea[window])
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
        glarea = win2glarea[screen.glscreen]
        glarea.framebuffer_id[] = glGetIntegerv(GL_FRAMEBUFFER_BINDING)
        GLMakie.render_frame(screen)
    end
    return Cint(true)
end

function realizecb(a)
    Gtk4.make_current(a)
    e = Gtk4.get_error(a)
    if e != C_NULL
        @async println("Error during realize callback")
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
        Gtk4.G_.set_required_version(glarea, 3, 3)
        ids = Dict{Symbol,Culong}()
        widget = new(glarea.handle, Ref{Int}(0), ids)
        return Gtk4.GLib.gobject_move_ref(widget, glarea)
    end
end

const GTKGLWindow = GtkGLMakie

const screens = Dict{Ptr{Gtk4.GtkGLArea}, GLMakie.Screen}();
const win2glarea = Dict{WindowType, GtkGLMakie}();

"""
    grid(screen::GLMakie.Screen{T}) where T <: GtkWindow

For a GtkMakie screen, get the GtkGrid containing the GtkGLArea where Makie draws. Other widgets can be added to this grid.
"""
grid(screen::GLMakie.Screen{T}) where T <: GtkWindow = screen.glscreen[]

"""
    glarea(screen::GLMakie.Screen{T}) where T <: GtkWindow

For a GtkMakie screen, get the GtkGLArea where Makie draws.
"""
glarea(screen::GLMakie.Screen{T}) where T <: GtkWindow = win2glarea[screen.glscreen]

GLMakie.framebuffer_size(w::WindowType) = GLMakie.framebuffer_size(win2glarea[w])
GLMakie.framebuffer_size(w::GTKGLWindow) = size(w) .* GLMakie.retina_scaling_factor(w)
GLMakie.window_size(w::GTKGLWindow) = size(w)

GLMakie.to_native(w::WindowType) = win2glarea[w]
GLMakie.to_native(gl::GTKGLWindow) = gl
GLMakie.pollevents(::GLMakie.Screen{T}) where T <: GtkWindow = nothing

function GLMakie.was_destroyed(nw::WindowType)
    !(nw.handle in Gtk4.G_.list_toplevels()) || Gtk4.G_.in_destruction(nw)
end
function Base.isopen(win::WindowType)
    GLMakie.was_destroyed(win) && return false
    return true
end
function GLMakie.set_screen_visibility!(nw::WindowType, b::Bool)
    if b
        Gtk4.show(nw)
    else
        Gtk4.hide(nw)
    end
end

function GLMakie.apply_config!(screen::GLMakie.Screen{T},config::GLMakie.ScreenConfig; start_renderloop=true) where T <: GtkWindow
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

    GLMakie.set_screen_visibility!(screen, config.visible)
    return screen
end

function Makie.colorbuffer(screen::GLMakie.Screen{T}, format::Makie.ImageStorageFormat = Makie.JuliaNative) where T <: GtkWindow
    if !isopen(screen)
        error("Screen not open!")
    end
    ShaderAbstractions.switch_context!(screen.glscreen)
    ctex = screen.framebuffer.buffers[:color]
    if size(ctex) != size(screen.framecache)
        screen.framecache = Matrix{RGB{Colors.N0f8}}(undef, size(ctex))
    end
    GLMakie.fast_color_data!(screen.framecache, ctex)
    if format == Makie.GLNative
        return screen.framecache
    elseif format == Makie.JuliaNative
        img = screen.framecache
        return PermutedDimsArray(view(img, :, size(img, 2):-1:1), (2, 1))
    end
end

function Base.close(screen::GLMakie.Screen{T}; reuse=true) where T <: GtkWindow
    GLMakie.set_screen_visibility!(screen, false)
    GLMakie.stop_renderloop!(screen; close_after_renderloop=false)
    if screen.window_open[]
        screen.window_open[] = false
    end
    empty!(screen)
    if reuse && screen.reuse
        push!(SCREEN_REUSE_POOL, screen)
    end
    glw = screen.glscreen
    if haskey(win2glarea, glw)
        glarea = win2glarea[glw]
        delete!(screens, Ptr{Gtk4.GtkGLArea}(glarea.handle))
        delete!(win2glarea, glw)
    end        
    close(toplevel(screen.glscreen))
    return
end

ShaderAbstractions.native_switch_context!(a::GTKGLWindow) = Gtk4.make_current(a)
ShaderAbstractions.native_switch_context!(a::WindowType) = ShaderAbstractions.native_switch_context!(win2glarea[a])

ShaderAbstractions.native_context_alive(x::WindowType) = !GLMakie.was_destroyed(x)
ShaderAbstractions.native_context_alive(x::GTKGLWindow) = !GLMakie.was_destroyed(toplevel(x))

function GLMakie.destroy!(nw::WindowType)
    was_current = ShaderAbstractions.is_current_context(nw)
    if !GLMakie.was_destroyed(nw)
        close(nw)
    end
    was_current && ShaderAbstractions.switch_context!()
end

"""
    GTKScreen(;
                   resolution = (200, 200),
                   app = nothing,
                   screen_config...)

Create a GtkMakie screen. The keyword argument `resolution` can be used to set the initial size of the window (which may be adjusted by Makie later). A GtkApplication instance can be passed using the keyword argument `app`. If this is done, a GtkApplicationWindow will be created rather than the default GtkWindow.

Supported `screen_config` arguments and their default values are:
* `title::String = "Makie"`: Sets the window title.
* `visible = true`: Whether or not the window should be visible when first created.
"""
function GTKScreen(;
                   resolution = (200, 200),
                   app = nothing,
                   screen_config...
    )
    config = Makie.merge_screen_config(GLMakie.ScreenConfig, screen_config)
    window, glarea = try
        w = if isnothing(app)
            GtkWindow(config.title, -1, -1, true, false)
        else
            GtkApplicationWindow(app, config.title)
        end
        f=Gtk4.scale_factor(w)
        Gtk4.default_size(w, resolution[1] ÷ f, resolution[2] ÷ f)
        config.visible && show(w)
        glarea = GtkGLMakie()
        glarea.hexpand = glarea.vexpand = true
        w, glarea
    catch e
        @warn("""
            Gtk4 couldn't create an OpenGL window.
        """)
        rethrow(e)
    end

    Gtk4.signal_connect(realizecb, glarea, "realize")
    grid = GtkGrid()
    window[] = grid
    grid[1,1] = glarea

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
    win2glarea[window] = glarea

    Gtk4.signal_connect(refreshwindowcb, glarea, "render", Cint, (Ptr{Gtk4.Gtk4.GdkGLContext},))

    return screen
end
