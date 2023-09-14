module KaiCLI

using TOML, Comonicon

function read_config()
    config_fp = expanduser("~/.config/kai-cli.toml")
    return isfile(config_fp) ? TOML.parsefile(config_fp) : nothing
end

const CONFIG = read_config()

function withawsenv(f)
    env = []
    if (!isnothing(CONFIG) && ("aws" in keys(CONFIG)))
        CONFIG_AWS = CONFIG["aws"]
        awskeys = intersect(["access_key_id", "secret_access_key", "default_region"], keys(CONFIG_AWS))
        if (length(awskeys) > 0)
            @assert length(awskeys) == 3 "please provide all aws keys (\"access_key_id\", \"secret_access_key\", \"default_region\") in the \"aws\" section of ~/.config/kai-cli.toml"
            push!(env, "AWS_ACCESS_KEY_ID" => CONFIG_AWS["access_key_id"])
            push!(env, "AWS_SECRET_ACCESS_KEY" => CONFIG_AWS["secret_access_key"])
            push!(env, "AWS_DEFAULT_REGION" => CONFIG_AWS["default_region"])
        end
    end
    if isempty(env)
        return f()
    else
        return withenv(f, env...)
    end
end

function Base.tryparse(::Type{Vector{T}}, s::AbstractString) where {T<:Real}
    if ((s[1] == '[') || (s[end] == ']'))
        @assert ((s[1] == '[') && (s[end] == ']'))
        s = s[2:end-1]
    end
    return parse.(T, split(s, ','))
end

@cast whoami() = println("my name is Kai Xu")

include("Weight.jl")
@cast Weight

@main

### precompilation

using PrecompileTools
using .Weight: WeightData, Dates, DateTime, Day, pretty_table, lineplot

@setup_workload begin
    @compile_workload begin
        redirect_stdout(devnull) do
            read_config()
            withawsenv() do 
                run(`echo precompilation`) 
            end
            tryparse(Vector{Int}, "[80,81]")
            
            KaiCLI.command_main(["-h"])

            KaiCLI.command_main(["weight", "-h"])
            let dt_bday = DateTime("1992-11-10", "yyyy-mm-dd"),
                dt_lst = collect(dt_bday:Day(1):dt_bday+Day(2)),
                w_lst = rand(length(dt_lst)),
                wd_lst = [WeightData(dt, w) for (dt, w) in zip(dt_lst, w_lst)]

                pretty_table(wd_lst)
                lineplot(wd_lst; targets=[80])
            end
        end
    end
end

end # module
