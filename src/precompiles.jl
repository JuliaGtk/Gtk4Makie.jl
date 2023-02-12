using SnoopPrecompile

let
    @precompile_setup begin
        @precompile_all_calls begin
            screen = GtkMakie.GTKScreen()
            close(screen)
        end
    end
end
