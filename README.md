# GtkMakie.jl

Interactive [Makie](https://github.com/JuliaPlots/Makie.jl) plots in [Gtk4](https://github.com/JuliaGtk/Gtk4.jl) windows.

Combines GTK's GtkGLArea and the GLMakie backend. The goal is an interactive widget that
can be used in Gtk4 applications.

This is still under development and is unregistered. To try it in the Julia REPL, clone or dev it and use:
```
using GtkMakie, GLMakie
screen = GtkMakie.GTKScreen(resolution=(800, 800))
display(screen, scatter(1:4))
```
Here `scatter(1:4)` can be replaced with other Makie plot commands or a function call that returns a `Figure`.

## Status

It produces a figure in a window. Most interactivity seems to work.
