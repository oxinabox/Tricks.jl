using Tricks
using InteractiveUtils
using Test

struct Iterable end; struct NonIterable end;
iterableness_static(::Type{T}) where T = static_hasmethod(iterate, Tuple{T}) ? Iterable() : NonIterable()

struct Foo end

@testset "static_hasmethod" begin
    @testset "positive: $(typeof(data))" for data in (
        "abc", [1,2,3], (2,3), ones(4,10,2), 'a',  1:100
    )
        T = typeof(data)
        @test iterableness_static(T) === Iterable()
        code_typed_ir = (@code_typed iterableness_static(T))[1].code
        @test code_typed_ir == [:(return $(QuoteNode(Iterable())))]
    end

    @testset "negative: $(typeof(data))" for data in (
        :a, rand, Int
    )
        T = typeof(data)
        @test iterableness_static(T) === NonIterable()
        code_typed = (@code_typed iterableness_static(T))
        @test code_typed[2] === NonIterable  # return type
        @test length(code_typed[1].code) <= 3  # currently has dead conditions on statements 1 and 2, but LLVM removed them.
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
end


@testset "static_methods" begin
    f(x) = x + 1
    @test (length ∘ collect ∘ static_methods)(f) == 1
    f(::Int) = 1
    @test (length ∘ collect ∘ static_methods)(f) == 2
end
