using PrecompileTools

let
    @setup_workload begin
        x=rand(5)
        @compile_workload begin
            screen = GTKScreen()
            display(screen, lines(x))
            close(screen)
            Makie._current_figure[] = nothing
        end
    end
end
