using Tricks
using InteractiveUtils
using Test

struct Iterable end; struct NonIterable end;
iterableness_static(::Type{T}) where T = static_hasmethod(iterate, Tuple{T}) ? Iterable() : NonIterable()

struct Foo end

# if code has no calls then it must be fully static
has_no_calls(ir) = all(stmt->!Meta.isexpr(stmt, :call), ir)

@testset "static_hasmethod" begin
    @testset "positive: $(typeof(data))" for data in (
        "abc", [1,2,3], (2,3), ones(4,10,2), 'a',  1:100
    )
        T = typeof(data)
        @test iterableness_static(T) === Iterable()
        code_typed = (@code_typed iterableness_static(T))

        @test code_typed[2] === Iterable  # return type
        @test has_no_calls(code_typed[1].code)
    end

    @testset "negative: $(typeof(data))" for data in (
        :a, rand, Int
    )
        T = typeof(data)
        @test iterableness_static(T) === NonIterable()
        code_typed = (@code_typed iterableness_static(T))

        @test code_typed[2] === NonIterable  # return type
        @test has_no_calls(code_typed[1].code)
    end

    @testset "add method" begin
        @test iterableness_static(Foo) === NonIterable()

        Base.iterate(::Foo) = ("Foo", nothing);
        Base.iterate(::Foo, ::Nothing) = nothing;
        Base.length(::Foo) = 1;
        @test collect(Foo()) == ["Foo"]

        @test iterableness_static(Foo) === Iterable()
    end

    @testset "delete method" begin
        @test iterableness_static(Foo) === Iterable()
        meth = first(methods(iterate, Tuple{Foo}))
        Base.delete_method(meth)
        @test_throws MethodError collect(Foo())

        @test iterableness_static(Foo) === NonIterable()
    end


    @testset "abstract type args" begin
        # https://github.com/oxinabox/Tricks.jl/issues/14

        goo(x::Integer) = 1
        @assert !hasmethod(goo, Tuple{Real})  # the behaviour we want to match
        @test !static_hasmethod(goo, Tuple{Real})

        goo(x::Number) = 2
        @assert hasmethod(goo, Tuple{Real})   # Now it _is_ covered.
        @test static_hasmethod(goo, Tuple{Real})   # Now it _is_ covered.
    end
end

module Bar
h(::Int) = 1

end
using .Bar

@testset "static_methods" begin
    # behavour
    f(x) = x + 1
    @test (length ∘ collect ∘ static_methods)(f) == 1
    f(::Int) = 1
    @test (length ∘ collect ∘ static_methods)(f) == 2

    g(::Int) = 1
    @test (length ∘ collect ∘ static_methods)(g) == 1
    g(x) = x+1
    @test (length ∘ collect ∘ static_methods)(g) == 2

    @test (length ∘ collect ∘ static_methods)(Bar.h) == 1
    Bar.h(x) = x
    @test (length ∘ collect ∘ static_methods)(Bar.h) == 2

    # Code Generation
    code_typed = (@code_typed static_methods(f))
    @test code_typed[2] === Base.MethodList  # return type
    @test has_no_calls(code_typed[1].code)
end
