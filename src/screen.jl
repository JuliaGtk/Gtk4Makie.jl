# Overrides for GLMakie's Screen and common code for the window and widget

const ScreenType = Union{GtkWindow, GtkGLArea}

Gtk4.@guarded Cint(false) function refreshwidgetcb(a, c, user_data)
    if haskey(screens, Ptr{GtkGLArea}(a))
        screen = screens[Ptr{GtkGLArea}(a)]
        isopen(screen) || return Cint(false)
        screen.render_tick[] = Makie.BackendTick
        glarea(screen).framebuffer_id[] = glGetIntegerv(GL_FRAMEBUFFER_BINDING)
        GLMakie.render_frame(screen)
    end
    return Cint(true)
end

function check_gl_error(a)
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

function realizecb(aptr, a)
    check_gl_error(a)
    nothing
end

mutable struct GtkGLMakie <: GtkGLArea
    handle::Ptr{GObject}
    framebuffer_id::Base.RefValue{Int}
    handlers::Dict{Symbol,Tuple{GObject,Culong}}
    inspector::Union{DataInspector,Nothing}
    figure::Union{Figure,Nothing}
    render_id::Culong

    function GtkGLMakie()
        glarea = GtkGLArea(;vexpand=true,hexpand=true)
        Gtk4.auto_render(glarea,false)
        Gtk4.allowed_apis(glarea, Gtk4.GLAPI_GL)
        # Following breaks rendering on my Mac
        Sys.isapple() || Gtk4.G_.set_required_version(glarea, 3, 3)
        ids = Dict{Symbol,Culong}()
        widget = new(getfield(glarea,:handle), Ref{Int}(0), ids, nothing, nothing, 0)
        return Gtk4.GLib.gobject_move_ref(widget, glarea)
    end
end

function _create_screen(a::GtkGLMakie, w, config, s)
    # tell GLAbstraction that we created a new context.
    # This is important for resource tracking, and only needed for the first context
    shader_cache = GLAbstraction.ShaderCache(a)
    ShaderAbstractions.switch_context!(a)
    fb = GLMakie.GLFramebuffer(s)

    postprocessors = [
        config.ssao ? ssao_postprocessor(fb, shader_cache) : empty_postprocessor(),
        OIT_postprocessor(fb, shader_cache),
        config.fxaa ? fxaa_postprocessor(fb, shader_cache) : empty_postprocessor(),
        to_screen_postprocessor(fb, shader_cache, a.framebuffer_id)
    ]
    
    screen = GLMakie.Screen(
        w, false, shader_cache, fb,
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
    screen
end

const screens = Dict{Ptr{Gtk4.GtkGLArea}, GLMakie.Screen}()

function _apply_config!(screen, config, start_renderloop)
    glw = screen.glscreen
    ShaderAbstractions.switch_context!(glw)

    screen.scalefactor[] = !isnothing(config.scalefactor) ? config.scalefactor : Gtk4.scale_factor(glw)
    screen.px_per_unit[] = !isnothing(config.px_per_unit) ? config.px_per_unit : screen.scalefactor[]

    function replace_processor!(postprocessor, idx)
        fb = screen.framebuffer
        shader_cache = screen.shader_cache
        post = screen.postprocessors[idx]
        if post.constructor !== postprocessor
            GLMakie.destroy!(screen.postprocessors[idx])
            screen.postprocessors[idx] = postprocessor(fb, shader_cache)
        end
        return
    end

    replace_processor!(config.ssao ? ssao_postprocessor : empty_postprocessor, 1)
    replace_processor!(config.oit ? OIT_postprocessor : empty_postprocessor, 2)
    replace_processor!(config.fxaa ? fxaa_postprocessor : empty_postprocessor, 3)

    # Set the config
    screen.config = config
    if !isnothing(screen.root_scene)
        resize!(screen, size(screen.root_scene)...)
    end

    GLMakie.set_screen_visibility!(screen, config.visible)
end

function Base.close(screen::GLMakie.Screen{T}; reuse=true) where T <: GtkWidget
    @debug("Close screen!")
    GLMakie.set_screen_visibility!(screen, false)
    GLMakie.stop_renderloop!(screen; close_after_renderloop=false)
    if screen.window_open[]
        screen.window_open[] = false
    end
    GLMakie.was_destroyed(screen.glscreen) || empty!(screen)
    if reuse && screen.reuse
        @debug("reusing screen!")
        push!(GLMakie.SCREEN_REUSE_POOL, screen)
    end
    glw = screen.glscreen
    if haskey(win2glarea, glw)
        glarea = win2glarea[glw]
        delete!(screens, Ptr{Gtk4.GtkGLArea}(glarea.handle))
        delete!(win2glarea, glw)
    end        
    close(toplevel(screen.glscreen))  # shouldn't do this for a widget
    return
end

mutable struct ScreenConfig
    title::String
    fullscreen::Bool
end

const Screen = GLMakie.Screen

function Screen(scene, config, args...)
    GTKScreen()
end

ShaderAbstractions.native_context_alive(x::ScreenType) = !GLMakie.was_destroyed(x)

function GLMakie.set_screen_visibility!(s::GLMakie.Screen{T}, b::Bool) where T <: GtkWidget
    nw = s.glscreen
    if b
        Gtk4.show(nw)
    else
        Gtk4.hide(nw)
    end
end

function Base.resize!(screen::Screen{T}, w::Int, h::Int) where T <: GtkWidget
    window = GLMakie.to_native(screen)
    (w > 0 && h > 0 && isopen(window)) || return nothing
    
    ShaderAbstractions.switch_context!(window)
    winscale = screen.scalefactor[] / Gtk4.scale_factor(window)
    winw, winh = round.(Int, winscale .* (w, h))
    if size(window) != (winw, winh)
        size_change(window, winw, winh)
    end

    # Then resize the underlying rendering framebuffers as well, which can be scaled
    # independently of the window scale factor.
    fbscale = screen.px_per_unit[]
    fbw, fbh = round.(Int, fbscale .* (w, h))
    resize!(screen.framebuffer, fbw, fbh)
    return nothing
end

# overload this to get access to the figure
function Base.display(screen::GLMakie.Screen{T}, figesque::Union{Makie.Figure,Makie.FigureAxisPlot}; update=true, display_attributes...) where T <: GtkWidget
    widget = glarea(screen)
    fig = isa(figesque,Figure) ? figesque : figesque.figure
    if widget.figure != fig
        widget.inspector = nothing
        widget.figure = fig
    end
    scene = Makie.get_scene(figesque)
    update && Makie.update_state_before_display!(figesque)
    display(screen, scene; display_attributes...)
    return screen
end


"""
    Gtk4Makie.activate!(; screen_config...)

Sets Gtk4Makie as the currently active backend and also optionally modifies the screen configuration using `screen_config` keyword arguments.
"""
function activate!(; screen_config...)
    Makie.inline!(false)
    #Makie.set_screen_config!(Gtk4Makie, screen_config)
    Makie.set_active_backend!(Gtk4Makie)
    return
end
