module Tricks

using Base: rewrap_unionall, unwrap_unionall, uncompressed_ast
using Base: CodeInfo

export static_hasmethod, static_methods, compat_hasmethod, static_fieldnames, static_fieldcount, static_fieldtypes

# This is used to create the CodeInfo returned by static_hasmethod.
_hasmethod_false(@nospecialize(f), @nospecialize(t)) = false
_hasmethod_true(@nospecialize(f), @nospecialize(t)) = true

"""
    static_hasmethod(f, type_tuple::Type{<:Tuple)

Like `hasmethod` but runs at compile-time (and does not accept a worldage argument).
"""
@generated function static_hasmethod(@nospecialize(f), @nospecialize(t::Type{T}),) where {T<:Tuple}
    # The signature type:
    method_insts = _method_instances(f, T)

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
    list_of_methods = _methods(f, T)
    ci = create_codeinfo_with_returnvalue([Symbol("#self#"), :f, :_T], [:T], (:T,), :($list_of_methods))

    # Now we add the edges so if a method is defined this recompiles
    mt = f.name.mt
    ci.edges = Core.Compiler.vect(mt, Tuple{Vararg{Any}})
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


# The below methods are copied and adapted from Julia Base:
# - https://github.com/JuliaLang/julia/blob/4931faa34a8a1c98b39fb52ed4eb277729120128/base/reflection.jl#L952-L966
# - https://github.com/JuliaLang/julia/blob/4931faa34a8a1c98b39fb52ed4eb277729120128/base/reflection.jl#L893-L896
# - https://github.com/JuliaLang/julia/blob/4931faa34a8a1c98b39fb52ed4eb277729120128/base/reflection.jl#L1047-L1055
# Like Base.methods, but accepts f as a _type_ instead of an instance.
function _methods(@nospecialize(f_type), @nospecialize(t_type),
                 mod::Union{Tuple{Module},AbstractArray{Module},Nothing}=nothing)
    tt = _combine_signature_type(f_type, t_type)
    lim, world = -1, typemax(UInt)
    mft = Core.Compiler._methods_by_ftype(tt, lim, world)
    ms = Base.Method[m.method for m in mft if (mod === nothing || m.method.module ∈ mod)]
    return Base.MethodList(ms, f_type.name.mt)
end
# Like Core.Compiler.method_instances, but accepts f as a _type_ instead of an instance.
function _method_instances(@nospecialize(f_type), @nospecialize(t_type))
    tt = _combine_signature_type(f_type, t_type)
    lim, world = -1, typemax(UInt)
    sm = Core.Compiler.specialize_method
    mft = Core.Compiler._methods_by_ftype(tt, lim, world)
    return Core.MethodInstance[sm(match) for match in mft]
end
# Like Base.signature_type, but starts with a type for f_type already.
function _combine_signature_type(@nospecialize(f_type::Type), @nospecialize(args::Type))
    u = unwrap_unionall(args)
    return rewrap_unionall(Tuple{f_type, u.parameters...}, args)
end

end  # module
