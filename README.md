# Gtk4Makie.jl

Interactive [Makie](https://github.com/JuliaPlots/Makie.jl) plots in [Gtk4](https://github.com/JuliaGtk/Gtk4.jl) windows.

This package combines GTK's GtkGLArea and the GLMakie backend. Mouse and keyboard interactivity works just like in GLMakie's GLFW-based backend. There are two ways to draw GLMakie plots using Gtk4Makie:
1. In widgets (`GtkMakieWidget`), which can be placed at will inside other Gtk4 layout widgets.
2. As single plots in windows (`GTKScreen`) analogous to GLMakie's `GLScreen`.

For the window-based plots, Control-W (or Command-W on a Mac) closes the window and F11 (or Command-Shift-F on a Mac) fullscreens the window. Control-S (or Command-S on a Mac) opens a dialog for saving the figure to a PNG file.

## Installation and quick start

To install in Julia's REPL, type ']' and then `add Gtk4Makie`. The following demonstrates how to produce a single GLMakie plot in a Gtk4 window:
```
using Gtk4Makie, GLMakie
screen = GTKScreen(resolution=(800, 800))
display(screen, scatter(1:4))
```
Here `scatter(1:4)` can be replaced with other Makie plot commands or a function call that returns a `Figure`.

## Status

Gtk4Makie has been successfully run on Windows, Mac, and Linux. However, a problem has been reported by one Linux user on NVidia hardware (https://github.com/JuliaGtk/Gtk4Makie.jl/issues/7). On Wayland, getting GTK4's OpenGL backend to work may require a bit of configuration (see [here](https://github.com/JuliaGtk/Gtk4.jl#enabling-gtk4s-egl-backend-linux)).

Users should be aware that this package unavoidably relies on Makie internals and is likely to break from time to time when upgrading Makie packages.

Those seeking a smoother experience should consider [MousetrapMakie.jl](https://github.com/Clemapfel/MousetrapMakie.jl), which offers better documentation and better support.

## Usage

### Using `GtkMakieWidget`

You can also place Makie plots in widgets:
```
using Gtk4, Gtk4Makie, GLMakie
win = GtkWindow(;visible=false,title="2 Makie widgets in one window")
p=GtkPaned(:v;position=200)
p[1]=GtkMakieWidget()
p[2]=GtkMakieWidget()
win[]=p

push!(p[1],lines(rand(10)))
push!(p[2],scatter(rand(10)))
show(win)
```

### Using `GTKScreen` (one GLMakie screen per GtkWindow)

To add other widgets around the Makie plot in the window-based `GTKScreen`, you can get the `GtkGrid` that holds the `GtkGLArea` using `g = grid(screen)`. Widgets can then be added using, for example, `g[1,2] = GtkButton("Do something")` (adds a button below the plot) or `insert!(g, glarea(screen), :top); g[1,1] = GtkButton("Do something else")` (adds a button above the plot).

The constructor for `GTKScreen` accepts the following keyword arguments:

- `resolution`: sets the initial default width and height of the window in pixels
- `title`: a string to use as the window title
- `fullscreen`: if `true`, the window is set to fullscreen mode immediately

By default, Gtk4Makie screen windows include a header bar with a save button and a menu button. To omit the header bar, create a screen using, for example, `GTKScreen(false; resolution=(800, 800))`.

For a Gtk4Makie `Screen`, you can access the `GtkGLArea` where it draws Makie plots using `glarea(screen)` and the GTK window it's in using `window(screen)`.

### Bonus functionality
A window showing the axes and plots in a figure and their attributes can be opened using `attributes_window(f=current_figure())`. This can be used to experiment with various attributes, or add axis labels and titles before saving a plot. This functionality is experimental, buggy, and likely to grow and evolve over time.

