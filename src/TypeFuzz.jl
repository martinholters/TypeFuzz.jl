module TypeFuzz

export testtypeintersect, testcases

using Base: unwrap_unionall, rewrap_unionall

randtype(const_allowed=false) = randtype(Base.Random.GLOBAL_RNG, const_allowed)

function randtype(rng::AbstractRNG, const_allowed=false)
    i = rand(rng, 1:(const_allowed ? 5 : 4))
    if i == 1
        return Int64
    elseif i == 2
        return Float64
    elseif i == 3
        return Val{randtype(rng, true)}
    elseif i == 4
        num = rand(rng, 1:5)
        return Tuple{[randtype(rng, true) for _ in 1:num]...}
    else
        return rand(rng, 1:5)
    end
end

randsupertype(t, varprefix::String="T") = randsupertype(Base.Random.GLOBAL_RNG, t, varprefix)

function randsupertype(rng::AbstractRNG, t, varprefix::String="T")
    vars = Pair{TypeVar, Any}[]
    r = _randsupertype!(rng, t, vars, varprefix)
    for v in vars
        r = UnionAll(v[1], r)
    end
    if !(t <: r)
        @show t
        @show r
        @show vars
        error("randsupertype invalid")
    end
    return r
end

function _randsupertype!(rng::AbstractRNG, t::DataType, vars, varprefix)
    np = length(t.parameters)
    if rand(rng, 1:np+2) == 1
        return genvar(rng, t, vars, varprefix)
    else
        if np == 0
            return t
        else
            return t.name.wrapper{[_randsupertype!(rng, tp, vars, varprefix) for tp in t.parameters]...}
        end
    end
end

function _randsupertype!(rng::AbstractRNG, t::Any, vars, varprefix)
    if rand(rng, 1:2) == 1
        return genvar(rng, t, vars, varprefix)
    else
        return t
    end
end

function genvar(rng::AbstractRNG, t, vars, varprefix)
    tv = nothing
    for v in vars
        if t == v[2] && rand(rng, 1:2) == 1
            tv = v[1]
        end
    end
    if tv === nothing
        if length(vars) >= 8
            return t
        else
            tv = TypeVar(Symbol(varprefix, length(vars)+1))
            push!(vars, tv => t)
        end
    end
    return tv
end

istuple(x) = x isa DataType && x <: Tuple
isval(x) = x isa DataType && x <: Val

function tryminimize(f::Function, args...)
    if any(arg -> arg isa UnionAll, args)
        args´ = tryminimize(map(unwrap_unionall, args)...) do args´´...
            f(map(rewrap_unionall, args´´, args)...)
        end
        return map(rewrap_unionall, args´, args)
    end

    if any(arg -> arg isa DataType, args)
        # at least one DataType instance (i.e. not a TypeVar)
        if all(arg -> !(arg isa DataType) || length(arg.parameters) == 1, args)
            # try to unwrap single element DataTypes
            args´ = map(arg -> arg isa DataType ? arg.parameters[1] : arg, args)
            if f(args´...)
                return tryminimize(f, args´...)
            end
        end

        np = minimum(arg -> arg isa DataType ? length(arg.parameters) : typemax(Int), args)
        if np == 0
            return args
        end
        if all(arg -> arg isa TypeVar || istuple(arg), args) && any(istuple, args)
            # Tuples or TypeVars, but at least one Tuple
            for i in 1:np
                # try removing tuple elements
                args´ = map(arg -> arg isa TypeVar ? arg : Tuple{arg.parameters[[1:i-1; i+1:end]]...}, args)
                if f(args´...)
                    return tryminimize(f, args´...)
                end
            end
        end

        paramsmat = Base.typed_hcat(Any, (collect(args[j].parameters[1:np]) for j in 1:length(args) if args[j] isa DataType)...)
        for i in 1:np
            # minimize parameters
            paramsmat[i,:] = collect(tryminimize(paramsmat[i,:]...) do paramsi´...
                args´ = collect(args)
                j´ = 1
                for j in eachindex(args)
                    if args[j] isa DataType
                        args´[j] = args[j].name.wrapper{paramsmat[1:i-1,j´]...,  paramsi´[j´], paramsmat[i+1:end,j´]...}
                        j´ += 1
                    end
                end
                f(args´...)
            end)
        end
        args´ = collect(args)
        j´ = 1
        for j in eachindex(args)
            if args[j] isa DataType
                args´[j] = args[j].name.wrapper{paramsmat[:,j´]...}
                j´ += 1
            end
        end
        return args´
    end
    return args
