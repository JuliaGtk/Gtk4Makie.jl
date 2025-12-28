function control(o::Observable{T}) where T <: Any
    # things like `title` use Observable[Any] and GtkObservables doesn't work well for this currently
    #if typeof(o[]) == String
    #    return widget(textbox(Any; value = o[], observable = o))
    #end
    s = repr(o[])
    if length(s) <= 50
        GtkLabel(s)  # TODO: use ellipsize? ellipsize=Gtk4.Pango.EllipsizeMode_MIDDLE)
    else
        GtkLabel("too long to show")
    end
end

function control(o::ComputePipeline.Computed, label="")
    if isa(o.parent, ComputePipeline.Input)
        if isa(o.value, Ref{Bool})
            return CheckButton(o, label)
        elseif isa(o.value, Ref{String})
            return TextBox(o, String)
        elseif isa(o.value, Ref{Float64})
            return TextBox(o, Float64)
        elseif isa(o.value, Ref{Float32})
            return TextBox(o, Float32)
        elseif isa(o.value, Ref{RGBA{Float32}})
            return ColorButton(o, RGBA{Float32})
        end
    end
    GtkLabel("type unknown or unsupported")
end

function control(o::Observable{T},label="") where T <: Bool
    CheckButton(o, label)
end

# we need to send in a range to use a spinbutton, so use a textbox

function control(o::Observable{T}) where T <: Number
    TextBox(o,T)
end

function alignmode_dropdown(o)
    dd = GtkDropDown(["Inside","Outside","Mixed"])
    on(o;update=true) do val
        if val == Inside()
            @idle_add Gtk4.G_.set_selected(dd,0)
        elseif val == Outside()
            @idle_add Gtk4.G_.set_selected(dd,1)
        elseif val == Mixed()
            @idle_add Gtk4.G_.set_selected(dd,2)
        end
    end
    signal_connect(dd,"notify::selected-item") do dd, pspec
        s = Gtk4.G_.get_selected(dd)
        if s == 0
            @idle_add o[] = Inside()
        elseif s == 1
            @idle_add o[] = Outside()
        elseif s == 2
            @idle_add o[] = Mixed()
        end
    end
    dd
end

# could use a row of togglebutton icons for this
function align_dropdown(o)
    dd = GtkDropDown(["left","center","right"])
    on(o; update=true) do val	
        if val === :left
            @idle_add Gtk4.G_.set_selected(dd,0)
        elseif val === :center
            @idle_add Gtk4.G_.set_selected(dd,1)
        elseif val === :right
            @idle_add Gtk4.G_.set_selected(dd,2)
        end
    end
    signal_connect(dd,"notify::selected-item") do dd, pspec
        s = Gtk4.G_.get_selected(dd)
        if s == 0
            @idle_add o[] = :left
        elseif s == 1
            @idle_add o[] = :center
        elseif s == 2
            @idle_add o[] = :right
        end
    end
    dd
end

function xaxisposition_dropdown(o)
    dd = GtkDropDown(["bottom","top"])
    on(o; update=true) do val
        if val === :bottom
            @idle_add Gtk4.G_.set_selected(dd,0)
        elseif val === :top
            @idle_add Gtk4.G_.set_selected(dd,1)
        end
    end
    signal_connect(dd,"notify::selected-item") do dd, pspec
        s = Gtk4.G_.get_selected(dd)
        if s == 0
            @idle_add o[] = :bottom
        elseif s == 1
            @idle_add o[] = :top
        end
    end
    dd
end

function yaxisposition_dropdown(o)
    dd = GtkDropDown(["left","right"])
    on(o; update=true) do val
        if val === :left
            @idle_add Gtk4.G_.set_selected(dd,0)
        elseif val === :right
            @idle_add Gtk4.G_.set_selected(dd,1)
        end
    end
    signal_connect(dd,"notify::selected-item") do dd, pspec
        s = Gtk4.G_.get_selected(dd)
        if s == 0
            @idle_add o[] = :left
        elseif s == 1
            @idle_add o[] = :right
        end
    end
    dd
end



# currently GtkObservable's colorbutton does not support RGBA, only RGB

