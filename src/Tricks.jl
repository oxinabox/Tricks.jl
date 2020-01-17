module Tricks

using Base: rewrap_unionall, unwrap_unionall, uncompressed_ast
using Base: CodeInfo

export static_hasmethod, static_methods

# This is used to create the CodeInfo returned by static_hasmethod.
_hasmethod_false(@nospecialize(f), @nospecialize(t)) = false
_hasmethod_true(@nospecialize(f), @nospecialize(t)) = true

"""
            static_hasmethod(f, type_tuple::Type{<:Tuple)

        Like `hasmethod` but runs at compile-time (and does not accept a worldage argument).

        !!! Note
            This absolutely must *not* be called dynamically. Else it will fail to update
            when new methods are declared.
            If you do not know how to ensure that it is not called dynamically,
            do not use this.
        """
@generated function static_hasmethod(@nospecialize(f), @nospecialize(t::Type{T}),) where {T<:Tuple}
    # The signature type:
    world = typemax(UInt)
    method_insts = Core.Compiler.method_instances(f.instance, T, world)
    method_doesnot_exist = isempty(method_insts)
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
        ci.edges = method_insts
    end
    return ci
end


function expr_to_codeinfo(m, argnames, spnames, sp, e)
    lam = Expr(:lambda, argnames,
               Expr(Symbol("scope-block"),
                    Expr(:block,
                        Expr(:return,
                            Expr(:block,
                                e,
                            )))))
    ex = if spnames === nothing
        lam
    else
        Expr(Symbol("with-static-parameters"), lam, spnames...)
    end

    # Get the code-info for the generatorbody in order to use it for generating a dummy
    # code info object.
    ci = ccall(:jl_expand, Any, (Any, Any), ex, m)
end

static_methods(@nospecialize(f)) = _static_methods(Main, f, Tuple{Vararg{Any}})
static_methods(@nospecialize(f) , @nospecialize(_T::Type)) = _static_methods(Main, f, _T)
@generated function _static_methods(@nospecialize(m::Module), @nospecialize(f) , @nospecialize(_T::Type{T})) where {T <: Tuple}
    world = typemax(UInt)
    methods(f.instance)

    ms = methods(f.instance, T)
    ci = expr_to_codeinfo(m, [Symbol("#self#"), :m, :f, :_T], [:T], (:T,), :($ms))

    method_insts = Core.Compiler.method_instances(f.instance, T, world)
    method_doesnot_exist = isempty(method_insts)

    mt = f.name.mt
    # Now we add the edges so if a method is defined this recompiles
    if method_doesnot_exist
        # No method so attach to method table
        mt = f.name.mt
        ci.edges = Core.Compiler.vect(mt, (mt, Tuple{Vararg{Any}}))
    else  # method exists, attach edges to all instances
        ci.edges = method_insts
    end
    return ci
end


end
