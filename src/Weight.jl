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

- `-t, --timestamp`: timestamp of the data; default to calling `now()`
- `-w, --workout`: workout that consumes the calories follow by
- `-c, --calories`: calories consumed by the workout
"""
@cast function track(weight::Float64; timestamp::String="", workout::String="", calories::Float64=0.0)
    dt = isempty(timestamp) ? now() : DateTime(string(Year(now()).value) * '/' * timestamp, "yyyy" * '/' * DT_FORMAT_SHORT)
    timestamp = Dates.format(dt, DT_FORMAT_LONG)

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

"""
delete weight by timestamp

# Args

- `timestamp`: timestamp in format of $DT_FORMAT_LONG
"""
@cast function delete(timestamp::String)
    key = Dict("timestamp" => Dict("S" => timestamp))

    cmd = ```
    aws dynamodb delete-item
    --table-name weight-tracker 
    --key $(JSON.json(key))
    ```
    withawsenv() do
        run(cmd)
    end

    @info "$key deleted"
end

const Maybe{T} = Union{Nothing, T} where {T}

struct WeightData{Tt<:DateTime,Twe<:AbstractFloat,Two<:Maybe{<:AbstractString},Tc<:Maybe{<:AbstractFloat}}
    datetime::Tt
    weight::Twe
    workout::Two
    calories::Tc
end
Base.show(io::IO, wd::WeightData) = 
    print(io, "WeightData($(Dates.format(wd.datetime, DT_FORMAT_SHORT)), $(@sprintf("%.2f", wd.weight)), $(wd.workout), $(@sprintf("%.2f", wd.calories)))")

WeightData(datetime, weight) = WeightData(datetime, weight, nothing, nothing)

function WeightData(rawdata)
    timestamp = rawdata["timestamp"]["S"]
    datetime = DateTime(timestamp, DT_FORMAT_LONG)
    weight = parse(Float64, rawdata["weight"]["N"])
    workout = ("workout" in keys(rawdata)) ? rawdata["workout"]["S"] : nothing
    calories = ("calories" in keys(rawdata)) ? parse(Float64, rawdata["calories"]["N"]) : nothing
    return WeightData(datetime, weight, workout, calories)
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
    data = hcat(
        map(wd -> Dates.format(wd.datetime, DT_FORMAT_SHORT), weightdata_lst),
        map(wd -> @sprintf("%.2f", wd.weight), weightdata_lst),
        map(wd -> isnothing(wd.workout) ? "-" : wd.workout, weightdata_lst),
        map(wd -> isnothing(wd.calories) ? "-" : @sprintf("%.2f", wd.calories), weightdata_lst),
    )
    pretty_table(
        data;
        header=["datetime", "weight", "workout", "calories"],
        crop=:none,
    )
end

"""
list past weight

# Args

- `num_days`: number of days to list

# Flags

- `-a, --all`: list all data
"""
@cast function list(num_days::Int=2; all::Bool=false)
    weightdata_lst = read_weightdata()
    if !all
        dt_latest = weightdata_lst[end].datetime
        dt_latest_days_off = dt_latest - Dates.Day(num_days)
        weightdata_lst = filter(wd -> wd.datetime >= dt_latest_days_off, weightdata_lst)
    end

    println("$num_days $(num_days > 1 ? "days" : "day") data:")
    pretty_table(weightdata_lst)
end

function lineplot(weightdata_lst::AbstractVector{<:WeightData}; minmax=false, targets=nothing)
    dt_lst = map(wd -> wd.datetime, weightdata_lst)
    w_lst = map(wd -> wd.weight, weightdata_lst)
    fig = lineplot(dt_lst, w_lst; xlabel="time", ylabel="kg", name="raw data", format=DT_FORMAT_SHORT, width=128, height=32)

    w_daily_lst = map(dt_lst) do dt
        wd_lst = filter(wd -> dt - Hour(12) <= wd.datetime <= dt + Hour(12), weightdata_lst)
        mean(wd -> wd.weight, wd_lst)
    end
    lineplot!(fig, dt_lst, w_daily_lst; name="daily avg.")
    
    if minmax
        wmin, wmax = extrema(w_lst)
        hline!(fig, wmin; name="min ($wmin)")
        hline!(fig, wmax; name="max ($wmax)")
    end
    
    !isnothing(targets) && foreach(targets) do target
        hline!(fig, target; name="target ($target)")
    end
    return fig
end

"""
plot weight trend

# Args

- `num_weeks`: number of weeks to plot

# Options

- `-t, --targets`: target weights to plot as horizontal lines

# Flags

- `-m, --minmax`: plot min & max over the displayed period
- `-a, --all`: plot all data
"""
@cast function plot(num_weeks::Int=1; minmax::Bool=false, targets::Vector{Int}=[80], all::Bool=false)
    weightdata_lst = read_weightdata()
    if !all
        dt_latest = weightdata_lst[end].datetime
        dt_latest_weeks_off = dt_latest - Dates.Week(num_weeks)
        weightdata_lst = filter(wd -> wd.datetime >= dt_latest_weeks_off, weightdata_lst)
    end

    println("$num_weeks $(num_weeks > 1 ? "weeks" : "week") data:")
    print(lineplot(weightdata_lst; minmax, targets))
end

end # module