#function control(o::Observable{T}) where T <: RGBA
#    widget(colorbutton(; observable=o))
#end

_setup_attr_cb(f, li) = set_child(li,GtkLabel(""))

function _bind_attr_cb(f, li)
    text = li[].string
    label = get_child(li)
    label.label = text
end

function _setup_con_cb(f, li)
    b=GtkCenterBox(:h)
    b[:center] = GtkLabel("type unsupported")
    set_child(li,b)
    nothing
end

_get_children(x,d,k) = nothing

function _get_children(g::GridLayout,d,i)
    sl=GtkStringList()
    for (j,c) in enumerate(contents(g))
        d["$i,$j"]=c
        push!(sl,"$i,$j")
    end
    sl
end

function _get_children(a::Union{Axis,Axis3,PolarAxis},d,i)
    sl=GtkStringList()
    for (j,c) in enumerate(plots(a))
        d["$i,$j"]=c
        push!(sl,"$i,$j")
    end
    sl
end

# output a GtkTreeListModel for a figure
function figure_tree_model(f)
    d=Dict{String,Any}()
    for (i,c) in enumerate(contents(f.layout))
        d[string(i)]=c
    end
    rootmodel=GtkStringList(collect(keys(d)))
    
    function create_model(pp)
        k=pp.string::String
        return _get_children(d[k],d,k)
    end
    
    GtkTreeListModel(Gtk4.GLib.GListModel(rootmodel),false, true, create_model),d
end

function _setup_axis_cb(f, li)
    tree_expander = GtkTreeExpander()
    set_child(tree_expander,GtkLabel(""))
    set_child(li,tree_expander)
end

function abbr_name(t)
    if occursin("{",t)
        return split(t,"{")[1]
    end
    return t
end

function axis_list(f)
    tlm,d = figure_tree_model(f)
    
    function bind_axis_cb(f, li)
        row = li[]
        tree_expander = get_child(li)
        Gtk4.set_list_row(tree_expander, row)
        text = Gtk4.get_item(row).string
        label = get_child(tree_expander)
        tname=repr(d[text])
        fulllabel = abbr_name(tname)
        if hasproperty(d[text],:label)
            fulllabel = fulllabel*": $(d[text].label[])"
        end
        label.label = fulllabel
        Gtk4.tooltip_text(label,tname)
    end
    
    factory = GtkSignalListItemFactory(_setup_axis_cb, bind_axis_cb)
    single_sel = GtkSingleSelection(Gtk4.GLib.GListModel(tlm))
    lb = GtkListView(GtkSelectionModel(single_sel), factory; vexpand=true)
    
    @idle_add signal_emit(single_sel, "selection-changed", Nothing, Cuint(0), Cuint(1))

    lb,d,tlm
end

# TODO:
# add more specialized controls that depend on the type of plot/axis/whatever
# for Heatmap, colormap, colorscale and clipping, 
# for Scatter, colormap, marker
# for Colorbar, colorrange
# for GridLayout, alignment and width

# we highlight the selected axis by changing the background color
# FIXME: this doesn't work for axes with heatmaps, probably other types too
# FIXME: we should allow multiple axis windows at once - remove these globals

const selected_axis = Ref{Any}(nothing)
prev_color = colorant"white"

function change_selected(thing)
    if selected_axis[] !== nothing
        selected_axis[].backgroundcolor[]=prev_color
    end
    if isa(thing, Axis)
        global prev_color = thing.backgroundcolor[]
        thing.backgroundcolor[] = colorant"lightblue"
        selected_axis[]=thing
    else
        selected_axis[]=nothing
    end
end

function on_axis_window_close_request(win)
    change_selected(nothing)
end

function fill_attributes!(attrlv,thing)
    # populate attrlv with attributes
    attrs = Symbol[]
    for p in sort(collect(propertynames(thing)))
        isa(getproperty(thing,p), Observable) && push!(attrs,p)
        isa(getproperty(thing,p), ComputePipeline.Computed) && push!(attrs,p)
    end
        
    sl = GtkStringList(string.(attrs))
    @idle_add Gtk4.model(attrlv, GtkSelectionModel(GtkNoSelection(Gtk4.GLib.GListModel(sl))))
