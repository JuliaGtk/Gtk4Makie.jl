using PrecompileTools: PrecompileTools, @compile_workload, @setup_workload

let
    @setup_workload begin
        x=rand(5)
        @compile_workload begin
            if !Gtk4.initialized[]
                @warn("Gtk4Makie precompile skipped: Gtk4 could not be initialized (are you on a headless system?)")
                return
            end
            screen = GTKScreen()
            display(screen, lines(x))
            closeall(; empty_shader = false)
        end
    end
end
