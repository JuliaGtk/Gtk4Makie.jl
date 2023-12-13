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
            @idle_add Gtk4.G_.set_selected(dd,2)
        end
    end
    signal_connect(dd,"notify::selected-item") do dd, pspec
        s = Gtk4.G_.get_selected(dd)
        if s == 0
            @idle_add o[] = :bottom
        elseif s == 2
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
            @idle_add Gtk4.G_.set_selected(dd,2)
        end
    end
    signal_connect(dd,"notify::selected-item") do dd, pspec
        s = Gtk4.G_.get_selected(dd)
        if s == 0
            @idle_add o[] = :left
        elseif s == 2
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

function axis_list(f)
    tlm,d = figure_tree_model(f)
    
    function bind_axis_cb(f, li)
        row = li[]
        tree_expander = get_child(li)
        Gtk4.set_list_row(tree_expander, row)
        text = Gtk4.get_item(row).string
        label = get_child(tree_expander)
        label.label = repr(d[text])
    end
    
    factory = GtkSignalListItemFactory(_setup_axis_cb, bind_axis_cb)
    lb = GtkListView(GtkSelectionModel(GtkSingleSelection(Gtk4.GLib.GListModel(tlm))), factory; vexpand=true)

    lb,d,tlm
end

# TODO:
# add more specialized controls that depend on the type of plot/axis/whatever
# for Heatmap, colormap, colorscale and clipping, 
# for Scatter, color, colormap, marker, visible
# for Colorbar, ticks, label, colorrange
# for GridLayout, alignment and width

# we highlight the selected axis by changing the background color
# FIXME: this doesn't work for axes with heatmaps, probably other types too
# FIXME: we should allow multiple axis windows at once - remove these globals

selected_axis = Ref{Any}(nothing)
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
    end
        
    sl = GtkStringList(string.(attrs))
    @idle_add Gtk4.model(attrlv, GtkSelectionModel(GtkNoSelection(Gtk4.GLib.GListModel(sl))))
end

function axis_title_settings(ax)
    g=GtkGrid()
    g[1,1] = GtkLabel("title")
    g[2,1] = TextBox(ax.title)
    g[3,1] = GtkLabel("subtitle")
    g[4,1] = TextBox(ax.subtitle)
    g[1:2,2] = control(ax.titlevisible, "visible")
    g[3:4,2] = control(ax.subtitlevisible, "visible")
    g[1,3] = GtkLabel("size")
    g[2,3] = control(ax.titlesize)
    g[3,3] = GtkLabel("size")
    g[4,3] = control(ax.subtitlesize)
    g[1,4] = GtkLabel("gap")
    g[2,4] = control(ax.titlegap)
    g[3,4] = GtkLabel("gap")
    g[4,4] = control(ax.subtitlegap)
    g[1,5] = GtkLabel("align")
    g[2,5] = align_dropdown(ax.titlealign)
    g
end

function axis_label_settings(ax)
    g=GtkGrid()
    g[1,1] = GtkLabel("X label")
    g[2,1] = TextBox(ax.xlabel)
    g[3,1] = GtkLabel("Y label")
    g[4,1] = TextBox(ax.ylabel)
    g[1:2,2] = control(ax.xlabelvisible, "visible")
    g[3:4,2] = control(ax.ylabelvisible, "visible")
    g[1,3] = GtkLabel("size")
    g[2,3] = control(ax.xlabelsize)
    g[3,3] = GtkLabel("size")
    g[4,3] = control(ax.ylabelsize)
    g[1,4] = GtkLabel("padding")
    g[2,4] = control(ax.xlabelpadding)
    g[3,4] = GtkLabel("padding")
    g[4,4] = control(ax.ylabelpadding)
    g[3:4,5] = control(ax.flip_ylabel, "flip_ylabel")
    g
end

function axis_grid_settings(ax)
    g=GtkGrid()
    g[1:2,1] = GtkLabel("X grid")
    g[1:2,2] = control(ax.xgridvisible, "visible")
    g[3:4,1] = GtkLabel("Y grid")
    g[3:4,2] = control(ax.ygridvisible, "visible")
    g[1,3] = GtkLabel("width")
    g[2,3] = control(ax.xgridwidth)
    g[3,3] = GtkLabel("width")
    g[4,3] = control(ax.ygridwidth)
    g[1:2,4] = control(ax.leftspinevisible, "left spine visible")
    g[1:2,5] = control(ax.rightspinevisible, "right spine visible")
    g[3:4,4] = control(ax.topspinevisible, "top spine visible")
    g[3:4,5] = control(ax.bottomspinevisible, "bottom spine visible")
    g[1:2,6] = GtkLabel("spine width")
    g[3:4,6] = control(ax.spinewidth)
    g
