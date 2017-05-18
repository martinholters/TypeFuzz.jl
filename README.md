# Fuzz testing of the Julia type system

At present, the consistency of `typeintersect` and `issubtype` is tested. This
is done by randomly constructing a type `x`, and then randomly
widening/generalizing it to obtain two (probably different) types `a` and `b`
such that
```julia
x <: a && x <: b
```
It is then verified that
```julia
typeintersect(a, b) == typeintersect(b, a)    &&
x <: typeintersect(a, b)                      &&
typeintersect(a, b) <: a                      &&
typeintersect(a, b) <: b
```

The constructed types are made of nested `Tuple`s, `Val`s, `Int64`s, `Float64`s,
and integer constants. The random widening is performed by introducing
`TypeVar`s and wrapping in a `UnionAll` (with bounds `Union{} <: T <: Any`) at
the outmost level. Thus, the types may be deeply nested, but are conceptually
simple as they do not contain `Union`s, `Vararg`s, or non-trivial `TypeVar`
bounds.

The main entry point is `testtypeintersect(n=1)`, which will run the above `n`
times and return a list of expressions that fail by returning `false` or
throwing an exception, although they should return `true`.

## Example

```julia
julia> using TypeFuzz

julia> srand(2); # for reproducibility

julia> fails=TypeFuzz.testtypeintersect(150)
10-element Array{Expr,1}:
 :(let a = Tuple{T1,T2,Int64} where T1 where T2, b = Tuple{Tuple{S1},S1,S3} where S1 where S3
        typeintersect(a, b) == typeintersect(b, a)
    end)
 :(let b = Tuple{Tuple{S1},S1,S3} where S1 where S3
        typeintersect(b, Tuple{T1,T2,Int64} where T1 where T2) <: b
    end)                         
 :(let a = Tuple{Val{T1},T1,T2} where T1 where T2, b = Tuple{S3,S4,3} where S3 where S4
        typeintersect(a, b) == typeintersect(b, a)
    end)      
 :(let a = Tuple{Val{T1},T1,T2} where T1 where T2
        typeintersect(a, Tuple{S3,S4,3} where S3 where S4) <: a
    end)                               
 :(let b = Tuple{S2,Tuple{S2}} where S2
        typeintersect(Tuple{Int64,T2} where T2, b) <: b
    end)                                                 
 :(let b = Tuple{S3,S4,Val{S4}} where S3 where S4
        typeintersect(b, Tuple{Val{T1},T1,T2} where T1 where T2) <: b
    end)                         
 :(let a = Tuple{Tuple{T8,T8},T8} where T8, b = Tuple{S3,Int64} where S3
        typeintersect(a, b) == typeintersect(b, a)
    end)                     
 :(let a = Tuple{Tuple{T8},T8} where T8
        typeintersect(a, Tuple{S3,Int64} where S3) <: a
    end)                                                 
 :(let a = Tuple{Tuple{T8},T8} where T8
        typeintersect(Tuple{S3,Int64} where S3, a) <: a
    end)                                                 
 :(typeintersect(Tuple{S2,1} where S2, Tuple{T2,T2} where T2))
```

A convenience function `testcases(failures)` is provided to turn these into test
cases using `@test_broken`:
```julia
julia> testset = :(@testset "some tests found by TypeFuzz" begin $(testcases(fails)) end)
:(@testset "some tests found by TypeFuzz" begin  # REPL[12], line 1:
            begin
                @test_broken let a = Tuple{T1,T2,Int64} where T1 where T2, b = Tuple{Tuple{S1},S1,S3} where S1 where S3
                        typeintersect(a, b) == typeintersect(b, a)
                    end
                @test_broken let b = Tuple{Tuple{S1},S1,S3} where S1 where S3
                        typeintersect(b, Tuple{T1,T2,Int64} where T1 where T2) <: b
                    end
                @test_broken let a = Tuple{Val{T1},T1,T2} where T1 where T2, b = Tuple{S3,S4,3} where S3 where S4
                        typeintersect(a, b) == typeintersect(b, a)
                    end
                @test_broken let a = Tuple{Val{T1},T1,T2} where T1 where T2
                        typeintersect(a, Tuple{S3,S4,3} where S3 where S4) <: a
                    end
                @test_broken let b = Tuple{S2,Tuple{S2}} where S2
                        typeintersect(Tuple{Int64,T2} where T2, b) <: b
                    end
                @test_broken let b = Tuple{S3,S4,Val{S4}} where S3 where S4
                        typeintersect(b, Tuple{Val{T1},T1,T2} where T1 where T2) <: b
                    end
                @test_broken let a = Tuple{Tuple{T8,T8},T8} where T8, b = Tuple{S3,Int64} where S3
                        typeintersect(a, b) == typeintersect(b, a)
                    end
                @test_broken let a = Tuple{Tuple{T8},T8} where T8
                        typeintersect(a, Tuple{S3,Int64} where S3) <: a
                    end
                @test_broken let a = Tuple{Tuple{T8},T8} where T8
                        typeintersect(Tuple{S3,Int64} where S3, a) <: a
                    end
                @test_broken typeintersect(Tuple{S2,1} where S2, Tuple{T2,T2} where T2)
                @test_broken let a = Tuple{Tuple{T1,T3},Float64,T1} where T1 where T3, b = Tuple{Tuple{S1,Val{S1}},S1,Float64} where S1
                        typeintersect(a, b) == typeintersect(b, a)
                    end
                @test_broken let b = Tuple{Tuple{S1,Val{S1}},S1,Float64} where S1
                        typeintersect(Tuple{Tuple{T1,T3},Float64,T1} where T1 where T3, b) <: b
                    end
                @test_broken let a = Tuple{Tuple{T1,T3},Float64,T1} where T1 where T3
                        typeintersect(Tuple{Tuple{S1,Val{S1}},S1,Float64} where S1, a) <: a
                    end
            end
        end)

julia> using Base.Test

julia> eval(testset);
Test Summary:                | Broken  Total
some tests found by TypeFuzz |     13     13
```

## Caveats

At present, fuzz testing the type system unfortunately is likely to result in
endless loops or crashes inside Julia. In these cases, no information is
retained as to which types caused the problem. It is therefore highly advised
to issue an explicit `srand` to be able to reproduce any problems.
