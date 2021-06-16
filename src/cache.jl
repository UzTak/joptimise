"""
Cache for optimizer
"""



## Derivative types
abstract type AbstractDiffMethod end

struct ForwardAD <: AbstractDiffMethod end
struct ReverseAD <: AbstractDiffMethod end
struct RevZyg <: AbstractDiffMethod end  # only used for gradients (not jacobians)
struct ForwardFD <: AbstractDiffMethod end
struct CentralFD <: AbstractDiffMethod end
struct ComplexStep <: AbstractDiffMethod end
struct UserDeriv <: AbstractDiffMethod end   # user-specified derivatives


FD = Union{ForwardFD, CentralFD, ComplexStep}

"""
convert to type used in FiniteDiff package
"""
function finitediff_type(dtype)
    if isa(dtype, ForwardFD)
        fdtype = Val{:forward}
    elseif isa(dtype, CentralFD)
        fdtype = Val{:central}
    elseif isa(dtype, ComplexStep)
        fdtype = Val{:complex}
    end
    return fdtype
end


## Gradients
# internally used cache for gradients and jacobians (separately)
struct GradOrJacCache{T1,T2,T3,T4}
    f!::T1
    work::T2
    cache::T3
    dtype::T4
end


function gradientcache(dtype::FD, func!, nx, ng)

    df = zeros(nx)
    x = zeros(nx)
    fdtype = finitediff_type(dtype)
    cache = FiniteDiff.GradientCache(df, x, fdtype)

    return GradOrJacCache(func!, nothing, cache, dtype)
end


function gradient!(df, x, cache::GradOrJacCache{T1,T2,T3,T4}
    where {T1,T2,T3,T4<:FD})

    FiniteDiff.finite_difference_gradient!(df, cache.f!, x, cache.cache)

    return nothing
end



## Sparcity
abstract type AbstractSparsityPattern end

struct DensePattern <: AbstractSparsityPattern end

struct SparsePattern{TI} <: AbstractSparsityPattern
    rows::Vector{TI}
    cols::Vector{TI}
end


"""
    SparsePattern(A::SparseMatrixCSC)
construct sparse pattern from representative sparse matrix
# Arguments
- `A::SparseMatrixCSC`: sparse jacobian
"""
function SparsePattern(A::SparseMatrixCSC)
    rows, cols, _ = findnz(A)
    return SparsePattern(rows, cols)
end


"""
    SparsePattern(A::Matrix)
construct sparse pattern from representative matrix
# Arguments
- `A::Matrix`: sparse jacobian
"""
function SparsePattern(A::Matrix)
    return SparsePattern(sparse(A))
end


"""
    SparsePattern(::FD, func!, ng, x1, x2, x3)
detect sparsity pattern by computing derivatives (using finite differencing)
at three different locations. Entries that are zero at all three
spots are assumed to always be zero.
# Arguments
- `func!::Function`: function of form f = func!(g, x)
- `ng::Int`: number of constraints
- `x1,x2,x3::Vector{Float}`:: three input vectors.
"""
function SparsePattern(dtype::FD, func!, ng, x1, x2, x3)

    fdtype = finitediff_type(dtype)
    cache = FiniteDiff.JacobianCache(x1, zeros(ng), fdtype)

    nx = length(x1)
    J1 = zeros(ng, nx)
    J2 = zeros(ng, nx)
    J3 = zeros(ng, nx)
    FiniteDiff.finite_difference_jacobian!(J1, func!, x1, cache)
    FiniteDiff.finite_difference_jacobian!(J2, func!, x2, cache)
    FiniteDiff.finite_difference_jacobian!(J3, func!, x3, cache)

    @. J1 = abs(J1) + abs(J2) + abs(J3)
    Jsp = sparse(J1)

    return SparsePattern(Jsp)
end


#  used internally to get rows and cols for dense jacobian
function _get_sparsity(::DensePattern, nx, nf)
    len = nf*nx
    rows = [i for i = 1:nf, j = 1:nx][:]
    cols = [j for i = 1:nf, j = 1:nx][:]
    return rows, cols
