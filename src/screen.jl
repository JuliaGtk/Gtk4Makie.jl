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

mutable struct GtkGLMakie <: GtkGLArea
    handle::Ptr{GObject}
    framebuffer_id::Ref{Int}
    handlers::Dict{Symbol,Tuple{GObject,Culong}}
    inspector::Union{DataInspector,Nothing}

    function GtkGLMakie()
        glarea = GtkGLArea()
        Gtk4.auto_render(glarea,false)
        # Following breaks rendering on my Mac
        Sys.isapple() || Gtk4.G_.set_required_version(glarea, 3, 3)
        ids = Dict{Symbol,Culong}()
        widget = new(getfield(glarea,:handle), Ref{Int}(0), ids, nothing)
        return Gtk4.GLib.gobject_move_ref(widget, glarea)
    end
end

const GTKGLWindow = GtkGLMakie

const screens = Dict{Ptr{Gtk4.GtkGLArea}, GLMakie.Screen}();
const win2glarea = Dict{WindowType, GtkGLMakie}();

"""
    grid(screen::GLMakie.Screen{T}) where T <: GtkWindow

For a Gtk4Makie screen, get the GtkGrid containing the GtkGLArea where Makie draws. Other widgets can be added to this grid.
"""
grid(screen::GLMakie.Screen{T}) where T <: GtkWindow = screen.glscreen[]

"""
    glarea(screen::GLMakie.Screen{T}) where T <: GtkWindow

For a Gtk4Makie screen, get the GtkGLArea where Makie draws.
"""
glarea(screen::GLMakie.Screen{T}) where T <: GtkWindow = win2glarea[screen.glscreen]

"""
    window(screen::GLMakie.Screen{T}) where T <: GtkWindow

Get the Gtk4 window corresponding to a Gtk4Makie screen.
"""
window(screen::GLMakie.Screen{T}) where T <: GtkWindow = screen.glscreen

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
    @debug("Applying screen config to existing screen")
    glw = screen.glscreen
    ShaderAbstractions.switch_context!(glw)

    # TODO: figure out what to do with "focus_on_show" and "float"
    Gtk4.decorated(glw, config.decorated)
    Gtk4.title(glw,config.title)
    config.fullscreen && Gtk4.fullscreen(glw)

    if !isnothing(config.monitor)
        # TODO: set monitor where this window appears?
    end

    # following could probably be shared between Gtk4Makie and GLMakie
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
    @debug("Close screen!")
    GLMakie.set_screen_visibility!(screen, false)
    GLMakie.stop_renderloop!(screen; close_after_renderloop=false)
    if screen.window_open[]
        screen.window_open[] = false
    end
    if !GLMakie.was_destroyed(screen.glscreen)
        empty!(screen)
    end
    if reuse && screen.reuse
        @debug("reusing screen!")
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

function _toggle_fullscreen(win)
    if Gtk4.isfullscreen(win)
        Gtk4.unfullscreen(win)
    else
        Gtk4.fullscreen(win)
    end
end

function fullscreen_cb(::Ptr,par,screen)
    win=window(screen)
    @idle_add _toggle_fullscreen(win)
    nothing
end

function inspector_cb(ptr::Ptr,par,screen)
    ac = convert(GSimpleAction, ptr)
    gv=GVariant(par)
    set_state(ac, gv)
    g = glarea(screen)
    if gv[Bool]
        if isnothing(g.inspector)
            g.inspector = DataInspector()
        end
        Makie.enable!(g.inspector)
    else
        isnothing(g.inspector) || Makie.disable!(g.inspector)
    end
    nothing
end

function close_cb(::Ptr,par,screen)
    win=window(screen)
    @idle_add Gtk4.destroy(win)
    nothing
end

function save_cb(::Ptr,par,screen)
    dlg = GtkFileDialog()
    function file_save_cb(obj, res)
        dlg = convert(GtkFileDialog, obj)
        leaftype = Gtk4.GLib.find_leaf_type(res)
        resobj = convert(leaftype, res)
        try
            gfile = Gtk4.G_.save_finish(dlg, Gtk4.GLib.GAsyncResult(resobj))
            filepath=Gtk4.GLib.path(Gtk4.GLib.GFile(gfile))
            if endswith(filepath,".png")
                GLMakie.save(filepath,screen.root_scene)
            elseif endswith(filepath,".pdf") || endswith(filepath,".svg")
                # if we imported CairoMakie we could use that to save to these formats
            end
        catch e
            return nothing
        end
    end
    Gtk4.G_.save(dlg, window(screen), nothing, file_save_cb)
    nothing
