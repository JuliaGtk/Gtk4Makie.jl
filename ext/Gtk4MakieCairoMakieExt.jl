module Gtk4MakieCairoMakieExt

using Gtk4Makie

import CairoMakie

Gtk4Makie.get_cairomakie_extension() = Gtk4MakieCairoMakieExt

function savecairo(filename,f)
    CairoMakie.save(filename, f; backend = CairoMakie)
end

end