end

function _add_labeled_widget(g,c,r,label,w)
    g[c,r] = GtkLabel(label)
    g[c+1,r] = w
end

function axis_title_settings(ax)
    g=GtkGrid(;margin_start=5)
    _add_labeled_widget(g,1,1,"title",TextBox(ax.title))
    _add_labeled_widget(g,3,1,"subtitle",TextBox(ax.subtitle))
    g[1,2] = ColorButton(ax.titlecolor)
    g[2,2] = control(ax.titlevisible, "visible")
    g[3,2] = ColorButton(ax.subtitlecolor)
    g[4,2] = control(ax.subtitlevisible, "visible")
    _add_labeled_widget(g,1,3,"size",control(ax.titlesize))
    _add_labeled_widget(g,3,3,"size",control(ax.subtitlesize))
    _add_labeled_widget(g,1,4,"gap",control(ax.titlegap))
    _add_labeled_widget(g,3,4,"gap",control(ax.subtitlegap))
    _add_labeled_widget(g,1,5,"align",align_dropdown(ax.titlealign))
    g
end

function axis_label_settings(ax)
    g=GtkGrid(;margin_start=5)
    _add_labeled_widget(g,1,1,"X label",TextBox(ax.xlabel))
    _add_labeled_widget(g,3,1,"Y label",TextBox(ax.ylabel))
    g[1,2] = ColorButton(ax.ylabelcolor)
    g[2,2] = control(ax.xlabelvisible, "visible")
    g[3,2] = ColorButton(ax.xlabelcolor)
    g[4,2] = control(ax.ylabelvisible, "visible")
    _add_labeled_widget(g,1,3,"size",control(ax.xlabelsize))
    _add_labeled_widget(g,3,3,"size",control(ax.ylabelsize))
    _add_labeled_widget(g,1,4,"padding",control(ax.xlabelpadding))
    _add_labeled_widget(g,3,4,"padding",control(ax.ylabelpadding))
    g[3:4,5] = control(ax.flip_ylabel, "flip_ylabel")
    g
end

function axis_grid_settings(ax)
    g=GtkGrid(;margin_start=5)
    g[1:2,1] = GtkLabel("X grid")
    g[1,2] = ColorButton(ax.xgridcolor)
    g[2,2] = control(ax.xgridvisible, "visible")
    g[3:4,1] = GtkLabel("Y grid")
    g[3,2] = ColorButton(ax.ygridcolor)
    g[4,2] = control(ax.ygridvisible, "visible")
    _add_labeled_widget(g,1,3,"width",control(ax.xgridwidth))
    _add_labeled_widget(g,3,3,"width",control(ax.ygridwidth))
    g[1,4] = ColorButton(ax.leftspinecolor)
    g[2,4] = control(ax.leftspinevisible, "left spine visible")
    g[1,5] = ColorButton(ax.rightspinecolor)
    g[2,5] = control(ax.rightspinevisible, "right spine visible")
    g[3,4] = ColorButton(ax.topspinecolor)
    g[4,4] = control(ax.topspinevisible, "top spine visible")
    g[3,5] = ColorButton(ax.bottomspinecolor)
    g[4,5] = control(ax.bottomspinevisible, "bottom spine visible")
    g[1:2,6] = GtkLabel("spine width")
    g[3:4,6] = control(ax.spinewidth)
    g
end

