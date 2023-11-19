# 

const WindowType = Union{Gtk4.GtkWindowLeaf, Gtk4.GtkApplicationWindowLeaf}

const win2glarea = Dict{WindowType, GtkGLMakie}()

function Base.resize!(screen::Screen{T}, w::Int, h::Int) where T <: WindowType
    window = GLMakie.to_native(screen)
    (w > 0 && h > 0 && isopen(window)) || return nothing
    
    ShaderAbstractions.switch_context!(window)
    winscale = screen.scalefactor[] / Gtk4.scale_factor(window)
    winw, winh = round.(Int, winscale .* (w, h))
    if size(window) != (winw, winh)
        Gtk4.default_size(window, winw, winh)
    end

    # Then resize the underlying rendering framebuffers as well, which can be scaled
    # independently of the window scale factor.
    fbscale = screen.px_per_unit[]
    fbw, fbh = round.(Int, fbscale .* (w, h))
    resize!(screen.framebuffer, fbw, fbh)
    return nothing
end

"""
    grid(screen::GLMakie.Screen{T}) where T <: GtkWindow

For a Gtk4Makie screen, get the GtkGrid containing the GtkGLArea where Makie draws. Other widgets can be added to this grid.
"""
grid(screen::GLMakie.Screen{T}) where T <: GtkWindow = screen.glscreen[]

GLMakie.framebuffer_size(w::WindowType) = GLMakie.framebuffer_size(win2glarea[w])
GLMakie.window_size(w::GtkWindow) = size(w)
GLMakie.to_native(w::WindowType) = win2glarea[w]

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
    return _apply_config!(screen, config, start_renderloop)
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
    _close(screen, reuse)
    return
end

GLMakie.pollevents(::GLMakie.Screen{T}) where T <: GtkWindow = nothing

ShaderAbstractions.native_switch_context!(a::WindowType) = ShaderAbstractions.native_switch_context!(win2glarea[a])

ShaderAbstractions.native_context_alive(x::WindowType) = !GLMakie.was_destroyed(x)

function GLMakie.destroy!(nw::WindowType)
    was_current = ShaderAbstractions.is_current_context(nw)
    if !GLMakie.was_destroyed(nw)
        close(nw)
    end
    was_current && ShaderAbstractions.switch_context!()
end

# overload this to get access to the figure
function Base.display(screen::GLMakie.Screen{T}, figesque::Union{Makie.Figure,Makie.FigureAxisPlot}; update=true, display_attributes...) where T <: GtkWindow
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

