module Tricks

using Base: rewrap_unionall, unwrap_unionall, uncompressed_ast
using Base: CodeInfo

export static_hasmethod, static_methods, static_method_count, compat_hasmethod,
        static_fieldnames, static_fieldcount, static_fieldtypes

# This is used to create the CodeInfo returned by static_hasmethod.
_hasmethod_false(@nospecialize(f), @nospecialize(t)) = false
_hasmethod_true(@nospecialize(f), @nospecialize(t)) = true


@generated function _static_hasmethod(@nospecialize(f), @nospecialize(t::Type{T}),) where {T<:Tuple}
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

"""
    static_hasmethod(f, type_tuple::Type{<:Tuple)

Like `hasmethod` but runs at compile-time (and does not accept a worldage argument).
"""
const static_hasmethod = if VERSION >= v"1.10.0-DEV.609"
    # Feature is now part of julia itself
    hasmethod
else
    _static_hasmethod
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
if VERSION >= v"1.10.0-DEV.609"
    function __static_methods(world, source, T, self, f, _T)
        list_of_methods = _methods(f, T, nothing, world)
        ci = create_codeinfo_with_returnvalue([Symbol("#self#"), :f, :_T], [:T], (:T,), :($list_of_methods))

        # Now we add the edges so if a method is defined this recompiles
        ci.edges = _method_table_all_edges_all_methods(f, T, world)
        return ci
    end
    @eval function static_methods(@nospecialize(f) , @nospecialize(_T::Type{T})) where {T <: Tuple}
        $(Expr(:meta, :generated, __static_methods))
        $(Expr(:meta, :generated_only))
    end
else
    @generated function static_methods(@nospecialize(f) , @nospecialize(_T::Type{T})) where {T <: Tuple}
        world = typemax(UInt)
        list_of_methods = _methods(f, T, nothing, world)
        ci = create_codeinfo_with_returnvalue([Symbol("#self#"), :f, :_T], [:T], (:T,), :($list_of_methods))

        # Now we add the edges so if a method is defined this recompiles
        ci.edges = _method_table_all_edges_all_methods(f, T, world)
        return ci
    end
end

function _method_table_all_edges_all_methods(f, T, world = Base.get_world_counter())
    mt = f.name.mt

    # We add an edge to the MethodTable itself so that when any new methods
    # are defined, it recompiles the function.
    mt_edges = Core.Compiler.vect(mt, Tuple{Vararg{Any}})

    # We want to add an edge to _every existing method instance_, so that
    # the deletion of any one of them will trigger recompilation of the function.
    method_insts = _method_instances(f, T, world)
    covering_method_insts = method_insts

    return vcat(mt_edges, covering_method_insts)
end

"""
    static_method_count(f, [type_tuple::Type{<:Tuple])
    static_method_count(@nospecialize(f)) = _static_methods(Main, f, Tuple{Vararg{Any}})
Returns `length(methods(f, tt))` but runs at compile-time (and does not accept a worldage argument).
"""
static_method_count(@nospecialize(f)) = static_method_count(f, Tuple{Vararg{Any}})
if VERSION >= v"1.10.0-DEV.609"
    function __static_method_count(world, source, T, self, f, _T)
        method_count = length(_methods(f, T, nothing, world))
        ci = create_codeinfo_with_returnvalue([Symbol("#self#"), :f, :_T], [:T], (:T,), :($method_count))

        # Now we add the edges so if a method is defined this recompiles
        ci.edges = _method_table_all_edges_all_methods(f, T, world)
        return ci
    end
    @eval function static_method_count(@nospecialize(f) , @nospecialize(_T::Type{T})) where {T <: Tuple}
        $(Expr(:meta, :generated, __static_method_count))
        $(Expr(:meta, :generated_only))
    end
else
    @generated function static_method_count(@nospecialize(f) , @nospecialize(_T::Type{T})) where {T <: Tuple}
        world = typemax(UInt)
        method_count = length(_methods(f, T, nothing, world))
        ci = create_codeinfo_with_returnvalue([Symbol("#self#"), :f, :_T], [:T], (:T,), :($method_count))

        # Now we add the edges so if a method is defined this recompiles
        ci.edges = _method_table_all_edges_all_methods(f, T, world)
        return ci
    end
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
                  mod::Union{Tuple{Module},AbstractArray{Module},Nothing}=nothing, world = Base.get_world_counter())
    tt = _combine_signature_type(f_type, t_type)
    lim = -1
    mft = Core.Compiler._methods_by_ftype(tt, lim, world)
    if mft === nothing
        ms = Base.Method[]
    else
        ms = Base.Method[_get_method(m) for m in mft if (mod === nothing || m.method.module ∈ mod)]
    end
    return Base.MethodList(ms, f_type.name.mt)
end

# Like Core.Compiler.method_instances, but accepts f as a _type_ instead of an instance.
function _method_instances(@nospecialize(f_type), @nospecialize(t_type), world = Base.get_world_counter())
    tt = _combine_signature_type(f_type, t_type)
    lim = -1
    mft = Core.Compiler._methods_by_ftype(tt, lim, world)
    if mft === nothing
        return Core.MethodInstance[]
    else
        return Core.MethodInstance[_specialize_method(match) for match in mft]
    end
end
# Like Base.signature_type, but starts with a type for f_type already.
function _combine_signature_type(@nospecialize(f_type::Type), @nospecialize(args::Type))
    u = unwrap_unionall(args)
    return rewrap_unionall(Tuple{f_type, u.parameters...}, args)
end
# MethodMatch is only defined in v1.6+, so the values returned from _methods_by_ftype need
# a bit of massaging here.
if VERSION < v"1.6"
    # _methods_by_ftype returns a triple
    _get_method((mtypes, msp, method)) = method
    # Core.Compiler.specialize_method(::MethodMatch) is only defined on v1.6+
    function _specialize_method(method_data)
        mtypes, msp, m = method_data
        instance = ccall(:jl_specializations_get_linfo, Ref{Core.MethodInstance}, (Any, Any, Any), m, mtypes, msp)
        return instance
    end
else
    # _methods_by_ftype returns a MethodMatch
    _get_method(method_match) = method_match.method
    _specialize_method = Core.Compiler.specialize_method
end

end  # module
