module KaiCLI

using Comonicon

@cast whoami() = println("my name is Kai Xu")

module Weight

using Comonicon, JSON, Dates, Printf, UnicodePlots

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
    run(cmd)
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
    rawdata_lst = JSON.parse(read(cmd, String))["Items"]

    weightdata_lst = [WeightData(rawdata) for rawdata in rawdata_lst]
    sort!(weightdata_lst; by=(wd -> wd.datetime))

    return weightdata_lst
end

@cast function list(num_days::Int=1; all::Bool=false)
    weightdata_lst = read_weightdata()
    if !all
        dt_latest = weightdata_lst[end].datetime
        dt_latest_days_off = dt_latest - Dates.Day(num_days)
        weightdata_lst = filter(wd -> wd.datetime >= dt_latest_days_off, weightdata_lst)
    end

    println("$num_days $(num_days > 1 ? "days" : "day") data:")
    # TODO use PrettyTables.jl for this
    for wd in weightdata_lst
        println(wd)
    end
end

@cast function plot(num_weeks::Int=1; all::Bool=false)
    weightdata_lst = read_weightdata()
    if !all
        dt_latest = weightdata_lst[end].datetime
        dt_latest_weeks_off = dt_latest - Dates.Week(num_weeks)
        weightdata_lst = filter(wd -> wd.datetime >= dt_latest_weeks_off, weightdata_lst)
    end

    x = map(wd -> wd.datetime, weightdata_lst)
    y = map(wd -> wd.weight, weightdata_lst)
    print(lineplot(x, y; title="$num_weeks $(num_weeks > 1 ? "weeks" : "week") data", xlabel="time", name="weight (kg)", format=DT_FORMAT_SHORT, width=128, height=32))
end

end # module Weight

@cast Weight

@main

### precompilation

using PrecompileTools

@setup_workload begin
    @compile_workload begin
        redirect_stdout(devnull) do
            KaiCLI.command_main(["-h"])
            KaiCLI.command_main(["weight", "-h"])
        end
    end
end

end # module KaiCLI
