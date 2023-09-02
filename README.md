# Gtk4Makie.jl

Interactive [Makie](https://github.com/JuliaPlots/Makie.jl) plots in [Gtk4](https://github.com/JuliaGtk/Gtk4.jl) windows.

This package combines GTK's GtkGLArea and the GLMakie backend. The ultimate goal is an interactive widget that can be used in Gtk4 applications. Currently, this is out of reach (see [here](https://github.com/JuliaGtk/Gtk4Makie.jl/pull/3)), but Gtk4Makie can draw one GLMakie plot per window, and other Gtk4 widgets can be added around the plot. Mouse and keyboard interactivity works just like in GLMakie's GLFW-based backend. Control-W (or Command-W on a Mac) closes the window and F11 (or Command-Shift-F on a Mac) fullscreens the window.

## Quick start

To install in Julia's REPL, type ']' and then `add Gtk4Makie`. The following demonstrates how to produce a GLMakie plot in a Gtk4 window:
```
using Gtk4Makie, GLMakie
screen = Gtk4Makie.GTKScreen(resolution=(800, 800))
display(screen, scatter(1:4))
```
Here `scatter(1:4)` can be replaced with other Makie plot commands or a function call that returns a `Figure`.

## Adding other widgets

For a Gtk4Makie `Screen`, you can access the `GtkGLArea` where it draws Makie plots using `glarea(screen)` and the GTK window using `window(screen)`. To add other widgets, you can get the `GtkGrid` that holds the `GtkGLArea` using `g = grid(screen)`. Widgets can then be added using, for example, `g[1,2] = GtkButton("Do something")` (adds a button below the plot) or `insert!(g, glarea(screen), :top); g[1,1] = GtkButton("Do something else")` (adds a button above the plot).

## Status

Gtk4Makie has been successfully run on Windows, Mac, and Linux. However, a problem has been reported by one Linux user on NVidia hardware (https://github.com/JuliaGtk/Gtk4Makie.jl/issues/7). On Wayland, getting GTK4's OpenGL backend to work may require a bit of configuration (see [here](https://github.com/JuliaGtk/Gtk4.jl#enabling-gtk4s-egl-backend-linux)).