end

function axis_ticks_settings(ax)
    g=GtkGrid()
    g[1:2,1] = GtkLabel("X ticks")
    g[1:2,2] = control(ax.xticksvisible, "visible")
    g[3:4,1] = GtkLabel("Y ticks")
    g[3:4,2] = control(ax.yticksvisible, "visible")
    g[1,3] = GtkLabel("width")
    g[2,3] = control(ax.xtickwidth)
    g[3,3] = GtkLabel("width")
    g[4,3] = control(ax.ytickwidth)
    g[1,4] = GtkLabel("size")
    g[2,4] = control(ax.xticksize)
    g[3,4] = GtkLabel("size")
    g[4,4] = control(ax.yticksize)
    g[1:2,5] = control(ax.xticksmirrored,"mirrored")
    g[3:4,5] = control(ax.yticksmirrored,"mirrored")
    g[1,6] = GtkLabel("label size")
    g[2,6] = control(ax.xticklabelsize)
    g[3,6] = GtkLabel("label size")
    g[4,6] = control(ax.yticklabelsize)
    g[1,7] = GtkLabel("label pad")
    g[2,7] = control(ax.xticklabelpad)
    g[3,7] = GtkLabel("label pad")
    g[4,7] = control(ax.yticklabelpad)
    g[1,8] = GtkLabel("label rotation")
    g[2,8] = control(ax.xticklabelrotation)
    g[3,8] = GtkLabel("label rotation")
    g[4,8] = control(ax.yticklabelrotation)
    g
end

function colorbar_settings(cb)
    g=GtkGrid()
    g[1,1] = GtkLabel("Label")
    g[2,1] = TextBox(cb.label)
    # these are Observable{Any} so don't currently work with GtkObservables
    #g[1:2,2] = checkbox(cb.labelvisible, "visible")
    #g[1,3] = GtkLabel("size")
    #g[2,3] = control(cb.labelsize)
    #g[1,4] = GtkLabel("padding")
    #g[2,4] = control(cb.labelpadding)
    g
end

# Window for controlling attributes of Axes and children
function attributes_window(f=current_figure())
    win = GtkWindow("Axes and Plots", 900, 500)
    
    sw = GtkScrolledWindow()
    lb,d,sl_axes = axis_list(f)
    sw[]=lb
    
    p = GtkPaned(:h; position=200)
    p[1] = sw
    
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
    p[2] = stackbox
    
    attrsw = GtkScrolledWindow()
    attrsw[] = attrlv
    
    signal_connect(sm,"selection-changed") do sel, position, n_items
        position = Gtk4.G_.get_selected(sel)
        row = Gtk4.G_.get_row(sl_axes,position)
        row!==nothing || return
        p = Gtk4.get_item(row).string
        thing = d[p]
        
        change_selected(thing)
        
        function populate_stack()
            empty!(st)
            if isa(thing, Axis)
                push!(st, axis_title_settings(thing), "axis_title", "Title")
                push!(st, axis_label_settings(thing), "axis_labels", "Axis labels")
                push!(st, axis_ticks_settings(thing), "axis_ticks", "Ticks")
                push!(st, axis_grid_settings(thing), "axis_grid", "Grid & spine")
            end
            if isa(thing, Colorbar)
                push!(st, colorbar_settings(thing), "colorbar", "Colorbar")
            end
            push!(st, attrsw, "attr", "All")
            Cint(0)
        end
        
        fill_attributes!(attrlv,thing)
        
        function bind_con_cb(f, li)
            text = li[].string
            box = get_child(li)
            name = Symbol(text)
            if name === :alignmode
                box[:center] = alignmode_dropdown(getproperty(thing,name))
            else
                box[:center] = control(getproperty(thing,name))
            end
            nothing
        end
        control_factory = GtkSignalListItemFactory(_setup_con_cb, bind_con_cb)
        Gtk4.factory(concol, control_factory)
        
        @idle_add populate_stack()
    end
    
    win[]=p
    
    signal_connect(on_axis_window_close_request, win, "close-request")
    
    win
end

