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

@cast whoami() = println("my name is Kai Xu")

module Weight

using Printf, Dates, Statistics, Comonicon, JSON, PrettyTables, UnicodePlots
using ..KaiCLI: withawsenv

import PrettyTables: pretty_table
import UnicodePlots: lineplot

const DT_FORMAT_LONG = "mm/dd/yyyy-HH:MM:SS"
const DT_FORMAT_SHORT = "mm/dd HH:MM"

"""
track weight

# Args

- `weight`: weight in kilograms

# Options

- `-w, --workout`: workout that consumes the calories follow by
- `-c, --calories`: calories consumed by the workout
"""
@cast function track(weight::Float64; workout::String="", calories::Float64=0.0)
    timestamp = Dates.format(now(), DT_FORMAT_LONG)
    item = Dict(
        "timestamp" => Dict("S" => timestamp),
        "weight" => Dict("N" => string(weight)),
    )
    if (!isempty(workout) || !iszero(calories))
        @assert (!isempty(workout) && !iszero(calories)) "-w, --workout has to be provided together with -c, --calories"
        item["workout"] = Dict("S" => workout)
        item["calories"] = Dict("N" => string(calories))
    end

    cmd = ```
    aws dynamodb put-item 
    --table-name weight-tracker 
    --item $(JSON.json(item))
    ```
    withawsenv() do
        run(cmd)
    end

    @info "$item tracked"
end

struct WeightData{Tt<:DateTime,Tw<:AbstractFloat}
    datetime::Tt
    weight::Tw
end
Base.show(io::IO, wd::WeightData) = print(io, "WeightData($(Dates.format(wd.datetime, DT_FORMAT_SHORT)), $(@sprintf("%.2f", wd.weight)))")

function WeightData(rawdata)
    timestamp = rawdata["timestamp"]["S"]
    datetime = DateTime(timestamp, DT_FORMAT_LONG)
    weight = parse(Float64, rawdata["weight"]["N"])
    return WeightData(datetime, weight)
end

function read_weightdata()
    cmd = ```
    aws dynamodb scan 
    --table-name weight-tracker 
    --output json
    ```
    out = withawsenv() do
        read(cmd, String)
    end
    rawdata_lst = JSON.parse(out)["Items"]

    weightdata_lst = [WeightData(rawdata) for rawdata in rawdata_lst]
    sort!(weightdata_lst; by=(wd -> wd.datetime))

    return weightdata_lst
end

function pretty_table(weightdata_lst::AbstractVector{<:WeightData})
    pretty_table(
        Dict(
            "datetime" => map(wd -> Dates.format(wd.datetime, DT_FORMAT_SHORT), weightdata_lst),
            "weight" => map(wd -> @sprintf("%.2f", wd.weight), weightdata_lst),
        );
        header=["datetime", "weight"]
    )
end

@cast function list(num_days::Int=1; all::Bool=false)
    weightdata_lst = read_weightdata()
    if !all
        dt_latest = weightdata_lst[end].datetime
        dt_latest_days_off = dt_latest - Dates.Day(num_days)
        weightdata_lst = filter(wd -> wd.datetime >= dt_latest_days_off, weightdata_lst)
    end

    println("$num_days $(num_days > 1 ? "days" : "day") data:")
    returnpretty_table(weightdata_lst)
end

function lineplot(weightdata_lst::AbstractVector{<:WeightData})
    dt_lst = map(wd -> wd.datetime, weightdata_lst)
    w_lst = map(wd -> wd.weight, weightdata_lst)
    fig = lineplot(dt_lst, w_lst; xlabel="time", ylabel="kg", name="weight", format=DT_FORMAT_SHORT, width=128, height=32)
    w_daily_lst = map(dt_lst) do dt
        wd_lst = filter(wd -> dt - Hour(12) <= wd.datetime <= dt + Hour(12), weightdata_lst)
        mean(wd -> wd.weight, wd_lst)
    end
    lineplot!(fig, dt_lst, w_daily_lst; name="daily avg.")
    hline!(fig, 80.0; name="target")
    return fig
end

@cast function plot(num_weeks::Int=1; all::Bool=false)
    weightdata_lst = read_weightdata()
    if !all
        dt_latest = weightdata_lst[end].datetime
        dt_latest_weeks_off = dt_latest - Dates.Week(num_weeks)
        weightdata_lst = filter(wd -> wd.datetime >= dt_latest_weeks_off, weightdata_lst)
    end

    println("$num_weeks $(num_weeks > 1 ? "weeks" : "week") data:")
    print(lineplot(weightdata_lst))
end

end # module Weight

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
            
            KaiCLI.command_main(["-h"])

            KaiCLI.command_main(["weight", "-h"])
            let dt_bday = DateTime("1992-11-10", "yyyy-mm-dd"),
                dt_lst = collect(dt_bday:Day(1):dt_bday+Day(2)),
                w_lst = rand(length(dt_lst)),
                wd_lst = [WeightData(dt, w) for (dt, w) in zip(dt_lst, w_lst)]

                pretty_table(wd_lst)
                lineplot(wd_lst)
            end
        end
    end
end

end # module KaiCLI
