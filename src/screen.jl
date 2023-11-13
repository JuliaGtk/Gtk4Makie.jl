Gtk4.@guarded Cint(false) function refreshwindowcb(a, c, user_data)
    if haskey(screens, Ptr{GtkGLArea}(a))
        screen = screens[Ptr{GtkGLArea}(a)]
        isopen(screen) || return Cint(false)
        render_to_glarea(screen, win2glarea[screen.glscreen])
    end
    return Cint(true)
end

function realizecb(aptr, a)
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
    nothing
end

mutable struct GtkGLMakie <: GtkGLArea
    handle::Ptr{GObject}
    framebuffer_id::Ref{Int}
    handlers::Dict{Symbol,Tuple{GObject,Culong}}
    inspector::Union{DataInspector,Nothing}
    figure::Union{Figure,Nothing}
    render_id::Culong

    function GtkGLMakie()
        glarea = GtkGLArea()
        Gtk4.auto_render(glarea,false)
        # Following breaks rendering on my Mac
        Sys.isapple() || Gtk4.G_.set_required_version(glarea, 3, 3)
        ids = Dict{Symbol,Culong}()
        widget = new(getfield(glarea,:handle), Ref{Int}(0), ids, nothing, nothing, 0)
        return Gtk4.GLib.gobject_move_ref(widget, glarea)
    end
end

const screens = Dict{Ptr{Gtk4.GtkGLArea}, GLMakie.Screen}()

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

function _apply_config!(screen, config, start_renderloop)
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
end

function _close(screen, reuse)
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
    isnothing(screen.root_scene) && return nothing
    if gv[Bool]
        Gtk4.make_current(g)
        if isnothing(g.inspector)
            g.inspector = DataInspector()
        end
        Makie.enable!(g.inspector)
    else
        isnothing(g.inspector) || Makie.disable!(g.inspector)
    end
    nothing
end

function figure_cb(ptr::Ptr,par,screen)
    g = glarea(screen)
    isnothing(g.figure) && return nothing
    @idle_add attributes_window(g.figure)
    nothing
end

function close_cb(::Ptr,par,screen)
    win=window(screen)
    @idle_add Gtk4.destroy(win)
    nothing
end

function save_cb(::Ptr,par,screen)
    isnothing(screen.root_scene) && return nothing
    dlg = GtkFileDialog()
    function file_save_cb(dlg, resobj)
        try
            gfile = Gtk4.G_.save_finish(dlg, Gtk4.GLib.GAsyncResult(resobj))
            filepath=Gtk4.GLib.path(Gtk4.GLib.GFile(gfile))
            if endswith(filepath,".png") || endswith(filepath,".jpg")
                img = colorbuffer(screen)
                fo = endswith(filepath,".png") ? FileIO.format"PNG" : FileIO.format"JPEG"
                open(filepath, "w") do io
                    FileIO.save(FileIO.Stream{fo}(Makie.raw_io(io)), img)
                end
            elseif endswith(filepath,".pdf") || endswith(filepath,".svg")
                ext = Base.get_extension(Gtk4Makie, :Gtk4MakieCairoMakieExt)
                if !isnothing(ext)
                    ext.savecairo(filepath, screen.root_scene)
                else
                    info_dialog("Can't save to PDF or SVG, CairoMakie module not found.", window(screen)) do
                    end
                end
            else
                info_dialog("File extension not supported.", window(screen)) do
                end
            end
        catch e
            error_dialog("Failed to save: $e") do
            end
        end
        return nothing
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
    add_action(m,"figure",figure_cb,screen)
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
    add_shortcut(sc,Sys.isapple() ? "<Meta>I" : "<Control>I", "win.inspector")
end

mutable struct ScreenConfig
    title::String
    fullscreen::Bool
end

const Screen = GLMakie.Screen

function Screen(scene, config, args...)
    GTKScreen()
end

const menuxml = """
<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <menu id="screen_menu">
    <section>
      <item>
        <attribute name="label">Fullscreen</attribute>
        <attribute name="action">win.fullscreen</attribute>
      </item>
      <item>
        <attribute name="label">Save</attribute>
        <attribute name="action">win.save</attribute>
      </item>
      <item>
        <attribute name="label">Inspector</attribute>
        <attribute name="action">win.inspector</attribute>
      </item>
      <item>
        <attribute name="label">Axes and plots</attribute>
        <attribute name="action">win.figure</attribute>
      </item>
    </section>
  </menu>
</interface>
"""

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
            menu_button = GtkMenuButton(;icon_name="open-menu-symbolic")
            b = GtkBuilder(menuxml, -1)
            menu = b["screen_menu"]
            Gtk4.G_.set_menu_model(menu_button, menu)
            push!(hb, menu_button)
            save_button = GtkButton("Save"; action_name = "win.save")
            push!(hb,save_button)
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

    Gtk4.on_realize(realizecb, glarea)
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

    Gtk4.on_render(refreshwindowcb, glarea)
    
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

"""
    Gtk4Makie.activate!(; screen_config...)

Sets Gtk4Makie as the currently active backend and also optionally modifies the screen configuration using `screen_config` keyword arguments.
"""
function activate!(; screen_config...)
    if haskey(screen_config, :pause_rendering)
        error("pause_rendering got renamed to pause_renderloop.")
    end
    Makie.inline!(false)
    #Makie.set_screen_config!(Gtk4Makie, screen_config)
    Makie.set_active_backend!(Gtk4Makie)
    return
end
