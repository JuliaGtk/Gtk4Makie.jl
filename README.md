# GtkMakie.jl

Interactive [Makie](https://github.com/JuliaPlots/Makie.jl) plots in [Gtk4](https://github.com/JuliaGtk/Gtk4.jl) windows.

This package combines GTK's GtkGLArea and the GLMakie backend. The ultimate goal is an interactive widget that can be used in Gtk4 applications. Currently, this is out of reach (see [here](https://github.com/JuliaGtk/GtkMakie.jl/pull/3)), but GtkMakie can draw one GLMakie plot per window, and other Gtk4 widgets can be added around the plot. Mouse and keyboard interactivity works just like in GLMakie's GLFW-based backend.

## Installation

This is still under development and is unregistered. To try it in the Julia REPL, clone or dev it and use:
```
using GtkMakie, GLMakie
screen = GtkMakie.GTKScreen(resolution=(800, 800))
display(screen, scatter(1:4))
```
Here `scatter(1:4)` can be replaced with other Makie plot commands or a function call that returns a `Figure`.

## Adding other widgets

For a GtkMakie `Screen`, you can access the `GtkGLArea` where it draws Makie plots using `glarea(screen)` and the GTK window using `window(screen)`. To add other widgets, you can get the `GtkGrid` that holds the `GtkGLArea` using `g = grid(screen)`. Widgets can then be added using, for example, `g[1,2] = GtkButton("Do something")` (adds a button below the plot) or `insert!(g, glarea(screen), :top); g[1,1] = GtkButton("Do something else")` (adds a button above the plot).

## Status

GtkMakie has been successfully run on Windows, Mac, and Linux. However, a problem has been reported by one Linux user on NVidia hardware (https://github.com/JuliaGtk/GtkMakie.jl/issues/7). On Wayland, getting GTK4's OpenGL backend to work may require a bit of configuration (see [here](https://github.com/JuliaGtk/Gtk4.jl#enabling-gtk4s-egl-backend-linux)).
