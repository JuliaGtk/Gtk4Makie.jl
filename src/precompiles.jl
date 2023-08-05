using PrecompileTools

let
    @setup_workload begin
        x=rand(5)
        @compile_workload begin
            screen = GTKScreen()
            display(screen, lines(x))
            close(screen)
            Makie.CURRENT_FIGURE[] = nothing
        end
    end
end