end

testtypeintersect(n::Int=1) = testtypeintersect(Base.Random.GLOBAL_RNG, n)

function testtypeintersect(rng::AbstractRNG, n::Int=1)
    failures = Expr[]
    for i in 1:n
        _testtypeintersect!(rng, failures)
    end
    return failures
end

function _testtypeintersect!(rng::AbstractRNG, failures)
    x = randtype(rng)
    a = randsupertype(rng, x, "T")
    b = randsupertype(rng, x, "S")
    r1 = nothing
    r2 = nothing
    try
        r1 = typeintersect(a, b)
    catch e
        a´, b´ = tryminimize(a, b) do a, b
            try
                typeintersect(a, b)
            catch e
                return true
            end
            return false
        end
        push!(failures, :(typeintersect($a´, $b´)))
    end
    try
        r2 = typeintersect(b, a)
    catch e
        a´, b´ = tryminimize(a, b) do a, b
            try
                typeintersect(b, a)
            catch e
                return true
            end
            return false
        end
        push!(failures, :(typeintersect($b´, $a´)))
    end
    if r1 !== nothing && r2 !== nothing && r1 != r2
        a´, b´ = tryminimize(a, b) do a, b
            typeintersect(a,b) != typeintersect(b, a)
        end
        push!(failures, Expr(:let, :(typeintersect(a, b) == typeintersect(b, a)), :(a = $(a´)), :(b = $(b´))))
    end
    if r1 !== nothing
        if !(x <: r1)
            a´, b´, x´ = tryminimize(a, b, x) do a, b, x
                x <: a && x <: b && !(x <: typeintersect(a,b))
            end
            push!(failures, :($(x´) <: typeintersect($(a´), $(b´))))
        end
        if !(r1 <: a)
            a´, b´ = tryminimize(a, b) do a, b
                !(typeintersect(a,b) <: a)
            end
            push!(failures, Expr(:let, :(typeintersect(a, $(b´)) <: a), :(a = $(a´))))
        end
        if !(r1 <: b)
            a´, b´ = tryminimize(a, b) do a, b
                !(typeintersect(a,b) <: b)
            end
            push!(failures, Expr(:let, :(typeintersect($(a´), b) <: b), :(b = $(b´))))
        end
    end
    if r2 !== nothing && r1 != r2
        if !(x <: r2)
            a´, b´, x´ = tryminimize(a, b, x) do a, b, x
                x <: a && x <: b && !(x <: typeintersect(b, a))
            end
            push!(failures, :($(x´) <: typeintersect($(b´), $(a´))))
        end
        if !(r2 <: a)
            a´, b´ = tryminimize(a, b) do a, b
                !(typeintersect(b, a) <: a)
            end
            push!(failures, Expr(:let, :(typeintersect($b´, a) <: a), :(a = $(a´))))
        end
        if !(r2 <: b)
            a´, b´ = tryminimize(a, b) do a, b
                !(typeintersect(b, a) <: b)
            end
            push!(failures, Expr(:let, :(typeintersect(b, $a´) <: b), :(b = $(b´))))
        end
    end
    return failures
end

testcases(failures::Vector{Expr}) = Expr(:block, (:(@test_broken $failure) for failure in failures)...)


end