end

#  used internally to get rows and cols for sparse jacobian
_get_sparsity(sp::SparsePattern, nx, nf) = sp.rows, sp.cols


# ## Derivative types
# abstract type AbstractDiffMethod end
#
# struct ForwardAD <: AbstractDiffMethod end
# struct ReverseAD <: AbstractDiffMethod end
# struct RevZyg <: AbstractDiffMethod end  # only used for gradients (not jacobians)
# struct ForwardFD <: AbstractDiffMethod end
# struct CentralFD <: AbstractDiffMethod end
# struct ComplexStep <: AbstractDiffMethod end
# struct UserDeriv <: AbstractDiffMethod end   # user-specified derivatives
#
#
# FD = Union{ForwardFD, CentralFD, ComplexStep}
#
# """
# convert to type used in FiniteDiff package
# """
# function finitediff_type(dtype)
#     if isa(dtype, ForwardFD)
#         fdtype = Val{:forward}
#     elseif isa(dtype, CentralFD)
#         fdtype = Val{:central}
#     elseif isa(dtype, ComplexStep)
#         fdtype = Val{:complex}
#     end
#     return fdtype
# end


# ## Sparsity patterns
# abstract type AbstractSparsityPattern end
#
# struct DensePattern <: AbstractSparsityPattern end
#
# struct SparsePattern{TI} <: AbstractSparsityPattern
#     rows::Vector{TI}
#     cols::Vector{TI}
# end
#
#
# """
#     SparsePattern(A::SparseMatrixCSC)
# construct sparse pattern from representative sparse matrix
# # Arguments
# - `A::SparseMatrixCSC`: sparse jacobian
# """
# function SparsePattern(A::SparseMatrixCSC)
#     rows, cols, _ = findnz(A)
#     return SparsePattern(rows, cols)
# end
#
#
# """
#     SparsePattern(A::Matrix)
# construct sparse pattern from representative matrix
# # Arguments
# - `A::Matrix`: sparse jacobian
# """
# function SparsePattern(A::Matrix)
#     return SparsePattern(sparse(A))
# end
#
#
# """
#     SparsePattern(::FD, func!, ng, x1, x2, x3)
# detect sparsity pattern by computing derivatives (using finite differencing)
# at three different locations. Entries that are zero at all three
# spots are assumed to always be zero.
# # Arguments
# - `func!::Function`: function of form f = func!(g, x)
# - `ng::Int`: number of constraints
# - `x1,x2,x3::Vector{Float}`:: three input vectors.
# """
# function SparsePattern(dtype::FD, func!, ng, x1, x2, x3)
#
#     fdtype = finitediff_type(dtype)
#     cache = FiniteDiff.JacobianCache(x1, zeros(ng), fdtype)
#
#     nx = length(x1)
#     J1 = zeros(ng, nx)
#     J2 = zeros(ng, nx)
#     J3 = zeros(ng, nx)
#     FiniteDiff.finite_difference_jacobian!(J1, func!, x1, cache)
#     FiniteDiff.finite_difference_jacobian!(J2, func!, x2, cache)
#     FiniteDiff.finite_difference_jacobian!(J3, func!, x3, cache)
#
#     @. J1 = abs(J1) + abs(J2) + abs(J3)
#     Jsp = sparse(J1)
#
#     return SparsePattern(Jsp)
# end
#
#
# #  used internally to get rows and cols for dense jacobian
# function _get_sparsity(::DensePattern, nx, nf)
#     len = nf*nx
#     rows = [i for i = 1:nf, j = 1:nx][:]
#     cols = [j for i = 1:nf, j = 1:nx][:]
#     return rows, cols
# end
#
# #  used internally to get rows and cols for sparse jacobian
# _get_sparsity(sp::SparsePattern, nx, nf) = sp.rows, sp.cols


