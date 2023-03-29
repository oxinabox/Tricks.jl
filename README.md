# Tricks
<!--
[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://oxinabox.github.io/Tricks.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://oxinabox.github.io/Tricks.jl/dev)
-->
[![Codecov](https://codecov.io/gh/oxinabox/Tricks.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/oxinabox/Tricks.jl)


| ⚠️ Notice ⚠️ |
| --- |
| **Tricks.jl is not required post-Julia v1.10.0-DEV.609. |
|The features of running `methods` etc at compile-time are now built into the language. |
| It can still be used for compatibility with older versions of the language. |


Tricks.jl is an particularly ~evil~ cunning package that does tricks with the Julia edge system.

Currently it has the following tricks:
### `static_hasmethod`.
This is like `hasmethod` but it does not trigger any dynamic lookup of the method table.
It just returns the constant `true` or `false`.
If methods are added, recompilation is triggered.

**If you can make a reproducible case of `static_hasmethod` not working please post in [#2](https://github.com/oxinabox/Tricks.jl/issues/2).**  
I think it can't actually happen, and can't actually be called dynamically in a way that breaks it.

### `static_methods`
This is just like `methods`, but again it doesn't trigger any dynamic lookup of the method tables.

**If you can make a reproducible case of `static_methods` not working please [open an issue](https://github.com/oxinabox/Tricks.jl/issues/).**  

### `static_fieldnames`, `static_fieldtypes`, `static_fieldcount`
Just like `Base.fieldnames` `Base.fieldtypes`, and `Base.fieldcount` but will participate in constant
propagation and will be free of runtime dynamism.


## Uses
### We can use `static_hasmethod` to declare traits.
For demonstration we include versions based on static and nonstatic `has_method`.
```jl
julia> using Tricks: static_hasmethod

julia> struct Iterable end; struct NonIterable end;

julia> iterableness_dynamic(::Type{T}) where T = hasmethod(iterate, Tuple{T}) ? Iterable() : NonIterable()
iterableness_dynamic (generic function with 1 method)

julia> iterableness_static(::Type{T}) where T = static_hasmethod(iterate, Tuple{T}) ? Iterable() : NonIterable()
iterableness_static (generic function with 1 method)
```

### Demo:
```jl
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
```jl
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
```jl
julia> struct Foo end

julia> iterableness_static(Foo)
NonIterable()
```
Initially, it wasn't iterable,
but now we will add the iteration methods to it:

```jl
julia> Base.iterate(::Foo) = ("Foo", nothing);

julia> Base.iterate(::Foo, ::Nothing) = nothing;

julia> Base.length(::Foo) = 1;

julia> collect(Foo())
1-element Array{Any,1}:
 "Foo"

julia> iterableness_static(Foo)
Iterable()
```

# Julia version support
The core trick that Tricks.jl relies on was introduced in Julia 1.3.
As such most of its methods do not work on earlier julia versions.

For compatability purposes we do provide:
 - `compat_hasmethod`, which picks between `static_hasmethod` or `hasmethod` depending on the Julia version.