function axis_ticks_settings(ax)
    g=GtkGrid(;margin_start=5)
    g[1:2,1] = GtkLabel("X ticks")
    g[1,2] = ColorButton(ax.xtickcolor)
    g[2,2] = control(ax.xticksvisible, "visible")
    g[3:4,1] = GtkLabel("Y ticks")
    g[3,2] = ColorButton(ax.ytickcolor)
    g[4,2] = control(ax.yticksvisible, "visible")
    _add_labeled_widget(g,1,3,"width",control(ax.xtickwidth))
    _add_labeled_widget(g,3,3,"width",control(ax.ytickwidth))
    _add_labeled_widget(g,1,4,"size",control(ax.xticksize))
    _add_labeled_widget(g,3,4,"size",control(ax.yticksize))
    g[1:2,5] = control(ax.xticksmirrored,"mirrored")
    g[3:4,5] = control(ax.yticksmirrored,"mirrored")
    _add_labeled_widget(g,1,6,"label size",control(ax.xticklabelsize))
    _add_labeled_widget(g,3,6,"label size",control(ax.yticklabelsize))
    _add_labeled_widget(g,1,7,"label pad",control(ax.xticklabelpad))
    _add_labeled_widget(g,3,7,"label pad",control(ax.yticklabelpad))
    _add_labeled_widget(g,1,8,"label rotation",control(ax.xticklabelrotation))
    _add_labeled_widget(g,3,8,"label rotation",control(ax.yticklabelrotation))
    g
end

function colorbar_label_and_ticks_settings(cb)
    g=GtkGrid(;margin_start=5)
    _add_labeled_widget(g,1,1,"label",TextBox(cb.label))
    g[1,2] = ColorButton(cb.labelcolor, Any)
    g[2,2] = CheckButton(cb.labelvisible, "visible")
    _add_labeled_widget(g,1,3,"size",TextBox(cb.labelsize,Int))
    _add_labeled_widget(g,1,4,"padding",TextBox(cb.labelpadding,Float32))
    g[1:2,5] = CheckButton(cb.flip_vertical_label, "flip vertical label")

    g[3:4,1] = GtkLabel("Ticks")
    g[3,2] = ColorButton(cb.tickcolor)
    g[4,2] = CheckButton(cb.ticksvisible, "visible")
    _add_labeled_widget(g,3,3,"width",TextBox(cb.tickwidth,Float32))
    _add_labeled_widget(g,3,4,"size",TextBox(cb.ticksize,Float32))
    _add_labeled_widget(g,3,5,"label size",TextBox(cb.ticklabelsize, Int))
    _add_labeled_widget(g,3,6,"label pad",TextBox(cb.ticklabelpad, Float32))
    _add_labeled_widget(g,3,7,"label rotation",TextBox(cb.ticklabelrotation, Float32))
    g
end

function colorbar_size_range_and_clip_settings(cb)
    g=GtkGrid(;margin_start=5)
    _add_labeled_widget(g,1,1,"Size",TextBox(cb.size, Int))
    _add_labeled_widget(g,1,2,"Number of steps", TextBox(cb.nsteps, Int))
    g
end

function heatmap_settings(hm)
    g=GtkGrid(;margin_start=5)
    g[1,1] = CheckButton(hm.interpolate, "interpolate")
    g
end

const _linestyles=string.([:solid, :dash, :dot, :dashdot, :dashdotdot])

# setting linestyle observable is broken
# https://github.com/MakieOrg/Makie.jl/issues/803
# https://github.com/MakieOrg/Makie.jl/issues/3693
function linestyle_dropdown(o)
    dd = GtkDropDown(_linestyles)
    on(o;update=true) do val
        i=findfirst(==(string(val)),_linestyles)
        if i!==nothing
            @idle_add Gtk4.selected!(dd,i)
        end
    end
    signal_connect(dd,"notify::selected-item") do dd, pspec
        ss = Gtk4.selected(dd)
        @idle_add o[] = Symbol(_linestyles[ss])
    end
    dd
end

function marker_dropdown(o)
    s=string.(keys(Makie.default_marker_map()))
    dd = GtkDropDown(s)
    on(o;update=true) do val
        i=findfirst(==(string(val)),s)
        if i!==nothing
            @idle_add Gtk4.selected!(dd,i)
        end
    end
    signal_connect(dd,"notify::selected-item") do dd, pspec
        ss = Gtk4.selected(dd)
        @idle_add o[] = Symbol(s[ss])
    end
    dd
end

function scatter_settings(sc)
    g=GtkGrid(;margin_start=5)
    g[1,1] = CheckButton(sc.visible, "visible")
    _add_labeled_widget(g,1,2,"stroke width", TextBox(sc.strokewidth, Int))
    _add_labeled_widget(g,1,3,"marker size", TextBox(sc.markersize, Int))
    _add_labeled_widget(g,1,4,"marker", marker_dropdown(sc.marker))
    _add_labeled_widget(g,1,5,"color", ColorButton(sc.color))
    g
