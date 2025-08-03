# Windows with one GLMakie plot inside (like GLMakie's GLFW windows)

## Makie overloads

function GLMakie.was_destroyed(nw::GtkWindow)
    Gtk4.G_.in_destruction(nw)
end
Base.isopen(win::GtkWindow) = Gtk4.visible(win)

function GLMakie.apply_config!(screen::GLMakie.Screen{T},config::GLMakie.ScreenConfig; start_renderloop=true) where T <: GtkWindow
    # TODO: figure out what to do with "focus_on_show" and "float"
    glw = screen.glscreen
    Gtk4.decorated(glw, config.decorated)
    Gtk4.title(glw,config.title)
    config.fullscreen && Gtk4.fullscreen(glw)

    if !isnothing(config.monitor)
        # TODO: set monitor where this window appears?
    end

    return _apply_config!(screen, config, start_renderloop)
end

GLMakie.destroy!(nw::GtkWindow) = nothing

GLMakie.GLAbstraction.require_context(ctx::GtkGLMakie, current::GtkWindowLeaf) = nothing
GLMakie.GLAbstraction.require_context(ctx::GtkGLMakie, current::GtkApplicationWindowLeaf) = nothing
GLMakie.GLAbstraction.require_context(ctx::GtkWindowLeaf, current::GtkGLMakie) = nothing
GLMakie.GLAbstraction.require_context(ctx::GtkApplicationWindowLeaf, current::GtkGLMakie) = nothing

GLMakie.framebuffer_size(w::GtkWindow) = GLMakie.framebuffer_size(win2glarea[w])

function ShaderAbstractions.native_switch_context!(w::GtkWindow)
    if haskey(win2glarea, w)
        ShaderAbstractions.native_switch_context!(win2glarea[w])
    else
        @debug("Unable to find GtkGLArea in native_switch_context!")
    end
end
function ShaderAbstractions.native_context_alive(x::GtkWindow)
    return !was_destroyed(x)
end

## Gtk4Makie overloads

const win2glarea = Dict{GtkWindow, GtkGLMakie}()

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

##

"""
    grid(screen::GLMakie.Screen{T}) where T <: GtkWindow

For a Gtk4Makie screen, get the GtkGrid containing the GtkGLArea where Makie draws. Other
widgets can be added to this grid.
"""
function grid(screen::GLMakie.Screen{T}) where T <: GtkWindow
    g = screen.glscreen[]
    g === nothing && error("No grid found for screen")
    g
end

function menubutton(screen::GLMakie.Screen{T}) where T <: GtkWindow
    win=screen.glscreen
    hb = Gtk4.titlebar(win)
    hb === nothing && error("No headerbar found")
    wh=first(hb)::GtkWindowHandleLeaf
    cb=first(wh)::GtkCenterBoxLeaf
    first(cb[:end])::GtkMenuButtonLeaf
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
    isnothing(screen.scene) && return nothing
    if gv[Bool]
        Gtk4.make_current(g)
        if isnothing(g.inspector) && !isnothing(g.figure)
            g.inspector = DataInspector(g.figure)
        end
        isnothing(g.inspector) || Makie.enable!(g.inspector)
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
    @idle_add Gtk4.visible(win, false)
    nothing
end

function closeall_cb(::Ptr,par,user_data)
    @idle_add GLMakie.closeall()
    nothing
end

function save_cb(::Ptr,par,screen)
    isnothing(screen.scene) && return nothing
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
                    ext.savecairo(filepath, screen.scene)
                else
                    info_dialog("Can't save to PDF or SVG, CairoMakie module not found.", window(screen)) do
                    end
                end
            else
                info_dialog("File extension not supported.", window(screen)) do
                end
            end
        catch e
            if !isa(e, Gtk4.GLib.GErrorException)
                error_dialog("Failed to save: $e", window(screen)) do
                end
            end
        end
        return nothing
    end
    dlg = GtkFileDialog()
    Gtk4.G_.save(dlg, window(screen), nothing, file_save_cb)
    nothing
end

function copy_cb(::Ptr,par,screen)
    isnothing(screen.scene) && return nothing
    # There must be a way of doing this without creating a temp file, but this works
    temppath, tempio = mktemp()
    img = colorbuffer(screen)
    fo = FileIO.format"PNG"
    FileIO.save(FileIO.Stream{fo}(Makie.raw_io(tempio)), img)
    close(tempio)
    arr = read(temppath)
    rm(temppath)
    b=Gtk4.GLib.GBytes(arr)
    cp = GdkContentProvider("image/png", b)
    c = Gtk4.clipboard(GdkDisplay())
    Gtk4.content(c, cp)
    nothing
end

function shortcuts_cb(::Ptr,par,nothing)
    b=GtkBuilder(joinpath(@__DIR__, "shortcuts-window.ui"))
    w=b["shortcuts"]
    show(w)
    nothing
end