## Dense Jacobian cache
# internally-used cache for dense jacobians
struct DenseCache{T1,T2,T3,T4,T5}
    f!::T1  # function
    gwork::T2  # typicaly a gradient vector
    Jwork::T3   # jacobian vector/matrix
    cache::T4  # cache used by differentiation method
    dtype::T5  # diff method
end


"""
    _create_cache(sp::DensePattern, dtype::ForwardAD, func!, nx, ng)
Cache for dense jacobian using forward-mode AD.
# Arguments
- `func!::function`: function of form: f = func!(g, x)
- `nx::Int`: number of design variables
- `ng::Int`: number of constraints
"""
function _create_cache(sp::DensePattern, dtype::ForwardAD, func!, nx, ng)

    function combine!(fg, x)
        fg[1] = func!(@view(fg[2:end]), x)
    end

    g = zeros(1 + ng)
    x = zeros(nx)
    config = ForwardDiff.JacobianConfig(combine!, g, x)
    J = DiffResults.JacobianResult(g, x)

    return DenseCache(combine!, g, J, config, dtype)
end

"""
    evaluate!(g, df, dg, x, cache::DenseCache{T1,T2,T3,T4,T5} where {T1,T2,T3,T4,T5<:ForwardAD})
evaluate function and derivatives for a dense jacobian with forward-mode AD
# Arguments
- `g::Vector{Float}`: constraints, modified in place
- `df::Vector{Float}`: objective gradient, modified in place
- `dg::Vector{Float}`: constraint jacobian, modified in place (order specified by sparsity pattern)
- `x::Vector{Float}`: design variables, input
- `cache::DenseCache`: cache generated by `_create_cache`
"""
function evaluate!(g, df, dg, x, cache::DenseCache{T1,T2,T3,T4,T5}
    where {T1,T2,T3,T4,T5<:ForwardAD})

    ForwardDiff.jacobian!(cache.Jwork, cache.f!, cache.gwork, x, cache.cache)
    fg = DiffResults.value(cache.Jwork)   # reference not copy
    J = DiffResults.jacobian(cache.Jwork)  # reference not copy
    f = fg[1]
    g[:] = fg[2:end]
    df[:] = J[1, :]
    dg[:] = J[2:end, :][:]

    return f
end


"""
    _create_cache(sp::DensePattern, dtype::FD, func!, nx, ng)
Cache for dense jacobian using finite differencing
# Arguments
- `func!::function`: function of form: f = func!(g, x)
- `nx::Int`: number of design variables
- `ng::Int`: number of constraints
"""
function _create_cache(sp::DensePattern, dtype::FD, func!, nx, ng)

    function combine!(fg, x)
        fg[1] = func!(@view(fg[2:end]), x)
    end

    fgwork = zeros(1 + ng)
    Jwork = zeros(1 + ng, nx)

    x = zeros(nx)
    fdtype = finitediff_type(dtype)
    cache = FiniteDiff.JacobianCache(x, fgwork, fdtype)

    return DenseCache(combine!, fgwork, Jwork, cache, dtype)
end


"""
    evaluate!(g, df, dg, x, cache::DenseCache{T1,T2,T3,T4,T5} where {T1,T2,T3,T4,T5<:FD})
evaluate function and derivatives for a dense jacobian with finite differencing
# Arguments
- `g::Vector{Float}`: constraints, modified in place
- `df::Vector{Float}`: objective gradient, modified in place
- `dg::Vector{Float}`: constraint jacobian, modified in place (order specified by sparsity pattern)
- `x::Vector{Float}`: design variables, input
- `cache::DenseCache`: cache generated by `_create_cache`
"""
function evaluate!(g, df, dg, x, cache::DenseCache{T1,T2,T3,T4,T5}
    where {T1,T2,T3,T4,T5<:FD})

    cache.f!(cache.gwork, x)
    f = cache.gwork[1]
    g[:] = cache.gwork[2:end]

    FiniteDiff.finite_difference_jacobian!(cache.Jwork, cache.f!, x, cache.cache)
    df[:] = cache.Jwork[1, :]
    dg[:] = cache.Jwork[2:end, :][:]

    return f