end

function lines_settings(li)
    g=GtkGrid(;margin_start=5)
    g[1,1] = CheckButton(li.visible, "visible")
    _add_labeled_widget(g,1,2,"line width", TextBox(li.linewidth, Float64))
    _add_labeled_widget(g,1,3,"line color", ColorButton(li.color,Any))
    g
end

push_to_stack(st, thing) = nothing
function push_to_stack(st::GtkStack, thing::Axis)
    push!(st, axis_title_settings(thing), "axis_title", "Title")
    push!(st, axis_label_settings(thing), "axis_labels", "Axis labels")
    push!(st, axis_ticks_settings(thing), "axis_ticks", "Ticks")
    push!(st, axis_grid_settings(thing), "axis_grid", "Grid & spine")
end

function push_to_stack(st::GtkStack, thing::Colorbar)
    push!(st, colorbar_label_and_ticks_settings(thing), "colorbar_axis", "Axis and Ticks")
    push!(st, colorbar_size_range_and_clip_settings(thing), "colorbar_size", "Size, etc.")
end

function push_to_stack(st::GtkStack, thing::Heatmap)
    push!(st, heatmap_settings(thing), "heatmap", "Heatmap")
end

function push_to_stack(st::GtkStack, thing::Scatter)
    push!(st, scatter_settings(thing), "scatter", "Scatter")
end

function push_to_stack(st::GtkStack, thing::Lines)
    push!(st, lines_settings(thing), "lines", "Lines")
end

# Window for controlling attributes of Axes and children
function attributes_window(f=current_figure())
    win = GtkWindow("Axes and Plots (experimental)", 900, 500)
    
    # close if figure screen closes
    q=findfirst(s->glarea(s).figure == f, screens)
    if q !== nothing
        screen_window = window(screens[q])
        signal_connect(screen_window,"close-request") do w
            destroy(win)
            return false
        end
    end
        
    sw = GtkScrolledWindow()
    lb,d,sl_axes = axis_list(f)
    sw[]=lb
    
    paned = GtkPaned(:h; position=200)
    paned[1] = sw
    
    attr_factory = GtkSignalListItemFactory(_setup_attr_cb, _bind_attr_cb)
    attrlv = GtkColumnView(;vexpand=true)
    attcol = GtkColumnViewColumn("Attribute", attr_factory)
    concol = GtkColumnViewColumn("Value", nothing)
    
    Gtk4.G_.append_column(attrlv,attcol)
    Gtk4.G_.append_column(attrlv,concol)
    
    sm = Gtk4.model(lb)
    
    stackbox = GtkBox(:v)
    st = GtkStack()
    switcher = GtkStackSwitcher()
    Gtk4.G_.set_stack(switcher, st)
    push!(stackbox,switcher)
    push!(stackbox,st)
    paned[2] = stackbox
    
    attrsw = GtkScrolledWindow()
    attrsw[] = attrlv
    
    signal_connect(sm,"selection-changed") do sel, position, n_items
        position = Gtk4.G_.get_selected(sel)
        row = Gtk4.G_.get_row(sl_axes,position)
        row!==nothing || return
        p = Gtk4.get_item(row).string
        thing = d[p]
        
        change_selected(thing)
        
        fill_attributes!(attrlv,thing)
        
        function bind_con_cb(f, li)
            text = li[].string
            box = get_child(li)
            name = Symbol(text)
            try
            if name === :alignmode
                box[:center] = alignmode_dropdown(getproperty(thing,name))
            else
                box[:center] = control(getproperty(thing,name))
            end
            catch e
            end
            nothing
        end
        control_factory = GtkSignalListItemFactory(_setup_con_cb, bind_con_cb)
        @idle_add begin
            Gtk4.factory(concol, control_factory)
            empty!(st)
            push_to_stack(st, thing)
            push!(st, attrsw, "attr", "All")
            Cint(0)
        end
    end
    
    win[]=paned
    
    signal_connect(on_axis_window_close_request, win, "close-request")
    
    win
end

