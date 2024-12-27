using PrecompileTools: PrecompileTools, @compile_workload, @setup_workload

let
    @setup_workload begin
        x=rand(5)
        @compile_workload begin
            screen = GTKScreen()
            display(screen, lines(x))
            d=DataInspector()
            close(screen)
            Makie.CURRENT_FIGURE[] = nothing
        end
    end
end
