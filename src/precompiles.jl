using SnoopPrecompile

let
    @precompile_setup begin
        x=rand(5)
        @precompile_all_calls begin
            screen = GtkMakie.GTKScreen()
            display(screen, lines(x))
            close(screen)
            Makie._current_figure[] = nothing
        end
    end
end
