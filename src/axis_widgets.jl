_setup_box_cb(f, li) = set_child(li,GtkBox(:h))
_indx(li) = parse(Int,li[].string)

_linestyle_descr(::Nothing) = "solid"
_linestyle_descr(s) = string(s)

# a ColumnView widget that shows a list of plots, with:
# - "label" : TODO: make editable
# - a checkbox for "visible"
# - a colorbutton for the color
# - TODO: selector for linestyle
# - TODO: refresh method

function interactive_legend(ax; color_column = true, style_column = false)
    ps = plots(ax)
    #ps, labels = Makie.get_labeled_plots(ax; merge=false, unique=false) # this fetches only labeled plots and optionally does some nice merging/uniquifying
    sl=GtkStringList(string.(1:length(ps)))
    label_view = GtkColumnView(GtkSelectionModel(GtkNoSelection(GListModel(sl))) ; vexpand=true)
    
    function bind_label_cb(f, li)
        i=_indx(li)
        label = get_child(li)
        if haskey(ps[i].attributes, :label)
            label.label = ps[i].label[]
        else
            label.label = ""
        end
    end
    
    label_factory = GtkSignalListItemFactory(_setup_attr_cb, bind_label_cb)
    labelcol = GtkColumnViewColumn("Label", label_factory)
    Gtk4.G_.append_column(label_view,labelcol)
    
    function bind_vis_cb(f, li)
        box = get_child(li)
        i=_indx(li)
        empty!(box)
        if haskey(ps[i].attributes, :visible)
            push!(box, CheckButton(ps[i].visible, ""))
        end
    end
    
    vis_factory = GtkSignalListItemFactory(_setup_box_cb, bind_vis_cb)
    viscol = GtkColumnViewColumn("Visible", vis_factory)
    Gtk4.G_.append_column(label_view,viscol)
    
    if color_column
        function bind_linecolor_cb(f, li)
            box = get_child(li)
            i=_indx(li)
            empty!(box)
            if haskey(ps[i].attributes, :color)
                push!(box, ColorButton(ps[i].color))
            end
        end
    
        linecolor_factory = GtkSignalListItemFactory(_setup_box_cb, bind_linecolor_cb)
        linecolorcol = GtkColumnViewColumn("Color", linecolor_factory)
        Gtk4.G_.append_column(label_view,linecolorcol)
    end
    
    if style_column
        function bind_style_cb(f, li)
            box = get_child(li)
            i=_indx(li)
            empty!(box)
            if haskey(ps[i].attributes, :marker)
                push!(box, marker_dropdown(ps[i].marker))
            elseif haskey(ps[i].attributes, :linestyle)
                #push!(box, linestyle_dropdown(ps[i].linestyle)) # changing linestyle is broken
                push!(box, GtkLabel(_linestyle_descr(ps[i].linestyle[])))
            end
        end
    
        style_factory = GtkSignalListItemFactory(_setup_box_cb, bind_style_cb)
        stylecol = GtkColumnViewColumn("Style", style_factory)
        Gtk4.G_.append_column(label_view,stylecol)
    end
    
    label_view
end