end


"""
    _create_cache(sp::DensePattern, dtype::UserDeriv, func!, nx, ng)
Cache for dense Jacobian with user-supplied derivatives
# Arguments
- `func!::function`: function of form: f = func!(g, df, dg, x)
- `nx::Int`: number of design variables
- `ng::Int`: number of constraints
"""
function _create_cache(sp::DensePattern, dtype::UserDeriv, func!, nx, ng)
    Jwork = zeros(ng, nx)
    return DenseCache(func!, 0.0, Jwork, nothing, dtype)
end

"""
    evaluate!(g, df, dg, x, cache::DenseCache{T1,T2,T3,T4,T5} where {T1,T2,T3,T4,T5<:UserDeriv})
evaluate function and derivatives for a dense jacobian with user-provided derivatives
# Arguments
- `g::Vector{Float}`: constraints, modified in place
- `df::Vector{Float}`: objective gradient, modified in place
- `dg::Vector{Float}`: constraint jacobian, modified in place (order specified by sparsity pattern)
- `x::Vector{Float}`: design variables, input
- `cache::DenseCache`: cache generated by `_create_cache`
"""
function evaluate!(g, df, dg, x, cache::DenseCache{T1,T2,T3,T4,T5}
    where {T1,T2,T3,T4,T5<:UserDeriv})
    f = cache.f!(g, df, cache.Jwork, x)
    dg[:] = cache.Jwork[:]

    return f
end




## Spare Jacobians
# ------ sparse jacobians -------------

"""
    sparsejacobiancache(sp::SparsePattern, dtype::ForwardAD, func!, nx, ng)
Cache for sparse jacobian using ForwardDiff
# Arguments
- `func!::function`: function of form: f = func!(g, x)
- `nx::Int`: number of design variables
- `ng::Int`: number of constraints
"""
function sparsejacobiancache(sp::SparsePattern, dtype::ForwardAD, func!, nx, ng)

    g = zeros(ng)
    x = zeros(nx)
    Jsp = sparse(sp.rows, sp.cols, ones(length(sp.rows)))
    colors = SparseDiffTools.matrix_colors(Jsp)
    cachesp = SparseDiffTools.ForwardColorJacCache(func!, x, dx=g, colorvec=colors, sparsity=Jsp)

    return GradOrJacCache(func!, Jsp, cachesp, dtype)
end


"""
    sparsejacobian!(dg, x, cache::GradOrJacCache{T1,T2,T3,T4} where {T1,T2,T3,T4<:ForwardAD})
evaluate sparse jacobian using ForwardDiff
# Arguments
- `dg::Vector{Float}`: constraint jacobian, modified in place
- `x::Vector{Float}`: design variables, input
- `cache::GradOrJacCache`: cache generated by `sparsejacobiancache`
"""
function sparsejacobian!(dg, x, cache::GradOrJacCache{T1,T2,T3,T4}
    where {T1,T2,T3,T4<:ForwardAD})

    SparseDiffTools.forwarddiff_color_jacobian!(cache.work, cache.f!, x, cache.cache)
    dg[:] = cache.work.nzval

    return nothing
end



"""
    sparsejacobiancache(sp::SparsePattern, dtype::FD, func!, nx, ng)
Cache for sparse jacobian using finite differencing
# Arguments
- `func!::function`: function of form: f = func!(g, x)
- `nx::Int`: number of design variables
- `ng::Int`: number of constraints
"""
function sparsejacobiancache(sp::SparsePattern, dtype::FD, func!, nx, ng)

    g = zeros(ng)
    x = zeros(nx)
    Jsp = sparse(sp.rows, sp.cols, ones(length(sp.rows)))
    colors = SparseDiffTools.matrix_colors(Jsp)
    fdtype = finitediff_type(dtype)
    cache = FiniteDiff.JacobianCache(x, fdtype, colorvec=colors, sparsity=Jsp)

    return GradOrJacCache(func!, Jsp, cache, dtype)
