module Tricks

using Base: rewrap_unionall, unwrap_unionall, uncompressed_ast
using Base: CodeInfo

export static_hasmethod, static_methods, static_method_count, compat_hasmethod,
        static_fieldnames, static_fieldcount, static_fieldtypes

# This is used to create the CodeInfo returned by static_hasmethod.
_hasmethod_false(@nospecialize(f), @nospecialize(t)) = false
_hasmethod_true(@nospecialize(f), @nospecialize(t)) = true

"""
    static_hasmethod(f, type_tuple::Type{<:Tuple)

Like `hasmethod` but runs at compile-time (and does not accept a worldage argument).
"""
@generated function static_hasmethod(@nospecialize(f), @nospecialize(t::Type{T}),) where {T<:Tuple}
    # The signature type:
    world = typemax(UInt)
    method_insts = Core.Compiler.method_instances(f.instance, T, world)

    ftype = Tuple{f, fieldtypes(T)...}
    covering_method_insts = [mi for mi in method_insts if ftype <: mi.def.sig]

    method_doesnot_exist = isempty(covering_method_insts)
    ret_func = method_doesnot_exist ? _hasmethod_false : _hasmethod_true
    ci_orig = uncompressed_ast(typeof(ret_func).name.mt.defs.func)
    ci = ccall(:jl_copy_code_info, Ref{CodeInfo}, (Any,), ci_orig)

    # Now we add the edges so if a method is defined this recompiles
    if method_doesnot_exist
        # No method so attach to method table
        mt = f.name.mt
        typ = rewrap_unionall(Tuple{f, unwrap_unionall(T).parameters...}, T)
        ci.edges = Core.Compiler.vect(mt, typ)
    else  # method exists, attach edges to all instances
        ci.edges = covering_method_insts
    end
    return ci
end



function create_codeinfo_with_returnvalue(argnames, spnames, sp, value)
    expr = Expr(:lambda,
        argnames,
        Expr(Symbol("scope-block"),
            Expr(:block,
                Expr(:return, value),
            )
        )
    )
    if spnames !== nothing
        expr = Expr(Symbol("with-static-parameters"), expr, spnames...)
    end
    ci = ccall(:jl_expand, Any, (Any, Any), expr, @__MODULE__)
    return ci
end

"""
    static_methods(f, [type_tuple::Type{<:Tuple])
    static_methods(@nospecialize(f)) = _static_methods(Main, f, Tuple{Vararg{Any}})

Like `methods` but runs at compile-time (and does not accept a worldage argument).
"""
static_methods(@nospecialize(f)) = static_methods(f, Tuple{Vararg{Any}})
@generated function static_methods(@nospecialize(f) , @nospecialize(_T::Type{T})) where {T <: Tuple}
    list_of_methods = methods(f.instance, T)
    ci = create_codeinfo_with_returnvalue([Symbol("#self#"), :f, :_T], [:T], (:T,), :($list_of_methods))

    # Now we add the edges so if a method is defined this recompiles
    ci.edges = _method_table_all_edges_all_methods(f, T)
    return ci
end

function _method_table_all_edges_all_methods(f, T)
    mt = f.name.mt

    # We add an edge to the MethodTable itself so that when any new methods
    # are defined, it recompiles the function.
    mt_edges = Core.Compiler.vect(mt, Tuple{Vararg{Any}})

    # We want to add an edge to _every existing method instance_, so that
    # the deletion of any one of them will trigger recompilation of the function.
    world = typemax(UInt)
    method_insts = Core.Compiler.method_instances(f.instance, T, world)
    covering_method_insts = method_insts

    return [mt_edges..., covering_method_insts...]
end

"""
    static_method_count(f, [type_tuple::Type{<:Tuple])
    static_method_count(@nospecialize(f)) = _static_methods(Main, f, Tuple{Vararg{Any}})
Returns `length(methods(f, tt))` but runs at compile-time (and does not accept a worldage argument).
"""
static_method_count(@nospecialize(f)) = static_method_count(f, Tuple{Vararg{Any}})
@generated function static_method_count(@nospecialize(f) , @nospecialize(_T::Type{T})) where {T <: Tuple}
    method_count = length(methods(f.instance, T))
    ci = create_codeinfo_with_returnvalue([Symbol("#self#"), :f, :_T], [:T], (:T,), :($method_count))

    # Now we add the edges so if a method is defined this recompiles
    ci.edges = _method_table_all_edges_all_methods(f, T)
    return ci
end

@static if VERSION < v"1.3"
    const compat_hasmethod = hasmethod
else
    const compat_hasmethod = static_hasmethod
end

Base.@pure static_fieldnames(t::Type) = Base.fieldnames(t)
Base.@pure static_fieldtypes(t::Type) = Base.fieldtypes(t)
Base.@pure static_fieldcount(t::Type) = Base.fieldcount(t)

end  # module