function add_window_actions(ag,screen)
    m = Gtk4.GLib.GActionMap(ag)
    @static if @load_preference("backend", "GLMakie") == "GLMakie"  # these actions don't currently work with the Gtk4Makie backend
        add_action(m,"save",save_cb,screen)
        add_action(m,"copy",copy_cb,screen)
        add_stateful_action(m,"inspector",false,inspector_cb,screen)
        Sys.isapple() || add_action(m,"shortcuts",shortcuts_cb,nothing)  # throw this in here since many of the shortcuts don't work
    end
    add_action(m,"close",close_cb,screen)
    add_action(m,"closeall",closeall_cb,nothing)
    add_action(m,"fullscreen",fullscreen_cb,screen)
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
    add_shortcut(sc,Sys.isapple() ? "<Meta><Shift>W" : "<Control><Shift>W", "win.closeall")
    add_shortcut(sc,Sys.isapple() ? "<Meta><Shift>F" : "F11", "win.fullscreen")
    add_shortcut(sc,Sys.isapple() ? "<Meta>I" : "<Control>I", "win.inspector")
end

const shortcuts_ui = @static if !Sys.isapple() && @load_preference("backend", "GLMakie") == "GLMakie"
    """
     <item>
        <attribute name="label">Keyboard shortcuts</attribute>
        <attribute name="action">win.shortcuts</attribute>
     </item>
    """
else
    ""
end

const menu_glmakie_xml = if @load_preference("backend", "GLMakie") == "GLMakie"
    """
    <item>
        <attribute name="label">Save</attribute>
        <attribute name="action">win.save</attribute>
      </item>
      <item>
        <attribute name="label">Copy to clipboard</attribute>
        <attribute name="action">win.copy</attribute>
      </item>
      <item>
        <attribute name="label">Inspector</attribute>
        <attribute name="action">win.inspector</attribute>
      </item>
    """
else
    ""
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
      $(menu_glmakie_xml)
      <item>  <!-- Experimental! -->
        <attribute name="label">Axes and plots</attribute>
        <attribute name="action">win.figure</attribute>
      </item>
      $(shortcuts_ui)
    </section>
  </menu>
</interface>
"""

function _create_window(headerbar, size, app, config)
    try
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
            menu = b["screen_menu"]::Gtk4.GLib.GMenuLeaf
            Gtk4.G_.set_menu_model(menu_button, menu)
            push!(hb, menu_button)
        end
        add_window_shortcuts(w)
        isnothing(size) || Gtk4.default_size(w, size[1], size[2])
        config.fullscreen && Gtk4.fullscreen(w)
        config.visible && show(w)
        return w
    catch e
        @warn("""
            Gtk4Makie couldn't create a window.
        """)
        rethrow(e)
    end
end

function _create_area_and_grid()
    a = GtkGLMakie()
    grid = GtkGrid()
    Gtk4.on_realize(realizecb, a)
    grid[1,1] = a
    a, grid
end

const default_use_headerbar = Sys.isapple() ? false : true

"""
    GTKScreen(headerbar=true;
              size = (200, 200),
              app = nothing,
              screen_config...)

Create a Gtk4Makie window screen. If `headerbar` is `true`, the window will include a
header bar with a menu button. The keyword argument `size` can be used to set the initial
size of the window (which may be adjusted by Makie later). A GtkApplication instance can be
passed using the keyword argument `app`. If this is done, a GtkApplicationWindow will be
created rather than the default GtkWindow.

Supported `screen_config` arguments and their default values are:
* `title::String = "Makie"`: Sets the window title.
* `fullscreen = false`: Whether or not the window should be fullscreened when first created.
"""
function GTKScreen(headerbar=default_use_headerbar;
                   size::Union{Nothing, Tuple{Int, Int}} = nothing,
                   resolution::Union{Nothing, Tuple{Int, Int}} = nothing,
                   app = nothing,
                   screen_config...
    )
    config = Makie.merge_screen_config(GLMakie.ScreenConfig, Dict{Symbol, Any}(screen_config))
    window = _create_window(headerbar, size, app, config)

    a, grid = _create_area_and_grid()
    window[] = grid
    
    s = if !isnothing(resolution) && isnothing(size)
        resolution
    else
        isnothing(size) ? (10,10) : size
    end
    screen = _create_screen(a, window, config, s)
    win2glarea[window] = a
    GLMakie.apply_config!(screen, config)

    if isnothing(app)
        ag = Gtk4.GLib.GSimpleActionGroup()
        add_window_actions(ag,screen)
        push!(window, Gtk4.GLib.GActionGroup(ag), "win")
    else
        add_window_actions(Gtk4.GLib.GActionGroup(window),screen)
    end

    a.render_id = Gtk4.on_render(refreshwidgetcb, a)

    if !isnothing(size) || !isnothing(resolution)
        resize!(screen, s...)
    end

    _add_timeout(screen, a, window)

    return screen
end