end


"""
    sparsejacobian!(dg, x, cache::GradOrJacCache{T1,T2,T3,T4} where {T1,T2,T3,T4<:FD})
evaluate sparse jacobian using finite differencing
# Arguments
- `dg::Vector{Float}`: constraint jacobian, modified in place
- `x::Vector{Float}`: design variables, input
- `cache::GradOrJacCache`: cache generated by `sparsejacobiancache`
"""
function sparsejacobian!(dg, x, cache::GradOrJacCache{T1,T2,T3,T4}
    where {T1,T2,T3,T4<:FD})

    FiniteDiff.finite_difference_jacobian!(cache.work, cache.f!, x, cache.cache)
    dg[:] = cache.work.nzval

    return nothing
end


## Gradient and sparce Jacobians
# internally used cache for gradients/jacobians
struct SparseCache{T1,T2}
    gradcache::T1
    jaccache::T2
end


"""
    _create_cache(sp::SparsePattern, dtype::T, func!, nx, ng) where T<:Vector
create cache for derivatives when the jacobian is sparse
# Arguments
- `sp::SparsePattern`: sparsity pattern
- `dtype::Vector{AbstractDiffMethod}`: differentiation method for gradient and jacobian (array of length two)
- `func!::function`: function of form: f = func!(g, x)
- `nx::Int`: number of design variables
- `ng::Int`: number of constraints
"""
function _create_cache(sp::SparsePattern, dtype::T, func!, nx, ng) where T<:Vector
    gradcache = gradientcache(dtype[1], func!, nx, ng)
    jaccache = sparsejacobiancache(sp, dtype[2], func!, nx, ng)

    return SparseCache(gradcache, jaccache)
end


"""
    evaluate!(g, df, dg, x, cache::T) where T <: SparseCache
evaluate function and derivatives for a sparse jacobian
# Arguments
- `g::Vector{Float}`: constraints, modified in place
- `df::Vector{Float}`: objective gradient, modified in place
- `dg::Vector{Float}`: constraint jacobian, modified in place (order specified by sparsity pattern)
- `x::Vector{Float}`: design variables, input
- `cache::SparseCache`: cache generated by `_create_cache`
"""
function evaluate!(g, df, dg, x, cache::SparseCache{T1,T2}) where {T1,T2}

    f = cache.gradcache.f!(g, x)
    gradient!(df, x, cache.gradcache)
    sparsejacobian!(dg, x, cache.jaccache)

    return f
end


"""
    _create_cache(sp::SparsePattern, dtype::UserDeriv, func!, nx, ng)
Cache for sparse jacobian with user-supplied derivatives
# Arguments
- `func!::function`: function of form: f = func!(g, df, dg, x)
- `nx::Int`: number of design variables
- `ng::Int`: number of constraints
"""
function _create_cache(sp::SparsePattern, dtype::UserDeriv, func!, nx, ng)
    return GradOrJacCache(func!, 0.0, nothing, dtype)
end


"""
    evaluate!(g, df, dg, x, cache::DenseCache{T1,T2,T3,T4,T5} where {T1,T2,T3,T4,T5<:UserDeriv})
evaluate function and derivatives for a dense jacobian with user-provided derivatives
# Arguments
- `g::Vector{Float}`: constraints, modified in place
- `df::Vector{Float}`: objective gradient, modified in place
- `dg::Vector{Float}`: constraint jacobian, modified in place (order specified by sparsity pattern)
- `x::Vector{Float}`: design variables, input
- `cache::DenseCache`: cache generated by `_create_cache`
"""
function evaluate!(g, df, dg, x, cache::GradOrJacCache{T1,T2,T3,T4}
    where {T1,T2,T3,T4<:UserDeriv})
    f = cache.f!(g, df, dg, x)

    return f
end