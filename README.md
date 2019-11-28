# Tricks
<!--
[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://oxinabox.github.io/Tricks.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://oxinabox.github.io/Tricks.jl/dev)
-->
[![Build Status](https://travis-ci.com/oxinabox/Tricks.jl.svg?branch=master)](https://travis-ci.com/oxinabox/Tricks.jl)
[![Build Status](https://ci.appveyor.com/api/projects/status/github/oxinabox/Tricks.jl?svg=true)](https://ci.appveyor.com/project/oxinabox/Tricks-jl)
[![Codecov](https://codecov.io/gh/oxinabox/Tricks.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/oxinabox/Tricks.jl)
[![Build Status](https://api.cirrus-ci.com/github/oxinabox/Tricks.jl.svg)](https://cirrus-ci.com/github/oxinabox/Tricks.jl)

Tricks.jl is an experimental package that does tricks with the with Julia edge system.

Currently it has 1 trick:
`static_hasmethod`.
This is like `hasmethod` but it does not trigger any dynamic lookup of the method table.
it just returns the constant `true` or `false`.
If methods are added, recompilation is triggered.

This is based on https://github.com/JuliaLang/julia/pull/32732
and that thread should be read before use.

**If you can make a reproducable case of `static_hasmethod` not working please post in [#2](https://github.com/oxinabox/Tricks.jl/issues/2)**

### We can use this to declare traits.
For demonstration we include versions based on static and nonstatic `has_method`.
```
julia> using Tricks: static_hasmethod

julia> struct Iterable end; struct NonIterable end;

julia> iterableness_dynamic(::Type{T}) where T = hasmethod(iterate, Tuple{T}) ? Iterable() : NonIterable()
iterableness_dynamic (generic function with 1 method)

julia> iterableness_static(::Type{T}) where T = static_hasmethod(iterate, Tuple{T}) ? Iterable() : NonIterable()
iterableness_static (generic function with 1 method)
```

### Demo: 
```
julia> using BenchmarkTools

julia> const examples =  (:a, "abc", [1,2,3], rand, (2,3), ones(4,10,2), 'a',  1:100);

julia> @btime [iterableness_dynamic(typeof(x)) for x in $examples]
  13.608 μs (5 allocations: 304 bytes)
8-element Array{Any,1}:
 NonIterable()
 Iterable()
 Iterable()
 NonIterable()
 Iterable()
 Iterable()
 Iterable()
 Iterable()

julia> @btime [iterableness_static(typeof(x)) for x in $examples]
  582.249 ns (5 allocations: 304 bytes)
8-element Array{Any,1}:
 NonIterable()
 Iterable()
 Iterable()
 NonIterable()
 Iterable()
 Iterable()
 Iterable()
 Iterable()
```

So it is over 20x faster.

this is because doesn't generate any code that has to run at runtime:
(i.e. it is not dynamic)
```
julia> @code_typed iterableness_static(String)
CodeInfo(
1 ─     return $(QuoteNode(Iterable()))
) => Iterable

julia> @code_typed iterableness_dynamic(String)
CodeInfo(
1 ─ %1 = $(Expr(:foreigncall, :(:jl_gf_invoke_lookup), Any, svec(Any, UInt64), 0, :(:ccall), Tuple{typeof(iterate),String}, 0xffffffffffffffff, 0xffffffffffffffff))::Any
│   %2 = (%1 === Base.nothing)::Bool
│   %3 = Core.Intrinsics.not_int(%2)::Bool
└──      goto #3 if not %3
2 ─      return $(QuoteNode(Iterable()))
3 ─      return $(QuoteNode(NonIterable()))
) => Union{Iterable, NonIterable}
```

### Demonstration of it updating:
```
julia> struct Foo end

julia> iterableness_static(Foo)
NonIterable()
```
Initially, it wasn't iterable,
but now we will add the iteration methods to it:

```
julia> Base.iterate(::Foo) = ("Foo", nothing);

julia> Base.iterate(::Foo, ::Nothing) = nothing;

julia> Base.length(::Foo) = 1;

julia> collect(Foo())
1-element Array{Any,1}:
 "Foo"

julia> iterableness_static(Foo)
Iterable()
```


