module Tricks

    using Base: rewrap_unionall, unwrap_unionall, uncompressed_ast
    using Base: CodeInfo

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
        typ = rewrap_unionall(Tuple{f, unwrap_unionall(T).parameters...}, T)
        world = typemax(UInt)
        method_doesnot_exist = ccall(:jl_gf_invoke_lookup, Any, (Any, UInt), typ, world) === nothing
        ret_func = method_doesnot_exist ? _hasmethod_false : _hasmethod_true
        ci_orig = uncompressed_ast(typeof(ret_func).name.mt.defs.func)
        ci = ccall(:jl_copy_code_info, Ref{CodeInfo}, (Any,), ci_orig)

        # Now we add the edges so if a method is defined this recompiles
        if method_doesnot_exist
            # No method so attach to method table
            mt = f.name.mt
            ci.edges = Core.Compiler.vect(mt, typ)
        end
        return ci
    end

end