end

function add_window_actions(ag,screen)
    m = Gtk4.GLib.GActionMap(ag)
    add_action(m,"save",save_cb,screen)
    add_action(m,"close",close_cb,screen)
    add_action(m,"fullscreen",fullscreen_cb,screen)
    add_stateful_action(m,"inspector",false,inspector_cb,screen)
end

function add_shortcut(sc,trigger,action)
    save_trigger = GtkShortcutTrigger(trigger)
    save_action = GtkShortcutAction("action($action)")
    save_shortcut = GtkShortcut(save_trigger,save_action)
    Gtk4.G_.add_shortcut(sc,save_shortcut)
end

function add_window_shortcuts(w)
    sc = GtkShortcutController(w)
    add_shortcut(sc,Sys.isapple() ? "<Meta>S" : "<Control>S", "win.save")
    add_shortcut(sc,Sys.isapple() ? "<Meta>W" : "<Control>W", "win.close")
    add_shortcut(sc,Sys.isapple() ? "<Meta><Shift>F" : "F11", "win.fullscreen")
end

"""
    GTKScreen(headerbar=true;
                   resolution = (200, 200),
                   app = nothing,
                   screen_config...)

Create a Gtk4Makie screen. If `headerbar` is `true`, the window will include a header bar with a save button. The keyword argument `resolution` can be used to set the initial size of the window (which may be adjusted by Makie later). A GtkApplication instance can be passed using the keyword argument `app`. If this is done, a GtkApplicationWindow will be created rather than the default GtkWindow.

Supported `screen_config` arguments and their default values are:
* `title::String = "Makie"`: Sets the window title.
* `fullscreen = false`: Whether or not the window should be fullscreened when first created.
"""
function GTKScreen(headerbar=true;
                   resolution = (200, 200),
                   app = nothing,
                   screen_config...
    )
    config = Makie.merge_screen_config(GLMakie.ScreenConfig, screen_config)
    # Creating the framebuffers requires that the window be realized, it seems...
    # It would be great to allow initially invisible windows so that we don't pop
    # up windows during precompilation.
    config.visible || error("Initially invisible windows are not currently supported.")
    window, glarea = try
        w = if isnothing(app)
            GtkWindow(config.title, -1, -1, true, false)
        else
            GtkApplicationWindow(app, config.title)
        end
        if headerbar
            hb = GtkHeaderBar()
            Gtk4.titlebar(w,hb)
            save_button = GtkButton("Save"; action_name = "win.save")
            push!(hb,save_button)
            inspector_button = GtkToggleButton("Inspector";
                                               action_name = "win.inspector")
            push!(hb, inspector_button)
        end
        add_window_shortcuts(w)
        f=Gtk4.scale_factor(w)
        Gtk4.default_size(w, resolution[1] ÷ f, resolution[2] ÷ f)
        config.fullscreen && Gtk4.fullscreen(w)
        config.visible && show(w)
        glarea = GtkGLMakie()
        glarea.hexpand = glarea.vexpand = true
        w, glarea
    catch e
        @warn("""
            Gtk4Makie couldn't create a window.
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

    if isnothing(app)
        ag = Gtk4.GLib.GSimpleActionGroup()
        add_window_actions(ag,screen)
        push!(window, Gtk4.GLib.GActionGroup(ag), "win")
    else
        add_window_actions(Gtk4.GLib.GActionGroup(window),screen)
    end

    Gtk4.signal_connect(refreshwindowcb, glarea, "render", Cint, (Ptr{Gtk4.Gtk4.GdkGLContext},))
    
    # start polling for changes to the scene every 50 ms - fast enough?
    update_timeout = Gtk4.GLib.g_timeout_add(50) do
        GLMakie.requires_update(screen) && Gtk4.queue_render(glarea)
        if GLMakie.was_destroyed(window)
            return Cint(0)
        end
        Cint(1)
    end

    return screen
end
