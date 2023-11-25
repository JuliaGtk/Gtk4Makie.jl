module Gtk4MakieCairoMakieExt

using Gtk4Makie

import CairoMakie

function savecairo(filename,f)
    CairoMakie.save(filename, f; backend = CairoMakie)
end

end
